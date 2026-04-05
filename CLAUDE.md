# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TeXForge is a personal fork of [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html) — a macOS LaTeX/TeX editor with integrated PDF preview, written in Objective-C. It is a document-based Cocoa application (NSDocument architecture). Licensed under GNU GPL v2.

### What TeXForge adds over TeXShop

- **AI inline completion** — Copilot-style ghost text via Ollama (local), Claude API, or GitHub Copilot
- **Modern keyboard shortcuts** — Tab/Shift+Tab for indent/unindent (with selection), Cmd+/ to toggle comment; original TeXShop shortcuts (Cmd+]/[, Cmd+Shift+]/[) are preserved
- **Updated defaults** — Solarized Lite theme, SF Mono Regular 12pt font, amber/copper icon

Everything else (typesetting, PDF viewer, SyncTeX, macros, multi-file projects, localization) is inherited from the original TeXShop codebase.

## Building

- **CLI (recommended):** `./build.sh` (Debug) or `./build.sh Release`
- **Xcode:** Open `TeXForge.xcodeproj`, build with Cmd+B
- No package managers — all dependencies are vendored in `3rdparty/`
- No test targets; testing is manual through the application UI
- No Apple Developer account needed — uses ad-hoc code signing (`CODE_SIGN_IDENTITY=-`)
- Built app: `build/Debug/TeXForge.app` or `build/Release/TeXForge.app`
- The build script handles a macOS quirk: `.nib`/`.rtfd` package directories get auto-assigned `FinderInfo` extended attributes that block code signing, so `build.sh` strips them and re-signs after compilation

## Architecture

### Document-Based App Pattern

The app follows the standard `NSDocumentController` → `NSDocument` → `NSWindowController` pattern:

- **`TSDocumentController`** — Custom document controller handling encoding selection and stationery
- **`TSDocument`** (~11K lines) — Central model class managing the full document lifecycle. Split into categories for maintainability:
  - `TSDocument-Jobs` — Typesetting execution via `NSTask` (supports pdfTeX, XeLaTeX, LuaLaTeX, ConTeXt, custom engines)
  - `TSDocument-SyncTeX` — Bidirectional source↔PDF synchronization
  - `TSDocument-Syntax` — Syntax highlighting
  - `TSDocument-Color`, `TSDocument-XML`, `TSDocument-HTML`, `TSDocument-Scrap`, `TSDocument-RootFile`, etc.
- **`TSAppDelegate`** — App lifecycle, menu management, panel coordination

### Major Subsystems

| Subsystem | Key Classes | Notes |
|-----------|-------------|-------|
| Text Editor | `TSTextView` (extends `NSTextView`), `TSLayoutManager`, `NoodleLineNumberView` | Syntax coloring, macro completion, drag-and-drop |
| PDF Viewer | `MyPDFKitView` (extends `PDFView`), plus categories for Annotations, Gestures, Magnification, ExternalEditor | Primary viewer; `MyPDFView` is a legacy fallback |
| Typesetting | `TSDocument-Jobs` | Launches TeX engines as `NSTask`; engine selected via `% !TEX program=` magic comments or preferences |
| SyncTeX | `TSDocument-SyncTeX`, `synctex_parser.h/c` | Forward/backward sync between source and PDF |
| Preferences | `TSPreferences` (~2.9K lines), `TSPreferences-Color` | Engine paths, colors, fonts, themes (`DarkTheme.plist`, `LiteTheme.plist`) |
| Macros | `TSMacroMenuController` (singleton), `TSMacroTreeNode`, `TSMacroEditor` | Hierarchical macro system loaded from `~/Library/TeXForge/Macros/Macros.plist` |
| Toolbar | `TSToolbarController` | Typeset buttons, program selection |
| Window Mgmt | `TSWindowManager` (singleton), `TSTextEditorWindow`, `TSPreviewWindow`, `TSConsoleWindow` | Multi-window coordination |
| Copilot | `TSCopilotManager`, `TSCopilotAPIClient`, `TSCopilotOverlayView`, `TSTextView+Copilot` | Inline AI completion integration |

### Globals

`globals.h/m` (~25K) defines all `NSUserDefaults` keys, magic comment parsing, file type enumerations, and color constants. This is the first place to look for preference keys and app-wide constants.

### Typesetting Flow

1. User triggers compile → `TSDocument` resolves root file (multi-file projects)
2. Engine determined from `% !TEX program=` comment or preferences
3. `environmentForSubTask` builds PATH with TeX binary paths
4. `NSTask` launched with the selected engine
5. stdout/stderr captured to console window
6. On completion: PDF reloaded, SyncTeX file parsed

## Key Directories

- **`Sources/`** — All Objective-C source (~160 files). Mix of ARC and MRC.
- **`Resources/Interfaces/`** — XIB/NIB files with 13 language localizations
- **`Resources/TeXShop/`** — Engine scripts, shell script wrappers, macros, templates, command completion data
- **`3rdparty/`** — Vendored: Sparkle (auto-update), OgreKit (regex/search), zlib, Spotlight mdimporter
- **`Resources/Shellscripts/`** — ~30 helper shell scripts for TeX operations

## Vendored Frameworks

- **Sparkle 1.24.0** — Software auto-update (embedded in app bundle)
- **OgreKit 2.1.12** — Regex-based find/replace (embedded in app bundle)
- Both are code-signed on copy during build

### Sparkle Auto-Update (currently disabled)

Automatic update checking is disabled at multiple levels:

1. **Compile-time** — `Sources/UseSparkle.h`: `#define USESPARKLE` is commented out, so all Sparkle code in `TSPreferences.m` is excluded via `#ifdef`
2. **Info.plist** — `Resources/Info.plist`: `SUFeedURL` is empty (no appcast URL configured)
3. **Factory defaults** — `Resources/Shellscripts/FactoryDefaults.plist`: `SparkleAutomaticUpdate` is `false`

To re-enable automatic update checking:
1. Uncomment `#define USESPARKLE` in `Sources/UseSparkle.h`
2. Set `SUFeedURL` in `Resources/Info.plist` to a valid appcast URL
3. Optionally set `SparkleAutomaticUpdate` to `true` in `FactoryDefaults.plist` (or let users enable it in Preferences)

Related preference keys (defined in `globals.h/m`): `SparkleAutomaticUpdateKey`, `SparkleIntervalKey`. The preferences UI for Sparkle is in `TSPreferences.m` (`sparkleAutomaticCheck:` action). A legacy manual update checker also exists in `TSAppDelegate.m` (`checkForUpdate:`) that hits the original TeXShop server.

## Conventions

- Objective-C with Cocoa/AppKit patterns (delegates, IBOutlet/IBAction, NSNotification)
- Large classes decomposed via ObjC categories (e.g., `TSDocument(JobProcessing)`)
- Singletons for app-wide managers (`TSWindowManager`, `TSMacroMenuController`)
- UI defined in XIB/NIB files, not programmatic
- File associations and document types configured in `Resources/Info.plist`
- AppleScript support via `TSDocumentScripting` and `TeXShop.scriptSuite`
