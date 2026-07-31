import Foundation
import Sparkle

/// Sparkle auto-updates. The updater only runs from the assembled .app —
/// the feed URL and signing key live in its Info.plist (written by
/// make-app.sh), and a bare `swift run` dev build has neither.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    let isAvailable: Bool
    private let controller: SPUStandardUpdaterController

    private init() {
        isAvailable = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(
            startingUpdater: isAvailable, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
