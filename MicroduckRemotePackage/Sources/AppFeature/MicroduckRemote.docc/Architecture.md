# Architecture

Explore how MicroduckRemote separates protocol models, WebRTC transport, App Intents, and SwiftUI features across modular Swift Package targets.

## Package Layout

The Xcode workspace links thin iOS (`MicroduckRemote`) and macOS (`MicroduckRemoteMac`) app targets to a single local Swift Package (`MicroduckRemotePackage`):

| Target | Responsibility |
| --- | --- |
| `DuckProtocol` | Wire-level JSON-RPC structs, WebRTC signalling payloads, telemetry frames, velocity/safety constants, and intent bridge models. Zero UI or WebRTC dependencies. |
| `DuckDependencies` | Point-Free `swift-dependencies` client interfaces (`DuckSessionClient`, `HuggingFaceAuthClient`, `HubCatalogClient`, `IntentTelemetryClient`, `DuckSharedStateClient`) and `DuckMoveStepExecutor`. |
| `DuckWebRTC` | Live `WebRTC` peer connection, Metal H.264 video rendering (`VideoTrackRegistry` + one-shot JPEG capture), cold-start bootstrap barrier, and Hugging Face OAuth/Hub clients. |
| `DuckIntents` | WebRTC-free target containing all 17 `@AppIntent(.tool)` intents, `AppEntity` / `@AppEntity(.generable)` models, `CardSnippet` SwiftUI views, `DuckIntentRunner`, and `IntentTelemetryTracer`. |
| `WingmanFeature` | In-app Apple `FoundationModels` agent (`SystemLanguageModel` + `PrivateCloudComputeLanguageModel`), multimodal `Attachment(cgImage)` camera inspection tools, streaming `@Generable` `WingmanMissionPlan` composer, and `WingmanView`. |
| `CockpitFeature` | Live driving cockpit, Metal camera overlay, dual thumbsticks, gamepad polling, expressive controls drawer, Wingman sheet integration, soundboard, posture/mode controls, and 8×8 ToF depth visualization. |
| `TricksFeature` | Hugging Face Hub policy browser, search/filtering, and multi-stage trick download/install/run workflow. |
| `TelemetryFeature` | Live 50 Hz loop chart, battery/thermal gauges, `mapd` occupancy grid viewer, RPC console, and live Siri & App Intents call inspector. |
| `RoomScanFeature` | Apple RoomPlan LiDAR scanning, multi-room merging, MuJoCo MJCF XML generation, and iCloud Drive bookmark sync. |
| `SimulatorFeature` | macOS `scripts/duck-sim` process manager, scene scanner/stager, enriched toolchain `PATH`, and live daemon log reader. |
| `AppFeature` | Root navigation shell, adaptive iOS/macOS tab structure, and connection sheet. |

## Key Engineering Details

### Single-Consumer WebRTC & Cold-Start Intents

Microduck's WebRTC daemon accepts one active control session at a time. All App Intents conform to `LiveActivityIntent` so they execute in-process against `LiveDuckSessionEngine.shared`. When an intent runs via `DuckIntentRunner.runConnectedTool`, `DuckSessionClient.connectForIntent` resolves the saved `LastConnectionPreference`, waits for the full bootstrap barrier (`controlOpen`, `hello`, `system.info`, `robot.policies`, `robot.health`), runs the command, and arms a 30-second headless idle disconnect timer when running in the background.

### 10 Hz Deadman & Obstacle Guard

`robotd` enforces a 500 ms movement deadman timer (`[safety] deadman_ms`). `DuckMoveStepExecutor` streams `robot.move` commands at 10 Hz (`100 ms`), checks upright safety (`fallen`, `pickedUp`) and the central 50% cone of the 8×8 forward ToF sensor (`< 200 mm`) on every tick, and guarantees a terminal zero-velocity pulse even on task cancellation.

### Backward Breakaway Velocity Mapping

Microduck's `velstand.onnx` balance policy remains in its standing basin for small negative linear velocities down to `-0.40 m/s`. `DuckConstants.backwardLinearVelocity(magnitude:)` maps non-zero backward stick and intent magnitudes into `[-0.42, -0.50] m/s` so backward walking responds immediately while forward walking stays smoothly scaled across `[0, 0.30] m/s`.
