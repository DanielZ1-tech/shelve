import Foundation

// MARK: - Natural Language Rule Parser

struct AIRuleCreator {

    static func createRule(from input: String) -> ClassifierRule {
        let text = input.lowercased()

        var exts:       [String]         = []
        var keywords:   [String]         = []
        var conditions: [FileCondition]  = []
        var moveToTrash                  = false
        var folderName                   = "Custom"

        // ── Trash intent ──────────────────────────────────────────────────────
        if any(text, ["trash", "delete", "remove", "discard", "clean up"]) {
            moveToTrash = true
        }

        // ── Partial / failed downloads ────────────────────────────────────────
        if any(text, ["partial", "failed download", "incomplete", "crdownload", "broken"]) {
            var c = FileCondition(); c.kind = .partialDownload; conditions.append(c)
            if folderName == "Custom" { folderName = "FailedDownloads" }
        }

        // ── Downloaded from internet ──────────────────────────────────────────
        if any(text, ["from internet", "from web", "from browser", "web download", "downloaded from"]) {
            var c = FileCondition(); c.kind = .fromInternet; conditions.append(c)
            if folderName == "Custom" { folderName = "WebDownloads" }
        }

        // ── File types → extensions + default folder ──────────────────────────
        let detected = detectTypes(text)
        exts += detected.exts
        if folderName == "Custom", let fn = detected.folder { folderName = fn }

        // Explicit .ext tokens in the original input
        for ext in extractExplicitExtensions(input) where !exts.contains(ext) {
            exts.append(ext)
        }

        // ── Date condition ────────────────────────────────────────────────────
        if let c = extractDate(text) { conditions.append(c) }

        // ── Time-of-day condition ─────────────────────────────────────────────
        if let c = extractTime(text) {
            conditions.append(c)
            if folderName == "Custom" { folderName = "TimeFiles" }
        }

        // ── File size condition ───────────────────────────────────────────────
        if let c = extractSize(text) { conditions.append(c) }

        // ── Name pattern ──────────────────────────────────────────────────────
        if let (op, pattern) = extractNamePattern(text) {
            var c = FileCondition(); c.kind = .namePattern; c.nameOp = op; c.namePattern = pattern
            conditions.append(c)
            if !keywords.contains(pattern) { keywords.append(pattern) }
        }

        // ── Quoted keywords ───────────────────────────────────────────────────
        for q in extractQuoted(input) where !keywords.contains(q) { keywords.append(q) }

        // ── Explicit destination ("to Archive", "into OldStuff") ─────────────
        if let dest = extractDestination(input) { folderName = dest }

        return ClassifierRule(
            id:          folderName,
            extensions:  Array(Set(exts)),
            keywords:    keywords,
            conditions:  conditions,
            moveToTrash: moveToTrash
        )
    }

    // MARK: - File type detection

    private struct Detected { var exts: [String]; var folder: String? }

