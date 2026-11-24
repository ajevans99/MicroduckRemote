---
name: explore-apartment
description: Checks 8x8 ToF obstacle clearances, safely wanders rooms avoiding furniture and walls, inspects interesting props with head gaze and camera photos, and reacts playfully.
---

# Explore Apartment and Sense Obstacles

Use this guidance whenever the user asks what is close to Microduck, which direction is clear, or asks Microduck to explore the room, wander the apartment, or check out nearby toys and props.

## Check proximity before or during navigation

- Use `GetDuckProximityIntent` whenever the user asks "is anything in front of Microduck?", "how close is the wall?", "which way is clear?", or before steering through a tight doorway or around furniture.
- Report the left, front, and right clearances cleanly and follow the recommended open direction (`forward`, `turnLeft`, `turnRight`, or `clear`).
- If an obstacle warning is active, avoid walking straight forward into the obstacle unless the user explicitly asks to nudge or kick a floor prop.

## Prepare and run apartment exploration

- Microduck must be standing before exploring. If it is sitting, disabled, or fallen, call the posture tool to stand it up first, then call `ExploreApartmentIntent`.
- If an autonomous play mode (such as Soccer or Laser Tracking) is currently active, disable it first so it does not compete with exploration steering.
- Use `ExploreApartmentIntent` for bounded multi-leg wandering ("explore the living room", "wander around the apartment for 15 seconds", "look around and play with toys"). Keep `playfulReactions` enabled unless the user specifically asks for quiet or straight-line scouting.
- If the user says stop, freeze, or halt at any time, immediately call `EmergencyStopDuckIntent`.

## Combine sensing, photos, and playful reactions

- For requests like "explore the room and show me what you find", run `ExploreApartmentIntent` (or check proximity and turn toward an open direction), aim Microduck's head with `DirectDuckGazeIntent` if needed, and snap a photo with `SnapDuckPhotoIntent` so you can describe the room or props.
- When Microduck spots a floor prop (such as a soccer ball, cone, or block) in a photo or close proximity reading, offer to kick it (`PerformTrickIntent`), react playfully (`PlayDuckSoundIntent` or `SetDuckLightIntent`), or continue exploring another room.
