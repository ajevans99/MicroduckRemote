---
name: navigate-and-walk
description: Safely prepares Microduck to stand up, walk, turn, sidestep, back up, or follow multi-leg movement requests while handling sitting state, falls, and obstacles.
---

# Navigate and Walk Microduck

Use this guidance whenever the user asks Microduck to move, walk, back up, turn around, sidestep, patrol, or follow a multi-step path.

## Prepare before moving

- Microduck cannot walk while sitting, disabled, fallen, or picked up.
- If the user asks to stand up and walk in the same request, call the posture tool to stand Microduck up first, wait for it to succeed, and then call the move tool.
- If a move call fails because Microduck is sitting or disabled, stand Microduck up with the posture tool and retry the requested move automatically rather than giving up.
- If Microduck has fallen, recover it with the posture tool before walking. If Microduck is picked up, inform the user to set it down first.
- If the user says stop, freeze, halt, or anything urgent, immediately call the emergency stop tool.

## Plan multi-leg movements

- Prefer **real-world, sensor-terminated tools** over raw timed steps:
  - Use `WalkDuckDistanceIntent` for walking or sidestepping real distances (meters or feet: 1 ft ≈ 0.30 m; "a little bit" ≈ 0.25 m, "a step" ≈ 0.4 m, "across the room" ≈ 1.5 m).
  - Use `TurnDuckAngleIntent` for exact turns (90° for a quarter turn, 180° to turn around, 45° for a slight pivot).
  - Use `ApproachWithDuckIntent` when the user says "walk up to the wall/couch/ball" (`.approach`, e.g. 25–35 cm) or "back up until you have room" (`.backUpUntilClear`, e.g. 60 cm).
  - Only use `MoveDuckStepIntent` when the user specifically asks for a duration in seconds.
- Break compound paths like "walk forward half a meter, turn around, and come back" into sequential closed-loop calls.
- Prefer moderate speed (around 60–65% for walking, 80% for turning) indoors unless the user asks for fast or slow movement.
- Keep obstacle detection enabled for forward movement unless the user explicitly asks to ignore obstacles or push something like a ball.

## Handle early stops

- If a forward walk stops early because of an obstacle, report how close the obstacle was and offer to turn left, turn right, or back up rather than blindly repeating the same forward step.
