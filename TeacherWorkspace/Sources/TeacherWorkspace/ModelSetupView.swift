import SwiftUI

/// Full-window first-run gate: with no model anywhere, the assistant can't
/// do anything, so setup replaces the UI entirely until the download
/// installs. Model *upgrades* (an older model still works) never come here —
/// they get the non-blocking ModelSetupCard instead.
struct ModelGateView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var downloader = ModelDownloader.shared
    private var t: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "graduationcap")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 76, height: 76)
                .background(Circle().fill(t.accentSoft))
                .padding(.bottom, 18)
            Text("Welcome to \(AppInfo.productName)")
                .font(.system(size: 24, weight: .bold))
            Text("One quick download and your assistant runs privately on this Mac —\nchats, rosters, and student notes stay here.")
                .font(.system(size: 13.5))
                .foregroundStyle(t.sub)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            ModelSetupCard(layout: .gate)
                .frame(maxWidth: 480)
                .padding(.top, 28)
            Spacer()
            Text("One-time download · after this, \(AppInfo.productName) works fully offline")
                .font(.system(size: 11.5))
                .foregroundStyle(t.dim)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.bg)
    }
}

/// Model download UI used two ways: `.gate` inside the first-run gate above,
/// and `.inline` above the composer for non-blocking model upgrades.
/// Disappears on its own once the download verifies and installs.
struct ModelSetupCard: View {
    enum Layout { case inline, gate }
    var layout: Layout = .inline

    @EnvironmentObject var state: AppState
    @ObservedObject private var downloader = ModelDownloader.shared
    private var t: Theme { state.theme }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if layout == .inline {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(t.accent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(t.accentSoft))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
                if case .downloading(let received, let total) = downloader.phase {
                    ProgressView(value: Double(received), total: Double(max(total, 1)))
                        .progressViewStyle(.linear)
                        .tint(t.accent)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            actionButton
        }
        .padding(layout == .gate ? 18 : 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
        .padding(.horizontal, 20)
        .padding(.bottom, layout == .inline ? 4 : 0)
    }

    private var iconName: String { ModelPhaseCopy.icon(downloader.phase) }

    private var title: String {
        switch downloader.phase {
        case .idle: return "One-time setup: download the AI model"
        case .downloading: return "Downloading the AI model…"
        case .paused: return "Download paused"
        case .verifying: return "Verifying download…"
        case .installed: return "Model installed"
        case .failed: return "Download didn't finish"
        }
    }

    private var detail: String {
        let spec = downloader.spec
        switch downloader.phase {
        case .idle:
            return "\(spec.displayName) (\(ModelPhaseCopy.fmt(spec.byteSize))) runs privately on this Mac."
        case .installed:
            return "You're all set — the assistant is ready."
        default:
            return ModelPhaseCopy.progressDetail(downloader.phase) ?? ""
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch downloader.phase {
        case .idle:
            ModelPrimaryButton("Download") { downloader.start() }
        case .downloading:
            ModelSecondaryButton("Pause") { downloader.pause() }
        case .paused:
            ModelPrimaryButton("Resume") { downloader.start() }
        case .failed:
            ModelPrimaryButton("Retry") { downloader.start() }
        case .verifying, .installed:
            EmptyView()
        }
    }
}

/// Download-phase wording shared by the first-run card and the Models page,
/// so the two surfaces can't drift into describing the same state differently.
enum ModelPhaseCopy {
    static func icon(_ phase: ModelDownloader.Phase) -> String {
        switch phase {
        case .failed: return "exclamationmark.triangle"
        case .verifying, .installed: return "checkmark.shield"
        default: return "arrow.down.circle"
        }
    }

    /// The mid-download states, where every surface says the same thing. Nil
    /// for idle and installed — those read differently next to a setup
    /// headline than they do on a card that already names the model.
    static func progressDetail(_ phase: ModelDownloader.Phase) -> String? {
        switch phase {
        case .downloading(let received, let total):
            return "\(fmt(received)) of \(fmt(max(total, 1))) — you can keep exploring while it downloads."
        case .paused(let received):
            return "\(fmt(received)) so far — resume anytime; it picks up where it left off."
        case .verifying:
            return "Checking the file arrived intact."
        case .failed(let message):
            return message
        case .idle, .installed:
            return nil
        }
    }

    static func fmt(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// What a teacher sees when a model wants more memory than the Mac has.
    /// It still downloads and still runs — just slowly, once macOS starts
    /// swapping — so this says that rather than taking the choice away.
    static func ramWarning(_ spec: ModelSpec) -> String {
        let gb = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        return "Built for \(spec.recommendedRAMGB) GB of memory — this Mac has \(gb) GB, so replies will be slow."
    }
}

/// Filled and outlined buttons, shared by the setup card and the Models page.
struct ModelPrimaryButton: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.sendFg)
                .padding(.vertical, 7)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.sendBg))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct ModelSecondaryButton: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.sub)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(t.border))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
