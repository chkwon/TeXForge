# TeXForge

**TeXForge** is a fork of [TeXShop](https://pages.uoregon.edu/koch/texshop/texshop.html) -- the classic macOS LaTeX editor by Richard Koch. TeXForge inherits everything from TeXShop (typesetting, PDF preview, SyncTeX, macros, multi-file projects, etc.) and adds features aimed at a more modern editing experience.

TeXForge is a personal project and is not affiliated with or endorsed by the original TeXShop project.

## What TeXForge adds over TeXShop

### AI-powered inline completion

TeXForge brings Copilot-style ghost text to LaTeX editing. Suggestions appear as a semi-transparent overlay and can be accepted with Tab. Three providers are supported:

- **Ollama** -- local, private completions via any Ollama-hosted model
- **Claude API** -- Anthropic's Claude
- **GitHub Copilot** -- via OAuth device flow and SSE streaming

### Auto-loaded bibliography for cite/ref completion

TeXShop's cite-key completion historically required BibDesk.app to be open in the background. TeXForge replaces that with an in-memory bibliography parser:

- Auto-discovers and reads the `.bib` files referenced from the document via `\bibliography{}`, `\addbibresource{}`, and `\nobibliography{}`.
- Watches the source and bib files; the cache reparses automatically when any of them change on disk.
- Press **Cmd+Esc** inside `\cite{` (and natbib variants like `\citet`, `\citep`) to open the standard completion dropdown. Each row shows `<key> % <author> (<year>) <title>` so you can spot the right reference at a glance; only the bare cite key is committed to the buffer.
- The same mechanism powers `\ref{` / `\eqref{` / `\pageref{` / `\autoref{` against `\label{}` definitions in the source.

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
| Cite/ref completion source | Requires BibDesk.app running | Auto-loaded from referenced `.bib` files (with file watching) |
| Cite metadata in dropdown | Cite key only | `<key> % <author> (<year>) <title>` |
| Tab/Shift+Tab indent | -- | Yes (when text selected) |
| Cmd+/ toggle comment | -- | Yes |
| Default theme | LiteTheme | Solarized Lite |
| Default font | System user font | SF Mono Regular 12pt |
| App icon | Blue | Amber/Copper |
| Bundle ID | `edu.uoregon.TeXShop` | `net.chkwon.TeXForge` |

Everything else -- typesetting engines, PDF viewer, SyncTeX, macro system, multi-language support, OgreKit find/replace -- is inherited from the original TeXShop codebase.

## Installing

Pre-built releases are on the [Releases page](https://github.com/chkwon/TeXForge/releases/latest). Apple Silicon (M-series) only.

1. Download `TeXForge-vX.Y.Z-arm64.zip` from the latest release.
2. Unzip in Finder.
3. Drag `TeXForge.app` to `/Applications`.
4. Launch from `/Applications` or Spotlight.

Releases from v1.1.6 onward are signed with a Developer ID Application certificate and notarized by Apple, so Gatekeeper opens them with no warning. Earlier releases were ad-hoc signed and required stripping `com.apple.quarantine` manually -- see the [v1.1.5 README](https://github.com/chkwon/TeXForge/blob/v1.1.5/README.md#installing) for those instructions.

## Updating

TeXForge has a built-in updater that watches the GitHub Releases page.

- Pick **TeXForge → Check for Updates** from the menu bar.
- The updater fetches the latest release, compares versions, and -- if a newer release exists -- downloads the zip, verifies its SHA-256, atomically replaces the running app, and relaunches.
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

No Apple Developer account is needed -- the build uses ad-hoc code signing by default.

Developer ID signing and Apple notarization are also supported locally, driven by environment variables; see `CLAUDE.md` ("Developer ID signing and notarization") for the full list.

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

4. The `release.yml` GitHub Actions workflow triggers on the `v*` tag push, imports a Developer ID certificate into a temporary keychain, builds an arm64 Release, signs the bundle with hardened runtime and a secure timestamp, submits to Apple's notary service, staples the ticket, zips the result, and publishes a GitHub release with auto-generated notes.

   Required Apple Developer credentials are referenced from [`.github/workflows/release.yml`](.github/workflows/release.yml) as repo secrets; configure them under Settings → Secrets and variables → Actions before cutting a release. If any are missing or invalid, the "Set up signing keychain" or "Build Apple Silicon release" step will fail.
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
