# Contributing to MicroduckRemote

Thanks for your interest in contributing to **MicroduckRemote**!

## Requirements

- **macOS 27.3+** and **Xcode 27.3+** (iOS 27.3 / macOS 27.3 SDKs for Siri AI `@AppIntent(.tool)`, `@AppEntity(.generable)`, `CardSnippet`, `Skills.skillsbundle`, and `SiriEvaluations`).
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`) if you modify `project.yml`.
- Optional for local simulation: [`pollen-robotics/microduck`](https://github.com/pollen-robotics/microduck) (`scripts/duck-sim`) and `microduck_rl`.

## Local Signing Setup

To avoid committing personal Apple Developer Team IDs or bundle identifiers:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` (gitignored) with your `DEVELOPMENT_TEAM` and a unique `APP_BUNDLE_ID`. `App/Info.plist`, `App/Info-macOS.plist`, `MicroduckRemote.entitlements`, `DuckConstants`, and `MicroduckSiriEvaluations` all derive their bundle ID, App Group, iCloud container, and OAuth URL name from `$(APP_BUNDLE_ID)` automatically.

## Running Tests & Verification

1. **Swift Package unit tests** (iOS Simulator):
   ```bash
   cd MicroduckRemotePackage
   xcodebuild test \
     -scheme MicroduckRemotePackage-Package \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -derivedDataPath ../DerivedData
   ```
2. **Siri AI metadata analyzer** (after building `MicroduckRemote` or `MicroduckRemoteMac`):
   ```bash
   xcrun sirimetadataanalyzer path/to/Microduck.app
   ```
   Ensure it reports `0 findings`.
3. **Regenerating the Xcode project** (after editing `project.yml`):
   ```bash
   xcodegen generate
   ```

## Pull Requests

- Keep changes focused and include unit tests in `MicroduckRemotePackage/Tests/` for new protocol, dependency, or App Intent behavior.
- Never commit `Config/Local.xcconfig`, Hugging Face tokens, or personal Apple Team IDs.
- Run `xcrun sirimetadataanalyzer` whenever you add or edit App Intents, App Entities, or `App/Skills.skillsbundle`.
