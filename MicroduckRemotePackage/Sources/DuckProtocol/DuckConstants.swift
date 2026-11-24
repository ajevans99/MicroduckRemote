import Foundation

public enum DuckConstants {
  public static let apiVersion = 68
  public static let defaultLocalSignallingURL = "ws://127.0.0.1:8443"
  public static let defaultRendezvousURL = "https://pollen-robotics-reachy-mini-central.hf.space"
  public static let defaultTurnCredentialsURL = "https://fastrtc-turn-service.hf.space/credentials"
  public static let hubModelsAPIURL = "https://huggingface.co/api/models"
  public static let huggingFaceBaseURL = "https://huggingface.co"
  public static let huggingFaceDeviceClientID = "26be6b09-91c5-47da-9861-d2d2bb7a7e36"
  public static let officialOrg = "pollen-robotics"
  public static let officialPolicySetRepo = "pollen-robotics/microduck-policies"
  public static let robotKind = "microduck"
  public static let maxLinearVelocity = 0.3
  /// `velstand.onnx` (v7/v9) stays in its standing basin until `vx <= -0.42 m/s`.
  public static let minBackwardBreakawayVelocity = 0.42
  public static let maxBackwardLinearVelocity = 0.50
  public static let maxAngularVelocity = 1.5
  /// Trained standing body-pose ranges from `duck-ipc-proto` (`PoseParams`).
  /// The robot does not clamp `robot.pose`, so clients must stay within these limits.
  public static let minPoseZ = -0.025
  public static let maxPoseZ = 0.010
  public static let maxPoseRollRadians = 0.26
  public static let maxPosePitchRadians = 0.26
  /// Mechanical `head_roll` travel limit from Microduck MJCF (±0.4363 rad ≈ ±25°).
  public static let maxHeadRollRadians = 0.43

  /// Maps a normalized backward magnitude in `0...1` into the effective backward
  /// walking band `[minBackwardBreakawayVelocity, maxBackwardLinearVelocity]`.
  public static func backwardLinearVelocity(magnitude: Double) -> Double {
    let m = min(max(magnitude, 0.0), 1.0)
    guard m > 0.01 else { return 0.0 }
    let span = maxBackwardLinearVelocity - minBackwardBreakawayVelocity
    return -(minBackwardBreakawayVelocity + m * span)
  }
  public static let intentHz = 10
  public static let defaultHoldSeconds = 3.0
  public static let jointDeviationFullScaleRadians = 0.20
  public static let defaultBundleIdentifier = "com.microduck.remote"

  public static var appBundleIdentifier: String {
    if let bundleID = Bundle.main.bundleIdentifier, !bundleID.hasPrefix("com.apple.") {
      return bundleID
    }
    return defaultBundleIdentifier
  }

  public static var appGroupID: String {
    "group.\(appBundleIdentifier)"
  }

  public static var iCloudContainerID: String {
    "iCloud.\(appBundleIdentifier)"
  }
  public static let iCloudDriveScenesFolderName = "Microduck Scenes"
  public static let syncedScenesSubdirectory = "Documents/Scenes"
  public static let headlessIdleTimeoutSeconds = 30.0
  public static let maxStepDurationSeconds = 10.0
  public static let defaultMinObstacleDistanceMm = 200
  public static let defaultProximityWarningMm = 350
  public static let defaultProximityClearMm = 600
  public static let tofMaxRangeMm = 4000

  public static let builtInSkills: [String] = [
    "roulade",
    "kick_left",
    "kick_right",
    "ground_pick",
    "sit_toggle",
  ]

  public static let jointNames: [String] = [
    "left_hip_yaw",
    "left_hip_roll",
    "left_hip_pitch",
    "left_knee",
    "left_ankle",
    "neck_pitch",
    "head_pitch",
    "head_yaw",
    "head_roll",
    "mouth",
    "right_hip_yaw",
    "right_hip_roll",
    "right_hip_pitch",
    "right_knee",
    "right_ankle",
  ]
}

public enum SoundTag: String, CaseIterable, Identifiable, Sendable, Codable {
  case chirp
  case greet
  case inquire
  case alarm
  case peck
  case coo
  case wheee

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .chirp: "Chirp"
    case .greet: "Greet"
    case .inquire: "Inquire"
    case .alarm: "Alarm"
    case .peck: "Peck"
    case .coo: "Coo"
    case .wheee: "Wheee"
    }
  }

  public var systemImage: String {
    switch self {
    case .chirp: "waveform"
    case .greet: "hand.wave.fill"
    case .inquire: "questionmark.bubble.fill"
    case .alarm: "exclamationmark.triangle.fill"
    case .peck: "chevron.down.circle.fill"
    case .coo: "heart.fill"
    case .wheee: "wind"
    }
  }

  public var isHoldable: Bool {
    self == .wheee
  }
}

public enum LookGeometry {
  public static let forwardX = 1.0
  public static let lateralSpanY = 0.7
  public static let baseHeightZ = 0.2
  public static let verticalSpanZ = 0.45

  public static func lookTarget(normalizedX: Double, normalizedY: Double) -> RobotLookParams {
    let clampedX = min(max(normalizedX, -1.0), 1.0)
    let clampedY = min(max(normalizedY, -1.0), 1.0)
    return RobotLookParams(
      x: forwardX,
      y: -clampedX * lateralSpanY,
      z: baseHeightZ - clampedY * verticalSpanZ,
      neckPitch: 0.0
    )
  }
}

public struct SseStreamParser: Sendable {
  private var buffer = ""

  public init() {}

  public mutating func ingest(_ chunk: String) -> [String] {
    buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
    var payloads: [String] = []
    while let range = buffer.range(of: "\n\n") {
      let frame = String(buffer[..<range.lowerBound])
      buffer.removeSubrange(..<range.upperBound)
      let joined = frame
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { $0.hasPrefix("data:") }
        .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        .joined()
      if !joined.isEmpty {
        payloads.append(joined)
      }
    }
    return payloads
  }
}
