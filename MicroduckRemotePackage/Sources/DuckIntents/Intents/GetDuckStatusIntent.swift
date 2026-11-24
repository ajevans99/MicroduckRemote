import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import SwiftUI

@AppIntent(.tool)
public struct GetDuckStatusIntent: LiveActivityIntent {
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

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckStatusEntity> & ProvidesDialog & ShowsSnippetView {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let status = try await IntentTelemetryTracer.traceTool(
      intentName: "GetDuckStatusIntent",
      displayTitle: "Get Microduck Status"
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(
        timeout: .seconds(6),
        refreshIfOpen: true
      )
      setContext(connection.contextLabel)

      let snapshot = await duckSession.currentSnapshot()
      let entity = DuckStatusEntity(snapshot: snapshot)
      return (entity, entity.spokenSummary)
    }

    return .result(
      value: status,
      dialog: IntentDialog(stringLiteral: status.spokenSummary),
      view: DuckStatusCardView(status: status, isCompact: false)
    )
  }
}
