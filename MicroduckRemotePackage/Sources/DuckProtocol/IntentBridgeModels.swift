import CasePaths
import Foundation

@CasePathable
@dynamicMemberLookup
public enum LastConnectionPreference: Codable, Equatable, Sendable {
  case localSimulator(url: String)
  case rendezvous(serverURL: String, preferredPeerID: String?)
}

@CasePathable
public enum DuckSessionError: Equatable, Error, LocalizedError, CustomLocalizedStringResourceConvertible, Sendable {
  case missingHuggingFaceAccount
  case connectionFailed(String)
  case connectionTimedOut
  case duckFallen
  case duckPickedUp
  case duckNotStanding
  case noActiveVideoStream
  case frameCaptureTimedOut

  public var localizedStringResource: LocalizedStringResource {
    switch self {
    case .missingHuggingFaceAccount:
      "Sign in to Hugging Face in Microduck first so Siri can reach your duck."
    case let .connectionFailed(reason):
      LocalizedStringResource(stringLiteral: reason)
    case .connectionTimedOut:
      "Timed out waiting to connect to your Microduck."
    case .duckFallen:
      "Your duck has fallen over. Ask it to stand back up before moving."
    case .duckPickedUp:
      "Your duck's feet are off the ground. Set it down before walking."
    case .duckNotStanding:
      "Your duck's motors are disabled or sitting. Stand it up first."
    case .noActiveVideoStream:
      "Your duck's head camera isn't streaming video right now."
    case .frameCaptureTimedOut:
      "Timed out waiting for a camera frame from your duck."
    }
  }

  public var errorDescription: String? {
    String(localized: localizedStringResource)
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

public enum DuckLinearDirection: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
  case forward
  case backward
  case strafeLeft
  case strafeRight

  public var spokenLabel: String {
    switch self {
    case .forward: "forward"
    case .backward: "backward"
    case .strafeLeft: "left"
    case .strafeRight: "right"
    }
  }
}

/// Real-world, sensor-terminated motion goal driven by contact odometry (`odom`) and 8×8 ToF depth.
@CasePathable
@dynamicMemberLookup
public enum DuckMotionGoal: Codable, Equatable, Sendable {
  case moveDistance(
    direction: DuckLinearDirection,
    meters: Double,
    speedPercent: Double = 65.0,
    stopOnObstacle: Bool = true,
    minObstacleDistanceMm: Int = DuckConstants.defaultMinObstacleDistanceMm,
    timeoutSeconds: Double = 12.0
  )
  /// Positive `degrees` turns left (counterclockwise), negative turns right (clockwise).
  case turnAngle(
    degrees: Double,
    speedPercent: Double = 80.0,
    timeoutSeconds: Double = 8.0
  )
  /// Walks forward until the forward 8×8 ToF sensor reads `<= targetClearanceMm`.
  case approachObstacle(
    targetClearanceMm: Int = 300,
    speedPercent: Double = 55.0,
    timeoutSeconds: Double = 10.0
  )
  /// Walks backward until the forward 8×8 ToF sensor reads `>= targetClearanceMm`.
  case backUpUntilClear(
    targetClearanceMm: Int = 600,
    speedPercent: Double = 60.0,
    timeoutSeconds: Double = 8.0
  )
}

public struct DuckMotionResult: Codable, Equatable, Sendable {
  @CasePathable
  @dynamicMemberLookup
  public enum StopReason: Codable, Equatable, Sendable {
    case reachedTarget
    case stoppedForObstacle(distanceMm: Int)
    case timedOut
    case interruptedBySafety(String)
  }

  public var goal: DuckMotionGoal
  public var stopReason: StopReason
  public var elapsedSeconds: Double
  public var distanceTraveledMeters: Double
  public var angleTurnedDegrees: Double
  public var finalFrontClearanceMm: Int?
  public var usedClosedLoopFeedback: Bool
  public var pulsesSent: Int

