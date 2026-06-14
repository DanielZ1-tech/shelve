import Foundation

// MARK: - Natural Language Rule Parser

struct AIRuleCreator {

    // Public result type so the sheet can show what was parsed
    struct ParseResult {
        var folderName:  String
        var extensions:  [String]
        var keywords:    [String]
        var conditions:  [FileCondition]
        var moveToTrash: Bool
        var summary:     [String]   // human-readable description of each detected thing

        var rule: ClassifierRule {
            ClassifierRule(id: folderName, extensions: Array(Set(extensions)),
                           keywords: keywords, conditions: conditions, moveToTrash: moveToTrash)
        }
    }

    static func createRule(from input: String) -> ClassifierRule {
        parse(input).rule
    }

    static func parse(_ input: String) -> ParseResult {
        let text = input.lowercased()

        var exts:       [String]        = []
        var keywords:   [String]        = []
        var conditions: [FileCondition] = []
        var moveToTrash                 = false
        var folderName                  = "Custom"
        var summary:    [String]        = []

        // ── Trash intent ──────────────────────────────────────────────────────
        if any(text, ["trash", "delete", "remove", "discard", "clean up",
                      "get rid of", "clear out", "wipe", "purge", "junk"]) {
            moveToTrash = true
            summary.append("🗑 Move to Trash")
        }

        // ── Partial / failed downloads ────────────────────────────────────────
        if any(text, ["partial", "failed download", "incomplete", "crdownload",
                      "broken download", "corrupt", ".part file", "half-downloaded"]) {
            var c = FileCondition(); c.kind = .partialDownload; conditions.append(c)
            if folderName == "Custom" { folderName = "FailedDownloads" }
            summary.append("⚠️ Partial/failed downloads only")
        }

        // ── Downloaded from internet ──────────────────────────────────────────
        if any(text, ["from internet", "from web", "from browser", "web download",
                      "downloaded from", "from online", "from safari", "from chrome",
                      "from firefox", "quarantine", "internet download"]) {
            var c = FileCondition(); c.kind = .fromInternet; conditions.append(c)
            if folderName == "Custom" { folderName = "WebDownloads" }
            summary.append("🌐 Downloaded from internet")
        }

        // ── File types → extensions ───────────────────────────────────────────
        let detected = detectTypes(text)
        exts += detected.exts
        if !detected.exts.isEmpty {
            summary.append("📄 Extensions: \(detected.exts.prefix(4).joined(separator: ", "))\(detected.exts.count > 4 ? "…" : "")")
        }
        if folderName == "Custom", let fn = detected.folder { folderName = fn }

        // Explicit .ext tokens
        for ext in extractExplicitExtensions(input) where !exts.contains(ext) {
            exts.append(ext)
        }

        // ── Keywords from file type context ───────────────────────────────────
        keywords += detected.keywords

        // ── Date condition ────────────────────────────────────────────────────
        if let c = extractDate(text) {
            conditions.append(c)
            let unitStr = c.dateUnit == .weeks ? "week" : c.dateUnit == .months ? "month" : "day"
            let opStr   = c.dateOp == .olderThan ? "older" : "newer"
            summary.append("📅 \(opStr.capitalized) than \(c.dateValue) \(unitStr)\(c.dateValue == 1 ? "" : "s")")
        }

        // ── Time-of-day condition ─────────────────────────────────────────────
        if let c = extractTime(text) {
            conditions.append(c)
            if folderName == "Custom" { folderName = "TimeFiles" }
            summary.append("🕐 Created \(c.timeFrom):00–\(c.timeTo):00")
        }

        // ── File size condition ───────────────────────────────────────────────
        if let c = extractSize(text) {
            conditions.append(c)
            let opStr = c.sizeOp == .largerThan ? "larger" : "smaller"
            summary.append("📦 \(opStr.capitalized) than \(c.sizeMB >= 1024 ? String(format:"%.1f GB", c.sizeMB/1024) : "\(Int(c.sizeMB)) MB")")
        }

        // ── Vague size words ──────────────────────────────────────────────────
        if conditions.first(where: { $0.kind == .fileSize }) == nil {
            if let c = extractVagueSize(text) {
                conditions.append(c)
                let opStr = c.sizeOp == .largerThan ? "larger" : "smaller"
                summary.append("📦 \(opStr.capitalized) than ~\(Int(c.sizeMB)) MB")
            }
        }

        // ── Name pattern ──────────────────────────────────────────────────────
        if let (op, pattern) = extractNamePattern(text) {
            var c = FileCondition(); c.kind = .namePattern; c.nameOp = op; c.namePattern = pattern
            conditions.append(c)
            if !keywords.contains(pattern) { keywords.append(pattern) }
            let opStr = op == .startsWith ? "starts with" : op == .endsWith ? "ends with" : "contains"
            summary.append("🔤 Name \(opStr) \"\(pattern)\"")
        }

        // ── Quoted keywords ───────────────────────────────────────────────────
        for q in extractQuoted(input) where !keywords.contains(q) { keywords.append(q) }

        // ── Inline keyword lists ("with the word X, Y or Z", "named X or Y") ──
        for kw in extractKeywordList(input) where !keywords.contains(kw) { keywords.append(kw) }
        if !keywords.isEmpty {
            summary.append("🔑 Keywords: \(keywords.prefix(5).joined(separator: ", "))")
        }

        // ── Destination ───────────────────────────────────────────────────────
        if let dest = extractDestination(input) {
            folderName = dest
        }

        if summary.isEmpty { summary.append("📁 Move to \(folderName)") }

        return ParseResult(
            folderName:  folderName,
            extensions:  Array(Set(exts)),
            keywords:    keywords,
            conditions:  conditions,
            moveToTrash: moveToTrash,
            summary:     summary
        )
    }

