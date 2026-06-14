import Foundation

// MARK: - Config Manager

final class ConfigManager: ObservableObject {

    static let shared = ConfigManager()

    private let configURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Shelve", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    private let logURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Shelve", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir.appendingPathComponent("moves.log")
    }()

    @Published var config: ShelveConfig

    private init() {
        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(ShelveConfig.self, from: data) {
            self.config = cfg
        } else {
            self.config = .default
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    // MARK: - Watch directories

    var watchURLs: [URL] {
        config.watchDirs.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    // MARK: - Move log

    func logMove(_ move: FileMove) {
        let df = ISO8601DateFormatter()
        let line = "\(df.string(from: move.timestamp))  \(move.fileName) → \(move.toFolder)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try? FileHandle(forWritingTo: logURL)
                handle?.seekToEndOfFile()
                handle?.write(data)
                handle?.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func recentMoves(limit: Int = 10) -> [HistoryEntry] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n").filter { $0.contains("→") }
        return lines.suffix(limit).reversed().compactMap { line -> HistoryEntry? in
            let parts = line.components(separatedBy: "→")
            guard parts.count == 2 else { return nil }
            let left = parts[0].trimmingCharacters(in: .whitespaces)
            let dest = parts[1].trimmingCharacters(in: .whitespaces)
            let tokens = left.split(separator: " ", maxSplits: 1)
            guard tokens.count == 2 else { return nil }
            return HistoryEntry(timestamp: String(tokens[0]),
                                fileName: String(tokens[1]),
                                destination: dest)
        }
    }

    func lastMove() -> HistoryEntry? {
        recentMoves(limit: 1).first
    }

    // MARK: - Stats

    func computeStats() -> ShelveStats {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return ShelveStats() }

        let lines = text.components(separatedBy: "\n").filter { $0.contains("→") }
        var stats = ShelveStats()
        stats.totalMoves = lines.count

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfWeek  = cal.date(byAdding: .day, value: -6, to: startOfToday)!

        var destCounts: [String: Int] = [:]
        var extCounts:  [String: Int] = [:]
        var dailyMap:   [Date: Int]   = [:]

        let isoDF = ISO8601DateFormatter()

        for line in lines {
            let parts = line.components(separatedBy: "→")
            guard parts.count == 2 else { continue }
            let left  = parts[0].trimmingCharacters(in: .whitespaces)
            let dest  = parts[1].trimmingCharacters(in: .whitespaces)
            let tokens = left.split(separator: " ", maxSplits: 1)
            guard tokens.count == 2 else { continue }
            let tsStr  = String(tokens[0])
            let fname  = String(tokens[1])
            let date   = isoDF.date(from: tsStr) ?? now

            if date >= startOfToday { stats.movesToday     += 1 }
            if date >= startOfWeek  { stats.movesThisWeek  += 1 }

            destCounts[dest, default: 0]                          += 1
            let ext = (fname as NSString).pathExtension.lowercased()
            if !ext.isEmpty { extCounts[ext, default: 0]          += 1 }

            if date >= startOfWeek {
                let day = cal.startOfDay(for: date)
                dailyMap[day, default: 0] += 1
            }
        }

        stats.topDestinations = destCounts.sorted { $0.value > $1.value }.prefix(5)
            .map { (name: $0.key, count: $0.value) }
        stats.topExtensions   = extCounts.sorted  { $0.value > $1.value }.prefix(6)
            .map { (ext: ".\($0.key)", count: $0.value) }

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE"
        stats.dailyCounts = (0..<7).reversed().compactMap { offset -> ShelveStats.DayCount? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            return ShelveStats.DayCount(label: dayFmt.string(from: day), date: day,
                                        count: dailyMap[day] ?? 0)
        }
        return stats
    }
}