    private static func detectTypes(_ text: String) -> Detected {
        let map: [(kw: [String], exts: [String], folder: String)] = [
            (["pdf"],
             [".pdf"], "Documents"),
            (["document","doc","word","text file","txt","rtf","pages","markdown"],
             [".pdf",".doc",".docx",".txt",".rtf",".pages",".md"], "Documents"),
            (["image","images","photo","photos","picture","pictures","screenshot","screenshots","jpg","jpeg","png","heic","gif"],
             [".jpg",".jpeg",".png",".gif",".webp",".heic",".heif",".tiff",".bmp"], "Images"),
            (["video","videos","movie","movies","film","films","clip","recording","mp4","mov","mkv"],
             [".mp4",".mov",".avi",".mkv",".wmv",".m4v"], "Videos"),
            (["audio","music","song","songs","podcast","podcasts","mp3","wav","flac"],
             [".mp3",".wav",".aac",".flac",".m4a",".ogg"], "Audio"),
            (["spreadsheet","spreadsheets","excel","csv","numbers","xls"],
             [".xlsx",".xls",".csv",".numbers"], "Spreadsheets"),
            (["presentation","presentations","slides","deck","powerpoint","keynote","ppt"],
             [".pptx",".ppt",".key",".odp"], "Presentations"),
            (["zip","archive","archives","compressed","rar","tar","7z"],
             [".zip",".tar",".gz",".rar",".7z",".bz2"], "Archives"),
            (["installer","installers","dmg","pkg","setup file","app install"],
             [".dmg",".pkg"], "Installers"),
            (["code","script","scripts","python","javascript","swift","source","program"],
             [".py",".js",".ts",".swift",".sh",".rb",".go",".java",".cpp"], "Code"),
            (["font","fonts","typeface"],
             [".ttf",".otf",".woff",".woff2"], "Fonts"),
            (["3d","model","models","stl","blend","obj","cad"],
             [".stl",".obj",".fbx",".blend",".3ds",".step"], "3D"),
        ]
        var result = Detected(exts: [], folder: nil)
        for entry in map {
            if entry.kw.contains(where: { text.contains($0) }) {
                result.exts += entry.exts
                if result.folder == nil { result.folder = entry.folder }
            }
        }
        return result
    }

    // MARK: - Explicit extensions

