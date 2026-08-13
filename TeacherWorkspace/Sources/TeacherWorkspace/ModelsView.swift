import SwiftUI

/// Manage the on-device models: pick which one answers, download another, and
/// delete the ones taking up gigabytes. Reached from the model line under the
/// composer and from Settings.
struct ModelsView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    /// Set while the teacher confirms a delete — a model file is a multi-GB
    /// download, so removing one always asks first.
    @State private var pendingDelete: ModelSpec?

    var body: some View {
        LibraryPage(
            title: "Models",
            subtitle: "The assistant runs on one of these, entirely on this Mac. Chats, rosters, and student notes stay here."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(ModelCatalog.all) { spec in
                    ModelCard(spec: spec,
                              downloader: ModelDownloader.downloader(for: spec),
                              onDelete: { pendingDelete = spec })
                }
            }
            storageNote
                .padding(.top, 18)
        }
        .alert("Delete \(pendingDelete?.displayName ?? "this model")?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let spec = pendingDelete { state.deleteModel(spec) }
                pendingDelete = nil
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        guard let spec = pendingDelete else { return "" }
        let freed = ModelPhaseCopy.fmt(spec.byteSize)
        // Losing the only model isn't a small thing — say so plainly rather
        // than letting the app drop back to the setup screen unannounced.
        let others = ModelCatalog.installedSpecs.filter { $0.id != spec.id }
        if others.isEmpty {
            return "This frees \(freed), and leaves no model installed — the assistant can't reply until you download one again."
        }
        if spec.id == state.activeModel.id, let next = others.first {
            return "This frees \(freed). The assistant will switch to \(next.displayName)."
        }
        return "This frees \(freed). You can download it again anytime."
    }

    private var storageNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
                    .padding(.top, 1)
                Text("Models are stored in ~/Library/Application Support/\(AppInfo.supportDirectory)/Models. Downloads come from Hugging Face; if your school network blocks them, ask IT to allow \(AppInfo.allowlistDomains.joined(separator: ", ")).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Meta's licence asks for this notice wherever Llama is offered.
            Text("Built with Llama.")
                .font(.system(size: 11))
                .foregroundStyle(t.dim)
                .padding(.leading, 18)
        }
    }
}

/// One model: what it is, whether it's here, and the one action that makes
/// sense right now.
private struct ModelCard: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    let spec: ModelSpec
    @ObservedObject var downloader: ModelDownloader
    let onDelete: () -> Void

    private var isInstalled: Bool { ModelCatalog.isInstalled(spec) }
    private var isActive: Bool { isInstalled && spec.id == state.activeModel.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(spec.blurb)
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if spec.exceedsSystemRAM {
                ramWarningChip
                    .padding(.top, 4)
            }
            if let progress = ModelPhaseCopy.progressDetail(downloader.phase) {
                Text(progress)
                    .font(.system(size: 12))
                    .foregroundStyle(isFailed ? t.red : t.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if case .downloading(let received, let total) = downloader.phase {
                ProgressView(value: Double(received), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(t.accent)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            footer
                .padding(.top, 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isActive ? t.accent.opacity(0.55) : t.border))
    }

    private var isFailed: Bool {
        if case .failed = downloader.phase { return true }
        return false
    }

    /// Amber, not red: this model runs, it just runs badly on this machine.
    /// Loud enough that nobody starts a 5 GB download without seeing it.
    private var ramWarningChip: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.warn)
                .padding(.top, 1)
            Text(ModelPhaseCopy.ramWarning(spec))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(t.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.warnSoft))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(t.warn.opacity(0.35)))
    }

    private var header: some View {
        // The tile is sized to the three lines beside it (name, specs,
        // licence) rather than to the icon — a smaller square left the row
        // looking top-heavy.
        HStack(spacing: 11) {
            Image(systemName: "cpu")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isInstalled ? t.accent : t.dim)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isInstalled ? t.accentSoft : t.hover))
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                // "16 GB+" rather than "16 GB or more": the wider tile leaves
                // just enough room for one line, and a wrapped word here made
                // the cards in a row different heights.
                Text("\(spec.tier) · \(ModelPhaseCopy.fmt(spec.byteSize)) · \(spec.recommendedRAMGB) GB+ RAM")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
                Text(spec.license)
                    .font(.system(size: 10.5))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if isActive {
                Circle().fill(t.green).frame(width: 7, height: 7)
                Text("Active")
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
            } else if !isInstalled && !spec.available {
                Text("Coming soon")
                    .font(.system(size: 12))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
            if ModelCatalog.isRemovable(spec) {
                deleteButton
            }
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        if isInstalled {
            if !isActive {
                // One request at a time: switching mid-placement would queue
                // behind the whole pipeline and read as a hang.
                ModelPrimaryButton("Use this model") { state.selectModel(spec) }
                    .disabled(state.isEvaluating)
                    .opacity(state.isEvaluating ? 0.5 : 1)
                    .help(state.isEvaluating ? "Finishing the current Skill Check first" : "")
            }
        } else {
            switch downloader.phase {
            case .downloading:
                ModelSecondaryButton("Pause") { downloader.pause() }
            case .paused:
                ModelPrimaryButton("Resume") { downloader.start() }
            case .failed:
                ModelPrimaryButton("Retry") { downloader.start() }
            case .verifying:
                EmptyView()
            case .idle, .installed:
                if spec.canDownload {
                    ModelPrimaryButton("Download") { downloader.start() }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.sub)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: t.hover)
        .help("Delete this model from this Mac")
    }
}

