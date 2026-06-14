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

// MARK: - File Condition

struct FileCondition: Codable, Identifiable {
    var id: UUID = UUID()
    var kind: Kind = .date

    enum CodingKeys: String, CodingKey {
        case id, kind, dateField, dateOp, dateValue, dateUnit
        case timeFrom, timeTo, sizeOp, sizeMB, nameOp, namePattern
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decode(UUID.self,          forKey: .id))          ?? UUID()
        kind        = (try? c.decode(Kind.self,          forKey: .kind))        ?? .date
        dateField   = (try? c.decode(DateField.self,     forKey: .dateField))   ?? .modified
        dateOp      = (try? c.decode(DateOperator.self,  forKey: .dateOp))      ?? .olderThan
        dateValue   = (try? c.decode(Int.self,           forKey: .dateValue))   ?? 30
        dateUnit    = (try? c.decode(DateUnit.self,      forKey: .dateUnit))    ?? .days
        timeFrom    = (try? c.decode(Int.self,           forKey: .timeFrom))    ?? 0
        timeTo      = (try? c.decode(Int.self,           forKey: .timeTo))      ?? 6
        sizeOp      = (try? c.decode(SizeOperator.self,  forKey: .sizeOp))      ?? .largerThan
        sizeMB      = (try? c.decode(Double.self,        forKey: .sizeMB))      ?? 100
        nameOp      = (try? c.decode(NameOperator.self,  forKey: .nameOp))      ?? .contains
        namePattern = (try? c.decode(String.self,        forKey: .namePattern)) ?? ""
    }

    // MARK: Condition kind
    enum Kind: String, Codable, CaseIterable {
        case date          = "Date"
        case timeOfDay     = "Time of Day"
        case fromInternet  = "Downloaded from Internet"
        case partialDownload = "Partial / Failed Download"
        case fileSize      = "File Size"
        case namePattern   = "Name Pattern"
    }

    // MARK: Date sub-fields
    enum DateField: String, Codable, CaseIterable {
        case created    = "Date Created"
        case modified   = "Date Modified"
        case lastOpened = "Last Opened"
    }
    enum DateOperator: String, Codable, CaseIterable {
        case olderThan = "older than"
        case newerThan = "newer than"
    }
    enum DateUnit: String, Codable, CaseIterable {
        case days   = "days"
        case weeks  = "weeks"
        case months = "months"
    }

    // MARK: Size sub-fields
    enum SizeOperator: String, Codable, CaseIterable {
        case largerThan  = "larger than"
        case smallerThan = "smaller than"
    }

    // MARK: Name sub-fields
    enum NameOperator: String, Codable, CaseIterable {
        case contains   = "contains"
        case startsWith = "starts with"
        case endsWith   = "ends with"
        case matches    = "matches regex"
    }

    // Date fields
    var dateField: DateField    = .modified
    var dateOp:    DateOperator = .olderThan
    var dateValue: Int          = 30
    var dateUnit:  DateUnit     = .days

    // Time of day fields (hour 0–23, wraps midnight if from > to)
    var timeFrom: Int = 0
    var timeTo:   Int = 6

    // File size fields
    var sizeOp: SizeOperator = .largerThan
    var sizeMB: Double       = 100

    // Name pattern fields
    var nameOp:      NameOperator = .contains
    var namePattern: String       = ""

    // MARK: Evaluation
    func matches(url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return false }

        switch kind {

        case .date:
            let fileDate: Date?
            switch dateField {
            case .created:    fileDate = attrs[.creationDate] as? Date
            case .modified:   fileDate = attrs[.modificationDate] as? Date
            case .lastOpened:
                let rv = try? url.resourceValues(forKeys: [.contentAccessDateKey])
                fileDate = rv?.contentAccessDate ?? attrs[.modificationDate] as? Date
            }
            guard let date = fileDate else { return false }
            let cal = Calendar.current
            let now = Date()
            let threshold: Date?
            switch dateUnit {
            case .days:   threshold = cal.date(byAdding: .day,         value: -dateValue, to: now)
            case .weeks:  threshold = cal.date(byAdding: .weekOfYear,  value: -dateValue, to: now)
            case .months: threshold = cal.date(byAdding: .month,       value: -dateValue, to: now)
            }
            guard let t = threshold else { return false }
            return dateOp == .olderThan ? date < t : date > t

        case .timeOfDay:
            let date = (attrs[.creationDate] as? Date) ?? Date()
            let hour = Calendar.current.component(.hour, from: date)
            if timeFrom <= timeTo {
                return hour >= timeFrom && hour < timeTo
            } else {
                // wraps midnight e.g. 22→3
                return hour >= timeFrom || hour < timeTo
            }

        case .fromInternet:
            // Files downloaded from the web have the com.apple.quarantine xattr
            let size = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0)
            return size >= 0

        case .partialDownload:
            let ext = url.pathExtension.lowercased()
            return ["crdownload", "download", "part", "partial", "tmp", "!ut", "bc!"].contains(ext)

        case .fileSize:
            let bytes = (attrs[.size] as? Int) ?? 0
            let mb = Double(bytes) / 1_048_576
            return sizeOp == .largerThan ? mb > sizeMB : mb < sizeMB

        case .namePattern:
            let name = url.lastPathComponent
            switch nameOp {
            case .contains:   return name.localizedCaseInsensitiveContains(namePattern)
            case .startsWith: return name.lowercased().hasPrefix(namePattern.lowercased())
            case .endsWith:   return name.lowercased().hasSuffix(namePattern.lowercased())
            case .matches:
                guard let rx = try? NSRegularExpression(pattern: namePattern) else { return false }
                return rx.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
            }
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
    var id: String
    var extensions: [String]
    var keywords: [String]
    var conditions: [FileCondition] = []
    var renameRules: [RenameRule]   = []
    var moveToTrash: Bool           = false
    var isEnabled: Bool             = true

    enum CodingKeys: String, CodingKey {
        case id, extensions, keywords, conditions, dateConditions
        case renameRules, moveToTrash, isEnabled
    }

    init(id: String, extensions: [String], keywords: [String],
         conditions: [FileCondition] = [], renameRules: [RenameRule] = [],
         moveToTrash: Bool = false, isEnabled: Bool = true) {
        self.id = id; self.extensions = extensions; self.keywords = keywords
        self.conditions = conditions; self.renameRules = renameRules
        self.moveToTrash = moveToTrash; self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self,          forKey: .id)
        extensions  = (try? c.decode([String].self,       forKey: .extensions))  ?? []
        keywords    = (try? c.decode([String].self,       forKey: .keywords))    ?? []
        conditions  = (try? c.decode([FileCondition].self, forKey: .conditions))
                   ?? (try? c.decode([FileCondition].self, forKey: .dateConditions))
                   ?? []
        renameRules = (try? c.decode([RenameRule].self,   forKey: .renameRules)) ?? []
        moveToTrash = (try? c.decode(Bool.self,           forKey: .moveToTrash)) ?? false
        isEnabled   = (try? c.decode(Bool.self,           forKey: .isEnabled))   ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey: .id)
        try c.encode(extensions,  forKey: .extensions)
        try c.encode(keywords,    forKey: .keywords)
        try c.encode(conditions,  forKey: .conditions)
        try c.encode(renameRules, forKey: .renameRules)
        try c.encode(moveToTrash, forKey: .moveToTrash)
        try c.encode(isEnabled,   forKey: .isEnabled)
    }

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
