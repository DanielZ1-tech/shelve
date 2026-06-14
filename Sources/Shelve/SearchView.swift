import SwiftUI

// MARK: - Glass effect compatibility shim

private extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
} 

// MARK: - Liquid Glass Search View (macOS 26 / Tahoe)

struct SearchView: View {

    @StateObject private var vm = SearchViewModel()
    @FocusState  private var fieldFocused: Bool

    private let blue   = Color(red: 0,     green: 0.478, blue: 1)
    private let purple = Color(red: 0.655, green: 0.545, blue: 0.980)

    var body: some View {
        VStack(spacing: 0) {

            // ── Search bar ───────────────────────────────────────────────────
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)

                TextField("Search files…", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($fieldFocused)
                    .onSubmit { vm.openSelected() }

                if vm.isSearching {
                    ProgressView().scaleEffect(0.55).padding(.trailing, 4)
                }

                // Mode pill
                Button(action: vm.toggleMode) {
                    Text(vm.mode == .files ? "Files" : "History")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(vm.mode == .files ? blue : purple))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                // Close button
                Button(action: { NSApp.keyWindow?.close() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .glass(in: Circle())
                .padding(.trailing, 12)
                .help("Close  ⎋")
            }
            .frame(height: 52)

            // ── Results drop-down ────────────────────────────────────────────
            if vm.hasContent {
                Divider().opacity(0.2)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if vm.mode == .files {
                            ForEach(Array(vm.results.enumerated()), id: \.element.id) { i, r in
                                GlassFileRow(result: r, isSelected: vm.selectedIndex == i)
                                    .onTapGesture { vm.selectedIndex = i; vm.openSelected() }
                                    .onHover { if $0 { vm.selectedIndex = i } }
                            }
                        } else {
                            ForEach(Array(vm.historyResults.enumerated()), id: \.element.id) { i, e in
                                GlassHistoryRow(entry: e, isSelected: vm.selectedIndex == i)
                                    .onTapGesture { vm.selectedIndex = i; vm.openSelected() }
                                    .onHover { if $0 { vm.selectedIndex = i } }
                            }
                        }
                        if vm.showNoResults {
                            Text("No results")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                                .padding(.vertical, 18)
                        }
                    }
                }
                .frame(maxHeight: 384)

                // ── Footer ───────────────────────────────────────────────────
                Divider().opacity(0.2)
                HStack {
                    Text("↩ open  ·  ↑↓ navigate  ·  Tab switch  ·  ⎋ close")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let n = vm.resultCount {
                        Text("\(n) result\(n == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
        }
        // Real liquid glass — refracts what's behind the window
        .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(.clear)
        .onAppear { fieldFocused = true }
        .onKeyPress(.upArrow)   { vm.navigate(-1); return .handled }
        .onKeyPress(.downArrow) { vm.navigate( 1); return .handled }
        .onKeyPress(.tab)       { vm.toggleMode();  return .handled }
        .onKeyPress(.escape)    { NSApp.keyWindow?.close(); return .handled }
    }
}

// MARK: - File Row

struct GlassFileRow: View {

    let result: SearchResult
    let isSelected: Bool
    private let blue = Color(red: 0, green: 0.478, blue: 1)
    private let purple = Color(red: 0.655, green: 0.545, blue: 0.980)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Badge
                Text(result.badgeText)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .glass(in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: 42, alignment: .center)

                Text(result.fileName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Relevance bar
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.07)).frame(width: 28, height: 3)
                    Capsule()
                        .fill(LinearGradient(colors: [blue, purple],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, 28 * result.score), height: 3)
                }

                Text(result.folder)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(isSelected ? blue.opacity(0.08) : .clear)
            .contentShape(Rectangle())

            Divider().opacity(0.12).padding(.leading, 16)
        }
    }
}

// MARK: - History Row

struct GlassHistoryRow: View {

    let entry: HistoryEntry
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(entry.timestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 70, alignment: .leading)

                Text(entry.fileName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("→ \(entry.destination)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(isSelected ? Color.orange.opacity(0.08) : .clear)
            .contentShape(Rectangle())

            Divider().opacity(0.12).padding(.leading, 16)
        }
    }
}

// MARK: - View Model

enum SearchMode { case files, history }

@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query          = "" { didSet { scheduleSearch() } }
    @Published var mode           = SearchMode.files { didSet { runSearch() } }
    @Published var results        : [SearchResult]  = []
    @Published var historyResults : [HistoryEntry]  = []
    @Published var selectedIndex  = 0
    @Published var isSearching    = false

    var hasContent: Bool  { !results.isEmpty || !historyResults.isEmpty || showNoResults }
    var showNoResults: Bool {
        !query.isEmpty && !isSearching &&
        (mode == .files ? results.isEmpty : historyResults.isEmpty)
    }
    var resultCount: Int? {
        guard !query.isEmpty else { return nil }
        return mode == .files ? results.count : historyResults.count
    }

    private var debounceTask: Task<Void, Never>?

    func toggleMode() { mode = mode == .files ? .history : .files; selectedIndex = 0 }

    func navigate(_ delta: Int) {
        let count = mode == .files ? results.count : historyResults.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    func openSelected() {
        if mode == .files {
            guard selectedIndex < results.count else { return }
            let p = results[selectedIndex].path
            if FileManager.default.fileExists(atPath: p.path) {
                NSWorkspace.shared.activateFileViewerSelecting([p])
            }
        } else {
            guard selectedIndex < historyResults.count else { return }
            let e = historyResults[selectedIndex]
            for base in ConfigManager.shared.watchURLs {
                let c = base.appendingPathComponent(e.destination)
                              .appendingPathComponent(e.fileName)
                if FileManager.default.fileExists(atPath: c.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([c]); return
                }
            }
        }
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []; historyResults = []; return
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; historyResults = []; return }
        isSearching = true
        let m = mode
        Task {
            if m == .files {
                let hits = await Task.detached(priority: .userInitiated) {
                    SearchEngine.shared.search(query: q)
                }.value
                results = hits
            } else {
                historyResults = historySearch(q)
            }
            selectedIndex = 0
            isSearching = false
        }
    }

    nonisolated func historySearch(_ q: String) -> [HistoryEntry] {
        ConfigManager.shared.recentMoves(limit: 100).filter {
            $0.fileName.localizedCaseInsensitiveContains(q) ||
            $0.destination.localizedCaseInsensitiveContains(q)
        }
    }
}
