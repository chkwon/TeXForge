# TeXForge

TeXForge is a macOS LaTeX editor forked from [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html), adding inline AI code completion (Copilot-style ghost text) for LaTeX editing.

## What TeXForge Adds

TeXForge builds on TeXShop -- the classic macOS TeX/LaTeX editor by Richard Koch -- and adds AI-powered inline completions from multiple providers:

- **Ollama** -- local, private completions via any Ollama-hosted model
- **Claude API** -- Anthropic's Claude for high-quality LaTeX suggestions
- **GitHub Copilot** -- GitHub Copilot via OAuth device flow and SSE streaming

Suggestions appear as ghost text (semi-transparent overlay) and can be accepted with Tab, similar to code editors with Copilot integration.

## Differences from TeXShop

| Feature | TeXShop | TeXForge |
|---------|---------|----------|
| Inline AI completion | No | Yes (Ollama, Claude, GitHub Copilot) |
| App icon | Blue | Amber/Copper |
| Bundle ID | `edu.uoregon.TeXShop` | `com.chkwon.TeXForge` |

TeXForge is a personal fork and is not affiliated with or endorsed by the original TeXShop project.

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

Open `TeXShop.xcodeproj` and build with Cmd+B.

No Apple Developer account is needed -- the build uses ad-hoc code signing.

## Branching Strategy

- **`master`** -- Tracks upstream TeXShop. Never commit fork changes here.
- **`forge`** -- Fork branch with TeXForge customizations. Merge `master` into `forge` to pick up upstream updates.

## License

TeXForge is licensed under the [GNU General Public License v2.0](LICENSE), the same license as the original TeXShop.

Original TeXShop is Copyright 2001-2025, Richard Koch.

## Acknowledgments

TeXForge is built on the work of Richard Koch and all TeXShop contributors. See [Credits.rtf](Credits.rtf) for the full list.

- Upstream: [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html) ([source](https://github.com/TeXShop/TeXShop))