/// Quick switcher hanging off the model line under the composer: the models
/// that are here, one click to swap, and a way through to the full page.
struct ModelPickerPopover: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ON-DEVICE MODEL")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.66)
                .foregroundStyle(t.dim)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(ModelCatalog.all) { spec in
                ModelPickerRow(spec: spec,
                               downloader: ModelDownloader.downloader(for: spec),
                               onDismiss: onDismiss)
            }
            if state.isEvaluating {
                Text("Finishing the current Skill Check first.")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            Rectangle().fill(t.border).frame(height: 1)
                .padding(.vertical, 5)
            Button {
                onDismiss()
                state.setView(.models)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(t.sub)
                        .frame(width: 16)
                    Text("Manage models…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(t.text)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover)
        }
        .padding(6)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(t.card)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
                .shadow(color: .black.opacity(t.isDark ? 0.55 : 0.25), radius: 30, y: 20)
        )
    }

}

/// A row in the picker. Its own view so the download progress it shows keeps
/// ticking while the popover is open.
private struct ModelPickerRow: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    let spec: ModelSpec
    @ObservedObject var downloader: ModelDownloader
    var onDismiss: () -> Void

    var body: some View {
        let installed = ModelCatalog.isInstalled(spec)
        let active = installed && spec.id == state.activeModel.id
        Button {
            if installed {
                state.selectModel(spec)
                onDismiss()
            } else if spec.canDownload {
                // Stay put — the row turns into a progress line the teacher
                // can watch, and the composer keeps working meanwhile.
                downloader.start()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: active ? "checkmark.circle.fill" : (installed ? "circle" : "arrow.down.circle"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? t.accent : t.dim)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spec.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.text)
                    HStack(spacing: 4) {
                        // Same amber as the card's chip, so the caution reads
                        // the same here as it does on the Models page.
                        if spec.exceedsSystemRAM {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(t.warn)
                        }
                        Text(rowDetail(installed: installed))
                            .font(.system(size: 11))
                            .foregroundStyle(spec.exceedsSystemRAM ? t.warn : t.dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: t.hover)
        .disabled(active || state.isEvaluating || (!installed && !spec.canDownload))
        .opacity(!installed && !spec.canDownload ? 0.55 : 1)
    }

    private func rowDetail(installed: Bool) -> String {
        if installed {
            let state = spec.id == self.state.activeModel.id ? "in use" : "installed"
            return spec.exceedsSystemRAM
                ? "\(spec.tier) · \(state) · slow on this Mac"
                : "\(spec.tier) · \(state)"
        }
        switch downloader.phase {
        case .downloading(let received, let total):
            return "Downloading — \(ModelPhaseCopy.fmt(received)) of \(ModelPhaseCopy.fmt(max(total, 1)))"
        case .paused(let received):
            return "Paused at \(ModelPhaseCopy.fmt(received))"
        case .verifying:
            return "Verifying…"
        case .failed:
            return "Download didn't finish — open Manage models"
        case .idle, .installed:
            guard spec.canDownload else { return "\(spec.tier) · coming soon" }
            return spec.exceedsSystemRAM
                ? "Needs \(spec.recommendedRAMGB) GB · download \(ModelPhaseCopy.fmt(spec.byteSize))"
                : "\(spec.tier) · download \(ModelPhaseCopy.fmt(spec.byteSize))"
        }
    }
}
