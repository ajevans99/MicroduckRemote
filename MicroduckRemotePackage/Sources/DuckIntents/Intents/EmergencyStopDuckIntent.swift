import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct EmergencyStopDuckIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Stop Microduck"
  public static let description = IntentDescription(
    "Immediately halts Microduck's walking movement and cancels any active trick while keeping leg servos upright."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  public static var parameterSummary: some ParameterSummary {
    Summary("Immediately stop Microduck")
  }

  public init() {}

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let dialogText = try await IntentTelemetryTracer.traceTool(
      intentName: "EmergencyStopDuckIntent",
      displayTitle: "Stop Microduck"
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(timeout: .seconds(5))
      setContext(connection.contextLabel)

      await duckSession.sendMove(.zero)
      try await duckSession.stop()

      let message = "Stopped \(connection.duckName)."
      return (message, message)
    }

    return .result(value: dialogText)
  }
}
