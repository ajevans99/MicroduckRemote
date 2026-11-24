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

    let initial = await duckSession.currentSnapshot()
    let duckName: String
    if initial.controlOpen {
      duckName = initial.phase.connected?.name ?? "Microduck"
    } else {
      let identity = try await duckSession.ensureConnected(.seconds(6))
      duckName = identity.name
    }

    let request = direction.makeRequest(
      durationSeconds: durationSeconds,
      speedPercent: speedPercent,
      stopOnObstacle: stopOnObstacle
    )
    let result = try await duckSession.performMoveStep(request)
    let elapsed = result.elapsedSeconds.formatted(.number.precision(.fractionLength(0...1)))

    switch result.stopReason {
    case .completed:
      return .result(dialog: "Moved \(duckName) \(direction.spokenLabel) for \(elapsed) seconds.")
    case let .stoppedForObstacle(distanceMm):
      return .result(
        dialog: "Stopped \(duckName) after \(elapsed) seconds — obstacle detected \(distanceMm) mm ahead."
      )
    case let .interruptedBySafety(reason):
      return .result(dialog: "Stopped \(duckName) early after \(elapsed) seconds: \(reason).")
    }
  }
}
