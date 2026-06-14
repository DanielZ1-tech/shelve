import AppKit

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let menuBar = MenuBarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SetupWizardController.needsSetup {
            SetupWizardController.shared.show {
                self.startMenuBar()
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
            startMenuBar()
        }
    }

    private func startMenuBar() {
        menuBar.setup()
        MenuDelegate.shared.onWillOpen = { [weak self] in
            self?.menuBar.refreshMenu()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { FileWatcher.shared.stop() }
}
