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

## Installing

Pre-built releases are on the [Releases page](https://github.com/chkwon/TeXForge/releases/latest). Apple Silicon (M-series) only.

1. Download `TeXForge-vX.Y.Z-arm64.zip` from the latest release.
2. Unzip and drag `TeXForge.app` into `/Applications`.
3. Strip the macOS quarantine attribute -- without this, Gatekeeper refuses to open the app:

   ```bash
   xattr -dr com.apple.quarantine /Applications/TeXForge.app
   ```

4. Launch TeXForge from `/Applications` or Spotlight.

The `xattr` step is needed because TeXForge ships with an ad-hoc code signature, not an Apple-issued Developer ID signature. macOS attaches `com.apple.quarantine` to anything downloaded by a browser, and Gatekeeper blocks ad-hoc signed apps that carry it. Removing the attribute is the official escape hatch.

You only need this step on the first install. The in-app updater strips the attribute automatically on subsequent updates.

## Updating

TeXForge has a built-in updater that watches the GitHub Releases page.

- Pick **TeXForge → Check for Updates** from the menu bar.
- The updater fetches the latest release, compares versions, and -- if a newer release exists -- downloads the zip, verifies its SHA-256, replaces the running app, and relaunches.
- Apple Silicon only (matches the build).
- No background polling -- the check only runs when you invoke the menu item.

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

## Releasing

Maintainer checklist for cutting a new release:

1. Bump the version. Set both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to the new `X.Y.Z` in `TeXForge.xcodeproj/project.pbxproj` (four lines, all the same value -- find/replace works).
2. Commit on `main`:

   ```bash
   git commit -am "Bump version to X.Y.Z"
   git push origin main
   ```

3. Tag the bump commit and push the tag:

   ```bash
   git tag -a vX.Y.Z -m "TeXForge X.Y.Z"
   git push origin vX.Y.Z
   ```

4. The `release.yml` GitHub Actions workflow triggers on the `v*` tag push, builds an arm64 Release, zips the app, and publishes a GitHub release with auto-generated notes.
5. Verify:

   ```bash
   gh release view vX.Y.Z
   ```

   Confirm the release is published (not draft, not prerelease) and that `TeXForge-vX.Y.Z-arm64.zip` is attached.

To roll back a bad release:

```bash
gh release delete vX.Y.Z --yes
git push --delete origin vX.Y.Z
```

Then revert the bump commit and re-tag once fixed. Users who already auto-updated cannot be rolled back -- the in-app updater only moves forward.

## License

TeXForge is licensed under the [GNU General Public License v2.0](LICENSE), the same license as the original TeXShop.

Original TeXShop is Copyright 2001-2025, Richard Koch.

## Acknowledgments

TeXForge is built on the work of Richard Koch and all TeXShop contributors. See [Credits.rtf](Credits.rtf) for the full list.

- Upstream: [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html) ([source](https://github.com/TeXShop/TeXShop))
