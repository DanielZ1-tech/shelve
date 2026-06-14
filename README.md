# Shelve

A native macOS menu bar app that automatically organizes your Downloads folder. Built entirely in Swift and SwiftUI — no Python, no Electron.

![macOS](https://img.shields.io/badge/macOS-26+-black) ![Swift](https://img.shields.io/badge/Swift-6.2-orange) ![License](https://img.shields.io/badge/license-MIT-blue)

---

## Features

- **Auto-classify** — watches your Downloads folder and sorts files into subfolders automatically
- **Smart rules** — match by file extension, keyword, or date (older than X days, newer than X weeks, etc.)
- **Auto-rename** — add date prefixes, lowercase filenames, replace spaces, add custom prefixes/suffixes
- **Move to Trash** — rules can trash files instead of sorting them (great for old installers)
- **TF-IDF search** — fast full-text search across all your organized files
- **History mode** — see every move Shelve has made, with one-click undo
- **Setup wizard** — first-launch onboarding to get you configured in seconds
- **Liquid Glass UI** — native macOS 26 design language throughout

---

## Getting Started

### Requirements

- macOS 26+
- Xcode 16+

### Run in Xcode

1. Clone the repo and open the `shelve-native` folder in Xcode (it detects `Package.swift` automatically)
2. Set the scheme to **Shelve** and destination to **My Mac**
3. Hit **⌘R**

### Build a distributable .app

```bash
# After building in Xcode (⌘B):
./build-app.sh
```

Drag `Shelve.app` to `/Applications`.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧F | Open search |
| ⌘K | Classify now |
| ⌘Z | Undo last move |
| ↑ ↓ | Navigate results |
| Tab | Toggle Files / History |
| ↩ | Open in Finder |
| ⎋ | Close search |

---

## How Rules Work

Each rule has:
- **Extensions** — e.g. `.pdf`, `.docx`
- **Keywords** — matched against the filename
- **Date conditions** — e.g. "modified older than 30 days"
- **Rename steps** — applied in order before moving
- **Move to Trash** — trashes the file instead of sorting it

A file is moved if it matches an extension or keyword **or** any date condition. Rules are fully editable in **Settings → Rules**.

---

## Config

Stored at `~/Library/Application Support/Shelve/config.json`. Editable via the Settings window (menu bar icon → Settings).

---

## Project Structure

| File | Purpose |
|------|---------|
| `AppDelegate.swift` | App entry point, setup wizard gate |
| `MenuBarManager.swift` | Menu bar icon and menu |
| `SearchPanel.swift` | Native `NSPanel` for the search window |
| `SearchView.swift` | SwiftUI search UI |
| `SearchEngine.swift` | TF-IDF search in pure Swift |
| `Classifier.swift` | Rule matching, file moves, trash, rename |
| `FileWatcher.swift` | FSEvents-based folder watching |
| `Config.swift` | JSON config persistence |
| `Models.swift` | Shared data types |
| `SetupWizard.swift` | First-launch onboarding flow |
| `SettingsView.swift` | Settings window (General, Rules, About) |
