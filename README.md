# mded

A minimal macOS markdown editor with a side-by-side preview pane and a Finder Quick Look extension. SwiftUI shell, AppKit split editor, WebKit preview. Renders via marked.js + highlight.js styled with github-markdown-css.

## Features

- Live preview alongside a monospaced editor pane (550 px default split)
- Two-way scroll sync between editor and preview
- Quick Look previews for `.md` files in Finder (same renderer as the in-app preview)
- **Appearance** menu: System / Light / Dark / Evening (Evening is a cream-on-charcoal palette extending to both panes)
- Underscores are treated as literal characters, so identifiers and paths like `__init__`, `snake_case_func`, and `/path/to/some_file.md` don't get italicised or bolded
- Standard `*emphasis*` and `**bold**` continue to work
- Relative image paths in markdown (`![alt](image.png)`) resolve against the document's directory

## Install

### Notarised release (recommended for colleagues)

Download the latest `mded-<version>.zip` from the [Releases](https://github.com/ersatzben/mded/releases) page, unzip, drag `mded.app` into `/Applications`. Double-click to launch — Apple-notarised, no Gatekeeper prompts.

### From source

```bash
git clone git@github.com:ersatzben/mded.git
cd mded
./install.sh
```

Requirements: Xcode and Command Line Tools (`xcode-select --install`). The script builds Release with ad-hoc signing, installs to `/Applications`, refreshes Launch Services, and resets the Quick Look extension host. First launch needs right-click → **Open** to clear Gatekeeper for the ad-hoc-signed binary.

## Develop

The Xcode project is generated from [`project.yml`](project.yml) via [xcodegen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml`:

```bash
xcodegen generate
```

Otherwise, open `mded.xcodeproj` directly in Xcode. macOS 14.0+, Swift 5.9.

Layout:

| Path | Role |
|---|---|
| `mded/` | Main app (SwiftUI shell + AppKit editor + WebKit preview) |
| `QuickLookExtension/` | The Finder Quick Look appex |
| `Shared/MarkdownRenderer.swift` | HTML/CSS/JS template used by both targets |
| `mded/Resources/` | Bundled CSS, JS, fonts, asset catalogue |

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

`release.sh` builds Release with Developer ID + Hardened Runtime, submits to Apple's notary service, staples the ticket, and emits `dist/mded-<version>.zip` ready to attach to a GitHub Release.

## Acknowledgements

mded bundles and depends on these projects:

- [marked.js](https://marked.js.org) — MIT
- [highlight.js](https://highlightjs.org) — BSD-3-Clause
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) — MIT

## License

MIT — see [LICENSE](LICENSE).
