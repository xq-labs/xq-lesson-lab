import Foundation

/// The privacy promise, in one place.
///
/// This does for the claim what `AppInfo.productName` does for the name, and
/// for the same reason: it was repeated verbatim across a dozen views, and a
/// promise that lives in a dozen places drifts. It drifted the moment
/// off-device review shipped.
///
/// The rule this file encodes: **weaken only where the claim actually became
/// conditional.** The absolutes that survive are the ones on the roster,
/// classroom, chat, and Skill Check screens — the FERPA surface, where nothing
/// changed and nothing will. Blanket-weakening every string would give away
/// the strongest part of the pitch to describe a feature most teachers will
/// never turn on.
enum PrivacyCopy {

    /// Off, or no key. For that install this is still literally true, so it
    /// is still what that teacher reads.
    static let localOnly = """
        The AI model runs entirely on this Mac. Chats, rosters, and student \
        notes never leave it.
        """

    /// Configured. The honest version.
    static let localFirst = """
        The AI model runs entirely on this Mac. Chats, rosters, and student \
        notes stay here — nothing is sent anywhere unless you ask for a second \
        opinion and approve exactly what goes.
        """

    static func promise(frontierEnabled: Bool) -> String {
        frontierEnabled ? localFirst : localOnly
    }

    /// The settings-popover version, which has room to name the exception and
    /// the thing that is never excepted.
    static func settingsPromise(frontierEnabled: Bool) -> String {
        guard frontierEnabled else {
            return "Private by design — " + localOnly.prefix(1).lowercased() + localOnly.dropFirst()
        }
        return """
            Private by design — the AI runs on this Mac, and your chats, rosters, \
            and student notes stay here. The one exception is a second opinion, \
            which you start by hand and see in full before it sends. Student work \
            in Skill Check is never sent, at all.
            """
    }

    /// Short form, for tight spaces.
    static func short(frontierEnabled: Bool) -> String {
        frontierEnabled
            ? "Runs on this Mac. Nothing leaves without your say-so."
            : "Runs on this Mac. Nothing leaves it."
    }
}
