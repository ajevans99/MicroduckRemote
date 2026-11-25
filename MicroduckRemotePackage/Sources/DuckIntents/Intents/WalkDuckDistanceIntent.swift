import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct WalkDuckDistanceIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Walk Microduck Distance"
  public static let description = IntentDescription(
    "Walks or sidesteps Microduck a real-world distance in meters (0.1 to 3.0 m) using closed-loop contact odometry, automatically decelerating near the target and stopping early if the 8x8 depth sensor sees an obstacle."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Direction",
    description: "Direction to walk or sidestep.",
    default: .forward
  )
  public var direction: DuckWalkDirection

  @Parameter(
    title: "Distance (Meters)",
    description: "Target travel distance in meters (0.1 to 3.0 m). For feet, 1 foot is approximately 0.30 meters.",
    default: 0.5,
    controlStyle: .field,
    inclusiveRange: (0.1, 3.0)
  )
  public var distanceMeters: Double

  @Parameter(
    title: "Speed (%)",
    description: "Walking speed percentage from 20% (slow) to 100% (full speed).",
    default: 65.0,
    controlStyle: .slider,
    inclusiveRange: (20.0, 100.0)
  )
  public var speedPercent: Double

  @Parameter(
    title: "Stop on Obstacle",
    description: "When walking forward, automatically stop if the 8x8 depth sensor sees an obstacle closer than 200 mm.",
    default: true
  )
  public var stopOnObstacle: Bool

  public static var parameterSummary: some ParameterSummary {
    Summary("Walk Microduck \(\.$direction) \(\.$distanceMeters) meters at \(\.$speedPercent)% speed") {
      \.$stopOnObstacle
    }
  }

  public init() {}

  public init(
    direction: DuckWalkDirection = .forward,
    distanceMeters: Double = 0.5,
    speedPercent: Double = 65.0,
    stopOnObstacle: Bool = true
  ) {
    self.direction = direction
    self.distanceMeters = distanceMeters
    self.speedPercent = speedPercent
    self.stopOnObstacle = stopOnObstacle
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    let clampedMeters = min(max(distanceMeters, 0.1), 3.0)
    let goal = DuckMotionGoal.moveDistance(
      direction: direction.linearDirection,
      meters: clampedMeters,
      speedPercent: speedPercent,
      stopOnObstacle: stopOnObstacle
    )

    let resultText = try await DuckIntentRunner.runConnectedTool(
      intentName: "WalkDuckDistanceIntent",
      displayTitle: "Walk Microduck Distance",
      parameters: [
        .init(key: "direction", value: direction.rawValue),
        .init(key: "distance", value: String(format: "%.2fm", clampedMeters)),
        .init(key: "speed", value: "\(Int(speedPercent.rounded()))%"),
        .init(key: "stopOnObstacle", value: stopOnObstacle ? "true" : "false"),
      ],
      refreshIfOpen: true
    ) { connection, duckSession in
      let result = try await duckSession.performMotion(goal)
      let traveled = String(format: "%.2f", result.distanceTraveledMeters)
      let modeTag = result.usedClosedLoopFeedback ? "odometry" : "timed fallback"

      switch result.stopReason {
      case .reachedTarget:
        return "Walked \(connection.duckName) \(direction.linearDirection.spokenLabel) \(traveled) m (\(modeTag))."
      case let .stoppedForObstacle(distanceMm):
        return "Stopped \(connection.duckName) after \(traveled) m — obstacle detected \(distanceMm) mm ahead."
      case .timedOut:
        return "Stopped \(connection.duckName) after \(traveled) m (reached safety timeout)."
      case let .interruptedBySafety(reason):
        return "Stopped \(connection.duckName) early after \(traveled) m: \(reason)."
      }
    }

    return .result(value: resultText)
  }
}
