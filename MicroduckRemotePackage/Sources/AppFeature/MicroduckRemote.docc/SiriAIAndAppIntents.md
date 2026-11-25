# Siri AI & App Intents

Control Microduck conversationally across Siri AI, Shortcuts, Spotlight, and the Action Button using 14 `@AppIntent(.tool)` tools, 5 `Skills.skillsbundle` playbooks, and interactive `CardSnippet` cards.

@Image(source: "siri-ai-card", alt: "Siri AI multi-step command and interactive Duck Status CardSnippet")

## Tool Intents

All 14 intents live in the `DuckIntents` target, conform to `@AppIntent(.tool)` and `LiveActivityIntent` (running in-process so they share the single-consumer WebRTC slot), and return structured values (`ReturnsValue`) so Siri AI can chain multi-step requests naturally.

| Intent | Return Value | Description |
| --- | --- | --- |
| `EmergencyStopDuckIntent` | `String` | Immediately zeroes velocity and halts active skills |
| `SetDuckPostureIntent` | `DuckStatusEntity` | Idempotent Stand Up (waits for rise), Sit Down (waits for 2.2 s settle), Fall Recovery, and Home Pose |
| `MoveDuckStepIntent` | `String` | Bounded 10 Hz walk, sidestep, or in-place turn with upright safety and 8×8 ToF obstacle stop |
| `GetDuckStatusIntent` | `DuckStatusEntity` | Live telemetry snapshot with interactive `CardSnippet` (**Sit** / **Stand Up** / **Stop**) |
| `GetDuckProximityIntent` | `DuckProximityEntity` | Analyzes the 8×8 ToF grid into left/front/right clearances and low-object hints with a `CardSnippet` |
| `ExploreApartmentIntent` | `String` | Bounded, cancellation-safe closed-loop apartment wander, obstacle avoidance, and prop inspection |
| `PerformTrickIntent` | `String` | Runs any built-in or Hugging Face skill resolved via `InstalledSkillEntity` |
| `PerformDuckRoutineIntent` | `DuckRoutine` | Executes a 2–6 step expressive skit (movement, gaze, sounds, beak open, head tilt, crouch) via `@AppEntity(.generable)` |
| `ControlDuckBeakIntent` | `String` | Opens, closes, sets exact percentage, or runs a 10 Hz animated chomp with guaranteed cleanup |
| `DirectDuckGazeIntent` | `String` | Smoothly aims head pitch and yaw by percentage |
| `SnapDuckPhotoIntent` | `DuckPhotoEntity` | Captures an upright JPEG frame (`Transferable` + `CardSnippet`) |
| `PlayDuckSoundIntent` | `String` | Plays expressive sounds, including cancellation-safe 10 Hz held `wheee` |
| `SetDuckModeIntent` | `String` | Toggles Autonomous Roaming, Soccer, Laser Tracking, or Theremin modes |
| `SetDuckLightIntent` | `String` | Sets the RGB face light color or turns it off |

## App Skills (`Skills.skillsbundle`)

`App/Skills.skillsbundle` is compiled by Xcode (`wrapper.skillsbundle` → `Metadata.appintents/Skills.skillsc`) and teaches Siri AI how to orchestrate tools for complex requests:

- **`navigate-and-walk`** — Stands Microduck up before walking, splits compound paths using full-speed turn timing (~1 s ≈ 90°, ~2.1 s ≈ 180°), and pivots cleanly on obstacle stops.
- **`inspect-surroundings`** — Aims gaze or turns around before snapping photos, and pans left → center → right for room scans.
- **`expressive-choreography`** — Uses `ControlDuckBeakIntent` for direct beak commands and `PerformDuckRoutineIntent` (with beak, head tilt, and crouch parameters) for open-ended moods and skits.
- **`autonomous-play-modes`** — Ensures Microduck is standing before enabling Autonomous, Soccer, Laser Tracking, or Theremin modes and turns them off before manual driving.
- **`explore-apartment`** — Checks proximity with `GetDuckProximityIntent`, runs bounded `ExploreApartmentIntent` sweeps, and inspects discovered obstacles or playground props.

### Example Prompts

- *"In Microduck, stand up and walk forward for 2 seconds"*
- *"In Microduck, walk forward a bit, turn around, and take a photo"*
- *"In Microduck, look to the left and tell me what you see"*
- *"In Microduck, act suspicious and look around"*
- *"Check status in Microduck"*

## Live Siri & App Intent Telemetry

Every tool call and entity query is recorded by `IntentTelemetryTracer` into `IntentTelemetryClient` and displayed live in the **Telemetry** tab under **Siri & App Intents**, showing tool names, bound parameters, cold-start vs. warm connection status, latency, and outcomes.

## Siri Evaluations

The `MicroduckSiriEvaluations` UI testing target (`MicroduckSiriEvaluations/MicroduckSiriEvaluationTests.swift`) uses Apple's `SiriEvaluations` framework to test single-tool routing, multi-step compound prompts, and `Skills.skillsbundle` loading on macOS 27.3+.
