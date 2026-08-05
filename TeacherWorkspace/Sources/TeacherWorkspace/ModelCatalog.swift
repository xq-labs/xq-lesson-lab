import Foundation

/// One on-device model the app knows how to run: where to get it, how to
/// verify it, and what to call it in the UI. Everything that used to be a
/// `static let` on LlamaBackend or AppInfo lives here, once per model.
struct ModelSpec: Identifiable, Hashable {
    /// Stable id — persisted as the teacher's choice, so never rename one.
    let id: String
    /// GGUF basename without the extension, on disk and in the release asset.
    let fileName: String
    let displayName: String
    /// Short label for the picker: what a teacher is choosing between.
    let tier: String
    let blurb: String
    let downloadURL: String
    /// `shasum -a 256` of the release asset. Nil until the asset is published —
    /// a model with no checksum can never be downloaded (see `canDownload`).
    let sha256: String?
    let byteSize: Int64
    let contextTokens: Int32
    let recommendedRAMGB: Int
    /// Qwen models take an empty `<think></think>` block so replies start
    /// immediately instead of spending the budget reasoning. Other families
    /// have no such span, and prefilling one corrupts the prompt.
    let usesThinkPrefill: Bool
    /// Shown on the model's card — these are other people's weights, and the
    /// terms differ between them.
    let license: String
    /// False while the GGUF isn't published yet — the card reads "Coming soon"
    /// instead of offering a download that would 404. See RELEASING.md.
    let available: Bool

    /// Nothing is downloaded without a checksum to verify it against.
    var canDownload: Bool { available && sha256 != nil }

    /// True when this Mac has less memory than the model wants. Advisory: the
    /// download stays available, the UI just says what to expect.
    var exceedsSystemRAM: Bool {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        // Machines report a little under the round number they're sold as.
        return gb + 0.5 < Double(recommendedRAMGB)
    }
}

/// The models this build offers, smallest first. Adding one is an entry here —
/// see RELEASING.md § "Adding a model" for where the checksum comes from.
///
/// Everything but the default streams straight from Hugging Face: GitHub
/// release assets are capped at 2 GB, which the 4B and 9B both exceed.
enum ModelCatalog {
    /// Hugging Face serves the file at /resolve/, redirecting to its CDN.
    private static func huggingFace(_ repo: String, _ file: String) -> String {
        "https://huggingface.co/\(repo)/resolve/main/\(file).gguf"
    }

    static let qwen08B = ModelSpec(
        id: "qwen3.5-0.8b",
        fileName: "Qwen3.5-0.8B-Q4_K_M",
        displayName: "Qwen3.5-0.8B",
        tier: "Fastest",
        blurb: "The lightest option — a quick download that keeps up on an older or 8 GB Mac. Fine for drafting and tidying up text; the bigger models read student work more carefully.",
        downloadURL: huggingFace("unsloth/Qwen3.5-0.8B-GGUF", "Qwen3.5-0.8B-Q4_K_M"),
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517",
        byteSize: 532_517_120,
        contextTokens: 8192,
        recommendedRAMGB: 8,
        usesThinkPrefill: true,
        license: "Apache 2.0",
        available: true)

    static let qwen2B = ModelSpec(
        id: "qwen3.5-2b",
        fileName: "Qwen3.5-2B-Q4_K_M",
        displayName: "Qwen3.5-2B",
        tier: "Balanced",
        blurb: "The default. Fast on every Apple-silicon Mac, and strong enough for lesson planning, rubrics, and Skill Check.",
        // The default ships from our own fixed-tag release, so first launch
        // depends on nothing but GitHub; it's the same file as the Hugging
        // Face original, checksum included.
        downloadURL: "https://github.com/\(AppInfo.githubRepo)/releases/download/model-qwen3.5-2b/Qwen3.5-2B-Q4_K_M.gguf",
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
        byteSize: 1_280_835_840,
        contextTokens: 8192,
        recommendedRAMGB: 8,
        usesThinkPrefill: true,
        license: "Apache 2.0",
        available: true)

