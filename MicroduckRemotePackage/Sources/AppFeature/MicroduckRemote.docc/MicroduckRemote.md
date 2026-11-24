# ``AppFeature``

@Metadata {
  @DisplayName("MicroduckRemote")
  @PageColor(blue)
}

Native SwiftUI and Metal remote control app for driving, observing, and automating a simulated or physical Microduck robot on iOS 27.3 and macOS 27.3.

@Image(source: "logo", alt: "MicroduckRemote app icon")

## Overview

MicroduckRemote connects to Microduck over WebRTC (either locally via `scripts/duck-sim` or remotely via Hugging Face Rendezvous + TURN) and brings together live H.264 Metal camera streaming, dual-thumbstick and gamepad driving, Hugging Face trick installation, on-device LiDAR RoomPlan → MuJoCo scene scanning, a native macOS simulator launcher, and full **iOS/macOS 27.3 Siri AI** integration.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:SimulatorAndLocalDriving>

### Siri AI & Automation

- <doc:SiriAIAndAppIntents>

### Scanning & Simulation

- <doc:LiDARRoomScanning>

### Internals

- <doc:Architecture>
