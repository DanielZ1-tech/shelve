# Shelve — Native macOS App

Full Swift rewrite of the Shelve Downloads organizer.  
Replaces all Python/tkinter/rumps code with native AppKit + SwiftUI.

## Open in Xcode

1. Open Xcode
2. File → Open → select the `shelve-native` folder (Xcode detects Package.swift automatically)
3. Set the scheme target to **Shelve** and destination to **My Mac**
4. ⌘R to run

## What's in here

| File | Replaces |
|------|----------|
| `AppDelegate.swift` | app entry point |
| `MenuBarManager.swift` | `menubar.py` (rumps) |
| `SearchPanel.swift` | `search_window.py` (tkinter NSPanel wrapper) |
| `SearchView.swift` | `search_window.py` (SwiftUI UI — **fixes typing**) |
| `SearchEngine.swift` | `search.py` (TF-IDF in pure Swift) |
| `Classifier.swift` | `classifier.py` (rule-based, extension + keyword) |
| `FileWatcher.swift` | Python `watchdog` (FSEvents native) |
| `Config.swift` | `classifier_config.py` (JSON in ~/Library/Application Support/Shelve) |
| `Models.swift` | shared data types |

## Why the search bar now works

The old `search_window.py` used `overrideredirect(True)` on a tkinter window to 
get a borderless look. On macOS, that makes the window non-activatable — it can 
never receive keyboard focus no matter how many `focus_force()` calls you make.

The fix: use a native `NSPanel` with `becomesKeyOnlyIfNeeded = false` and call 
`makeKey()` after ordering front. Native windows handle focus correctly by design.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧F | Open search |
| ⌘K | Classify now |
| ⌘Z | Undo last move |
| ↑↓ | Navigate results |
| Tab | Switch Files/History mode |
| ↩ | Open in Finder |
| ⎋ | Close search |

## Config

Stored at: `~/Library/Application Support/Shelve/config.json`

```json
{
  "watchDirs": ["~/Downloads"],
  "autoClassify": true,
  "classifyInterval": 60
}
```

## Build a distributable .app

Product → Archive in Xcode, then Distribute App → Direct Distribution.
