import Foundation

// MARK: - Search Results

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let folder: String
    let path: URL
    let ext: String
    let score: Double

    var badgeText: String {
        let map: [String: String] = [
            ".pdf": "PDF", ".docx": "DOC", ".doc": "DOC", ".txt": "TXT", ".md": "MD",
            ".xlsx": "XLS", ".pptx": "PPT", ".jpg": "IMG", ".jpeg": "IMG", ".png": "IMG",
            ".heic": "IMG", ".webp": "IMG", ".mp4": "VID", ".mov": "VID", ".mp3": "AUD",
            ".zip": "ZIP", ".dmg": "DMG", ".py": "PY", ".js": "JS", ".html": "WEB",
            ".stl": "3D", ".blend": "3D", ".epub": "BOOK", ".swift": "SWF",
        ]
        return map[ext.lowercased()] ?? "FILE"
    }
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let fileName: String
    let destination: String
}

// MARK: - File Move Log

struct FileMove: Codable {
    let timestamp: Date
    let fileName: String
    let fromPath: String
    let toFolder: String
}

// MARK: - App Config

struct ShelveConfig: Codable {
    var watchDirs: [String]
    var autoClassify: Bool
    var classifyInterval: Int   // seconds
    var rules: [ClassifierRule]

    static var `default`: ShelveConfig {
        ShelveConfig(
            watchDirs: [FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Downloads").path],
            autoClassify: true,
            classifyInterval: 60,
            rules: ClassifierRule.defaults
        )
    }
}

// MARK: - Date Condition

struct DateCondition: Codable, Identifiable {
    var id: UUID = UUID()

    enum DateField: String, Codable, CaseIterable {
        case created     = "Date Created"
        case modified    = "Date Modified"
        case lastOpened  = "Last Opened"
    }
    enum DateOperator: String, Codable, CaseIterable {
        case olderThan = "is older than"
        case newerThan = "is newer than"
    }
    enum DateUnit: String, Codable, CaseIterable {
        case days   = "days"
        case weeks  = "weeks"
        case months = "months"
    }

    var field:    DateField    = .modified
    var op:       DateOperator = .olderThan
    var value:    Int          = 30
    var unit:     DateUnit     = .days

    /// Returns the threshold date and whether the file's attribute date satisfies this condition.
    func matches(url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return false }

        let fileDate: Date?
        switch field {
        case .created:
            fileDate = attrs[.creationDate] as? Date
        case .modified:
            fileDate = attrs[.modificationDate] as? Date
        case .lastOpened:
            // kMDItemLastUsedDate via extended attributes; fall back to modification date
            let resourceValues = try? url.resourceValues(forKeys: [.contentAccessDateKey])
            fileDate = resourceValues?.contentAccessDate ?? attrs[.modificationDate] as? Date
        }

        guard let date = fileDate else { return false }

        let calendar = Calendar.current
        let now = Date()
        let threshold: Date?
        switch unit {
        case .days:   threshold = calendar.date(byAdding: .day,   value: -value, to: now)
        case .weeks:  threshold = calendar.date(byAdding: .weekOfYear, value: -value, to: now)
        case .months: threshold = calendar.date(byAdding: .month, value: -value, to: now)
        }
        guard let t = threshold else { return false }

        switch op {
        case .olderThan: return date < t
        case .newerThan: return date > t
        }
    }
}

// MARK: - Rename Rule

struct RenameRule: Codable, Identifiable {
    var id: UUID = UUID()

    enum Operation: String, Codable, CaseIterable {
        case addDatePrefix   = "Add date prefix"
        case lowercase       = "Lowercase"
        case replaceSpaces   = "Replace spaces with underscores"
        case addPrefix       = "Add custom prefix"
        case addSuffix       = "Add custom suffix"
    }

    var operation: Operation = .addDatePrefix
    var value: String = ""   // used for prefix/suffix value, or date format

    func apply(to filename: String, fileURL: URL) -> String {
        let name = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        switch operation {
        case .addDatePrefix:
            let fmt = DateFormatter()
            fmt.dateFormat = value.isEmpty ? "yyyy-MM-dd" : value
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let date = (attrs?[.creationDate] as? Date) ?? Date()
            return "\(fmt.string(from: date))_\(name)\(suffix)"

        case .lowercase:
            return filename.lowercased()

        case .replaceSpaces:
            return name.replacingOccurrences(of: " ", with: "_") + suffix

        case .addPrefix:
            return "\(value)\(name)\(suffix)"

        case .addSuffix:
            return "\(name)\(value)\(suffix)"
        }
    }
}

// MARK: - Classifier Rule

struct ClassifierRule: Codable, Identifiable {
    var id: String          // folder name
    var extensions: [String]
    var keywords: [String]
    var dateConditions: [DateCondition] = []
    var renameRules: [RenameRule] = []
    var moveToTrash: Bool = false

    static var defaults: [ClassifierRule] {
        [
            ClassifierRule(id:"Documents",
                extensions: [".pdf", ".doc", ".docx", ".txt", ".rtf", ".odt",
                             ".pages", ".md", ".epub", ".mobi"],
                keywords: ["report", "invoice", "resume", "cv", "letter",
                           "contract", "agreement", "notes", "essay", "draft"]),

            ClassifierRule(id:"Spreadsheets",
                extensions: [".xlsx", ".xls", ".csv", ".numbers", ".ods"],
                keywords: ["budget", "finance", "data", "sheet", "table",
                           "tracker", "ledger", "accounts"]),

            ClassifierRule(id:"Presentations",
                extensions: [".pptx", ".ppt", ".key", ".odp"],
                keywords: ["slides", "deck", "presentation", "pitch"]),

            ClassifierRule(id:"Images",
                extensions: [".jpg", ".jpeg", ".png", ".gif", ".webp",
                             ".heic", ".heif", ".tiff", ".bmp", ".svg", ".raw"],
                keywords: ["photo", "image", "screenshot", "picture", "wallpaper"]),

            ClassifierRule(id:"Videos",
                extensions: [".mp4", ".mov", ".avi", ".mkv", ".wmv",
                             ".m4v", ".flv", ".webm"],
                keywords: ["video", "movie", "film", "clip", "recording"]),

            ClassifierRule(id:"Audio",
                extensions: [".mp3", ".wav", ".aac", ".flac", ".m4a",
                             ".ogg", ".wma", ".aiff"],
                keywords: ["audio", "music", "podcast", "song", "track"]),

            ClassifierRule(id:"Archives",
                extensions: [".zip", ".tar", ".gz", ".rar", ".7z",
                             ".bz2", ".xz", ".dmg", ".pkg"],
                keywords: ["archive", "backup", "compressed"]),

            ClassifierRule(id:"Code",
                extensions: [".py", ".js", ".ts", ".swift", ".java", ".c",
                             ".cpp", ".h", ".rs", ".go", ".rb", ".php",
                             ".html", ".css", ".json", ".yaml", ".sh"],
                keywords: ["script", "code", "source", "app", "project"]),

            ClassifierRule(id:"3D",
                extensions: [".stl", ".obj", ".fbx", ".blend", ".3ds",
                             ".step", ".stp", ".iges", ".f3d"],
                keywords: ["model", "mesh", "3d", "print", "cad"]),

            ClassifierRule(id:"Fonts",
                extensions: [".ttf", ".otf", ".woff", ".woff2"],
                keywords: ["font", "typeface"]),

            ClassifierRule(id:"Installers",
                extensions: [".dmg", ".pkg", ".exe", ".msi"],
                keywords: ["installer", "setup", "install"]),
        ]
    }
}