    // MARK: - File type detection

    private struct Detected {
        var exts: [String]; var folder: String?; var keywords: [String] = []
    }

    private static func detectTypes(_ text: String) -> Detected {
        typealias Entry = (kw: [String], exts: [String], folder: String, extraKw: [String])
        let map: [Entry] = [
            // Documents
            (["pdf"],
             [".pdf"], "Documents", []),
            (["document","doc","word","text file","txt","rtf","pages","markdown","md file","writing","report","essay","note","notes"],
             [".pdf",".doc",".docx",".txt",".rtf",".pages",".md",".odt"], "Documents", []),
            // Ebooks
            (["ebook","ebooks","epub","kindle","mobi","book","books","reading"],
             [".epub",".mobi",".azw",".azw3",".pdf"], "Ebooks", ["ebook","book"]),
            // Receipts / invoices
            (["receipt","receipts","invoice","invoices","tax","taxes","billing","expense","statement"],
             [".pdf",".csv"], "Receipts", ["receipt","invoice","tax","statement"]),
            // Images
            (["image","images","photo","photos","picture","pictures","screenshot","screenshots",
              "jpg","jpeg","png","heic","gif","graphic","graphics","wallpaper","scan","scanned"],
             [".jpg",".jpeg",".png",".gif",".webp",".heic",".heif",".tiff",".bmp",".svg"], "Images", []),
            // Design files
            (["design","designs","mockup","mockups","figma","sketch","photoshop","illustrator",
              "psd","ai file","xd","wireframe"],
             [".psd",".ai",".sketch",".fig",".xd",".afdesign",".afphoto"], "Design", ["design","mockup"]),
            // Videos
            (["video","videos","movie","movies","film","films","clip","clips","recording","recordings",
              "mp4","mov","mkv","footage","screencast","timelapse","reel"],
             [".mp4",".mov",".avi",".mkv",".wmv",".m4v",".webm",".flv"], "Videos", []),
            // Audio
            (["audio","music","song","songs","podcast","podcasts","mp3","wav","flac",
              "track","tracks","sound","beat","beats","recording","sample","samples"],
             [".mp3",".wav",".aac",".flac",".m4a",".ogg",".opus",".aiff"], "Audio", []),
            // Spreadsheets
            (["spreadsheet","spreadsheets","excel","csv","numbers","xls","data","dataset","table"],
             [".xlsx",".xls",".csv",".numbers",".ods"], "Spreadsheets", []),
            // Presentations
            (["presentation","presentations","slides","slide deck","deck","powerpoint","keynote","ppt"],
             [".pptx",".ppt",".key",".odp"], "Presentations", []),
            // Archives
            (["zip","archive","archives","compressed","rar","tar","7z","bundle","package","backup"],
             [".zip",".tar",".gz",".rar",".7z",".bz2",".xz",".tar.gz"], "Archives", []),
            // Installers
            (["installer","installers","dmg","pkg","setup file","app install","application","app file"],
             [".dmg",".pkg"], "Installers", []),
            // Code
            (["code","script","scripts","python","javascript","typescript","swift","source","program",
              "html","css","java","kotlin","rust","golang","ruby","php","sql"],
             [".py",".js",".ts",".swift",".sh",".rb",".go",".java",".cpp",".c",
              ".h",".rs",".html",".css",".php",".sql",".kt",".r"], "Code", []),
            // Fonts
            (["font","fonts","typeface","typefaces","typography"],
             [".ttf",".otf",".woff",".woff2"], "Fonts", []),
            // 3D / CAD
            (["3d","3d model","models","stl","blend","obj","cad","mesh","render","blender",
              "solidworks","fusion","step","iges","dwg"],
             [".stl",".obj",".fbx",".blend",".3ds",".step",".iges",".dwg",".dxf"], "3D", []),
            // Emails
            (["email","emails","mail","eml","msg","outlook","message"],
             [".eml",".msg",".mbox"], "Emails", ["email"]),
            // Temp / junk
            (["temp","temporary","cache","cached","junk","garbage","log file","crash","dump"],
             [".tmp",".temp",".cache",".log",".dmp",".crash"], "Temp", ["temp","log"]),
            // Torrent
            (["torrent"],
             [".torrent"], "Torrents", []),
        ]
        var result = Detected(exts: [], folder: nil)
        for entry in map {
            if entry.kw.contains(where: { text.contains($0) }) {
                result.exts += entry.exts
                if result.folder == nil { result.folder = entry.folder }
                result.keywords += entry.extraKw
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
        // Word numbers
        let wordNums: [(word: String, val: Int)] = [
            ("one",1),("two",2),("three",3),("four",4),("five",5),("six",6),("seven",7),
            ("eight",8),("nine",9),("ten",10),("fifteen",15),("twenty",20),("thirty",30),
            ("sixty",60),("ninety",90),("a ",1),("an ",1),
        ]

        // Named periods
        if any(text, ["today","this morning","this afternoon"]) {
            var c = FileCondition(); c.kind = .date; c.dateOp = .newerThan; c.dateValue = 1; c.dateUnit = .days; return c
        }
        if any(text, ["this week","last week"]) {
            var c = FileCondition(); c.kind = .date; c.dateOp = .olderThan; c.dateValue = 7; c.dateUnit = .days; return c
        }
        if any(text, ["this month","last month"]) {
            var c = FileCondition(); c.kind = .date; c.dateOp = .olderThan; c.dateValue = 1; c.dateUnit = .months; return c
        }
        if any(text, ["this year","last year"]) {
            var c = FileCondition(); c.kind = .date; c.dateOp = .olderThan; c.dateValue = 12; c.dateUnit = .months; return c
        }
        if any(text, ["old","stale","outdated","ancient"]) && !any(text, ["older than","more than"]) {
            var c = FileCondition(); c.kind = .date; c.dateOp = .olderThan; c.dateValue = 30; c.dateUnit = .days; return c
        }
        if any(text, ["recent","new","latest","fresh"]) {
            var c = FileCondition(); c.kind = .date; c.dateOp = .newerThan; c.dateValue = 7; c.dateUnit = .days; return c
        }

        let rules: [(pattern: String, op: FileCondition.DateOperator)] = [
            ("older than (\\d+) (day|week|month|year)s?",    .olderThan),
            ("more than (\\d+) (day|week|month|year)s? old", .olderThan),
            ("(\\d+)\\+ (day|week|month|year)s? old",        .olderThan),
            ("(\\d+) (day|week|month|year)s? ago",           .olderThan),
            ("at least (\\d+) (day|week|month|year)s? old",  .olderThan),
            ("newer than (\\d+) (day|week|month|year)s?",    .newerThan),
            ("less than (\\d+) (day|week|month|year)s? old", .newerThan),
            ("within (\\d+) (day|week|month|year)s?",        .newerThan),
            ("in the (last|past) (\\d+) (day|week|month|year)s?", .newerThan),
            ("last (\\d+) (day|week|month|year)s?",          .newerThan),
        ]
        for rule in rules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                // handle "in the last N" which has capture group offset
                let groupOffset = rule.pattern.hasPrefix("in the") ? 1 : 0
                let value   = intCapture(m, 1 + groupOffset, text) ?? 30
                let unitStr = strCapture(m, 2 + groupOffset, text) ?? "day"
                let unit: FileCondition.DateUnit = unitStr.hasPrefix("year")  ? .months
                                                 : unitStr.hasPrefix("week")  ? .weeks
                                                 : unitStr.hasPrefix("month") ? .months : .days
                let finalValue = unitStr.hasPrefix("year") ? value * 12 : value
                var c = FileCondition()
                c.kind = .date; c.dateOp = rule.op; c.dateValue = finalValue; c.dateUnit = unit
                return c
            }
        }

        // Word number fallback: "three weeks old", "a month ago"
        for wn in wordNums {
            for (unit, unitWord) in [(FileCondition.DateUnit.days,"day"),(FileCondition.DateUnit.weeks,"week"),(FileCondition.DateUnit.months,"month")] {
                if text.contains("\(wn.word)\(unitWord)") || text.contains("\(wn.word) \(unitWord)") {
                    var c = FileCondition()
                    c.kind = .date; c.dateOp = .olderThan; c.dateValue = wn.val; c.dateUnit = unit
                    return c
                }
            }
        }

        return nil
    }

