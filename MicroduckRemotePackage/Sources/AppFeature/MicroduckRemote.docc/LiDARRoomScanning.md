# LiDAR Room Scanning & MuJoCo Export

Scan real rooms on iPhone Pro or iPad Pro with Apple RoomPlan and sync ready-to-run MuJoCo MJCF scenes to the macOS simulator via iCloud Drive.

## Capturing a Scan on iOS

1. Open the **Room Scan** tab on a LiDAR-equipped iPhone Pro or iPad Pro and grant Camera access.
   - On iOS Simulator or devices without LiDAR (`RoomCaptureSession.isSupported == false`), load the built-in sample two-room apartment to preview floor plans and test MJCF export.
2. Tap **Start LiDAR Scan** and pan smoothly across walls, doorways, windows, and furniture.
3. **Single room:** Tap **Finish** once the room geometry stabilizes.
4. **Multi-room (same floor):** Walk into the adjacent room while keeping the connecting doorway in view, tap **Next Room** to finalize the current room without pausing the shared `ARSession`, scan the next room, and tap **Finish** when done.

On-device `StructureBuilder` merges multi-room scans (falling back to shared-`ARSession` alignment if merging fails) and deduplicates shared interior partitions.

## Configuring MuJoCo Export

Before saving `scene_<slug>.xml`, customize the scene for Microduck's walking policy:

- **Doorway Policy:**
  - **Open Doorways** — Carves open detected doorways and archways with overhead lintels.
  - **Open All Doors** — Forces closed doors open for seamless multi-room traversal.
  - **Solid Doors** — Exports closed doors as solid collision boxes.
- **Scene Tuning:** Toggle furniture collisions, floor visual overlays, dominant-wall axis alignment, and automatic `(0, 0)` indoor spawn clearance.

## Syncing to macOS via iCloud Drive

1. Tap **Choose iCloud Folder & Save** once on iOS to select **iCloud Drive › Microduck Scenes**. The choice is persisted via a security-scoped bookmark, so it works even with free Personal Teams without paid iCloud entitlements.
2. On macOS, the **Simulator** tab watches `~/Library/Mobile Documents/com~apple~CloudDocs/Microduck Scenes/` (or any custom folder you choose) for `scene_<slug>.xml` files and optional `scene_<slug>.json` metadata sidecars.
3. Select a synced room scan and click **Launch Simulator** (or **Restart with Scene**). MicroduckRemote stages the XML into `microduck_rl` automatically so relative `<include file="robot_groundcontact_backlash.xml" />` references resolve cleanly.
