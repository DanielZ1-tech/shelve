import AppKit
import SwiftUI

// MARK: - Setup Wizard Controller

final class SetupWizardController {

    static let shared = SetupWizardController()
    private var window: NSWindow?

    static var needsSetup: Bool {
        !UserDefaults.standard.bool(forKey: "shelve.setupComplete")
    }

    func show(onComplete: @escaping () -> Void) {
        // Temporarily show in Dock so the wizard window can become key
        NSApp.setActivationPolicy(.regular)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "Welcome to Shelve"
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.center()
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView:
            SetupWizardView {
                UserDefaults.standard.set(true, forKey: "shelve.setupComplete")
                w.close()
                onComplete()
            }
        )
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Setup Wizard View

private struct SetupWizardView: View {

    let onFinish: () -> Void

    @State private var step = 0
    @State private var watchPaths: [String] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
    ]
    @State private var autoClassify = true
    @State private var interval = 60

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                         Color(red: 0.1, green: 0.1, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        Circle()
                            .fill(i <= step ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                            .animation(.spring(response: 0.3), value: step)
                    }
                }
                .padding(.top, 28)

                Spacer()

                // Step content
                Group {
                    switch step {
                    case 0: WelcomeStep()
                    case 1: FolderStep(watchPaths: $watchPaths)
                    case 2: AutoClassifyStep(autoClassify: $autoClassify, interval: $interval)
                    default: DoneStep()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)

                Spacer()

                // Navigation buttons
                HStack {
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(WizardSecondaryButton())
                    }
                    Spacer()
                    Button(step < 3 ? "Continue" : "Start Using Shelve") {
                        if step < 3 {
                            withAnimation { step += 1 }
                        } else {
                            applySettings()
                            onFinish()
                        }
                    }
                    .buttonStyle(WizardPrimaryButton())
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 560, height: 420)
        .preferredColorScheme(.dark)
    }

    private func applySettings() {
        var cfg = ConfigManager.shared.config
        cfg.watchDirs = watchPaths.isEmpty
            ? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path]
            : watchPaths
        cfg.autoClassify = autoClassify
        cfg.classifyInterval = interval
        ConfigManager.shared.config = cfg
        ConfigManager.shared.save()
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("📂")
                .font(.system(size: 72))
            Text("Welcome to Shelve")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text("Shelve automatically organizes your Downloads folder\nand lets you search any file instantly from the menu bar.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 48)
    }
}

private struct FolderStep: View {
    @Binding var watchPaths: [String]

    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var presets: [(label: String, icon: String, path: String)] {
        [
            ("Downloads", "arrow.down.circle.fill",
             (home as NSString).appendingPathComponent("Downloads")),
            ("Desktop",   "desktopcomputer",
             (home as NSString).appendingPathComponent("Desktop")),
            ("Documents", "doc.fill",
             (home as NSString).appendingPathComponent("Documents")),
        ]
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.white)

            Text("Which folders should Shelve watch?")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text("Shelve monitors these folders and organizes new files automatically. You can change this later.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Preset toggles
            VStack(spacing: 8) {
                ForEach(presets, id: \.path) { preset in
                    let on = watchPaths.contains(preset.path)
                    Button {
                        if on { watchPaths.removeAll { $0 == preset.path } }
                        else  { watchPaths.append(preset.path) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(on ? .white : .white.opacity(0.5))
                                .frame(width: 22)
                            Text(preset.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(on ? .white : .white.opacity(0.6))
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(on ? Color.green : .white.opacity(0.3))
                                .font(.system(size: 18))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(on ? .white.opacity(0.14) : .white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)

            // Custom folders added by picker
            let customs = watchPaths.filter { path in !presets.map(\.path).contains(path) }
            if !customs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(customs, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.white.opacity(0.7))
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                watchPaths.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 40)
            }

            // Add custom button
            Button(action: pickCustomFolder) {
                Label("Add Custom Folder…", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch These Folders"
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path
                if !watchPaths.contains(path) { watchPaths.append(path) }
            }
        }
    }
}

private struct AutoClassifyStep: View {
    @Binding var autoClassify: Bool
    @Binding var interval: Int

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text("Auto-organize files")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Shelve can automatically sort new files into\nsubfolders based on type and keywords.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Toggle("Automatically classify new files", isOn: $autoClassify)
                    .toggleStyle(.switch)
                    .foregroundStyle(.white)

                if autoClassify {
                    HStack {
                        Text("Check every")
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: Binding(
                            get: { Double(interval) },
                            set: { interval = Int($0) }
                        ), in: 10...300, step: 10)
                        Text("\(interval)s")
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 36, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 48)
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're all set!")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text("Shelve lives in your menu bar — look for the 📂 icon.\nUse ⌘⇧F to open the search bar at any time.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Button Styles

struct WizardPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct WizardSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.1)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
