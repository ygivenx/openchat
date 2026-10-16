# OpenChat

Native macOS client for any OpenAI-compatible API — with simple local tools.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Xcode 15+](https://img.shields.io/badge/Xcode-15%2B-blue) ![License Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-green)

## Features

- **Chat** — streaming, cancellable, concurrent per-chat, with reasoning display
- **Vision** — paste/drop images (auto-resized, base64 `image_url`)
- **Files** — attach any file (≤5 MB) as context
- **Tools** — `web_search`/`web_fetch` (DuckDuckGo, SafeSearch), `remember`/`recall` (persistent memory), `save_file` (Save panel) with safety guards
- **Privacy** — chats in Application Support, API keys in Keychain, no telemetry

## Quick Start

```bash
open MacApp/OpenChat.xcodeproj
# Set Base URL (e.g. http://localhost:8000/v1) and Model in Settings → Test
```

Both HTTP and HTTPS endpoints supported.

## Build

```bash
xcodebuild build -project MacApp/OpenChat.xcodeproj -scheme OpenChat -configuration Debug
open ~/Library/Developer/Xcode/DerivedData/OpenChat-*/Build/Products/Debug/OpenChat.app
```

## iOS

Native iPhone/iPad app in `MacApp/OpenChatiOS` + `OpenChatiOS.xcodeproj` — shares `OpenAIClient`/`ChatHistory`/`Tools` with macOS, uses `PHPicker`/`UIDocumentPicker` + `UIKit` media handling. Open `MacApp/OpenChatiOS.xcodeproj` and run on Simulator (iOS 16+).

## Release (signed + notarized)

```bash
export DEVELOPER_ID_APPLICATION="Apple Development: Name (TEAMID)"
export APPLE_TEAM_ID="TEAMID"
export NOTARY_PROFILE="notary-profile" # from `xcrun notarytool store-credentials`
./scripts/release-macos.sh
# DMG
hdiutil create -volname "OpenChat" -srcfolder MacApp/build/release/OpenChat.app -ov -format UDZO MacApp/build/release/OpenChat.dmg
```

See `scripts/archive-appstore.sh` for App Store Connect archive.

## Project

```
MacApp/OpenChat/         # SwiftUI app
MacApp/OpenChat.xcodeproj
branding/                # logo/icon sources
scripts/                 # release helpers
```

## License

Apache 2.0 — see [LICENSE](LICENSE).