    static let llama3B = ModelSpec(
        id: "llama3.2-3b",
        fileName: "Llama-3.2-3B-Instruct-Q4_K_M",
        displayName: "Llama 3.2 3B",
        tier: "Alternative",
        blurb: "Meta's model, for a second opinion when a reply doesn't sound right. Writes plainly and follows instructions closely; it doesn't reason step by step the way the Qwen models do.",
        downloadURL: huggingFace("unsloth/Llama-3.2-3B-Instruct-GGUF", "Llama-3.2-3B-Instruct-Q4_K_M"),
        sha256: "6c99cc00ae910f6a532a80022cb4bc1939094527a089c29294b841c0bd87f74d",
        byteSize: 2_019_377_600,
        contextTokens: 8192,
        recommendedRAMGB: 16,
        // No thinking span in this family — prefilling one would corrupt it.
        usesThinkPrefill: false,
        // Meta's licence asks for a "Built with Llama" notice; it sits at the
        // foot of the Models page rather than crowding the card.
        license: "Llama 3.2 Community License",
        available: true)

    static let phi4Mini = ModelSpec(
        id: "phi4-mini",
        fileName: "Phi-4-mini-instruct-Q4_K_M",
        displayName: "Phi-4 mini",
        tier: "Microsoft",
        blurb: "Small but methodical — the steadiest of the light models at anything with steps in it, like working through a rubric or a maths explanation.",
        downloadURL: huggingFace("unsloth/Phi-4-mini-instruct-GGUF", "Phi-4-mini-instruct-Q4_K_M"),
        sha256: "88c00229914083cd112853aab84ed51b87bdf6b9ce42f532d8c85c7c63b1730a",
        byteSize: 2_491_874_272,
        contextTokens: 8192,
        recommendedRAMGB: 16,
        usesThinkPrefill: false,
        license: "MIT",
        available: true)

    static let qwen4B = ModelSpec(
        id: "qwen3.5-4b",
        fileName: "Qwen3.5-4B-Q4_K_M",
        displayName: "Qwen3.5-4B",
        tier: "Best quality",
        blurb: "Twice the size of the default, and noticeably better at long student work and multi-step placements. Worth it on a Mac with 16 GB or more.",
        downloadURL: huggingFace("unsloth/Qwen3.5-4B-GGUF", "Qwen3.5-4B-Q4_K_M"),
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
        byteSize: 2_740_937_888,
        contextTokens: 8192,
        recommendedRAMGB: 16,
        usesThinkPrefill: true,
        license: "Apache 2.0",
        available: true)

    static let gemmaE2B = ModelSpec(
        id: "gemma4-e2b",
        fileName: "gemma-4-E2B-it-Q4_K_M",
        displayName: "Gemma 4 E2B",
        tier: "Google",
        blurb: "Google's on-device model. Warm, readable prose — a good fit for family emails and feedback a student will read.",
        downloadURL: huggingFace("unsloth/gemma-4-E2B-it-GGUF", "gemma-4-E2B-it-Q4_K_M"),
        sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8",
        byteSize: 3_106_738_272,
        contextTokens: 8192,
        recommendedRAMGB: 16,
        usesThinkPrefill: false,
        license: "Gemma Terms of Use",
        available: true)

    static let gemmaE4B = ModelSpec(
        id: "gemma4-e4b",
        fileName: "gemma-4-E4B-it-Q4_K_M",
        displayName: "Gemma 4 E4B",
        tier: "Google · larger",
        blurb: "The bigger Gemma. Same voice as the E2B with more care over long documents — sits between the Qwen 4B and 9B in both size and judgment.",
        downloadURL: huggingFace("unsloth/gemma-4-E4B-it-GGUF", "gemma-4-E4B-it-Q4_K_M"),
        sha256: "85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87",
        byteSize: 4_977_171_584,
        contextTokens: 8192,
        recommendedRAMGB: 16,
        usesThinkPrefill: false,
        license: "Gemma Terms of Use",
        available: true)

    static let qwen9B = ModelSpec(
        id: "qwen3.5-9b",
        fileName: "Qwen3.5-9B-Q4_K_M",
        displayName: "Qwen3.5-9B",
        tier: "Most capable",
        blurb: "The best judgment on offer, and the largest download. Built for a 32 GB Mac — on anything smaller it will run, slowly.",
        downloadURL: huggingFace("unsloth/Qwen3.5-9B-GGUF", "Qwen3.5-9B-Q4_K_M"),
        sha256: "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8",
        byteSize: 5_680_522_464,
        contextTokens: 8192,
        recommendedRAMGB: 32,
        usesThinkPrefill: true,
        license: "Apache 2.0",
        available: true)

    /// Smallest first — the page and the picker both show them in this order,
    /// so a teacher reads the list as "how much am I asking of this Mac".
    static let all: [ModelSpec] = [
        qwen08B, qwen2B, llama3B, phi4Mini, qwen4B, gemmaE2B, gemmaE4B, qwen9B,
    ]
    static let defaultSpec = qwen2B

