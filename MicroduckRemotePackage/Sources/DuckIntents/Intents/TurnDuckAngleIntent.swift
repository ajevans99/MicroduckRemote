import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct TurnDuckAngleIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Turn Microduck Angle"
  public static let description = IntentDescription(
    "Rotates Microduck in place by an exact angle in degrees (15 to 360 degrees) using closed-loop heading feedback from contact odometry and the onboard IMU."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Direction",
    description: "Whether to turn left (counterclockwise) or right (clockwise).",
    default: .left
  )
  public var direction: DuckTurnDirection

  @Parameter(
    title: "Angle (Degrees)",
    description: "How many degrees to rotate in place (15 to 360). Use 90 for a quarter turn and 180 to turn around.",
    default: 90.0,
    controlStyle: .field,
    inclusiveRange: (15.0, 360.0)
  )
  public var angleDegrees: Double

  @Parameter(
    title: "Speed (%)",
    description: "Turn speed percentage from 25% (gentle) to 100% (fast).",
    default: 80.0,
    controlStyle: .slider,
    inclusiveRange: (25.0, 100.0)
  )
  public var speedPercent: Double

  public static var parameterSummary: some ParameterSummary {
    Summary("Turn Microduck \(\.$direction) \(\.$angleDegrees)° at \(\.$speedPercent)% speed")
  }

  public init() {}

  public init(
    direction: DuckTurnDirection = .left,
    angleDegrees: Double = 90.0,
    speedPercent: Double = 80.0
  ) {
    self.direction = direction
    self.angleDegrees = angleDegrees
    self.speedPercent = speedPercent
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    let clampedAngle = min(max(angleDegrees, 15.0), 360.0)
    let signedDegrees = direction == .left ? clampedAngle : -clampedAngle
    let goal = DuckMotionGoal.turnAngle(degrees: signedDegrees, speedPercent: speedPercent)

    let resultText = try await DuckIntentRunner.runConnectedTool(
      intentName: "TurnDuckAngleIntent",
      displayTitle: "Turn Microduck Angle",
      parameters: [
        .init(key: "direction", value: direction.rawValue),
        .init(key: "angle", value: "\(Int(clampedAngle.rounded()))°"),
        .init(key: "speed", value: "\(Int(speedPercent.rounded()))%"),
      ],
      refreshIfOpen: true
    ) { connection, duckSession in
      let result = try await duckSession.performMotion(goal)
      let turned = Int(abs(result.angleTurnedDegrees).rounded())
      let modeTag = result.usedClosedLoopFeedback ? "heading feedback" : "timed fallback"

      switch result.stopReason {
      case .reachedTarget:
        return "Turned \(connection.duckName) \(direction.rawValue) \(turned)° (\(modeTag))."
      case .timedOut:
        return "Stopped turning \(connection.duckName) after \(turned)° (reached safety timeout)."
      case let .stoppedForObstacle(distanceMm):
        return "Stopped turning \(connection.duckName) after \(turned)° (obstacle \(distanceMm) mm ahead)."
      case let .interruptedBySafety(reason):
        return "Stopped turning \(connection.duckName) early after \(turned)°: \(reason)."
      }
    }

    return .result(value: resultText)
  }
}
