import Foundation
import CryptoKit

/// Downloads the GGUF model on first launch (ship-small distribution).
/// Resumable, checksum-verified, and installed atomically into
/// ~/Library/Application Support/LessonLab/Models/.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    static let shared = ModelDownloader()

    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case paused(received: Int64)
        case verifying
        case installed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Fires once the model is verified and moved into place, so AppState
    /// can repaint views that key off `modelAvailable`.
    var onInstalled: (() -> Void)?

    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private lazy var session = URLSession(
        configuration: .default, delegate: DownloadDelegate(owner: self), delegateQueue: nil)

    /// Test override: TW_MODEL_URL points at a local server; TW_MODEL_SHA256
    /// replaces the expected checksum (or "skip" disables verification).
    nonisolated static var sourceURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["TW_MODEL_URL"], let url = URL(string: override) { return url }
        return URL(string: AppInfo.modelDownloadURL)!
    }

    private nonisolated static var expectedSHA256: String? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["TW_MODEL_SHA256"] {
            return override == "skip" ? nil : override
        }
        return AppInfo.modelSHA256
    }

    /// Where the downloaded model is installed (checked by locateModelFile).
    nonisolated static var installDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["TW_MODEL_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("\(AppInfo.supportDirectory)/Models", isDirectory: true)
    }

    nonisolated static var installedModelPath: String? {
        guard let path = installDirectory?
            .appendingPathComponent("\(LlamaBackend.modelFileName).gguf").path else { return nil }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - Controls

    func start() {
        switch phase {
        case .downloading, .verifying, .installed: return
        default: break
        }
        phase = .downloading(received: receivedSoFar, total: AppInfo.modelByteSize)
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            task = session.downloadTask(with: Self.sourceURL)
        }
        task?.resume()
    }

    func pause() {
        guard case .downloading = phase else { return }
        task?.cancel { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.resumeData = data
                self.phase = .paused(received: self.receivedSoFar)
            }
        }
    }

    private var receivedSoFar: Int64 {
        switch phase {
        case .downloading(let received, _): return received
        case .paused(let received): return received
        default: return 0
        }
    }

    // MARK: - Delegate plumbing (called from the session queue)

    fileprivate nonisolated func didWrite(received: Int64, total: Int64) {
        Task { @MainActor in
            // total is -1 when the server omits Content-Length; fall back to
            // the known release size so the bar still moves.
            let knownTotal = total > 0 ? total : AppInfo.modelByteSize
            if case .paused = self.phase { return }
            self.phase = .downloading(received: received, total: knownTotal)
        }
    }

    /// Runs verification + install synchronously on the session queue — the
    /// temp file URLSession hands over is deleted once this returns.
    fileprivate nonisolated func didFinish(tmp: URL) {
        Task { @MainActor in self.phase = .verifying }
        do {
            if let expected = Self.expectedSHA256 {
                let actual = try Self.sha256(of: tmp)
                guard actual == expected else {
                    throw DownloadError.checksumMismatch
                }
            }
            guard let dir = Self.installDirectory else { throw DownloadError.noInstallDirectory }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("\(LlamaBackend.modelFileName).gguf")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
            Task { @MainActor in
                self.phase = .installed
                self.onInstalled?()
            }
        } catch {
            Task { @MainActor in
                self.phase = .failed(Self.friendlyMessage(for: error))
            }
        }
    }

    fileprivate nonisolated func didFail(error: Error) {
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            if (error as NSError).code == NSURLErrorCancelled { return }  // pause path
            self.resumeData = resume
            self.phase = .failed(Self.friendlyMessage(for: error))
        }
    }

    private enum DownloadError: Error {
        case checksumMismatch, noInstallDirectory
    }

    private static func friendlyMessage(for error: Error) -> String {
        switch error {
        case DownloadError.checksumMismatch:
            return "The downloaded file didn't verify — it may have been corrupted in transit. Try again."
        case DownloadError.noInstallDirectory:
            return "Couldn't access Application Support to save the model."
        case let e as NSError where e.code == NSURLErrorNotConnectedToInternet:
            return "No internet connection. The download will pick up where it left off when you retry."
        default:
            return "\(error.localizedDescription) If your school network blocks downloads, ask IT to allow \(AppInfo.allowlistDomains.joined(separator: ", "))."
        }
    }

    /// Streamed SHA-256 so the 1.2 GB file never sits in memory.
    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 8 * 1024 * 1024)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Separate delegate object so ModelDownloader can stay @MainActor while
/// URLSession calls back on its own queue.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: ModelDownloader?
    init(owner: ModelDownloader) { self.owner = owner }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        owner?.didWrite(received: totalBytesWritten, total: totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move out of URLSession's temp spot before it's cleaned up, then
        // verify+install from our own copy.
        let holding = FileManager.default.temporaryDirectory
            .appendingPathComponent("lessonlab-model-\(UUID().uuidString).gguf")
        do {
            try FileManager.default.moveItem(at: location, to: holding)
            owner?.didFinish(tmp: holding)
        } catch {
            owner?.didFail(error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { owner?.didFail(error: error) }
    }
}
