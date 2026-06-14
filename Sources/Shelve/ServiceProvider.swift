import AppKit

// MARK: - Finder Quick Action (NSServices)

/// Registered via NSServices in Info.plist.
/// Right-click any file/folder in Finder → Services → "Classify with Shelve"
final class ServiceProvider: NSObject {

    static let shared = ServiceProvider()

    /// Called by macOS when the user invokes the "Classify with Shelve" service.
    @objc func classifyFiles(_ pasteboard: NSPasteboard,
                             userData: String?,
                             error errorPtr: AutoreleasingUnsafeMutablePointer<NSString>?) {
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self],
                                                 options: nil) as? [URL],
              !items.isEmpty else { return }

        var moved = 0
        for url in items {
            if let rule = Classifier.shared.classify(url: url) {
                let dest: URL
                if rule.moveToTrash {
                    dest = URL(fileURLWithPath: NSHomeDirectory())
                        .appendingPathComponent(".Trash")
                } else {
                    dest = url.deletingLastPathComponent()
                        .appendingPathComponent(rule.id, isDirectory: true)
                }
                do {
                    try FileManager.default.createDirectory(at: dest,
                                                            withIntermediateDirectories: true)
                    let target = dest.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.moveItem(at: url, to: target)

                    let move = FileMove(
                        timestamp: Date(),
                        fileName: url.lastPathComponent,
                        fromPath: url.deletingLastPathComponent().path,
                        toFolder: rule.moveToTrash ? "🗑 Trash" : rule.id
                    )
                    ConfigManager.shared.logMove(move)
                    NotificationManager.shared.notifyServiceClassify(
                        fileName: url.lastPathComponent,
                        destination: rule.id
                    )
                    moved += 1
                } catch {
                    // Leave file in place if move fails
                }
            }
        }

        if moved == 0 {
            // No rules matched — show a brief notification
            NotificationManager.shared.notifyServiceClassify(
                fileName: items.count == 1 ? items[0].lastPathComponent : "\(items.count) files",
                destination: "No matching rule"
            )
        }
    }
}
