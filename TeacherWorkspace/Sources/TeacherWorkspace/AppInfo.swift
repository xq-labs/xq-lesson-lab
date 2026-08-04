import Foundation

/// Product identity in one place. The name is still settling, so every
/// user-visible mention reads from here instead of hardcoding a string —
/// renaming again means editing this file plus the plist in make-app.sh.
enum AppInfo {
    static let productName = "XQ Lesson Lab"

    /// Marketing version + build number. make-app.sh reads these into the
    /// Info.plist, and the appcast must match — bump both here per release.
    static let version = "1.0.1"
    static let build = 2

    /// Bundle assembled by make-app.sh; kept in sync with it by hand.
    static let appBundleName = "\(productName).app"

    /// Folder under ~/Library/Application Support. No space, so shell paths
    /// in scripts and probes don't need quoting.
    static let supportDirectory = "LessonLab"

    // MARK: - Distribution endpoints

    /// GitHub repo that hosts release assets (DMG, update zips, model).
    static let githubRepo = "xq-labs/xq-lesson-lab"

    /// Landing page (Vercel). Also hosts the Sparkle appcast.
    /// Vercel names the project after the repo by default; if you pick a
    /// different name or a custom domain, update this and rebuild.
    static let websiteURL = "https://xq-lesson-lab.vercel.app"
    static let appcastURL = "\(websiteURL)/appcast.xml"

    /// Always points at the newest DMG (fixed asset name per release).
    static let latestDMGURL = "https://github.com/\(githubRepo)/releases/latest/download/Lesson-Lab.dmg"

    /// The model lives in its own fixed-tag release so app updates never
    /// re-upload 1.2 GB; a model upgrade is a new tag + new constants here.
    static let modelDownloadURL = "https://github.com/\(githubRepo)/releases/download/model-qwen3.5-2b/Qwen3.5-2B-Q4_K_M.gguf"
    static let modelSHA256 = "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"
    static let modelByteSize: Int64 = 1_280_835_840

    /// Domains school IT departments need to allow for download + updates.
    static let allowlistDomains = ["github.com", "objects.githubusercontent.com",
                                   URL(string: websiteURL)?.host ?? "xq-lesson-lab.vercel.app"]
}
