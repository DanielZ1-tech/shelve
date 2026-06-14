import AppKit
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            RulesSettingsTab()
                .tabItem { Label("Rules", systemImage: "folder.badge.gearshape") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 500)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {

    @ObservedObject var cfg = ConfigManager.shared

    var body: some View {
        Form {
            Section("Watched Folders") {
                ForEach(cfg.config.watchDirs, id: \.self) { dir in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text((dir as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 13))
                        Spacer()
                        Button {
                            cfg.config.watchDirs.removeAll { $0 == dir }
                            cfg.save()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(cfg.config.watchDirs.count <= 1)
                    }
                }
                Button(action: addFolder) {
                    Label("Add Folder…", systemImage: "plus")
                }
            }

            Section("Automation") {
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
        }
        .formStyle(.grouped)
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

// MARK: - Rules Tab

struct RulesSettingsTab: View {

    @ObservedObject var cfg = ConfigManager.shared
    @State private var selectedID: String? = nil
    @State private var showingNewRule = false
    @State private var newRuleName = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(cfg.config.rules, id: \.id, selection: $selectedID) { rule in
                    Label(rule.id, systemImage: iconName(for: rule.id))
                        .tag(rule.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button {
                        newRuleName = ""
                        showingNewRule = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(8)

                    Spacer()

                    if let sid = selectedID {
                        Button {
                            cfg.config.rules.removeAll { $0.id == sid }
                            cfg.save()
                            selectedID = cfg.config.rules.first?.id
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(width: 160)
            .sheet(isPresented: $showingNewRule) {
                NewRuleSheet(
                    name: $newRuleName,
                    existingNames: cfg.config.rules.map(\.id)
                ) { rule in
                    cfg.config.rules.append(rule)
                    cfg.save()
                    selectedID = rule.id
                }
            }

            Divider()

            if let sid = selectedID,
               let idx = cfg.config.rules.firstIndex(where: { $0.id == sid }) {
                RuleEditorView(
                    rule: cfg.config.rules[idx],
                    onSave: { updated in
                        cfg.config.rules[idx] = updated
                        cfg.save()
                    }
                )
                .id(sid)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Select a rule to edit")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func iconName(for id: String) -> String {
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

// MARK: - New Rule Sheet

struct NewRuleSheet: View {
    @Binding var name: String
    let existingNames: [String]
    let onCreate: (ClassifierRule) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var extensions: [String] = []
    @State private var keywords:   [String] = []
    @State private var conditions: [FileCondition] = []
    @State private var newExt      = ""
    @State private var moveToTrash = false
    @State private var aiPrompt    = ""
    @State private var isGenerating = false
    @State private var parsedSummary: [String] = []
    @State private var activeTab   = 0   // 0 = Smart, 1 = Manual

    private var isDuplicate: Bool { existingNames.contains(name.trimmingCharacters(in: .whitespaces)) }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isDuplicate }

    private let presets: [(label: String, icon: String, folder: String, exts: [String])] = [
        ("Documents",  "doc.fill",          "Documents",  [".pdf",".doc",".docx",".txt",".pages",".md"]),
        ("Images",     "photo.fill",         "Images",     [".jpg",".jpeg",".png",".gif",".webp",".heic"]),
        ("Videos",     "film.fill",          "Videos",     [".mp4",".mov",".avi",".mkv",".m4v"]),
        ("Audio",      "music.note",         "Audio",      [".mp3",".wav",".aac",".flac",".m4a"]),
        ("Archives",   "archivebox.fill",    "Archives",   [".zip",".tar",".gz",".rar",".7z"]),
        ("Code",       "chevron.left.forwardslash.chevron.right","Code",[".py",".js",".ts",".swift",".sh",".go"]),
        ("Installers", "shippingbox.fill",   "Installers", [".dmg",".pkg"]),
        ("Design",     "paintpalette.fill",  "Design",     [".psd",".ai",".sketch",".fig",".xd"]),
        ("Ebooks",     "book.fill",          "Ebooks",     [".epub",".mobi",".azw"]),
        ("3D",         "cube.fill",          "3D",         [".stl",".obj",".fbx",".blend"]),
        ("Spreadsheets","tablecells.fill",   "Spreadsheets",[".xlsx",".csv",".numbers"]),
        ("Fonts",      "textformat",         "Fonts",      [".ttf",".otf",".woff",".woff2"]),
    ]

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            HStack {
                Text("New Rule")
                    .font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // ── Tab picker ───────────────────────────────────────────────────
            Picker("", selection: $activeTab) {
                Label("Smart", systemImage: "sparkles").tag(0)
                Label("Manual", systemImage: "slider.horizontal.3").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if activeTab == 0 {
                smartTab
            } else {
                manualTab
            }

            Divider()

            // ── Footer ───────────────────────────────────────────────────────
            HStack(spacing: 12) {
                // Preview
                if isValid {
                    HStack(spacing: 5) {
                        Image(systemName: moveToTrash ? "trash.fill" : "folder.fill")
                            .foregroundColor(moveToTrash ? .red : .accentColor)
                            .font(.system(size: 11))
                        Text(moveToTrash ? "Trash" : name.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(moveToTrash ? .red : .accentColor)
                        if !extensions.isEmpty {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(extensions.prefix(3).joined(separator: " "))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if isDuplicate {
                    Label("Name already used", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                Spacer()
                Button("Create Rule", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 540)
    }

    // MARK: - Smart Tab

    private var smartTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // AI prompt
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe your rule in plain English")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        TextField("e.g. trash big installers, move old PDFs to Archive…", text: $aiPrompt)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit(parseAI)
                        if isGenerating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Parse") { parseAI() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.purple.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.purple.opacity(0.2)))

                    // Example chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach([
                                "trash installers > 200MB",
                                "old PDFs to Archive",
                                "images from internet",
                                "partial downloads",
                                "large videos",
                                "files before 6am",
                                "receipts and invoices",
                                "design files to Design",
                            ], id: \.self) { ex in
                                Button { aiPrompt = ex; parseAI() } label: {
                                    Text(ex)
                                        .font(.system(size: 11))
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.purple.opacity(0.08)))
                                        .overlay(Capsule().strokeBorder(Color.purple.opacity(0.2)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Parsed result
                if !parsedSummary.isEmpty || isValid {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Result")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            // Folder name
                            HStack {
                                Label("Folder", systemImage: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                TextField("Folder name", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }

                            if !parsedSummary.isEmpty {
                                Divider()
                                ForEach(parsedSummary, id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: 12))
                                }
                            }

                            if !extensions.isEmpty {
                                Divider()
                                Text("Extensions")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TagWrapView(tags: extensions) { tag in
                                    extensions.removeAll { $0 == tag }
                                }
                            }

                            if !keywords.isEmpty {
                                Divider()
                                Text("Keywords (filename must contain one)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TagWrapView(tags: keywords) { tag in
                                    keywords.removeAll { $0 == tag }
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.12)))
                    }
                }

                if isDuplicate {
                    Label("A rule named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Manual Tab

    private var manualTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Folder name
                VStack(alignment: .leading, spacing: 6) {
                    Label("Folder Name", systemImage: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. Screenshots", text: $name)
                        .textFieldStyle(.roundedBorder)
                    if isDuplicate {
                        Label("Already exists", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundColor(.orange)
                    }
                }

                // Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(presets, id: \.folder) { p in
                            Button {
                                name = p.folder; extensions = p.exts
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: p.icon)
                                        .font(.system(size: 15))
                                        .foregroundColor(name == p.folder ? .white : .accentColor)
                                    Text(p.label)
                                        .font(.system(size: 10))
                                        .foregroundColor(name == p.folder ? .white : .primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(name == p.folder ? Color.accentColor : Color.secondary.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Extensions
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Extensions")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    if !extensions.isEmpty {
                        TagWrapView(tags: extensions) { tag in extensions.removeAll { $0 == tag } }
                    }
                    HStack {
                        TextField(".ext", text: $newExt)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit(addExt)
                        Button("Add", action: addExt)
                            .disabled(newExt.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                    }
                }

                // Trash toggle
                Toggle(isOn: $moveToTrash) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(moveToTrash ? .red : .secondary)
                        Text("Trash matched files instead of moving")
                            .font(.system(size: 13))
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func addExt() {
        var e = newExt.trimmingCharacters(in: .whitespaces).lowercased()
        if !e.hasPrefix(".") { e = "." + e }
        guard e != ".", !extensions.contains(e) else { return }
        extensions.append(e)
        newExt = ""
    }

    private func parseAI() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }
        isGenerating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let result   = AIRuleCreator.parse(prompt)
            name         = result.folderName
            extensions   = result.extensions.sorted()
            keywords     = result.keywords
            conditions   = result.conditions
            moveToTrash  = result.moveToTrash
            parsedSummary = result.summary
            aiPrompt     = ""
            isGenerating = false
        }
    }

    private func create() {
        let folderName = name.trimmingCharacters(in: .whitespaces)
        guard !folderName.isEmpty else { return }
        var rule = ClassifierRule(id: folderName, extensions: Array(Set(extensions)),
                                  keywords: keywords, conditions: conditions)
        rule.moveToTrash = moveToTrash
        onCreate(rule)
        name = ""; extensions = []; keywords = []; conditions = []; parsedSummary = []
        dismiss()
    }
}

// MARK: - Rule Editor

struct RuleEditorView: View {

    let rule: ClassifierRule
    let onSave: (ClassifierRule) -> Void

    @State private var extensions: [String]
    @State private var keywords: [String]
    @State private var conditions: [FileCondition]
    @State private var renameRules: [RenameRule]
    @State private var moveToTrash: Bool
    @State private var newExt = ""
    @State private var newKw  = ""

    init(rule: ClassifierRule, onSave: @escaping (ClassifierRule) -> Void) {
        self.rule   = rule
        self.onSave = onSave
        _extensions  = State(initialValue: rule.extensions)
        _keywords    = State(initialValue: rule.keywords)
        _conditions  = State(initialValue: rule.conditions)
        _renameRules = State(initialValue: rule.renameRules)
        _moveToTrash = State(initialValue: rule.moveToTrash)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(rule.id).font(.title2.bold())

                // MARK: Extensions
                GroupBox("File Extensions") {
                    VStack(alignment: .leading, spacing: 10) {
                        TagWrapView(tags: extensions) { tag in
                            extensions.removeAll { $0 == tag }
                            save()
                        }
                        HStack {
                            TextField(".ext", text: $newExt)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onSubmit(addExt)
                            Button("Add", action: addExt)
                                .disabled(newExt.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(6)
                }

                // MARK: Keywords
                GroupBox("Keywords") {
                    VStack(alignment: .leading, spacing: 10) {
                        TagWrapView(tags: keywords) { tag in
                            keywords.removeAll { $0 == tag }
                            save()
                        }
                        HStack {
                            TextField("keyword", text: $newKw)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit(addKw)
                            Button("Add", action: addKw)
                                .disabled(newKw.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(6)
                }

                // MARK: Conditions
                GroupBox("Conditions") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(conditions.indices, id: \.self) { i in
                            ConditionRow(condition: $conditions[i]) {
                                conditions.remove(at: i)
                                save()
                            }
                            if i < conditions.count - 1 { Divider() }
                        }
                        Button {
                            conditions.append(FileCondition())
                            save()
                        } label: {
                            Label("Add Condition", systemImage: "plus")
                        }
                        if !conditions.isEmpty {
                            Text("File moves if it matches an extension or keyword, OR any condition below.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }

                // MARK: Rename Rules
                GroupBox("Auto-Rename") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(renameRules.indices, id: \.self) { i in
                            RenameRuleRow(rule: $renameRules[i]) {
                                renameRules.remove(at: i)
                                save()
                            }
                            if i < renameRules.count - 1 { Divider() }
                        }
                        Button {
                            renameRules.append(RenameRule())
                            save()
                        } label: {
                            Label("Add Rename Step", systemImage: "plus")
                        }
                        if !renameRules.isEmpty {
                            Text("Steps apply in order before moving the file.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }

                // MARK: Move to Trash
                GroupBox {
                    Toggle(isOn: $moveToTrash) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .foregroundColor(moveToTrash ? .red : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Move to Trash instead of folder")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Matched files will be trashed rather than sorted.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: moveToTrash) { _, _ in save() }
                    .padding(6)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: Helpers

    private func save() {
        onSave(ClassifierRule(
            id: rule.id,
            extensions: extensions,
            keywords: keywords,
            conditions: conditions,
            renameRules: renameRules,
            moveToTrash: moveToTrash
        ))
    }

    private func addExt() {
        var t = newExt.trimmingCharacters(in: .whitespaces).lowercased()
        if !t.hasPrefix(".") { t = ".\(t)" }
        guard !t.isEmpty, t != ".", !extensions.contains(t) else { newExt = ""; return }
        extensions.append(t); newExt = ""; save()
    }

    private func addKw() {
        let t = newKw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, !keywords.contains(t) else { newKw = ""; return }
        keywords.append(t); newKw = ""; save()
    }
}

// MARK: - Rename Rule Row

struct RenameRuleRow: View {
    @Binding var rule: RenameRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $rule.operation) {
                ForEach(RenameRule.Operation.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            // Show value field only for ops that need it
            if rule.operation == .addPrefix || rule.operation == .addSuffix {
                TextField("text", text: $rule.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            } else if rule.operation == .addDatePrefix {
                TextField("yyyy-MM-dd", text: $rule.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Tag Components

struct TagWrapView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { tag in
                        TagChip(label: tag) { onRemove(tag) }
                    }
                }
            }
        }
    }

    private func rows() -> [[String]] {
        var result: [[String]] = []
        var i = 0
        while i < tags.count {
            result.append(Array(tags[i..<min(i + 6, tags.count)]))
            i += 6
        }
        return result
    }
}

struct TagChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .foregroundColor(.primary)
    }
}

// MARK: - Condition Row

struct ConditionRow: View {
    @Binding var condition: FileCondition
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("", selection: $condition.kind) {
                    ForEach(FileCondition.Kind.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 200)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            // Sub-controls per kind
            Group {
                switch condition.kind {

                case .date:
                    HStack(spacing: 6) {
                        Picker("", selection: $condition.dateField) {
                            ForEach(FileCondition.DateField.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }.labelsHidden().frame(width: 120)

                        Picker("", selection: $condition.dateOp) {
                            ForEach(FileCondition.DateOperator.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }.labelsHidden().frame(width: 100)

                        TextField("", value: $condition.dateValue, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 44)

                        Picker("", selection: $condition.dateUnit) {
                            ForEach(FileCondition.DateUnit.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }.labelsHidden().frame(width: 70)
                    }

                case .timeOfDay:
                    HStack(spacing: 6) {
                        Text("Between")
                        Picker("", selection: $condition.timeFrom) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }.labelsHidden().frame(width: 80)
                        Text("and")
                        Picker("", selection: $condition.timeTo) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }.labelsHidden().frame(width: 80)
                        Text("(based on creation time)")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }

                case .fromInternet:
                    Text("Matches files that were downloaded from the web (have quarantine flag).")
                        .font(.system(size: 11)).foregroundColor(.secondary)

                case .partialDownload:
                    Text("Matches .crdownload, .download, .part, .tmp and other incomplete files.")
                        .font(.system(size: 11)).foregroundColor(.secondary)

                case .fileSize:
                    HStack(spacing: 6) {
                        Text("Size is")
                        Picker("", selection: $condition.sizeOp) {
                            ForEach(FileCondition.SizeOperator.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }.labelsHidden().frame(width: 110)
                        TextField("", value: $condition.sizeMB, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 60)
                        Text("MB")
                    }

                case .namePattern:
                    HStack(spacing: 6) {
                        Text("Name")
                        Picker("", selection: $condition.nameOp) {
                            ForEach(FileCondition.NameOperator.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }.labelsHidden().frame(width: 110)
                        TextField("pattern", text: $condition.namePattern)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                    }
                }
            }
            .padding(.leading, 8)
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let suffix = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display):00 \(suffix)"
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "folder.fill.badge.gearshape")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("Shelve").font(.largeTitle.bold())
            Text("Version 2.0 · Native macOS")
                .foregroundColor(.secondary)
            Divider().frame(width: 200)
            Text("Automatic Downloads organizer\nwith TF-IDF powered search.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
