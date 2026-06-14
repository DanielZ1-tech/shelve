import AppKit
import SwiftUI

// MARK: - Menu Bar Manager

final class MenuBarManager {

    private var statusItem: NSStatusItem!
    private var classifyTimer: Timer?
    private let config  = ConfigManager.shared
    private let watcher = FileWatcher.shared

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📂"
        statusItem.button?.font  = .systemFont(ofSize: 14)

        buildMenu()
        startWatcher()
        startAutoClassifyTimer()

        // Initial index build
        DispatchQueue.global(qos: .background).async {
            SearchEngine.shared.reindex(watchURLs: ConfigManager.shared.watchURLs)
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        menu.addItem(menuItem("📂  Open Shelve",      action: #selector(openMain),      key: "o", modifiers: [.command]))
        menu.addItem(menuItem("🔍  Search Files…",  action: #selector(openSearch),    key: "f", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(menuItem("▶  Classify Now",     action: #selector(classifyNow),   key: "k", modifiers: [.command]))
        menu.addItem(menuItem("↩  Undo Last Move",   action: #selector(undoLast),      key: "z", modifiers: [.command]))
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Recent Moves", action: nil, keyEquivalent: "")
        let recentSub  = NSMenu(title: "Recent Moves")
        recentItem.submenu = recentSub
        menu.addItem(recentItem)
        refreshRecentMoves(in: recentSub)

        menu.addItem(.separator())
        menu.addItem(menuItem("📁  Open Downloads",  action: #selector(openDownloads), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Shelve",          action: #selector(quit),           key: "q"))

        statusItem.menu = menu
        statusItem.menu?.delegate = MenuDelegate.shared
    }

    private func menuItem(_ title: String, action: Selector, key: String,
                          modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    // MARK: - Actions

    @objc private func openMain() {
        MainWindowController.shared.show()
    }

    @objc private func openSearch() {
        SearchPanelController.shared.show()
    }

    @objc private func classifyNow() {
        statusItem.button?.title = "⏳"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let moves = Classifier.shared.classifyAll()
            DispatchQueue.main.async {
                self?.statusItem.button?.title = "📂"
                self?.refreshMenu()
                // macOS notification (if permission granted)
                if moves.isEmpty {
                    self?.flashStatus(body: "Nothing to classify")
                } else {
                    NotificationManager.shared.notifyMoves(moves)
                    self?.flashStatus(body: "Moved \(moves.count) file\(moves.count == 1 ? "" : "s")")
                }
            }
        }
    }

    @objc private func undoLast() {
        let ok = Classifier.shared.undoLastMove()
        flashStatus(body: ok ? "Last move undone." : "Nothing to undo.")
        if ok { refreshMenu() }
    }

    @objc private func openDownloads() {
        if let url = config.watchURLs.first {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Menu refresh

    func refreshMenu() {
        guard let menu = statusItem.menu else { return }
        // Find "Recent Moves" item by title
        for item in menu.items where item.title == "Recent Moves" {
            if let sub = item.submenu { refreshRecentMoves(in: sub) }
        }
    }

    private func refreshRecentMoves(in sub: NSMenu) {
        sub.removeAllItems()
        let moves = config.recentMoves(limit: 5)
        if moves.isEmpty {
            sub.addItem(NSMenuItem(title: "(no moves yet)", action: nil, keyEquivalent: ""))
        } else {
            for m in moves {
                let label = "\(m.timestamp)  \(String(m.fileName.prefix(28)))  →  \(m.destination)"
                sub.addItem(NSMenuItem(title: label, action: nil, keyEquivalent: ""))
            }
        }
    }

    // MARK: - File watcher

    private func startWatcher() {
        watcher.onChange = { [weak self] in
            guard let self = self else { return }
            if self.config.config.autoClassify {
                self.classifyNow()
            } else {
                // Just reindex so search stays current
                DispatchQueue.global(qos: .background).async {
                    SearchEngine.shared.reindex(watchURLs: ConfigManager.shared.watchURLs)
                }
            }
        }
        watcher.start(watching: config.watchURLs)
    }

    // MARK: - Auto-classify timer

    private func startAutoClassifyTimer() {
        let interval = TimeInterval(config.config.classifyInterval)
        classifyTimer = Timer.scheduledTimer(withTimeInterval: interval,
                                             repeats: true) { [weak self] _ in
            guard self?.config.config.autoClassify == true else { return }
            self?.classifyNow()
        }
    }

    // MARK: - Status bar flash

    private func flashStatus(body: String) {
        statusItem.button?.toolTip = body
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.statusItem.button?.toolTip = nil
        }
    }
}

// MARK: - Menu Delegate (refresh recent on open)

final class MenuDelegate: NSObject, NSMenuDelegate {
    static let shared = MenuDelegate()
    var onWillOpen: (() -> Void)?
    func menuWillOpen(_ menu: NSMenu) { onWillOpen?() }
}

