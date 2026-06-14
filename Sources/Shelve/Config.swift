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
}
