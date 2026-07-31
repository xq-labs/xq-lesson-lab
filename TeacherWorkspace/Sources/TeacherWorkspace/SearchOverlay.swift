import SwiftUI

struct SearchOverlay: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    private var t: Theme { state.theme }

    var body: some View {
        ZStack(alignment: .top) {
            t.scrim
                .ignoresSafeArea()
                .onTapGesture { state.searchOpen = false }
            VStack(spacing: 0) {
                searchField
                Rectangle().fill(t.border).frame(height: 1)
                resultsList
            }
            .frame(width: 620)
            .frame(maxHeight: 460)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(t.border))
            .shadow(color: .black.opacity(t.isDark ? 0.55 : 0.25), radius: 30, y: 20)
            .padding(.top, 110)
        }
        .onAppear { focused = true }
        .onExitCommand { state.searchOpen = false }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.dim)
            TextField("Search chats, rubrics, activities, PoGs…", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(t.text)
                .focused($focused)
            Text("esc")
                .font(.system(size: 11))
                .foregroundStyle(t.dim)
                .padding(.vertical, 1)
                .padding(.horizontal, 5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(t.border))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if !state.query.trimmingCharacters(in: .whitespaces).isEmpty && state.searchHits.isEmpty {
                    Text("No matches for “\(state.query)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(t.dim)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                }
                ForEach(state.searchGroups, id: \.label) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.label.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .kerning(0.66)
                            .foregroundStyle(t.dim)
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                        ForEach(group.items) { item in
                            resultRow(item)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func resultRow(_ item: AppState.SearchHit) -> some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(item.meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: t.hover)
    }
}
