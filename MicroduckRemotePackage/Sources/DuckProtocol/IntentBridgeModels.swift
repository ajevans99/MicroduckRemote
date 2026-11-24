import CasePaths
import Foundation

@CasePathable
@dynamicMemberLookup
public enum LastConnectionPreference: Codable, Equatable, Sendable {
  case localSimulator(url: String)
  case rendezvous(serverURL: String, preferredPeerID: String?)
}

@CasePathable
public enum DuckSessionError: Equatable, Error, LocalizedError, Sendable {
  case missingHuggingFaceAccount
  case connectionFailed(String)
  case connectionTimedOut
  case duckFallen
  case duckPickedUp
  case duckNotStanding
  case noActiveVideoStream
  case frameCaptureTimedOut

  public var errorDescription: String? {
    switch self {
    case .missingHuggingFaceAccount:
      "Sign in to Hugging Face in Microduck first so Siri can reach your duck."
    case let .connectionFailed(reason):
      reason
    case .connectionTimedOut:
      "Timed out waiting to connect to your Microduck."
    case .duckFallen:
      "Your duck has fallen over. Ask it to stand back up before moving."
    case .duckPickedUp:
      "Your duck's feet are off the ground. Set it down before walking."
    case .duckNotStanding:
      "Your duck's motors are disabled or sitting. Ask it to stand up first."
    case .noActiveVideoStream:
      "Your duck's head camera isn't streaming video right now."
    case .frameCaptureTimedOut:
      "Timed out waiting for a camera frame from your duck."
    }
  }
}

public struct DuckMoveStepRequest: Codable, Equatable, Sendable {
  public var vx: Double
  public var vy: Double
  public var vyaw: Double
  public var durationSeconds: Double
  public var stopOnObstacle: Bool
  public var minObstacleDistanceMm: Int

  public init(
    vx: Double = 0,
    vy: Double = 0,
    vyaw: Double = 0,
    durationSeconds: Double = 1.0,
    stopOnObstacle: Bool = true,
    minObstacleDistanceMm: Int = DuckConstants.defaultMinObstacleDistanceMm
  ) {
    self.vx = vx
    self.vy = vy
    self.vyaw = vyaw
    self.durationSeconds = durationSeconds
    self.stopOnObstacle = stopOnObstacle
    self.minObstacleDistanceMm = minObstacleDistanceMm
  }

  public var clampedTwist: RobotMoveParams {
    RobotMoveParams(
      vx: min(max(vx, -DuckConstants.maxBackwardLinearVelocity), DuckConstants.maxLinearVelocity),
      vy: min(max(vy, -DuckConstants.maxLinearVelocity), DuckConstants.maxLinearVelocity),
      vyaw: min(max(vyaw, -DuckConstants.maxAngularVelocity), DuckConstants.maxAngularVelocity)
    )
  }

  public var clampedDurationSeconds: Double {
    min(max(durationSeconds, 0.1), DuckConstants.maxStepDurationSeconds)
  }
}

public struct DuckMoveStepResult: Codable, Equatable, Sendable {
  @CasePathable
  @dynamicMemberLookup
  public enum StopReason: Codable, Equatable, Sendable {
    case completed
    case stoppedForObstacle(distanceMm: Int)
    case interruptedBySafety(String)
  }

  public var appliedTwist: RobotMoveParams
  public var elapsedSeconds: Double
  public var pulsesSent: Int
  public var stopReason: StopReason

  public init(
    appliedTwist: RobotMoveParams,
    elapsedSeconds: Double,
    pulsesSent: Int,
    stopReason: StopReason
  ) {
    self.appliedTwist = appliedTwist
    self.elapsedSeconds = elapsedSeconds
    self.pulsesSent = pulsesSent
    self.stopReason = stopReason
  }
}

public struct DuckCapturedFrame: Equatable, Sendable {
  public var jpegData: Data
  public var width: Int
  public var height: Int
  public var capturedAt: Date