    static func spec(id: String) -> ModelSpec? { all.first { $0.id == id } }

    // MARK: - Where models live

    /// Where downloaded models are installed. TW_MODEL_DIR pins tests to an
    /// explicit directory.
    static var installDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["TW_MODEL_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("\(AppInfo.supportDirectory)/Models", isDirectory: true)
    }

    static func installURL(for spec: ModelSpec) -> URL? {
        installDirectory?.appendingPathComponent("\(spec.fileName).gguf")
    }

    /// Resolution order: embedded in the app bundle (--bundle-model builds) →
    /// downloaded into Application Support → the dev checkout's Models/ folder.
    static func installedPath(for spec: ModelSpec) -> String? {
        if let bundled = Bundle.main.path(forResource: spec.fileName, ofType: "gguf") {
            return bundled
        }
        if let installed = installURL(for: spec)?.path,
           FileManager.default.fileExists(atPath: installed) {
            return installed
        }
        // TW_MODEL_DIR pins tests to an explicit directory — don't let the dev
        // checkout's real model leak into them.
        if ProcessInfo.processInfo.environment["TW_MODEL_DIR"] != nil { return nil }
        // Dev fallback for `swift run` / debug builds: TeacherWorkspace/Models/
        let devPath = URL(fileURLWithPath: #filePath)                     // …/Sources/TeacherWorkspace/ModelCatalog.swift
            .deletingLastPathComponent()                                  // …/Sources/TeacherWorkspace
            .deletingLastPathComponent()                                  // …/Sources
            .deletingLastPathComponent()                                  // …/TeacherWorkspace
            .appendingPathComponent("Models/\(spec.fileName).gguf").path
        return FileManager.default.fileExists(atPath: devPath) ? devPath : nil
    }

    static func isInstalled(_ spec: ModelSpec) -> Bool { installedPath(for: spec) != nil }

    /// Embedded in the app bundle, so there is no file of ours to delete.
    static func isBundled(_ spec: ModelSpec) -> Bool {
        Bundle.main.path(forResource: spec.fileName, ofType: "gguf") != nil
    }

    /// True only for a model *we* downloaded into Application Support. A
    /// bundled copy belongs to the app, and the dev checkout's Models/ folder
    /// belongs to the repo — offering a delete for either would be a button
    /// that does nothing.
    static func isRemovable(_ spec: ModelSpec) -> Bool {
        guard let installed = installedPath(for: spec), let ours = installURL(for: spec) else {
            return false
        }
        return installed == ours.path
    }

    static var installedSpecs: [ModelSpec] { all.filter(isInstalled) }

    /// False only when nothing runnable exists anywhere — the case where chat
    /// can't work at all and setup blocks the whole window.
    static var hasAnyInstalled: Bool { !installedSpecs.isEmpty }

    /// Deletes a downloaded model. llama.cpp must have unloaded the file first
    /// (see LlamaBackend.unload).
    static func remove(_ spec: ModelSpec) throws {
        guard isRemovable(spec), let url = installURL(for: spec) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Selection

    /// The teacher's chosen model. Lives in UserDefaults rather than
    /// PersistedState: it's read from the nonisolated paths that resolve the
    /// model file, and store.json's decoder is load-bearing (see Persistence).
    private static let selectionKey = "model.selected"

    static var selectedID: String? {
        get { UserDefaults.standard.string(forKey: selectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    /// The model that will actually load. Falls back past a selection whose
    /// file is gone, so deleting the active model can't strand the app.
    static var activeSpec: ModelSpec {
        // TW_MODEL_ID pins the model for probes and snapshots, the way
        // TW_MODEL_DIR pins where they look for it. It's still only a
        // selection: a pin whose file is gone falls through like any other.
        if let pinned = ProcessInfo.processInfo.environment["TW_MODEL_ID"],
           let spec = spec(id: pinned), isInstalled(spec) { return spec }
        if let id = selectedID, let spec = spec(id: id), isInstalled(spec) { return spec }
        // Never chosen, or the chosen one was deleted: the default wins if
        // it's here. Falling straight to `installedSpecs.first` would hand the
        // chat to whatever sorts first the moment a second model arrives.
        if isInstalled(defaultSpec) { return defaultSpec }
        if let installed = installedSpecs.first { return installed }
        return defaultSpec
    }
}