    private static func extractExplicitExtensions(_ text: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: "\\.[a-zA-Z0-9]{2,5}\\b") else { return [] }
        return rx.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]).lowercased() }
        }
    }

    // MARK: - Date condition

    private static func extractDate(_ text: String) -> FileCondition? {
        let rules: [(pattern: String, op: FileCondition.DateOperator)] = [
            ("older than (\\d+) (day|week|month)s?",   .olderThan),
            ("more than (\\d+) (day|week|month)s? old", .olderThan),
            ("(\\d+) (day|week|month)s? ago",           .olderThan),
            ("newer than (\\d+) (day|week|month)s?",    .newerThan),
            ("less than (\\d+) (day|week|month)s? old", .newerThan),
            ("within (\\d+) (day|week|month)s?",        .newerThan),
            ("last (\\d+) (day|week|month)s?",          .newerThan),
        ]
        for rule in rules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let value   = intCapture(m, 1, text) ?? 30
                let unitStr = strCapture(m, 2, text) ?? "day"
                let unit: FileCondition.DateUnit = unitStr.hasPrefix("week")  ? .weeks
                                                 : unitStr.hasPrefix("month") ? .months : .days
                var c = FileCondition()
                c.kind = .date; c.dateOp = rule.op; c.dateValue = value; c.dateUnit = unit
                return c
            }
        }
        return nil
    }

    // MARK: - Time-of-day condition

    private static func extractTime(_ text: String) -> FileCondition? {
        if any(text, ["overnight","at night","nighttime","night time"]) {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 22; c.timeTo = 6; return c
        }
        if any(text, ["early morning","early hours","very early"]) {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 0;  c.timeTo = 6; return c
        }

        // "between X[:mm] [am|pm] and Y[:mm] [am|pm]"
        let between = "between (\\d{1,2})(?::\\d{2})?\\s*(am|pm)? and (\\d{1,2})(?::\\d{2})?\\s*(am|pm)?"
        if let rx = try? NSRegularExpression(pattern: between),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let h1 = intCapture(m, 1, text) ?? 0;  let s1 = strCapture(m, 2, text) ?? ""
            let h2 = intCapture(m, 3, text) ?? 6;  let s2 = strCapture(m, 4, text) ?? ""
            var c = FileCondition(); c.kind = .timeOfDay
            c.timeFrom = hour24(h1, s1); c.timeTo = hour24(h2, s2); return c
        }

        // "before X [am|pm]"
        if let rx = try? NSRegularExpression(pattern: "before (\\d{1,2})\\s*(am|pm)?"),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let h = intCapture(m, 1, text) ?? 6; let s = strCapture(m, 2, text) ?? "am"
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 0; c.timeTo = hour24(h, s); return c
        }

        // "after X [pm]"
        if let rx = try? NSRegularExpression(pattern: "after (\\d{1,2})\\s*(am|pm)?"),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let h = intCapture(m, 1, text) ?? 20; let s = strCapture(m, 2, text) ?? "pm"
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = hour24(h, s); c.timeTo = 23; return c
        }

        return nil
    }

    // MARK: - File size condition

    private static func extractSize(_ text: String) -> FileCondition? {
        let rules: [(pattern: String, op: FileCondition.SizeOperator)] = [
            ("(?:larger|bigger|more|over) than? (\\d+(?:\\.\\d+)?)\\s*(kb|mb|gb)", .largerThan),
            ("over (\\d+(?:\\.\\d+)?)\\s*(kb|mb|gb)",                              .largerThan),
            ("(?:smaller|less|under) than? (\\d+(?:\\.\\d+)?)\\s*(kb|mb|gb)",      .smallerThan),
            ("under (\\d+(?:\\.\\d+)?)\\s*(kb|mb|gb)",                             .smallerThan),
        ]
        for rule in rules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                var mb   = dblCapture(m, 1, text) ?? 100
                let unit = strCapture(m, 2, text) ?? "mb"
                if unit == "gb" { mb *= 1024 } else if unit == "kb" { mb /= 1024 }
                var c = FileCondition(); c.kind = .fileSize; c.sizeOp = rule.op; c.sizeMB = mb
                return c
            }
        }
        return nil
    }

    // MARK: - Name pattern

    private static func extractNamePattern(_ text: String) -> (FileCondition.NameOperator, String)? {
        let rules: [(pattern: String, op: FileCondition.NameOperator)] = [
            ("(?:named|called) ['\"]?([\\w\\-\\.]+)['\"]?",                        .contains),
            ("(?:containing|with) ['\"]?([\\w\\-\\.]+)['\"]? in.{0,10} name",      .contains),
            ("(?:starts? with|beginning with) ['\"]?([\\w\\-\\.]+)['\"]?",         .startsWith),
            ("(?:ends? with|ending with) ['\"]?([\\w\\-\\.]+)['\"]?",              .endsWith),
        ]
        for rule in rules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let val = strCapture(m, 1, text), !val.isEmpty {
                return (rule.op, val)
            }
        }
        return nil
    }

    // MARK: - Destination ("to Archive", "into OldStuff")

    private static func extractDestination(_ text: String) -> String? {
        let patterns = [
            "(?:move|sort|file|put).{0,10}(?:to|into) ([A-Z][a-zA-Z0-9]+)",
            "(?:to|into) ([A-Z][a-zA-Z0-9]+)(?: folder)?",
        ]
        for pattern in patterns {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let val = strCapture(m, 1, text) { return val }
        }
        return nil
    }

    // MARK: - Quoted words

    private static func extractQuoted(_ text: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: "['\"]([^'\"]+)['\"]") else { return [] }
        return rx.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]).lowercased() }
        }
    }

    // MARK: - Utilities

    private static func any(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: { text.contains($0) })
    }

    private static func hour24(_ h: Int, _ suffix: String) -> Int {
        if suffix == "pm" && h != 12 { return h + 12 }
        if suffix == "am" && h == 12 { return 0 }
        return h
    }

    private static func intCapture(_ m: NSTextCheckingResult, _ g: Int, _ s: String) -> Int? {
        guard m.numberOfRanges > g, let r = Range(m.range(at: g), in: s) else { return nil }
        return Int(s[r])
    }
    private static func dblCapture(_ m: NSTextCheckingResult, _ g: Int, _ s: String) -> Double? {
        guard m.numberOfRanges > g, let r = Range(m.range(at: g), in: s) else { return nil }
        return Double(s[r])
    }
    private static func strCapture(_ m: NSTextCheckingResult, _ g: Int, _ s: String) -> String? {
        guard m.numberOfRanges > g, let r = Range(m.range(at: g), in: s) else { return nil }
        return String(s[r])
    }
}
