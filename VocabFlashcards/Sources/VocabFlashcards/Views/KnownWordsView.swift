import SwiftUI
import VocabKit

/// Manager for the two persistent word banks: the permanent Known list, and the temporary
/// "Almost Known" bank. Words can be sent back to new individually, or a whole bank at
/// once — clearing one never touches the other.
struct KnownWordsView: View {
    @ObservedObject var store: KnownWordsStore
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var searchText = ""
    @State private var showClearConfirm = false

    private var tab: AppState.WordBank { app.knownWordsTab }
    private var isAsideTab: Bool { tab == .aside }

    private var accent: Color { isAsideTab ? Palette.learning : Palette.success }
    private var count: Int { isAsideTab ? store.asideCount : store.count }

    private var entries: [(key: String, display: String)] {
        let all = isAsideTab ? store.sortedAsideEntries : store.sortedEntries
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.display.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            bankPicker
            Divider().opacity(0.4)
            if count == 0 {
                emptyState
            } else {
                searchField
                listBody
            }
            footer
        }
        .frame(width: 460, height: 560)
        .background(Color.surface(scheme))
        // ⌘⇧K / ⌘⇧A switch banks from the menu without going through the segments, so
        // reset the filter here too — otherwise the other bank opens pre-filtered by a
        // search the user can no longer see a reason for.
        .onChange(of: app.knownWordsTab) { _ in
            searchText = ""
            showClearConfirm = false
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(isAsideTab ? "Almost Known" : "Known Words")
                    .font(.rounded(20, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                Text(subtitle)
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Image(systemName: isAsideTab ? "hourglass" : "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var subtitle: String {
        if isAsideTab {
            return "Parked out of the new pile — never counted as known."
        }
        return "\(store.count) word\(store.count == 1 ? "" : "s") remembered across all files"
    }

    /// Segmented switch between the two banks. Counts live here so the size of each bank
    /// is visible without switching.
    private var bankPicker: some View {
        HStack(spacing: 4) {
            bankSegment(.known, "Known", store.count, Palette.success)
            bankSegment(.aside, "Almost", store.asideCount, Palette.learning)
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.06 : 0.04)))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func bankSegment(_ bank: AppState.WordBank, _ title: String,
                             _ value: Int, _ tint: Color) -> some View {
        let selected = tab == bank
        return Button {
            withAnimation(Motion.spring) {
                app.knownWordsTab = bank
                searchText = ""
                showClearConfirm = false
            }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.rounded(13, .semibold))
                Text("\(value)")
                    .font(.rounded(12, .semibold))
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .foregroundStyle(selected ? .white : Color.secondaryText(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondaryText(scheme))
                .font(.system(size: 13, weight: .medium))
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.rounded(14))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.secondaryText(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05)))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(entries, id: \.key) { entry in
                    HStack {
                        Image(systemName: isAsideTab ? "hourglass" : "checkmark.circle.fill")
                            .foregroundStyle(accent)
                            .font(.system(size: 15))
                        Text(entry.display)
                            .font(.rounded(15, .medium))
                            .foregroundStyle(Color.primaryText(scheme))
                        Spacer()
                        Button {
                            withAnimation(Motion.spring) { revert(entry.key) }
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.learning)
                        }
                        .buttonStyle(.plain)
                        .help(isAsideTab
                              ? "Send this word back to new"
                              : "Mark as unknown — move it back to “still learning”")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03)))
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                if entries.isEmpty {
                    Text("No matches for “\(searchText)”")
                        .font(.rounded(13, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func revert(_ key: String) {
        if isAsideTab { app.unmarkAside(key: key) } else { app.unmarkKnown(key: key) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: isAsideTab ? "hourglass" : "sparkles")
                .font(.system(size: 40))
                .foregroundStyle((isAsideTab ? Palette.learning : Palette.indigo).opacity(0.7))
            Text(isAsideTab ? "Nothing set aside" : "No known words yet")
                .font(.rounded(17, .semibold))
                .foregroundStyle(Color.primaryText(scheme))
            Text(isAsideTab
                 ? "Press A while studying to park a word you\nalmost know. It leaves the new pile until\nyou send it back."
                 : "Mark words as known while studying and\nthey'll appear here.")
                .font(.rounded(13, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if count > 0 {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(isAsideTab ? "Revert All to New" : "Clear All",
                          systemImage: isAsideTab ? "arrow.uturn.backward" : "trash")
                }
                .buttonStyle(GhostButtonStyle())
                .confirmationDialog(isAsideTab ? "Send all \(count) words back to new?" : "Remove all known words?",
                                    isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button(isAsideTab ? "Revert All" : "Remove All", role: .destructive) {
                        withAnimation(Motion.spring) {
                            if isAsideTab { app.revertAllAside() } else { app.clearKnownWords() }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(isAsideTab
                         ? "They'll show up as new words again. Your known words aren't affected."
                         : "This clears your entire known-word memory. It can't be undone.")
                }
            }
            Spacer()
            Button("Done") { app.showingKnownWords = false }
                .buttonStyle(FilledButtonStyle())
                .keyboardShortcut(.defaultAction)
            // Hidden Escape handler so the sheet dismisses on Esc too.
            Button("") { app.showingKnownWords = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .padding(16)
        .background(Color.surface(scheme))
        .overlay(Divider().opacity(0.4), alignment: .top)
    }
}