    // MARK: - Time-of-day condition

    private static func extractTime(_ text: String) -> FileCondition? {
        // Named periods
        if any(text, ["overnight","at night","nighttime","night time","late night"]) {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 22; c.timeTo = 6; return c
        }
        if any(text, ["early morning","early hours","very early","predawn","before dawn"]) {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 0; c.timeTo = 6; return c
        }
        if any(text, ["morning","in the morning"]) && !text.contains("between") {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 6; c.timeTo = 12; return c
        }
        if any(text, ["afternoon"]) && !text.contains("between") {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 12; c.timeTo = 17; return c
        }
        if any(text, ["evening","at evening"]) && !text.contains("between") {
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 17; c.timeTo = 22; return c
        }

        // "between X[:mm][am|pm] and Y[:mm][am|pm]"
        let between = "between (\\d{1,2})(?::\\d{2})?\\s*(am|pm)?\\s+and\\s+(\\d{1,2})(?::\\d{2})?\\s*(am|pm)?"
        if let rx = try? NSRegularExpression(pattern: between, options: .caseInsensitive),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let h1 = intCapture(m,1,text) ?? 0; let s1 = strCapture(m,2,text) ?? ""
            let h2 = intCapture(m,3,text) ?? 6; let s2 = strCapture(m,4,text) ?? ""
            var c = FileCondition(); c.kind = .timeOfDay
            c.timeFrom = hour24(h1,s1); c.timeTo = hour24(h2,s2); return c
        }

