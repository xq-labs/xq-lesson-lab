import Foundation

/// Product identity in one place. The name is still settling, so every
/// user-visible mention reads from here instead of hardcoding a string —
/// renaming again means editing this file plus the plist in make-app.sh.
enum AppInfo {
    static let productName = "XQ Lesson Lab"

    /// Marketing version + build number. make-app.sh reads these into the
    /// Info.plist, and the appcast must match — bump both here per release.
    static let version = "1.0.2"
    static let build = 3

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

    /// Models are described one spec at a time in ModelCatalog.swift — each
    /// with its own fixed-tag release, checksum, and size.

    /// Domains school IT departments need to allow for download + updates.
    /// Hugging Face serves every model but the default (GitHub release assets
    /// stop at 2 GB), redirecting from huggingface.co to its CDN.
    static let allowlistDomains = ["github.com", "objects.githubusercontent.com",
                                   "huggingface.co", "cdn.hf.co", "cdn-lfs.hf.co",
                                   URL(string: websiteURL)?.host ?? "xq-lesson-lab.vercel.app"]
}
