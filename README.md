# mded

A minimal macOS markdown editor with a side-by-side preview pane and a Finder Quick Look extension. SwiftUI shell, AppKit split editor, WebKit preview. Renders via marked.js + highlight.js styled with github-markdown-css.

## Features

- Live preview alongside a monospaced editor pane (550 px default split, remembered once you move it)
- Show both panes, the editor only, or the preview only, per window (View menu)
- Two-way scroll sync between editor and preview, matched by source line so images and code blocks don't cause drift
- Markdown syntax colouring in the editor (Settings → Editor)
- Return continues lists, numbered lists (renumbered), task lists and quotes; Return on an empty item ends the list. Tab and Shift-Tab indent and outdent list items
- Find in the editor or the preview: ⌘F searches whichever pane has focus
- Zoom both panes together (⌘+ / ⌘− / ⌘0)
- Status bar with word and character counts and reading time (View → Show Status Bar)
- Export as a self-contained HTML file (styles inlined, local images embedded, scripts stripped) or a paginated PDF, and print; always in the light theme
- Quick Look previews for Markdown files in Finder (same renderer as the in-app preview)
- Opens `.md`, `.markdown`, `.mdown`, `.mkd` and `.mkdn`; UTF-8 (with or without a BOM), UTF-16 and legacy encodings like Windows-1252, saved back in the encoding they were read in
- Links in the preview: web links open in your browser, links to other Markdown files open in mded, `#heading` links jump within the document (headings get GitHub-style ids)
- Reloads automatically when another app changes the file and you have no unsaved edits
- **Appearance** menu: System / Light / Dark / Evening (Evening is a charcoal-on-cream palette extending to both panes)
- Underscores are literal by default, so standalone identifiers like `__init__` and `_private` aren't bolded or italicised. Use `*emphasis*` and `**bold**`, or turn this off in Settings to get standard `_emphasis_` and `__bold__`
- Relative image paths in markdown (`![alt](image.png)`) resolve against the document's directory
- Closing a window with unsaved changes asks Save / Don't Save / Cancel; unsaved work is still autosaved in the background (to `~/Library/Autosave Information`, never into or beside your file) so it survives a crash

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 / ⌘2 / ⌘3 | Editor and preview / editor only / preview only |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / actual size |
| ⌘F, ⌘G, ⇧⌘G, ⌘E | Find, next, previous, use selection (in the focused pane) |
| ⌥⌘F | Find and replace (editor) |
| ⌘P, ⇧⌘P | Print, page setup |
| ⌘, | Settings |
| Tab / ⇧Tab | Indent / outdent list items |

### Security

HTML embedded in a Markdown file renders, but nothing in it can run: page JavaScript is disabled, and the renderer runs in an isolated script world. The preview never navigates away from the document. Local files are served to the preview only if they are images, audio or video. Quick Look previews also block remote content, so selecting a file in Finder doesn't contact any server.

## Install

### Homebrew (recommended)

```bash
brew install --cask ersatzben/mded/mded
```

Brew auto-taps `ersatzben/mded` on first invocation. Update with `brew upgrade --cask mded`. Apple-notarised, no Gatekeeper prompts.

### Pre-built zip

If you'd rather avoid Homebrew, grab the latest `mded-<version>.zip` from the [Releases](https://github.com/ersatzben/mded/releases) page, unzip, and drag `mded.app` into `/Applications`. Same notarised binary, just delivered manually.

### From source

```bash
git clone git@github.com:ersatzben/mded.git
cd mded
./install.sh
```

Requirements: Xcode and Command Line Tools (`xcode-select --install`). The script builds Release with ad-hoc signing, installs to `/Applications`, refreshes Launch Services, and resets the Quick Look extension host (offering to relaunch Finder). It won't replace a Homebrew-installed copy unless you set `MDED_FORCE_INSTALL=1`. First launch needs right-click → **Open** to clear Gatekeeper for the ad-hoc-signed binary.

## Develop

The Xcode project is generated from [`project.yml`](project.yml) via [xcodegen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml`:

```bash
xcodegen generate
```

Otherwise, open `mded.xcodeproj` directly in Xcode. macOS 14.0+, Swift 5.9.

Run the tests with `xcodebuild -project mded.xcodeproj -scheme mded test` (or ⌘U in Xcode). They cover the renderer (Markdown output, heading ids, source-line mapping, script blocking, image loading, DOM patching, HTML export), list editing, editor syntax scanning, word counts and text encodings. CI runs the build and tests on every push and pull request.

Layout:

| Path | Role |
|---|---|
| `mded/` | Main app (SwiftUI shell + AppKit editor + WebKit preview) |
| `QuickLookExtension/` | The Finder Quick Look appex |
| `Shared/` | Used by both targets (and the tests): preview page and web view setup, local-file scheme handler, text encoding, list editing, syntax scanning |
| `mded/Resources/renderer.js` | Preview renderer: marked.js configuration, highlighting, DOM patching, scroll sync |
| `mded/Resources/` | Bundled CSS, JS, asset catalogue |
| `Tests/` | Unit tests (not hosted in the app) |

## Release (notarised)

One-time setup:

```bash
xcrun notarytool store-credentials "mded-notary" \
    --apple-id "<your-apple-id>" \
    --team-id  "<your-team-id>" \
    --password "<app-specific-password>"   # from appleid.apple.com
```

Then for each release:

```bash
./release.sh 1.0.1
```

`release.sh` builds Release with Developer ID + Hardened Runtime, submits to Apple's notary service, staples the ticket, emits `dist/mded-1.0.1.zip`, commits the version bump, creates the GitHub release with the zip attached, and bumps the [homebrew-mded](https://github.com/ersatzben/homebrew-mded) cask so `brew upgrade --cask mded` picks it up.

Publishing requires a clean working tree on `main`, and a tag that's either new or already on `HEAD` (so a failed run can be resumed); the tag therefore always matches the shipped binary. The script stamps both `CFBundleShortVersionString` and `CFBundleVersion`, and puts the plists back if it stops before committing them.

Env-var escape hatches: `MDED_NO_PUBLISH=1` (build + notarise only, no git/release/tap steps; allows a dirty tree), `MDED_NO_TAP_BUMP=1` (release but don't touch the tap), `MDED_TAP_DIR=path` (override the tap repo location, default `~/dev/homebrew-mded`).

## Acknowledgements

mded bundles and depends on these projects:

- [marked.js](https://marked.js.org) — MIT
- [highlight.js](https://highlightjs.org) — BSD-3-Clause
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) — MIT

## License

MIT — see [LICENSE](LICENSE).
