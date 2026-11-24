# Getting Started

Configure local signing, open the Xcode workspace, and run the test suite and Siri metadata analyzer.

## Requirements

- **Xcode 27.3+** (iOS 27.3 and macOS 27.3 SDKs)
- **macOS 27.3+** to run `MicroduckRemoteMac` and Siri AI locally
- **iOS 27.3+** for physical iPhone/iPad builds (LiDAR scanning requires a LiDAR-equipped Pro device)
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) when modifying `project.yml`
- Optional for local simulation: [`pollen-robotics/microduck`](https://github.com/pollen-robotics/microduck) and `microduck_rl`

## Local Signing Configuration

The repository ships with neutral signing defaults in `Config/Base.xcconfig` (`APP_BUNDLE_ID = com.microduck.remote`, no committed Team ID) so you can clone and build without exposing personal Apple Developer credentials.

To build for a physical device or use your own bundle identifier, create a gitignored `Config/Local.xcconfig`:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set your Apple Development Team ID and a unique reverse-DNS bundle identifier:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
APP_BUNDLE_ID = com.yourname.microduckremote
```

All derived identifiers update automatically from `$(APP_BUNDLE_ID)`:

- App Groups (`group.$(PRODUCT_BUNDLE_IDENTIFIER)`) in `MicroduckRemote.entitlements` and `DuckConstants.appGroupID`
- iCloud container (`iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`) in `DuckConstants.iCloudContainerID`
- OAuth callback URL name (`$(PRODUCT_BUNDLE_IDENTIFIER).oauth`) in `App/Info.plist` and `App/Info-macOS.plist`
- Siri evaluation test bundle (`$(APP_BUNDLE_ID).sirieval`)

## Opening the Workspace

Always open `MicroduckRemoteWorkspace.xcworkspace` rather than `MicroduckRemote.xcodeproj` alone so Xcode indexes both application targets alongside `MicroduckRemotePackage`:

```bash
open MicroduckRemoteWorkspace.xcworkspace
```

- **iOS:** Select the **`MicroduckRemote`** scheme.
- **macOS:** Select the **`MicroduckRemoteMac`** scheme and choose **My Mac**.

## Running Tests & Verification

Run all Swift Package unit tests on an iOS 27.3 Simulator:

```bash
cd MicroduckRemotePackage
xcodebuild test \
  -scheme MicroduckRemotePackage-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ../DerivedData
```

After building an app target, validate the compiled App Intents metadata with Apple's built-in analyzer:

```bash
xcrun sirimetadataanalyzer path/to/Microduck.app
```

If you edit `project.yml`, regenerate the Xcode project before building:

```bash
xcodegen generate
```
