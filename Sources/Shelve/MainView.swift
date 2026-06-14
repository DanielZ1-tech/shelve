import SwiftUI
import AppKit

// MARK: - Navigation

enum MainSection: String, CaseIterable, Identifiable {
    case rules    = "Rules"
    case history  = "History"
    case settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .rules:    return "folder.badge.gearshape"
        case .history:  return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Root View

struct MainView: View {
    @State private var section: MainSection = .rules

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section)
                .frame(width: 196)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .fixedSize(horizontal: true, vertical: false)

            Divider()

            ZStack {
                RulesMainView()   .opacity(section == .rules    ? 1 : 0)
                HistoryMainView() .opacity(section == .history  ? 1 : 0)
                SettingsMainView().opacity(section == .settings ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 520)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var section: MainSection
    @ObservedObject var cfg = ConfigManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // App header
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .cornerRadius(8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shelve")
                        .font(.system(size: 14, weight: .semibold))
                    Text("v2.1")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Nav items
            VStack(spacing: 2) {
                ForEach(MainSection.allCases) { s in
                    SidebarItem(label: s.rawValue, icon: s.icon, active: section == s) {
                        section = s
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            // Footer
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(cfg.config.autoClassify ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(cfg.config.autoClassify ? "Auto on" : "Auto off")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct SidebarItem: View {
    let label: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(active ? .accentColor : .secondary)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(active ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rules Main View

struct RulesMainView: View {
    @ObservedObject var cfg = ConfigManager.shared
    @State private var selectedID: String? = nil
    @State private var aiPrompt = ""
    @State private var isGenerating = false
    @State private var aiError: String? = nil
    @State private var showNewRuleSheet = false
    @State private var newRuleName = ""

    private let hints = [
        "e.g. trash installers bigger than 200MB",
        "e.g. move PDFs older than 30 days to Archive",
        "e.g. files downloaded between midnight and 3am",
        "e.g. partial or failed downloads",
        "e.g. images larger than 50MB",
    ]
    @State private var hintIndex = 0

    var body: some View {
        HSplitView {

            // ── Left column: list ───────────────────────────────────────────
            VStack(spacing: 0) {

                // AI bar
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)

                        TextField(hints[hintIndex], text: $aiPrompt)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit { parse() }

                        if isGenerating {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            Button("Create") { parse() }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.purple))
                                .buttonStyle(.plain)
                                .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.purple.opacity(0.06))

                    if let err = aiError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                        withAnimation { hintIndex = (hintIndex + 1) % hints.count }
                    }
                }

                Divider()

                // Rule list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cfg.config.rules) { rule in
                            RuleListRow(
                                rule: rule,
                                isSelected: selectedID == rule.id,
                                onSelect: { selectedID = rule.id },
                                onToggle: {
                                    if let i = cfg.config.rules.firstIndex(where: { $0.id == rule.id }) {
                                        cfg.config.rules[i].isEnabled.toggle()
                                        cfg.save()
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }

                Divider()

                // Toolbar
                HStack {
                    Button { showNewRuleSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .help("New Rule")

                    Spacer()

                    if let sid = selectedID,
                       cfg.config.rules.contains(where: { $0.id == sid }) {
                        Button {
                            cfg.config.rules.removeAll { $0.id == sid }
                            cfg.save()
                            selectedID = cfg.config.rules.first?.id
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .help("Delete Rule")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 216, idealWidth: 216, maxWidth: 216, maxHeight: .infinity)
            .sheet(isPresented: $showNewRuleSheet) {
                NewRuleSheet(name: $newRuleName) { name in
                    guard !name.isEmpty,
                          !cfg.config.rules.contains(where: { $0.id == name }) else { return }
                    cfg.config.rules.append(ClassifierRule(id: name, extensions: [], keywords: []))
                    cfg.save()
                    selectedID = name
                }
            }

            // ── Right column: editor ────────────────────────────────────────
            ZStack {
                if let sid = selectedID,
                   let idx = cfg.config.rules.firstIndex(where: { $0.id == sid }) {
                    RuleEditorView(rule: cfg.config.rules[idx]) { updated in
                        cfg.config.rules[idx] = updated
                        cfg.save()
                    }
                    .id(sid)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.25))
                        Text("Select a rule to edit")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                        Button("New Rule") { showNewRuleSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func parse() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }
        isGenerating = true
        aiError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let rule = AIRuleCreator.createRule(from: prompt)
            cfg.config.rules.append(rule)
            cfg.save()
            selectedID = rule.id
            aiPrompt = ""
            isGenerating = false
        }
    }
}

// MARK: - Rule List Row

struct RuleListRow: View {
    let rule: ClassifierRule
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(rule.isEnabled ? .accentColor : .secondary.opacity(0.3))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            Image(systemName: folderIcon(rule.id))
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .accentColor : .secondary)

            Text(rule.id)
                .font(.system(size: 13))
                .foregroundColor(rule.isEnabled ? .primary : .secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .padding(.horizontal, 6)
    }

    private func folderIcon(_ id: String) -> String {
        switch id {
        case "Documents":     return "doc.fill"
        case "Images":        return "photo.fill"
        case "Videos":        return "film.fill"
        case "Audio":         return "music.note"
        case "Code":          return "chevron.left.forwardslash.chevron.right"
        case "Archives":      return "archivebox.fill"
        case "3D":            return "cube.fill"
        case "Spreadsheets":  return "tablecells.fill"
        case "Presentations": return "play.rectangle.fill"
        case "Fonts":         return "textformat"
        case "Installers":    return "shippingbox.fill"
        default:              return "folder.fill"
        }
    }
}

// MARK: - History Main View

struct HistoryMainView: View {
    @ObservedObject var cfg = ConfigManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.title3.bold())
                Spacer()
                let count = cfg.recentMoves(limit: 1000).count
                Text("\(count) move\(count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            let entries = cfg.recentMoves(limit: 500)
            if entries.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.25))
                    Text("No history yet")
                        .foregroundColor(.secondary)
                    Text("Classify some files to see moves here.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HistoryRow(entry: entry)
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    private var isTrash: Bool { entry.destination.contains("Trash") }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isTrash ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: isTrash ? "trash.fill" : "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(isTrash ? .red : .green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("→ \(entry.destination)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(entry.timestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Settings Main View

struct SettingsMainView: View {
    @ObservedObject var cfg = ConfigManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title3.bold())
                    .padding(.top, 4)

                // Watched Folders
                GroupBox("Watched Folders") {
                    VStack(alignment: .leading, spacing: 10) {
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        let presets: [(label: String, icon: String, path: String)] = [
                            ("Downloads", "arrow.down.circle.fill",
                             (home as NSString).appendingPathComponent("Downloads")),
                            ("Desktop",   "desktopcomputer",
                             (home as NSString).appendingPathComponent("Desktop")),
                            ("Documents", "doc.fill",
                             (home as NSString).appendingPathComponent("Documents")),
                        ]

                        // Preset quick-toggles
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.path) { preset in
                                let on = cfg.config.watchDirs.contains(preset.path)
                                Button {
                                    if on {
                                        guard cfg.config.watchDirs.count > 1 else { return }
                                        cfg.config.watchDirs.removeAll { $0 == preset.path }
                                    } else {
                                        cfg.config.watchDirs.append(preset.path)
                                    }
                                    cfg.save()
                                    FileWatcher.shared.start(watching: ConfigManager.shared.watchURLs)
                                } label: {
                                    Label(preset.label, systemImage: preset.icon)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(on ? Color.accentColor : Color.secondary.opacity(0.12))
                                        )
                                        .foregroundColor(on ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                                .help(on ? "Remove \(preset.label) from watched folders" : "Watch \(preset.label)")
                            }
                        }

                        Divider()

                        // All active watched folders with remove
                        ForEach(cfg.config.watchDirs, id: \.self) { dir in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 13))
                                Text((dir as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    guard cfg.config.watchDirs.count > 1 else { return }
                                    cfg.config.watchDirs.removeAll { $0 == dir }
                                    cfg.save()
                                    FileWatcher.shared.start(watching: ConfigManager.shared.watchURLs)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(cfg.config.watchDirs.count <= 1)
                                .help("Remove folder")
                            }
                        }

                        Button(action: addFolder) {
                            Label("Add Custom Folder…", systemImage: "plus")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                }

                // Automation
                GroupBox("Automation") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Auto-classify new files", isOn: Binding(
                            get: { cfg.config.autoClassify },
                            set: { cfg.config.autoClassify = $0; cfg.save() }
                        ))
                        if cfg.config.autoClassify {
                            HStack {
                                Text("Check every")
                                    .font(.system(size: 13))
                                Slider(
                                    value: Binding(
                                        get: { Double(cfg.config.classifyInterval) },
                                        set: { cfg.config.classifyInterval = Int($0); cfg.save() }
                                    ),
                                    in: 10...300, step: 10
                                )
                                Text("\(cfg.config.classifyInterval)s")
                                    .frame(width: 38, alignment: .trailing)
                                    .monospacedDigit()
                                    .font(.system(size: 13))
                            }
                        }
                    }
                    .padding(10)
                }

                // Rule Creator
                GroupBox("Smart Rule Creator") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type a plain-English description in the Rules tab and press Enter to create a rule instantly.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach([
                                "trash installers bigger than 200MB",
                                "move PDFs older than 30 days to Archive",
                                "files downloaded between midnight and 3am",
                                "partial or failed downloads",
                            ], id: \.self) { example in
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                        .foregroundColor(.purple)
                                    Text(example)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(10)
                }

                // About
                GroupBox("About") {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 44, height: 44)
                            .cornerRadius(10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shelve")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Version 2.1 · Native macOS 26")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Watch This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !cfg.config.watchDirs.contains(path) else { return }
        cfg.config.watchDirs.append(path)
        cfg.save()
        FileWatcher.shared.start(watching: ConfigManager.shared.watchURLs)
        DispatchQueue.global(qos: .background).async {
            SearchEngine.shared.reindex(watchURLs: ConfigManager.shared.watchURLs)
        }
    }
}
