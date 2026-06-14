import Foundation

// MARK: - File Classifier

final class Classifier {

    static let shared = Classifier()
    private let config = ConfigManager.shared

    // MARK: - Classify a single file

    func classify(url: URL) -> ClassifierRule? {
        let name = url.lastPathComponent.lowercased()
        let ext  = ".\(url.pathExtension.lowercased())"

        for rule in config.config.rules {
            guard rule.isEnabled else { continue }
            if rule.extensions.contains(ext) { return rule }
            if rule.keywords.contains(where: { name.contains($0) }) { return rule }
            if !rule.conditions.isEmpty,
               rule.conditions.contains(where: { $0.matches(url: url) }) {
                return rule
            }
        }
        return nil
    }

    // MARK: - Classify all loose files in watched dirs

    @discardableResult
    func classifyAll(dryRun: Bool = false) -> [FileMove] {
        var moves: [FileMove] = []
        let fm = FileManager.default

        for base in config.watchURLs {
            guard let entries = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }

            for file in entries {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: file.path, isDirectory: &isDir)
                guard !isDir.boolValue else { continue }

                guard let rule = classify(url: file) else { continue }

                // Apply rename rules to get final filename
                var finalName = file.lastPathComponent
                for renameRule in rule.renameRules {
                    finalName = renameRule.apply(to: finalName, fileURL: file)
                }

                if rule.moveToTrash {
                    // Trash the file
                    if dryRun {
                        moves.append(FileMove(timestamp: Date(), fileName: file.lastPathComponent,
                                              fromPath: file.path, toFolder: "Trash"))
                        continue
                    }
                    do {
                        var trashed: NSURL?
                        try fm.trashItem(at: file, resultingItemURL: &trashed)
                        let move = FileMove(timestamp: Date(), fileName: file.lastPathComponent,
                                            fromPath: file.path, toFolder: "🗑 Trash")
                        moves.append(move)
                        config.logMove(move)
                    } catch {
                        print("Shelve: trash failed for \(file.lastPathComponent) — \(error)")
                    }
                } else {
                    // Move to subfolder (with optional rename)
                    let destDir  = base.appendingPathComponent(rule.id, isDirectory: true)
                    let destFile = destDir.appendingPathComponent(finalName)

                    if dryRun {
                        moves.append(FileMove(timestamp: Date(), fileName: file.lastPathComponent,
                                              fromPath: file.path, toFolder: rule.id))
                        continue
                    }

                    if fm.fileExists(atPath: destFile.path) { continue }

                    do {
                        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                        // Rename in-place first if needed, then move
                        if finalName != file.lastPathComponent {
                            let renamed = file.deletingLastPathComponent().appendingPathComponent(finalName)
                            try fm.moveItem(at: file, to: renamed)
                            try fm.moveItem(at: renamed, to: destFile)
                        } else {
                            try fm.moveItem(at: file, to: destFile)
                        }
                        let move = FileMove(timestamp: Date(), fileName: file.lastPathComponent,
                                            fromPath: file.path, toFolder: rule.id)
                        moves.append(move)
                        config.logMove(move)
                    } catch {
                        print("Shelve: failed to move \(file.lastPathComponent) — \(error)")
                    }
                }
            }
        }

        if !dryRun && !moves.isEmpty {
            DispatchQueue.global(qos: .background).async {
                SearchEngine.shared.reindex(watchURLs: ConfigManager.shared.watchURLs)
            }
        }

        return moves
    }

    // MARK: - Undo last move

    @discardableResult
    func undoLastMove() -> Bool {
        guard let last = config.lastMove() else { return false }
        guard last.destination != "🗑 Trash" else { return false } // can't undo trash
        let fm = FileManager.default

        for base in config.watchURLs {
            let src  = base.appendingPathComponent(last.destination)
                          .appendingPathComponent(last.fileName)
            let dest = base.appendingPathComponent(last.fileName)

            if fm.fileExists(atPath: src.path) {
                do { try fm.moveItem(at: src, to: dest); return true }
                catch { print("Shelve undo failed: \(error)") }
            }
        }
        return false
    }
}
