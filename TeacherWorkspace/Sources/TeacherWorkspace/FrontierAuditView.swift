import SwiftUI
import AppKit

/// Every request that has ever left this Mac, newest first, with the exact
/// bytes still attached.
///
/// There is deliberately no "Clear log" button. An audit trail a user can
/// silently erase is not an audit trail — the file sits in Application
/// Support and can be deleted by hand if someone truly means to.
struct FrontierAuditView: View {
    @EnvironmentObject var state: AppState
    var dismiss: () -> Void

    @State private var entries: [FrontierAuditEntry] = []
    @State private var expanded: Set<String> = []

    private var t: Theme { state.theme }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Off-device review log")
                .font(.system(size: 16, weight: .bold))
            Text("Everything this app has sent outside your Mac. Blocked attempts are here too — they show the check working.")
                .font(.system(size: 12))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)

            if entries.isEmpty {
                Text("Nothing has ever been sent from this Mac.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(t.dim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in row(entry) }
                    }
                }
                .frame(maxHeight: 380)
            }

            HStack {
                Button("Export…") { export() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(t.card)
        .onAppear { entries = FrontierAuditLog.recent() }
    }

    @ViewBuilder
    private func row(_ entry: FrontierAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: entry.phase))
                    .font(.system(size: 11))
                    .foregroundStyle(tint(for: entry.phase))
                Text(Self.stamp.string(from: entry.at))
                    .font(.system(size: 12, weight: .medium))
                Text("· \(entry.modelId)")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
                Spacer()
                Text(entry.phase == "blocked" ? entry.gateVerdict : "\(entry.requestBytes) bytes")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
            }

            if let title = entry.subjectTitle {
                Text(title).font(.system(size: 11.5)).foregroundStyle(t.sub)
            }
            Text("\(entry.host)\(entry.path)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(t.dim)
            if let error = entry.error {
                Text(error).font(.system(size: 11)).foregroundStyle(t.red)
            }

            if let payload = entry.payload {
                Button {
                    if expanded.contains(entry.id) { expanded.remove(entry.id) }
                    else { expanded.insert(entry.id) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded.contains(entry.id)
                              ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("See exactly what was sent")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)

                if expanded.contains(entry.id) {
                    ScrollView {
                        Text(payload)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(t.sub)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 6).fill(t.input))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(t.bg))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border))
    }

    private func icon(for phase: String) -> String {
        switch phase {
        case "completed": return "checkmark.circle"
        case "blocked": return "hand.raised"
        case "failed": return "exclamationmark.circle"
        default: return "arrow.up.circle"
        }
    }

    private func tint(for phase: String) -> Color {
        switch phase {
        case "completed": return t.green
        case "blocked": return t.warn
        case "failed": return t.red
        default: return t.sub
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "off-device-review-log.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FrontierAuditLog.markdownTranscript().write(to: url, atomically: true,
                                                         encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