  public init(jpegData: Data, width: Int, height: Int, capturedAt: Date) {
    self.jpegData = jpegData
    self.width = width
    self.height = height
    self.capturedAt = capturedAt
  }
}

public struct DuckSharedSummary: Codable, Equatable, Sendable {
  public var isConnected: Bool
  public var duckName: String?
  public var peerID: String?
  public var isSimulated: Bool
  public var isEnabled: Bool
  public var isSitting: Bool
  public var isFallen: Bool
  public var isPickedUp: Bool
  public var activePolicy: String?
  public var batteryVolts: Double?
  public var batteryPercent: Int?
  public var maxMotorTempC: Int?
  public var hottestMotor: String?
  public var installedSkillNames: [String]
  public var updatedAt: Date

  public init(
    isConnected: Bool = false,
    duckName: String? = nil,
    peerID: String? = nil,
    isSimulated: Bool = false,
    isEnabled: Bool = false,
    isSitting: Bool = false,
    isFallen: Bool = false,
    isPickedUp: Bool = false,
    activePolicy: String? = nil,
    batteryVolts: Double? = nil,
    batteryPercent: Int? = nil,
    maxMotorTempC: Int? = nil,
    hottestMotor: String? = nil,
    installedSkillNames: [String] = DuckConstants.builtInSkills,
    updatedAt: Date = Date(timeIntervalSince1970: 0)
  ) {
    self.isConnected = isConnected
    self.duckName = duckName
    self.peerID = peerID
    self.isSimulated = isSimulated
    self.isEnabled = isEnabled
    self.isSitting = isSitting
    self.isFallen = isFallen
    self.isPickedUp = isPickedUp
    self.activePolicy = activePolicy
    self.batteryVolts = batteryVolts
    self.batteryPercent = batteryPercent
    self.maxMotorTempC = maxMotorTempC
    self.hottestMotor = hottestMotor
    self.installedSkillNames = installedSkillNames
    self.updatedAt = updatedAt
  }

  /// Compares only discrete control/widget-relevant fields so 50 Hz telemetry ticks
  /// don't trigger redundant `ControlCenter` / `WidgetCenter` reloads.
  public func hasSameControlSurfaceState(as other: DuckSharedSummary) -> Bool {
    isConnected == other.isConnected
      && duckName == other.duckName
      && peerID == other.peerID
      && isSimulated == other.isSimulated
      && isEnabled == other.isEnabled
      && isSitting == other.isSitting
      && isFallen == other.isFallen
      && isPickedUp == other.isPickedUp
      && activePolicy == other.activePolicy
      && installedSkillNames == other.installedSkillNames
      && batteryPercent.map({ $0 / 5 }) == other.batteryPercent.map({ $0 / 5 })
  }
}

extension TofFrame {
  /// Minimum valid distance (mm) in the central forward-facing 50% cone of the ToF matrix,
  /// ignoring bottom/edge cells that see the floor and invalid `<= 0` readings.
  public var frontObstacleDistanceMm: Int? {
    guard rows > 0, cols > 0, distanceMm.count >= rows * cols else { return nil }
    let rowStart = rows / 4
    let rowEnd = max(rowStart + 1, rows - (rows / 4))
    let colStart = cols / 4
    let colEnd = max(colStart + 1, cols - (cols / 4))

    var minMm: Int?
    for row in rowStart..<rowEnd {
      for col in colStart..<colEnd {
        let idx = row * cols + col
        let mm = distanceMm[idx]
        guard mm > 0 else { continue }
        if let statuses = status, idx < statuses.count, statuses[idx] != 0 {
          // VL53L5CX status 0 / 5 / 9 are valid; treat negative or 255 as invalid
          let st = statuses[idx]
          if st < 0 || st == 255 { continue }
        }
        if let current = minMm {
          if mm < current { minMm = mm }
        } else {
          minMm = mm
        }
      }
    }
    return minMm
  }
}
