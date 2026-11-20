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

  public func perform() async throws -> some AppIntents.IntentResult & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let snapshot = await duckSession.currentSnapshot()
    let duckName: String
    if snapshot.controlOpen {
      duckName = snapshot.phase.connected?.name ?? "Microduck"
    } else {
      let identity = try await duckSession.ensureConnected(.seconds(5))
      duckName = identity.name
    }

    await duckSession.sendMove(.zero)
    try await duckSession.stop()

    return .result(dialog: "Stopped \(duckName).")
  }
}
