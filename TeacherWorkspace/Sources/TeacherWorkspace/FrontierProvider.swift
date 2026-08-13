import Foundation

/// What a frontier model sends back: three strengths, three suggestions, and
/// a couple of questions worth sitting with. Small on purpose — a review a
/// teacher won't finish reading changes nothing.
struct ReviewSuggestion: Codable, Equatable, Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    /// The numbered step or criterion this is about, when there is one. Lets
    /// the card offer "Edit step 3" instead of making the teacher hunt.
    var stepNumber: Int?
}

struct ReviewResult: Codable, Equatable {
    var strengths: [String]
    var suggestions: [ReviewSuggestion]
    var questions: [String]
}

/// Where a provider's credential comes from.
///
/// This enum is the whole reason the protocol exists. v1 ships `.userKey`
/// only — the teacher's own key, in their own Keychain, under their own
/// agreement with the provider. An XQ-hosted proxy would be `.hosted`, and
/// the consent sheet, the redaction gate, and the audit log all sit *above*
/// this protocol, so adding it changes the transport and one copy string
/// rather than the feature.
enum FrontierCredential {
    case userKey(Keychain.Item)
    case hosted(URL)
}

protocol FrontierProvider {
    var id: String { get }
    var displayName: String { get }
    var modelId: String { get }
    var modelDisplayName: String { get }
    /// Named in the firewall error so school IT has a string to paste.
    var host: String { get }
    var credential: FrontierCredential { get }
    var isConfigured: Bool { get }

    func review(_ payload: ReviewPayload, lexicon: PIILexicon) async throws -> ReviewResult
}

/// Everything that can go wrong, in the order a teacher meets it.
///
/// Two rules hold across every message: the firewall case names the exact
/// hostname, and every failure ends by saying what still works. The app is
/// not broken — one optional feature is.
enum FrontierError: LocalizedError {
    case noKey
    case blocked([RedactionGate.Finding])
    case offline
    case blockedByNetwork(host: String)
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case outOfCredit
    case overloaded
    case refused(category: String?)
    case truncated
    case badResponse(status: Int)
    case malformed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No API key yet. Add one in Second opinions to turn this on."
        case .blocked:
            return "Not sent. The check found something that looks like a student's name."
        case .offline:
            return "No internet connection. Second opinions need one — everything "
                + "else in the app works offline."
        case .blockedByNetwork(let host):
            return "Couldn't reach \(host). School networks often block outside "
                + "services — ask your IT team to allow \(host). Everything else in "
                + "the app keeps working without it."
        case .unauthorized:
            return "That key wasn't accepted. Check you copied the whole thing from "
                + "console.anthropic.com — they start with sk-ant- and they're long."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Anthropic is asking us to slow down. Try again in about "
                    + "\(retryAfter) second\(retryAfter == 1 ? "" : "s")."
            }
            return "Anthropic is asking us to slow down. Wait about a minute and try again."
        case .outOfCredit:
            return "Your Anthropic account is out of credit. Add funds at "
                + "console.anthropic.com and try again — your key is still fine."
        case .overloaded:
            return "Anthropic's servers are having trouble. This one's not on you — "
                + "try again in a few minutes."
        case .refused:
            return "Claude declined to review this one. That's unusual for a lesson "
                + "plan — if it keeps happening, something in the text may have "
                + "tripped its safety filters."
        case .truncated:
            return "The review was cut short before it finished."
        case .badResponse(let status):
            return "Anthropic returned an unexpected error (\(status)). Nothing was "
                + "saved — try again, and everything else in the app keeps working."
        case .malformed:
            return "The reply came back garbled. Nothing was saved — try again."
        case .cancelled:
            return "Stopped. Nothing was sent."
        }
    }

    /// What the teacher can actually do about it, rendered as its own line
    /// under the message. Every case has one — an error that leaves someone
    /// with nowhere to go is a bug in this feature, and `TW_REVIEW_ERRORS`
    /// fails the build if one appears.
    var nextStep: String {
        switch self {
        case .noKey:
            return "Add a key to turn second opinions on."
        case .blocked:
            return "Take it out of the text above, then send again."
        case .offline:
            return "Everything else in the app works offline — try this again "
                + "when you're back on a network."
        case .blockedByNetwork(let host):
            return "Ask your IT team to allow \(host). Nothing else in the app needs it."
        case .unauthorized:
            return "Paste the key again, or make a new one at console.anthropic.com."
        case .rateLimited:
            return "Wait a moment, then send again."
        case .outOfCredit:
            return "Add funds at console.anthropic.com — your key is still fine."
        case .overloaded:
            return "Try again in a few minutes."
        case .refused:
            return "Try a different document. If it keeps happening on ordinary "
                + "plans, that's worth reporting."
        case .truncated:
            return "Send again — it usually finishes on a second try."
        case .badResponse, .malformed:
            return "Send again. Nothing was saved, and the rest of the app is unaffected."
        case .cancelled:
            return "Send again whenever you're ready."
        }
    }

    /// Trying again is worth offering for these and misleading for the rest.
    var isWorthRetrying: Bool {
        switch self {
        case .offline, .rateLimited, .overloaded, .badResponse, .malformed, .truncated:
            return true
        case .noKey, .blocked, .blockedByNetwork, .unauthorized, .outOfCredit,
             .refused, .cancelled:
            return false
        }
    }

    /// Maps URLSession's transport failures onto the cases above. Mirrors
    /// `ModelDownloader.friendlyMessage` in intent: say what happened, and
    /// what to do about it.
    static func from(urlError: URLError, host: String) -> FrontierError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateUntrusted:
            return .blockedByNetwork(host: host)
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .overloaded
        default:
            return .badResponse(status: urlError.errorCode)
        }
    }
}
