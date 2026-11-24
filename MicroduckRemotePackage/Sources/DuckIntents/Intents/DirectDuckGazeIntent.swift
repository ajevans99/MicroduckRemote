import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct DirectDuckGazeIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Aim Microduck Head"
  public static let description = IntentDescription(
    "Aims Microduck's head and camera toward a horizontal and vertical direction (for example look left, look up at a person, look down at the floor, or center ahead)."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Horizontal (%)",
    description: "Left/right gaze target from -100 (far left) through 0 (center) to 100 (far right).",
    default: 0.0,
    controlStyle: .slider,
    inclusiveRange: (-100.0, 100.0)
  )
  public var horizontalPercent: Double

  @Parameter(
    title: "Vertical (%)",
    description: "Up/down gaze target from -100 (look up) through 0 (level) to 100 (look down at the floor).",
    default: 0.0,
    controlStyle: .slider,
    inclusiveRange: (-100.0, 100.0)
  )
  public var verticalPercent: Double

  public static var parameterSummary: some ParameterSummary {
    Summary("Aim Microduck's head to (\(\.$horizontalPercent)%, \(\.$verticalPercent)%)")
  }

  public init() {}

  public init(horizontalPercent: Double = 0, verticalPercent: Double = 0) {
    self.horizontalPercent = horizontalPercent
    self.verticalPercent = verticalPercent
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let dialogText = try await IntentTelemetryTracer.traceTool(
      intentName: "DirectDuckGazeIntent",
      displayTitle: "Aim Microduck Head",
      parameters: [
        .init(key: "horizontal", value: "\(Int(horizontalPercent.rounded()))%"),
        .init(key: "vertical", value: "\(Int(verticalPercent.rounded()))%"),
      ]
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(timeout: .seconds(6))
      setContext(connection.contextLabel)

      let target = LookGeometry.lookTarget(
        normalizedX: min(max(horizontalPercent, -100), 100) / 100.0,
        normalizedY: min(max(verticalPercent, -100), 100) / 100.0
      )
      let result = await duckSession.sendLook(target)
      let message = result?.clamped == true
        ? "Aimed \(connection.duckName)'s head toward your target (clamped to joint limits)."
        : "Aimed \(connection.duckName)'s head."
      return (message, message)
    }

    return .result(value: dialogText)
  }
}
