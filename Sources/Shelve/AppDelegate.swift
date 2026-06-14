import AppKit

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let menuBar = MenuBarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the Finder Quick Action service provider
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()

        // Request notification permission (non-blocking; user sees system prompt once)
        NotificationManager.shared.requestPermission()

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
        MainWindowController.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { FileWatcher.shared.stop() }
}
