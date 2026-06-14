import AppKit
import SwiftUI

// MARK: - Search Panel (macOS 26 — .glassEffect() handles all materials)

final class SearchPanelController {

    static let shared = SearchPanelController()
    private var panel: NSPanel?
    private var clickMonitor: Any?

    func show() {
        if let panel = panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 52),
            styleMask:  [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing:    .buffered,
            defer:      false
        )

        panel.isFloatingPanel             = true
        panel.level                       = .floating
        panel.isOpaque                    = false
        panel.backgroundColor             = .clear   // glass handles the fill
        panel.hasShadow                   = true
        panel.titleVisibility             = .hidden
        panel.titlebarAppearsTransparent  = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded      = false
        panel.hidesOnDeactivate           = false    // accessory apps never "activate"

        let hosting = NSHostingView(rootView: SearchView())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        // Position: centred, ~22 % from top of screen
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x  = sf.minX + (sf.width  - 580) / 2
            let y  = sf.minY +  sf.height - sf.height * 0.22 - 52
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel

        // Dynamically resize panel height as SwiftUI content grows
        hosting.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object:  hosting,
            queue:   .main
        ) { [weak panel, weak hosting] _ in
            guard let panel, let hosting else { return }
            let fit = hosting.fittingSize
            var fr  = panel.frame
            let dh  = fit.height - fr.height
            fr.size.height = fit.height
            fr.origin.y   -= dh
            panel.setFrame(fr, display: true, animate: false)
        }

        panel.orderFrontRegardless()
        panel.makeKey()

        // Close when user clicks outside the panel
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        panel?.close()
        panel = nil
    }

    func toggle() { panel?.isVisible == true ? hide() : show() }
}
