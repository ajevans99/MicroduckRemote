# MicroduckRemote

Native SwiftUI + Metal iOS and macOS app for driving, observing, and installing Hugging Face tricks onto a simulated (`scripts/duck-sim`) or physical Microduck robot over WebRTC, with full Apple Shortcuts & Siri App Intents support on both platforms.

## Opening in Xcode

Always open **`MicroduckRemoteWorkspace.xcworkspace`** (rather than `.xcodeproj` alone) so Xcode indexes both app targets and `MicroduckRemotePackage`:

```bash
open MicroduckRemoteWorkspace.xcworkspace
```

- **iOS**: Select the **`MicroduckRemote`** scheme (iOS 27.3+).
- **macOS**: Select the **`MicroduckRemoteMac`** scheme and run on **My Mac** (macOS 27.2+).

## Driving `duck-sim` Locally

On **macOS**, open the **Simulator** tab (`⌘4`) in **Microduck** to launch, restart, and stop `scripts/duck-sim` directly—pick between built-in scenes (like `playground` or `backlash`), configure cameras (`a` / `all` / off), duck count (`1`–`4`), MuJoCo 3D viewer, and inspect live daemon logs.

You can also launch from the terminal in `pollen-robotics/microduck`:

1. Start `duck-sim` with camera support:
   ```bash
   DUCK_SIM_SCENE=playground DUCK_SIM_CAMERAS=a scripts/duck-sim
   ```
2. Make sure any browser console (`:8080` or `:7860`) is **disconnected** so the single-consumer WebRTC slot is free.
3. Run **`MicroduckRemote`** (on any iOS Simulator) or **`MicroduckRemoteMac`** (on My Mac)—the app auto-connects to `ws://127.0.0.1:8443` and streams live 30 fps H.264 Metal camera video plus 50 Hz telemetry.

## Syncing iPhone LiDAR Room Scans via iCloud Drive

The macOS **Simulator** tab watches **`iCloud Drive/Microduck Scenes/`** (`~/Library/Mobile Documents/com~apple~CloudDocs/Microduck Scenes/`, or any custom folder you choose) for exported `scene_<slug>.xml` MuJoCo scenes (and optional `scene_<slug>.json` sidecars). Selecting a synced LiDAR scan and clicking **Launch Simulator** (or **Restart with Scene**) automatically stages it into `microduck_rl` so relative robot includes resolve cleanly.

## Shortcuts & Siri (iOS & macOS)

Both targets bundle `MicroduckShortcuts` (`AppShortcutsProvider`) and `DuckIntents`, exposing 6 App Intents in the Shortcuts app, Spotlight, and Siri:

- **Stop Duck** (`EmergencyStopDuckIntent`)
- **Play Duck Sound** (`PlayDuckSoundIntent`)
- **Do Duck Trick** (`PerformTrickIntent`)
- **Duck Status** (`GetDuckStatusIntent`)
- **Duck Posture** (`SetDuckPostureIntent`)
- **Move Duck** (`MoveDuckStepIntent`)

On macOS, open the **Shortcuts** app (or Spotlight) after running `MicroduckRemoteMac` once to run or compose Microduck actions into workflows.

## Connecting from a Physical iPhone or Remote Mac

Tap or click the top status capsule (or press `⇧⌘K` on macOS) and switch to **Hugging Face** mode, sign in via browser device code or paste a token, and connect over Rendezvous + Cloudflare TURN to any duck signed into your account (`scripts/duck-sim ctl account login`).
