import UserNotifications
import AppKit

final class NotificationManager {

    static let shared = NotificationManager()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "shelve.notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "shelve.notificationsEnabled") }
    }

    func requestPermission(then completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted && !UserDefaults.standard.bool(forKey: "shelve.notificationsAsked") {
                    self.isEnabled = true   // default on if just granted
                }
                UserDefaults.standard.set(true, forKey: "shelve.notificationsAsked")
                completion?(granted)
            }
        }
    }

    func notifyMoves(_ moves: [FileMove]) {
        guard isEnabled, !moves.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Shelve"

        if moves.count == 1 {
            let m = moves[0]
            let dest = m.toFolder == "🗑 Trash" ? "Trash" : m.toFolder
            content.body = "\(m.fileName) → \(dest)"
        } else {
            let byDest = Dictionary(grouping: moves, by: \.toFolder)
            if byDest.count == 1, let (dest, files) = byDest.first {
                let d = dest == "🗑 Trash" ? "Trash" : dest
                content.body = "Moved \(files.count) files to \(d)"
            } else {
                let trashed = moves.filter { $0.toFolder.contains("Trash") }.count
                let moved   = moves.count - trashed
                var parts: [String] = []
                if moved   > 0 { parts.append("moved \(moved)") }
                if trashed > 0 { parts.append("trashed \(trashed)") }
                content.body = parts.joined(separator: ", ").capitalized + " file\(moves.count == 1 ? "" : "s")"
            }
        }
        content.sound = .default
        send(content)
    }

    func notifyServiceClassify(fileName: String, destination: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Shelve — Quick Classify"
        content.body = "\(fileName) → \(destination)"
        content.sound = .default
        send(content)
    }

    private func send(_ content: UNMutableNotificationContent) {
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
