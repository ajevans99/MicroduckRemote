---
name: expressive-choreography
description: Chooses between multi-step expressive routines and single-action beak, sound, light, gaze, or trick tools for moods, reactions, celebrations, greetings, or skits.
---

# Expressive Choreography vs. Direct Actions

Use this guidance to decide when to compose a multi-step routine versus calling a single dedicated tool.

## When to use the routine choreographer

- Use the duck routine tool for open-ended moods, emotions, skits, greetings, or celebrations such as "act suspicious", "celebrate", "greet my guest", "be spooky", "act curious", "sneak around", "show off", or "cheer me up".
- Compose 3 to 5 cohesive steps that tell a tiny story by combining head gaze, curious head tilt (`headTiltPercent`), beak opening (`beakOpenPercent`), standing crouch (`crouchPercent`), face light color, sounds, and optional bounded steps or built-in tricks.
- Use `headTiltPercent` (-100 left to +100 right) for curious, puzzled, or playful expressions (for example, tilting the head while playing `inquire` or looking up at a guest).
- Use `beakOpenPercent` (0 closed to 100 wide open) for gasps, yawns, cheers, or talking beats — alternate open and closed across adjacent steps for an expressive chatter.
- Use `crouchPercent` (0 normal height to 100 low crouch) for sneaky, shy, spooked, or ready-to-pounce moments, then return to `0` on the celebratory beat.
- Give the routine a playful short title and mood label, and keep each step's duration snappy (typically 0.6 to 2.0 seconds) so the performance feels lively.
- Turn the face light off on the final step if you changed it purely for a skit, unless the user asked to leave a color on. Beak, crouch pose, and head tilt automatically return to neutral when the routine finishes.

## When to use a single tool directly

- If the user asks directly to open, close, set, or chomp/chatter the beak (like "open your beak", "close your mouth", or "chomp your beak"), use the beak control tool directly.
- If the user asks for one specific sound (like "quack" or "say happy"), use the play sound tool directly.
- If the user asks for one specific installed trick by name (like "do a kick" or "pick up"), use the perform trick tool directly.
- If the user only asks to change the face light color or turn the light off, use the set light tool directly.
- If the user only asks to aim or turn the head toward a direction, use the direct gaze tool directly.
