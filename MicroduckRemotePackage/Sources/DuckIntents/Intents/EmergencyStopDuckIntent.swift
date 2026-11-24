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
    let dialogText = try await DuckIntentRunner.runConnectedTool(
      intentName: "EmergencyStopDuckIntent",
      displayTitle: "Stop Microduck",
      connectionTimeout: .seconds(5)
    ) { connection, duckSession in
      await duckSession.sendMove(.zero)
      try await duckSession.stop()
      return "Stopped \(connection.duckName)."
    }

    return .result(value: dialogText)
  }
}