        // "before X[am|pm]" / "earlier than X"
        let before = "(?:before|earlier than|prior to) (\\d{1,2})(?::\\d{2})?\\s*(am|pm)?"
        if let rx = try? NSRegularExpression(pattern: before, options: .caseInsensitive),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let h = intCapture(m,1,text) ?? 6; let s = strCapture(m,2,text) ?? "am"
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 0; c.timeTo = hour24(h,s); return c
        }

        // "after X[pm]" / "later than X"
        let after = "(?:after|later than) (\\d{1,2})(?::\\d{2})?\\s*(am|pm)?"
        if let rx = try? NSRegularExpression(pattern: after, options: .caseInsensitive),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let h = intCapture(m,1,text) ?? 20; let s = strCapture(m,2,text) ?? "pm"
            var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = hour24(h,s); c.timeTo = 23; return c
        }

        // "at midnight", "around 3am"
        let atTime = "(?:at|around|@) (midnight|noon|(\\d{1,2})(?::\\d{2})?\\s*(am|pm)?)"
        if let rx = try? NSRegularExpression(pattern: atTime, options: .caseInsensitive),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 1), in: text), text[r] == "midnight" {
                var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 0; c.timeTo = 2; return c
            } else if let r = Range(m.range(at: 1), in: text), text[r] == "noon" {
                var c = FileCondition(); c.kind = .timeOfDay; c.timeFrom = 11; c.timeTo = 13; return c
            } else {
                let h = intCapture(m,2,text) ?? 0; let s = strCapture(m,3,text) ?? ""
                let h24 = hour24(h,s)
                var c = FileCondition(); c.kind = .timeOfDay
                c.timeFrom = max(0,h24-1); c.timeTo = min(23,h24+1); return c
            }
        }

        return nil
    }

    // MARK: - File size condition

    private static func extractSize(_ text: String) -> FileCondition? {
        // Handle "X GB", "X MB", "X KB" with optional decimal
        let rules: [(pattern: String, op: FileCondition.SizeOperator)] = [
            ("(?:larger|bigger|more|over|greater|heavier|exceeds?)\\s+than?\\s+(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb|tb|k|m|g)", .largerThan),
            ("(?:over|above|exceeding|at least)\\s+(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb|tb|k|m|g)",  .largerThan),
            ("(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb|tb|k|m|g)\\s*(?:or )?(?:larger|bigger|more|above|and up|\\+)", .largerThan),
            ("(?:smaller|less|under|below|lighter|beneath)\\s+than?\\s+(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb|tb|k|m|g)", .smallerThan),
            ("(?:under|below|at most|no more than)\\s+(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb|tb|k|m|g)", .smallerThan),
            ("(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb|tb|k|m|g)\\s*(?:or )?(?:smaller|less|below|max)",   .smallerThan),
        ]
        for rule in rules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw  = strCapture(m,1,text)?.replacingOccurrences(of: ",", with: ".") ?? "100"
                var mb   = Double(raw) ?? 100
                let unit = (strCapture(m,2,text) ?? "mb").lowercased()
                switch unit {
                case "gb","g","tb": mb *= unit == "tb" ? 1024*1024 : 1024
                case "kb","k":      mb /= 1024
                default: break
                }
                var c = FileCondition(); c.kind = .fileSize; c.sizeOp = rule.op; c.sizeMB = mb
                return c
            }
        }
        return nil
    }

    // Vague size words when no explicit size given
    private static func extractVagueSize(_ text: String) -> FileCondition? {
        if any(text, ["huge","massive","enormous","giant","very large","very big"]) {
            var c = FileCondition(); c.kind = .fileSize; c.sizeOp = .largerThan; c.sizeMB = 500; return c
        }
        if any(text, ["large","big","heavy","bulky","bloated"]) {
            var c = FileCondition(); c.kind = .fileSize; c.sizeOp = .largerThan; c.sizeMB = 100; return c
        }
        if any(text, ["small","tiny","little","lightweight","minimal","mini"]) {
            var c = FileCondition(); c.kind = .fileSize; c.sizeOp = .smallerThan; c.sizeMB = 1; return c
        }
        return nil
    }

    // MARK: - Name pattern

    private static func extractNamePattern(_ text: String) -> (FileCondition.NameOperator, String)? {
        let rules: [(pattern: String, op: FileCondition.NameOperator)] = [
            ("(?:named|called|titled|with (?:the )?name)\\s+['\"]?([\\w\\-\\.\\s]+?)['\"]?(?:\\s|$)", .contains),
            ("(?:name )?contains?\\s+['\"]?([\\w\\-\\.]+)['\"]?",                   .contains),
            ("(?:with|containing)\\s+['\"]?([\\w\\-\\.]+)['\"]?\\s+in.{0,10}name", .contains),
            ("(?:starts?|begins?) with\\s+['\"]?([\\w\\-\\.]+)['\"]?",              .startsWith),
            ("(?:ends?|finishing) with\\s+['\"]?([\\w\\-\\.]+)['\"]?",              .endsWith),
            ("(?:matching|matches|that match)\\s+['\"]?([\\w\\-\\.\\*\\?]+)['\"]?", .contains),
            ("prefix\\s+['\"]?([\\w\\-\\.]+)['\"]?",                                .startsWith),
            ("suffix\\s+['\"]?([\\w\\-\\.]+)['\"]?",                                .endsWith),
        ]
        for rule in rules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let val = strCapture(m,1,text)?.trimmingCharacters(in: .whitespaces), !val.isEmpty {
                return (rule.op, val)
            }
        }
        return nil
    }

    // MARK: - Destination

    private static func extractDestination(_ text: String) -> String? {
        let patterns = [
            // "move ... to/into FolderName"
            "(?:move|sort|file|put|send|save|organize|place)\\s+.{0,20}?\\s+(?:to|into|in)\\s+([A-Z][a-zA-Z0-9_\\-]+)",
            // "to FolderName folder"
            "(?:to|into)\\s+(?:a\\s+folder\\s+(?:called|named)\\s+)?([A-Z][a-zA-Z0-9_\\-]+)(?:\\s+folder)?",
            // "folder called/named X"
            "folder\\s+(?:called|named)\\s+['\"]?([A-Za-z][a-zA-Z0-9_\\-]+)['\"]?",
            // "called/named X" anywhere
            "(?:called|named)\\s+['\"]?([A-Z][a-zA-Z0-9_\\-]+)['\"]?",
        ]
        for pattern in patterns {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            if let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let val = strCapture(m,1,text) {
                // Filter out common English words that aren't folder names
                let blacklist: Set<String> = ["The","A","An","To","From","Into","My","All",
                                              "Files","File","New","Old","Any","That","This","It","Me"]
                if !blacklist.contains(val) { return val }
            }
        }
        return nil
    }

    // MARK: - Keyword list extraction
    // Handles: "with the word report", "named report or review", "containing X, Y, or Z",
    //          "with 'report' or 'review' in the name", "titled X", book/author names

    private static func extractKeywordList(_ text: String) -> [String] {
        var found: [String] = []
        let lower = text.lowercased()

        // Pattern 1: "with the word(s) X, Y, or Z"
        let wordListPatterns = [
            "with the words? (.+?)(?:\\.|$|\\bto\\b|\\binto\\b|\\bolder\\b|\\bbigger\\b|\\blarger\\b)",
            "containing the words? (.+?)(?:\\.|$|\\bto\\b|\\binto\\b)",
            "(?:titled|named|called) (.+?)(?:\\.|$|\\bto\\b|\\binto\\b|\\bolder\\b)",
            "(?:with|containing|including|that (?:has|have|contain)) (.+?) in (?:the |their |its )?(?:name|title|filename)",
            "(?:with|having) (?:a |the )?(?:name|title|filename) (?:like|containing|of) (.+?)(?:\\.|$)",
        ]
        for pattern in wordListPatterns {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            if let m = rx.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let r = Range(m.range(at: 1), in: lower) {
                let chunk = String(lower[r])
                found += splitKeywords(chunk)
                break
            }
        }

        // Pattern 2: bare "or" list after a keyword trigger like "report, review, or summary"
        // Only pick this up if one of the trigger words is present
        let triggers = ["report","review","summary","invoice","receipt","budget",
                        "proposal","contract","agreement","statement","brief","memo",
                        "plan","draft","final","thesis","chapter","appendix","index"]
        for trigger in triggers where lower.contains(trigger) {
            if !found.contains(trigger) { found.append(trigger) }
        }

        return found.filter { !$0.isEmpty && $0.count > 1 }
    }

    // Splits "report, review or summary" → ["report","review","summary"]
    private static func splitKeywords(_ chunk: String) -> [String] {
        // Remove leading/trailing noise
        let clean = chunk
            .replacingOccurrences(of: #"\b(and|or|either|the|a|an)\b"#, with: ",",
                                  options: .regularExpression)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return clean
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 1 }
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
        let s = suffix.lowercased()
        if s == "pm" && h != 12 { return h + 12 }
        if s == "am" && h == 12 { return 0 }
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
