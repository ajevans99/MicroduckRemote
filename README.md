# MicroduckRemote

Native SwiftUI + Metal iOS app for driving, observing, and installing Hugging Face tricks onto a simulated (`scripts/duck-sim`) or physical Microduck robot over WebRTC.

## Opening in Xcode

Always open **`MicroduckRemoteWorkspace.xcworkspace`** (rather than `.xcodeproj` alone) so Xcode indexes both the app target and `MicroduckRemotePackage`:

```bash
open MicroduckRemoteWorkspace.xcworkspace
```

## Driving `duck-sim` Locally

1. Start `duck-sim` with camera support in `pollen-robotics/microduck`:
   ```bash
   DUCK_SIM_CAMERAS=a scripts/duck-sim
   ```
2. Make sure any browser console (`:8080` or `:7860`) is **disconnected** so the single-consumer WebRTC slot is free.
3. Run the **`MicroduckRemote`** scheme on any iOS Simulator—the app auto-connects to `ws://127.0.0.1:8443` and streams live 30 fps H.264 camera video plus 50 Hz telemetry.

## Connecting from a Physical iPhone

Tap the top status capsule in the app and switch to **Hugging Face** mode, paste your Hugging Face token (or sign in via PKCE OAuth), and connect over Rendezvous + Cloudflare TURN to any duck signed into your account (`scripts/duck-sim ctl account login`).
