<p align="center"><img src="resources/Brand/Quillside-Mark.png" width="112" alt="Quillside"></p>

# Quillside

**Stay in Apple Notes. Make your ideas clear.**

[简体中文](README.zh-CN.md) · [GitHub](https://github.com/Asxing/quillside) · [Website](https://asxing.github.io/quillside/) · [Releases](https://github.com/Asxing/quillside/releases) · [Build instructions](docs/development/BUILDING.md) · [Release workflow](docs/development/RELEASING.md) · [MIT](LICENSE)

A native macOS writing companion for Apple Notes. Leave comments beside the original text, revise several passages together, review the draft, and apply it with native undo. Your notes remain in Apple Notes.

**0.7.7 is a developer preview.** Official Developer ID signing, notarization, and clean-machine installation testing are not complete. Download the `UNNOTARIZED` DMG or ZIP from [Releases](https://github.com/Asxing/quillside/releases), or build from source. The DMG installs by dragging Quillside into Applications; no build tools are required.

## Features

- Inline comments with overall guidance and locally retained revision drafts.
- Selection-based AI editing, translation, follow-up revisions, and guarded writeback.
- Agents defined by a role prompt and selected Skills, with article, personal-note, and reporting scenarios.
- Slash commands, Markdown shortcuts, configurable formatting toolbar, and templates.
- Backlinks previewed and explicitly written into the note itself.
- Embedded Pi Agent with API-key, compatible-service, and supported subscription sign-in options. Model access and quotas depend on your provider and account.

The interface uses SwiftUI and AppKit; Pi runs in a bundled Node process. App users do not need to install Node. The Mac app currently has a primarily Chinese interface; the website supports Simplified Chinese, Traditional Chinese, and English.

## Build

Use macOS with Swift 6.2+, Python 3.10+, Node.js matching `.node-version`, npm, and ripgrep.

```sh
npm ci --prefix runtime/pi --ignore-scripts
./scripts/verify-stage1.sh
OPENNOTES_CODE_SIGN_IDENTITY=- ./scripts/bundle-app.sh release
open build/Quillside.app
```

The minimum build target is macOS 14. Local on-device testing covers Apple Silicon on macOS 26.5.2; wider compatibility and Intel distribution are not claimed. Local builds do not require paid Apple Developer membership. Ad-hoc updates may require permissions again.

Grant Accessibility and Automation → Notes as prompted. Read-only note identification and backlinks also use Full Disk Access. Configure models, Agents, and Skills in Settings, then return to Notes. Select text and click AI or press `⌥⌘A`.

## Privacy and scope

New Pi connections store API keys and OAuth credentials in an app-specific local file; existing compatible connections keep using Keychain. Model requests include the material and instructions for the action you explicitly start. Opening an editing panel does not automatically generate, search other notes, or call external tools.

Comments and draft history may include note content and remain on your Mac. Cancellation stops local processing and stale writeback; it cannot withdraw content already received by a provider. Compatibility identifiers retain `OpenNotes` internally.

A separate knowledge base, separate search, background synchronization, MCP/tools, and complete Obsidian file import/export are outside the current scope.

## Contributing and releases

See [CONTRIBUTING](CONTRIBUTING.md), [SECURITY](SECURITY.md), [architecture](docs/development/ARCHITECTURE.md), [verification](VERIFICATION.md), and [CHANGELOG](CHANGELOG.md). Use synthetic material for issues and screenshots.

Tag pushes build and upload app DMG/ZIP tester packages and source, add direct download links at the top of the Release, and trigger a verified website update; unnotarized builds are prereleases, and official builds must pass signing and notarization. CI checks are not a replacement for real Notes installation and writeback testing.

## License

MIT, with upstream copyright notices retained. See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md) for NotesPlus, NotesBridge, Yams/LibYAML, Humanizer-zh, and the separate Pi/Node dependency licenses.

Quillside is independently developed and is not affiliated with Apple or ProNotes.
