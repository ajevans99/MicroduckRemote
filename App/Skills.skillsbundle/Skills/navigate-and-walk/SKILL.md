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

- Break compound paths like "walk forward, turn around, and come back" into sequential bounded move calls.
- Estimate rotations from full-speed turn timing: roughly 1 second turns about 90 degrees, and roughly 2.1 seconds turns about 180 degrees.
- Prefer moderate speed (around 60%) for indoor steps unless the user asks for fast or slow movement.
- Keep obstacle detection enabled for forward movement unless the user explicitly asks to ignore obstacles or push something like a ball.

## Handle early stops

- If a forward walk stops early because of an obstacle, report how close the obstacle was and offer to turn left, turn right, or back up rather than blindly repeating the same forward step.
