import AVFoundation
import Speech
import SwiftUI

/// Microphone dictation for the composer, using Apple's on-device speech
/// recognizer (English only for now).
///
/// On-device recognition is required, not preferred: the product promise is
/// that student data never leaves the Mac, and `SFSpeechRecognizer` will
/// happily stream audio to Apple's servers when `requiresOnDeviceRecognition`
/// is false. If the Mac can't transcribe locally we refuse and say so.
@MainActor
final class DictationController: ObservableObject {
    /// A failure the teacher can act on: what went wrong, and the System
    /// Settings pane that fixes it (when there is one).
    struct Failure: Equatable {
        var message: String
        var settingsURL: URL?

        static func settings(_ message: String, _ pane: String) -> Failure {
            Failure(message: message, settingsURL: URL(string: pane))
        }

        static let keyboardPane = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        static let micPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        static let speechPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
    }

    enum Phase: Equatable {
        case idle
        case starting
        case listening
        case failed(Failure)
    }

    @Published private(set) var phase: Phase = .idle

    var isActive: Bool {
        switch phase {
        case .starting, .listening: return true
        case .idle, .failed: return false
        }
    }

    var failure: Failure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    /// Called with the full text the composer should show (base text the
    /// teacher had already typed, plus everything transcribed so far).
    var onText: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var baseText = ""

    func toggle(currentText: String) {
        if isActive {
            stop()
        } else {
            start(currentText: currentText)
        }
    }

    func start(currentText: String) {
        guard !isActive else { return }
        baseText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .starting

        guard Self.isLaunchedAsApp else {
            phase = .failed(Failure(message: "Dictation needs the packaged app — build it with make-app.sh and open \(AppInfo.appBundleName)."))
            return
        }
        guard let recognizer else {
            phase = .failed(Failure(message: "English dictation isn't available on this Mac."))
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            phase = .failed(.settings("On-device English dictation isn't installed on this Mac.", Failure.keyboardPane))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard await Self.requestSpeechAccess() else {
                self.phase = .failed(.settings("Speech recognition access was denied.", Failure.speechPane))
                return
            }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                self.phase = .failed(.settings("Microphone access was denied.", Failure.micPane))
                return
            }
            guard self.phase == .starting else { return }  // cancelled while waiting
            self.beginListening(with: recognizer)
        }
    }

    func stop() {
        guard isActive || task != nil else { return }
        teardownAudio()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if isActive { phase = .idle }
    }

    /// Clears a failure message once the teacher has seen it (e.g. on the next
    /// keystroke or send) so it doesn't sit under the composer forever.
    func clearError() {
        if case .failed = phase { phase = .idle }
    }

    // MARK: - Private

    private func beginListening(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            phase = .failed(Failure(message: "No microphone input is available."))
            self.request = nil
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            phase = .failed(Failure(message: "Couldn't start the microphone: \(error.localizedDescription)"))
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // `stop()` clears `request`; anything arriving after that —
                // including the cancellation error it provokes — is stale.
                guard self.request != nil else { return }
                if let result {
                    self.apply(transcript: result.bestTranscription.formattedString)
                    if result.isFinal { self.stop() }
                } else if let error {
                    self.finish(withError: error)
                }
            }
        }
        phase = .listening
    }

    private func apply(transcript: String) {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        onText?(baseText.isEmpty ? spoken : baseText + " " + spoken)
    }

    /// The recognizer ended the session itself. Whatever it already
    /// transcribed stays in the composer; only listening stops.
    private func finish(withError error: Error) {
        teardownAudio()
        request = nil
        task = nil
        let ns = error as NSError
        FileHandle.standardError.write(
            Data("dictation: \(ns.domain) \(ns.code) — \(ns.localizedDescription)\n".utf8))
        switch (ns.domain, ns.code) {
        // "No speech detected" is the normal end of a quiet session, not a fault.
        case ("kAFAssistantErrorDomain", 1110), ("kAFAssistantErrorDomain", 216):
            phase = .idle
        // The speech recognizer refuses to run at all while the system
        // Dictation switch is off, even though it reports on-device support.
        case ("kLSRErrorDomain", 201):
            phase = .failed(.settings(
                "Turn on Dictation in System Settings → Keyboard, then click the mic again.",
                Failure.keyboardPane))
        default:
            phase = .failed(Failure(message: "Dictation stopped: \(ns.localizedDescription)"))
        }
    }

    private func teardownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    struct ProbeFailure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Test hook (`TW_DICTATE_FILE`): runs the same on-device English
    /// recognizer over an audio file, so the speech path can be verified
    /// without a live microphone. `nonisolated` so the probe can run while
    /// the main thread waits on it.
    nonisolated static func transcribeFile(at url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProbeFailure(message: "no audio file at \(url.path)")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw ProbeFailure(message: "no en-US recognizer")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw ProbeFailure(message: "on-device recognition unavailable")
        }
        guard isLaunchedAsApp else {
            throw ProbeFailure(message: "run the probe with: open -n '\(AppInfo.appBundleName)' --env TW_DICTATE_FILE=<audio> --stdout <log>")
        }
        guard await requestSpeechAccess() else {
            throw ProbeFailure(message: "speech recognition access denied")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    /// TCC blames the *responsible* process for a privacy request. Run the
    /// executable straight from the bundle (or from `swift run`) and that's the
    /// shell, which carries no usage description — the request then aborts the
    /// process outright instead of prompting. Only ask when LaunchServices
    /// started us, which is the one case where the prompt is attributed to the
    /// app itself.
    nonisolated static var isLaunchedAsApp: Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil,
              let bundleID = Bundle.main.bundleIdentifier else { return false }
        return ProcessInfo.processInfo.environment["__CFBundleIdentifier"] == bundleID
    }

    nonisolated private static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
