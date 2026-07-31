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
            Text("One quick download and your assistant runs privately on this Mac —\nchats, rosters, and student notes never leave it.")
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

    private var iconName: String {
        switch downloader.phase {
        case .failed: return "exclamationmark.triangle"
        case .verifying, .installed: return "checkmark.shield"
        default: return "arrow.down.circle"
        }
    }

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
        switch downloader.phase {
        case .idle:
            return "\(LlamaBackend.modelDisplayName) (\(Self.fmt(AppInfo.modelByteSize))) runs privately on this Mac — nothing you type ever leaves it."
        case .downloading(let received, let total):
            return "\(Self.fmt(received)) of \(Self.fmt(max(total, 1))) — you can keep exploring while it downloads."
        case .paused(let received):
            return "\(Self.fmt(received)) so far — resume anytime; it picks up where it left off."
        case .verifying:
            return "Checking the file arrived intact."
        case .installed:
            return "You're all set — the assistant is ready."
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch downloader.phase {
        case .idle:
            primaryButton("Download") { downloader.start() }
        case .downloading:
            secondaryButton("Pause") { downloader.pause() }
        case .paused:
            primaryButton("Resume") { downloader.start() }
        case .failed:
            primaryButton("Retry") { downloader.start() }
        case .verifying, .installed:
            EmptyView()
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
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

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
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

    private static func fmt(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
