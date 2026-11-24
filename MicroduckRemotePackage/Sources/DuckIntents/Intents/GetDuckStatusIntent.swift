import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

public struct GetDuckStatusIntent: AppIntent {
  public static let title: LocalizedStringResource = "Get Microduck Status"
  public static let description = IntentDescription(
    "Checks Microduck's live health, posture (standing, sitting, fallen, picked up), battery voltage and percentage, hottest servo temperature, 50 Hz control loop rate, and movement limiters."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  public static var parameterSummary: some ParameterSummary {
    Summary("Get live status of Microduck")
  }

  public init() {}

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckStatusEntity> & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let initial = await duckSession.currentSnapshot()
    if !initial.controlOpen {
      _ = try await duckSession.ensureConnected(.seconds(6))
    } else {
      await duckSession.refreshSkills()
    }

    let snapshot = await duckSession.currentSnapshot()
    let status = DuckStatusEntity(snapshot: snapshot)
    return .result(
      value: status,
      dialog: IntentDialog(stringLiteral: status.spokenSummary)
    )
  }
}

@available(iOS 27.3, macOS 27.3, *)
extension GetDuckStatusIntent: ToolIntent, LiveActivityIntent {}
