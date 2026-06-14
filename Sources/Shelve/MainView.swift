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
            Divider()
            Group {
                switch section {
                case .rules:    RulesMainView()
                case .history:  HistoryMainView()
                case .settings: SettingsMainView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
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
                    .frame(width: 34, height: 34)
                    .cornerRadius(8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shelve").font(.system(size: 14, weight: .semibold))
                    Text("v2.1").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            // Nav
            VStack(spacing: 2) {
                ForEach(MainSection.allCases) { s in
                    Button(action: { section = s }) {
                        HStack(spacing: 10) {
                            Image(systemName: s.icon)
                                .font(.system(size: 13))
                                .frame(width: 18)
                                .foregroundColor(section == s ? .accentColor : .secondary)
                            Text(s.rawValue)
                                .font(.system(size: 13))
                                .foregroundColor(section == s ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(section == s ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

            // Status footer
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                HStack(spacing: 6) {
                    Circle()
                        .fill(cfg.config.autoClassify ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(cfg.config.autoClassify ? "Auto-classify on" : "Auto-classify off")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 180)
        .background(Color(NSColor.windowBackgroundColor))
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

    var body: some View {
        HStack(spacing: 0) {

            // Rule list column
            VStack(spacing: 0) {

                // AI creator bar
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                            .font(.system(size: 13))
                        TextField("Describe a rule in plain English…", text: $aiPrompt)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit { Task { await createWithAI() } }
                        if isGenerating {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Button("Create") { Task { await createWithAI() } }
                                .font(.system(size: 11, weight: .medium))
                                .buttonStyle(.plain)
                                .foregroundColor(.purple)
                                .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.purple.opacity(0.07))

                    if let err = aiError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                // Rule list
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(cfg.config.rules) { rule in
                            RuleListRow(
                                rule: rule,
                                isSelected: selectedID == rule.id,
                                onSelect:  { selectedID = rule.id },
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

                // Bottom toolbar
                HStack {
                    Button { showNewRuleSheet = true } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .help("New Rule")

                    Spacer()

                    if let sid = selectedID, cfg.config.rules.contains(where: { $0.id == sid }) {
                        Button {
                            cfg.config.rules.removeAll { $0.id == sid }
                            cfg.save()
                            selectedID = cfg.config.rules.first?.id
                        } label: {
                            Image(systemName: "minus").font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .help("Delete Rule")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .frame(width: 220)
            .sheet(isPresented: $showNewRuleSheet) {
                NewRuleSheet(name: $newRuleName) { name in
                    guard !name.isEmpty,
                          !cfg.config.rules.contains(where: { $0.id == name }) else { return }
                    cfg.config.rules.append(ClassifierRule(id: name, extensions: [], keywords: []))
                    cfg.save()
                    selectedID = name
                }
            }

            Divider()

            // Rule editor
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
                        .font(.system(size: 52))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Select a rule to edit")
                        .foregroundColor(.secondary)
                    Button("New Rule") { showNewRuleSheet = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @MainActor
    private func createWithAI() async {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }
        isGenerating = true
        aiError = nil
        // Small delay so the spinner shows
        try? await Task.sleep(nanoseconds: 150_000_000)
        let rule = AIRuleCreator.createRule(from: prompt)
        cfg.config.rules.append(rule)
        cfg.save()
        selectedID = rule.id
        aiPrompt = ""
        isGenerating = false
    }
}

// MARK: - Rule List Row

struct RuleListRow: View {
    let rule: ClassifierRule
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(rule.isEnabled ? .accentColor : .secondary.opacity(0.35))
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
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .padding(.horizontal, 4)
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
        let entries = cfg.recentMoves(limit: 500)
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                Text("\(entries.count) moves").foregroundColor(.secondary).font(.system(size: 12))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.3))
                    Text("No history yet").foregroundColor(.secondary)
                    Text("Run a classify to get started.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HistoryRow(entry: entry)
                            Divider().padding(.horizontal, 20)
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.destination == "🗑 Trash" ? "trash.fill" : "arrow.right.circle.fill")
                .foregroundColor(entry.destination == "🗑 Trash" ? .red : .green)
                .font(.system(size: 16))

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
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}

// MARK: - Settings Main View

struct SettingsMainView: View {
    @ObservedObject var cfg = ConfigManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2.bold())

                // Watched Folders
                GroupBox("Watched Folders") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cfg.config.watchDirs, id: \.self) { dir in
                            HStack {
                                Image(systemName: "folder.fill").foregroundColor(.accentColor)
                                Text((dir as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(size: 13))
                                Spacer()
                                Button {
                                    cfg.config.watchDirs.removeAll { $0 == dir }
                                    cfg.save()
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .disabled(cfg.config.watchDirs.count <= 1)
                            }
                        }
                        Button(action: addFolder) {
                            Label("Add Folder…", systemImage: "plus")
                        }
                    }
                    .padding(8)
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
                                Slider(
                                    value: Binding(
                                        get: { Double(cfg.config.classifyInterval) },
                                        set: { cfg.config.classifyInterval = Int($0); cfg.save() }
                                    ),
                                    in: 10...300, step: 10
                                )
                                Text("\(cfg.config.classifyInterval)s")
                                    .frame(width: 40, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(8)
                }

                // About
                GroupBox("About") {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable().frame(width: 44, height: 44).cornerRadius(10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shelve").font(.system(size: 15, weight: .semibold))
                            Text("Version 2.1 · Native macOS 26")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Text("Automatic Downloads organizer with AI-powered rules.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
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
