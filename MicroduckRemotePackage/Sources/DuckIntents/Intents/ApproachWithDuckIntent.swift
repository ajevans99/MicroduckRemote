import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct ApproachWithDuckIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Move Microduck to Clearance"
  public static let description = IntentDescription(
    "Drives Microduck forward until it is within a target clearance from an obstacle ahead, or backs up until open space ahead exceeds the target clearance, using live 8x8 ToF depth readings."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Mode",
    description: "Approach an object ahead or back up until clear space opens up.",
    default: .approach
  )
  public var mode: DuckClearanceMode

  @Parameter(
    title: "Target Clearance (cm)",
    description: "Desired distance in centimeters (15 to 150 cm) from the obstacle ahead.",
    default: 30,
    controlStyle: .field,
    inclusiveRange: (15, 150)
  )
  public var targetClearanceCm: Int

  @Parameter(
    title: "Speed (%)",
    description: "Movement speed percentage from 20% to 85%.",
    default: 55.0,
    controlStyle: .slider,
    inclusiveRange: (20.0, 85.0)
  )
  public var speedPercent: Double

  public static var parameterSummary: some ParameterSummary {
    Summary("\(\.$mode) to \(\.$targetClearanceCm) cm with Microduck") {
      \.$speedPercent
    }
  }

  public init() {}

  public init(
    mode: DuckClearanceMode = .approach,
    targetClearanceCm: Int = 30,
    speedPercent: Double = 55.0
  ) {
    self.mode = mode
    self.targetClearanceCm = targetClearanceCm
    self.speedPercent = speedPercent
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    let clampedCm = min(max(targetClearanceCm, 15), 150)
    let targetMm = clampedCm * 10
    let goal: DuckMotionGoal = switch mode {
    case .approach:
      .approachObstacle(targetClearanceMm: targetMm, speedPercent: speedPercent)
    case .backUpUntilClear:
      .backUpUntilClear(targetClearanceMm: targetMm, speedPercent: speedPercent)
    }

    let resultText = try await DuckIntentRunner.runConnectedTool(
      intentName: "ApproachWithDuckIntent",
      displayTitle: "Move Microduck to Clearance",
      parameters: [
        .init(key: "mode", value: mode.rawValue),
        .init(key: "targetClearance", value: "\(clampedCm) cm"),
        .init(key: "speed", value: "\(Int(speedPercent.rounded()))%"),
      ],
      refreshIfOpen: true
    ) { connection, duckSession in
      let result = try await duckSession.performMotion(goal)
      let clearanceText = result.finalFrontClearanceMm.map { "\($0 / 10) cm" } ?? "unknown clearance"

      switch result.stopReason {
      case .reachedTarget:
        switch mode {
        case .approach:
          return "\(connection.duckName) approached to \(clearanceText) from the obstacle ahead."
        case .backUpUntilClear:
          return "\(connection.duckName) backed up until clearance ahead reached \(clearanceText)."
        }
      case .timedOut:
        return "Stopped \(connection.duckName) at \(clearanceText) ahead (reached safety timeout)."
      case let .stoppedForObstacle(distanceMm):
        return "Stopped \(connection.duckName) at \(distanceMm / 10) cm ahead."
      case let .interruptedBySafety(reason):
        return "Stopped \(connection.duckName) early: \(reason)."
      }
    }

    return .result(value: resultText)
  }
}
