import SwiftUI
import VocabKit

/// Simple manager for the global known-word list. Lets the user search and remove words
/// they've forgotten. Removing a word means it will show up again in future study runs.
struct KnownWordsView: View {
    @ObservedObject var store: KnownWordsStore
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var searchText = ""
    @State private var showClearConfirm = false

    private var entries: [(key: String, display: String)] {
        let all = store.sortedEntries
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.display.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if store.count == 0 {
                emptyState
            } else {
                searchField
                listBody
            }
            footer
        }
        .frame(width: 460, height: 560)
        .background(Color.surface(scheme))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Known Words")
                    .font(.rounded(20, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                Text("\(store.count) word\(store.count == 1 ? "" : "s") remembered across all files")
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Palette.success)
        }
        .padding(20)
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
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.success)
                            .font(.system(size: 15))
                        Text(entry.display)
                            .font(.rounded(15, .medium))
                            .foregroundStyle(Color.primaryText(scheme))
                        Spacer()
                        Button {
                            withAnimation(Motion.spring) { app.unmarkKnown(key: entry.key) }
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.learning)
                        }
                        .buttonStyle(.plain)
                        .help("Mark as unknown — move it back to “still learning”")
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Palette.indigo.opacity(0.7))
            Text("No known words yet")
                .font(.rounded(17, .semibold))
                .foregroundStyle(Color.primaryText(scheme))
            Text("Mark words as known while studying and\nthey'll appear here.")
                .font(.rounded(13, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if store.count > 0 {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(GhostButtonStyle())
                .confirmationDialog("Remove all known words?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("Remove All", role: .destructive) {
                        withAnimation(Motion.spring) { app.clearKnownWords() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears your entire known-word memory. It can't be undone.")
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