  public init(
    goal: DuckMotionGoal,
    stopReason: StopReason,
    elapsedSeconds: Double,
    distanceTraveledMeters: Double = 0,
    angleTurnedDegrees: Double = 0,
    finalFrontClearanceMm: Int? = nil,
    usedClosedLoopFeedback: Bool = true,
    pulsesSent: Int = 0
  ) {
    self.goal = goal
    self.stopReason = stopReason
    self.elapsedSeconds = elapsedSeconds
    self.distanceTraveledMeters = distanceTraveledMeters
    self.angleTurnedDegrees = angleTurnedDegrees
    self.finalFrontClearanceMm = finalFrontClearanceMm
    self.usedClosedLoopFeedback = usedClosedLoopFeedback
    self.pulsesSent = pulsesSent
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

public enum TofRecommendedDirection: String, Codable, Equatable, Hashable, Sendable {
  case forward
  case turnLeft
  case turnRight
  case clear
}

public struct TofZoneAnalysis: Codable, Equatable, Hashable, Sendable {
  public var frontMm: Int?
  public var leftMm: Int?
  public var rightMm: Int?
  public var closestMm: Int?
  public var lowFrontObjectMm: Int?
  public var obstacleWarning: Bool
  public var recommendedDirection: TofRecommendedDirection

  public init(
    frontMm: Int?,
    leftMm: Int?,
    rightMm: Int?,
    closestMm: Int?,
    lowFrontObjectMm: Int? = nil,
    obstacleWarning: Bool,
    recommendedDirection: TofRecommendedDirection
  ) {
    self.frontMm = frontMm
    self.leftMm = leftMm
    self.rightMm = rightMm
    self.closestMm = closestMm
    self.lowFrontObjectMm = lowFrontObjectMm
    self.obstacleWarning = obstacleWarning
    self.recommendedDirection = recommendedDirection
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

    return minimumValidDistanceMm(rows: rowStart..<rowEnd, cols: colStart..<colEnd, treatNoTargetAsMaxRange: false)
  }

  /// Splits the 8×8 ToF frame into Left (cols `0..<colStart`), Front (cols `colStart..<colEnd`),
  /// and Right (cols `colEnd..<cols`) across the middle obstacle-height band (`rows 2..<6` on 8×8),
  /// matching Microduck's VL53L5CX orientation where row 0 is top and column 0 is sensor-left.
  public func analyzeZones(
    warningThresholdMm: Int = DuckConstants.defaultProximityWarningMm,
    clearThresholdMm: Int = DuckConstants.defaultProximityClearMm
  ) -> TofZoneAnalysis? {
    guard rows >= 2, cols >= 3, distanceMm.count >= rows * cols else { return nil }

    let rowStart = rows / 4
    let rowEnd = max(rowStart + 1, rows - (rows / 4))
    let colStart = max(1, cols / 4)
    let colEnd = min(cols - 1, max(colStart + 1, cols - (cols / 4)))

    let leftMm = minimumValidDistanceMm(rows: rowStart..<rowEnd, cols: 0..<colStart, treatNoTargetAsMaxRange: true)
    let frontMm = minimumValidDistanceMm(rows: rowStart..<rowEnd, cols: colStart..<colEnd, treatNoTargetAsMaxRange: true)
    let rightMm = minimumValidDistanceMm(rows: rowStart..<rowEnd, cols: colEnd..<cols, treatNoTargetAsMaxRange: true)

    guard leftMm != nil || frontMm != nil || rightMm != nil else { return nil }

    let measuredZones = [leftMm, frontMm, rightMm].compactMap { $0 }
    let closestMm = measuredZones.min()

    // Detect a close low object (such as a soccer ball or floor cone) when lower-front rows
    // see something much closer than the upper-front band above it.
    let lowFrontObjectMm: Int?
    if rows >= 6 {
      let lowBandStart = max(rowEnd - 1, rows - 3)
      let lowBandEnd = min(rows - 1, lowBandStart + 2)
      let upperBandEnd = max(rowStart + 1, lowBandStart)
      let lowMin = minimumValidDistanceMm(rows: lowBandStart..<lowBandEnd, cols: colStart..<colEnd, treatNoTargetAsMaxRange: false)
      let upperMin = minimumValidDistanceMm(rows: rowStart..<upperBandEnd, cols: colStart..<colEnd, treatNoTargetAsMaxRange: true)
      if let lowMin, lowMin < 360, (upperMin ?? DuckConstants.tofMaxRangeMm) > lowMin + 180 {
        lowFrontObjectMm = lowMin
      } else {
        lowFrontObjectMm = nil
      }
    } else {
      lowFrontObjectMm = nil
    }

    let frontClearance = frontMm ?? DuckConstants.tofMaxRangeMm
    let leftClearance = leftMm ?? DuckConstants.tofMaxRangeMm
    let rightClearance = rightMm ?? DuckConstants.tofMaxRangeMm

    let sideCloseThreshold = min(warningThresholdMm, DuckConstants.defaultMinObstacleDistanceMm)
    let obstacleWarning =
      frontClearance < warningThresholdMm
      || leftClearance < sideCloseThreshold
      || rightClearance < sideCloseThreshold

    let recommendedDirection: TofRecommendedDirection
    if frontClearance >= clearThresholdMm
      && leftClearance >= warningThresholdMm
      && rightClearance >= warningThresholdMm
    {
      recommendedDirection = .clear
    } else if frontClearance >= warningThresholdMm {
      recommendedDirection = .forward
    } else if leftClearance >= rightClearance {
      recommendedDirection = .turnLeft
    } else {
      recommendedDirection = .turnRight
    }

    return TofZoneAnalysis(
      frontMm: frontMm,
      leftMm: leftMm,
      rightMm: rightMm,
      closestMm: closestMm,
      lowFrontObjectMm: lowFrontObjectMm,
      obstacleWarning: obstacleWarning,
      recommendedDirection: recommendedDirection
    )
  }

  private func minimumValidDistanceMm(
    rows rowRange: Range<Int>,
    cols colRange: Range<Int>,
    treatNoTargetAsMaxRange: Bool
  ) -> Int? {
    var minMm: Int?
    var sawNoTarget = false

    for row in rowRange {
      for col in colRange {
        let idx = row * cols + col
        let mm = distanceMm[idx]
        if let statuses = status, idx < statuses.count {
          let st = statuses[idx]
          if st == 255 {
            if treatNoTargetAsMaxRange {
              sawNoTarget = true
            }
            continue
          }
          if st < 0 { continue }
        }
        guard mm > 0 else { continue }
        if let current = minMm {
          if mm < current { minMm = mm }
        } else {
          minMm = mm
        }
      }
    }

    if let minMm {
      return minMm
    }
    return sawNoTarget ? DuckConstants.tofMaxRangeMm : nil
  }
}
