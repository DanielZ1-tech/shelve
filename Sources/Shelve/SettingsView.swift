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
                NewRuleSheet(name: $newRuleName) { name in
                    guard !name.isEmpty,
                          !cfg.config.rules.contains(where: { $0.id == name }) else { return }
                    let rule = ClassifierRule(id: name, extensions: [], keywords: [])
                    cfg.config.rules.append(rule)
                    cfg.save()
                    selectedID = name
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
    let onCreate: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Rule").font(.headline)

            TextField("Folder name (e.g. Screenshots)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(create)

            Text("Files matched by this rule will be moved to a subfolder with this name.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 260)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
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
