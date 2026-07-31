import SwiftUI

/// Shown above the composer while the on-device model isn't installed yet
/// (ship-small builds download it on first launch). Disappears on its own
/// once the download verifies and installs.
struct ModelSetupCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var downloader = ModelDownloader.shared
    private var t: Theme { state.theme }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(t.accentSoft))
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
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
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
