# Simulator & Remote Driving

Launch the local MuJoCo simulator from macOS or connect remotely to physical ducks over Hugging Face Rendezvous.

@Image(source: "cockpit-ios", alt: "MicroduckRemote iOS Cockpit streaming live MuJoCo camera video")

## Driving `duck-sim` on macOS

On macOS, open the **Simulator** tab (`⌘4`) in **Microduck** to launch, restart, and stop `scripts/duck-sim` directly from the app:

- Choose between built-in MuJoCo scenes (such as `playground` or `backlash`) and iCloud-synced LiDAR room scans.
- Configure camera streaming (`Duck A`, `All Ducks`, or `Disabled`), duck count (`1`–`4`), initial keyframe (`SIT` or `STAND`), and the 3D MuJoCo viewer.
- Inspect live daemon logs (`body_server`, `robotd`, `mediad`, `tofd`, `autod`) with automatic ANSI cleanup.

The launcher automatically enriches `PATH` with Homebrew's `rustup` (`cargo`), `~/.cargo/bin`, `mise` shims, and Homebrew binaries so GUI-launched builds resolve Rust and GStreamer toolchains cleanly.

## Launching `duck-sim` from Terminal

You can also run the simulator directly from your `pollen-robotics/microduck` checkout:

```bash
DUCK_SIM_SCENE=playground DUCK_SIM_CAMERAS=a scripts/duck-sim
```

> Important: Microduck's WebRTC pipeline supports a single active consumer at a time (`robot_busy`). Disconnect any browser console (`:8080` or `:7860`) before connecting from MicroduckRemote.

When running on iOS Simulator or macOS, **Microduck** automatically connects to `ws://127.0.0.1:8443` and begins streaming 30 fps H.264 camera video alongside 50 Hz balance telemetry.

## Remote Connections via Hugging Face

To drive a physical Microduck or connect from a physical iPhone/iPad over the internet:

1. Tap or click the top status capsule (or press `⇧⌘K` on macOS).
2. Switch to **Hugging Face** mode.
3. Sign in using the browser device-code flow (uses Hugging Face's public device OAuth client ID) or paste an access token.
4. Select any online duck logged into your Hugging Face account (`scripts/duck-sim ctl account login`) to connect over Rendezvous SSE + Cloudflare TURN.

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
| --- | --- |
| `⌘1`–`⌘4` | Switch between Drive, Tricks, Telemetry & Map, and Simulator |
| `⇧⌘K` | Open connection settings |
| `⌘B` | Toggle Stand & Balance |
| `⌘.` | Emergency Stop |
| `⇧⌘S` | Toggle Soundboard |
| `⇧⌘D` | Toggle 8×8 ToF Depth Overlay |
