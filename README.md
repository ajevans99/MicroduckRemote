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

## Scanning a Room or Apartment to MuJoCo (MJCF)

The **Room Scan** tab uses Apple's on-device **RoomPlan** framework (camera + LiDAR) to scan a single room or multiple connected rooms on the same floor and export a ready-to-run MuJoCo MJCF scene (`scene_<name>.xml`) for the Microduck simulator.

### 1. Capture on iPhone (or Preview on Simulator)

1. Open the **Room Scan** tab on a LiDAR-equipped iPhone Pro or iPad Pro and grant Camera access when prompted.
   - On iOS Simulator or devices without LiDAR (`RoomCaptureSession.isSupported == false`), the app displays an unsupported-hardware notice and lets you load a sample two-room apartment to inspect the floor plan and test XML export.
2. Tap **Start LiDAR Scan** and slowly pan across walls, doorways, windows, and furniture.
3. **Single room:** Tap **Finish** when the room outline settles.
4. **Same-floor multi-room:** Walk into the next room while keeping doorways in view, tap **Next Room** to finalize the current room without pausing the shared `ARSession`, scan the adjacent room, and tap **Finish** when done. On-device `StructureBuilder` merges the captured rooms (falling back to shared-`ARSession` alignment if merging fails) and deduplicates shared interior partitions.

### 2. Review & Export `scene_<name>.xml`

- **Doorway policy:** Keep open doorways/archways carved open with overhead lintels (**Open Doorways**), force every detected door open for full multi-room traversal (**Open All Doors**), or export all doors as solid boxes (**Solid Doors**).
- **Scene tuning:** Toggle furniture collisions, floor visual overlays, dominant-wall axis alignment, and automatic `(0, 0)` indoor spawn clearance (which shifts the scene horizontally so Microduck spawns clear of walls and furniture on `z = 0`).
- Tap **Share / AirDrop XML** or **Save to Files** to export `scene_<name>.xml`.

### 3. Run in `duck-sim` (`microduck_rl`)

Exported scenes reference `<include file="robot_groundcontact_backlash.xml" />` and preserve the walking policy's ground-contact backlash robot setup and `INIT` / `STAND` / `SIT` / `FOLD` keyframes without duplicating robot meshes.

1. Place the exported `scene_<name>.xml` inside your `microduck_rl` checkout alongside `robot_groundcontact_backlash.xml`:
   ```text
   <microduck_rl>/src/mjlab_microduck/robot/microduck/scene_<name>.xml
   ```
2. Launch `duck-sim` from `pollen-robotics/microduck` with `DUCK_SIM_SCENE` set to `<name>` (without `scene_` or `.xml`):
   ```bash
   DUCK_SIM_SCENE=<name> DUCK_SIM_CAMERAS=a scripts/duck-sim
   ```
   *(You can also pass a slash-containing path to `DUCK_SIM_SCENE`, provided the XML file still lives in the directory containing `robot_groundcontact_backlash.xml` and `assets/` so MuJoCo resolves the relative `<include>`.)*

### Conventions & Limitations

- **Coordinates & primitives:** Right-handed ARKit (`X` right, `Y` up, `-Z` forward) is converted to MuJoCo (`X` right, `Y` forward, `Z` up) with floor height normalized to `z = 0` and full RoomPlan dimensions halved into MuJoCo `box` `(hx, hy, hz)` and `cylinder` `(radius, half_height)` extents.
- **Simplified static geometry:** Surfaces and furniture are approximated as static collision boxes/cylinders (`scan_*` geom names, compatible with multi-duck `MjSpec.attach`), curved walls are chord-approximated, and glass windows are visual-only panes inside carved wall openings.
- **Single navigable floor:** Multi-room scans keep rooms on the primary scanned story (`z = 0` plane); stairs, split-level floors, sloped terrain, and articulated/pushable doors or furniture are not modeled.
- **Physical-device requirement:** Live camera + LiDAR scanning cannot run in iOS Simulator and must be verified on a physical LiDAR-capable iPhone or iPad.

