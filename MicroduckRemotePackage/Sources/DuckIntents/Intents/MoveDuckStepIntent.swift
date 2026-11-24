import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct MoveDuckStepIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Move Microduck"
  public static let description = IntentDescription(
    "Walks, sidesteps, or turns Microduck for a bounded duration (0.2 to 5.0 seconds) at 10 Hz, automatically checking upright safety and stopping early if the forward 8x8 depth sensor detects an obstacle."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Direction",
    description: "Direction to walk, sidestep, or rotate in place.",
    default: .forward
  )
  public var direction: DuckMoveDirection

  @Parameter(
    title: "Duration (Seconds)",
    description: "How long in seconds (0.2 to 5.0) to move before stopping automatically. Roughly 2.1 seconds at 100% turn speed rotates 180 degrees.",
    default: 1.5,
    controlStyle: .field,
    inclusiveRange: (0.2, 5.0)
  )
  public var durationSeconds: Double

  @Parameter(
    title: "Speed (%)",
    description: "Movement speed percentage from 20% (slow) to 100% (full speed).",
    default: 60.0,
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
    Summary("Move Microduck \(\.$direction) for \(\.$durationSeconds) seconds at \(\.$speedPercent)% speed") {
      \.$stopOnObstacle
    }
  }

  public init() {}

  public init(
    direction: DuckMoveDirection,
    durationSeconds: Double = 1.5,
    speedPercent: Double = 60.0,
    stopOnObstacle: Bool = true
  ) {
    self.direction = direction
    self.durationSeconds = durationSeconds
    self.speedPercent = speedPercent
    self.stopOnObstacle = stopOnObstacle
  }

  public func perform() async throws -> some AppIntents.IntentResult & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let request = direction.makeRequest(
      durationSeconds: durationSeconds,
      speedPercent: speedPercent,
      stopOnObstacle: stopOnObstacle
    )
    let twist = request.clampedTwist

    let dialogText = try await IntentTelemetryTracer.traceTool(
      intentName: "MoveDuckStepIntent",
      displayTitle: "Move Microduck",
      parameters: [
        .init(key: "direction", value: direction.rawValue),
        .init(key: "duration", value: "\(durationSeconds.formatted(.number.precision(.fractionLength(0...2))))s"),
        .init(key: "speed", value: "\(Int(speedPercent.rounded()))%"),
        .init(key: "twist", value: String(format: "vx %+.2f, vy %+.2f, vyaw %+.2f", twist.vx, twist.vy, twist.vyaw)),
        .init(key: "stopOnObstacle", value: stopOnObstacle ? "true" : "false"),
      ]
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(
        timeout: .seconds(6),
        refreshIfOpen: true
      )
      setContext(connection.contextLabel)

      let result = try await duckSession.performMoveStep(request)
      let elapsed = result.elapsedSeconds.formatted(.number.precision(.fractionLength(0...1)))

      let message: String
      switch result.stopReason {
      case .completed:
        message = "Moved \(connection.duckName) \(direction.spokenLabel) for \(elapsed) seconds."
      case let .stoppedForObstacle(distanceMm):
        message = "Stopped \(connection.duckName) after \(elapsed) seconds — obstacle detected \(distanceMm) mm ahead."
      case let .interruptedBySafety(reason):
        message = "Stopped \(connection.duckName) early after \(elapsed) seconds: \(reason)."
      }
      return (message, message)
    }

    return .result(dialog: IntentDialog(stringLiteral: dialogText))
  }
}
