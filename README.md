# TeXForge

**TeXForge** is a fork of [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html) -- the classic macOS LaTeX editor by Richard Koch. TeXForge inherits everything from TeXShop (typesetting, PDF preview, SyncTeX, macros, multi-file projects, etc.) and adds features aimed at a more modern editing experience.

TeXForge is a personal project and is not affiliated with or endorsed by the original TeXShop project.

## What TeXForge adds over TeXShop

### AI-powered inline completion

TeXForge brings Copilot-style ghost text to LaTeX editing. Suggestions appear as a semi-transparent overlay and can be accepted with Tab. Three providers are supported:

- **Ollama** -- local, private completions via any Ollama-hosted model
- **Claude API** -- Anthropic's Claude
- **GitHub Copilot** -- via OAuth device flow and SSE streaming

### Modern keyboard shortcuts

TeXForge adds shortcuts familiar from VS Code and other editors, while keeping all original TeXShop shortcuts:

| Action | TeXShop | TeXForge (added) |
|--------|---------|------------------|
| Indent | Cmd+] | Tab (with selection) |
| Unindent | Cmd+[ | Shift+Tab (with selection) |
| Comment/Uncomment | Cmd+Shift+] / Cmd+Shift+[ | Cmd+/ (toggle) |

### Updated defaults

- **Theme**: Solarized Lite (instead of LiteTheme)
- **Font**: SF Mono Regular 12pt (instead of system user font)
- **Icon**: Amber/copper to visually distinguish from TeXShop

## Differences from TeXShop

| | TeXShop | TeXForge |
|---|---------|----------|
| AI inline completion | -- | Ollama, Claude, GitHub Copilot |
| Tab/Shift+Tab indent | -- | Yes (when text selected) |
| Cmd+/ toggle comment | -- | Yes |
| Default theme | LiteTheme | Solarized Lite |
| Default font | System user font | SF Mono Regular 12pt |
| App icon | Blue | Amber/Copper |
| Bundle ID | `edu.uoregon.TeXShop` | `com.chkwon.TeXForge` |

Everything else -- typesetting engines, PDF viewer, SyncTeX, macro system, multi-language support, OgreKit find/replace -- is inherited from the original TeXShop codebase.

## Building

### Prerequisites

- macOS with Xcode (or Command Line Tools)
- No package managers needed -- all dependencies are vendored

### Command Line (recommended)

```bash
./build.sh          # Debug build
./build.sh Release  # Release build
```

The built app is at `build/Debug/TeXForge.app` or `build/Release/TeXForge.app`.

### Xcode

Open `TeXForge.xcodeproj` and build with Cmd+B.

No Apple Developer account is needed -- the build uses ad-hoc code signing.

## License

TeXForge is licensed under the [GNU General Public License v2.0](LICENSE), the same license as the original TeXShop.

Original TeXShop is Copyright 2001-2025, Richard Koch.

## Acknowledgments

TeXForge is built on the work of Richard Koch and all TeXShop contributors. See [Credits.rtf](Credits.rtf) for the full list.

- Upstream: [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html) ([source](https://github.com/TeXShop/TeXShop))
