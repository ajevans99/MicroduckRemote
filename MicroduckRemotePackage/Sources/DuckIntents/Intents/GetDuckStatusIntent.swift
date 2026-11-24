import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

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

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckStatusEntity> {
    let status = try await DuckIntentRunner.runConnectedTool(
      intentName: "GetDuckStatusIntent",
      displayTitle: "Get Microduck Status",
      refreshIfOpen: true
    ) { _, duckSession in
      let snapshot = await duckSession.currentSnapshot()
      let entity = DuckStatusEntity(snapshot: snapshot)
      DuckStatusStore.shared.save(entity)
      return (entity, entity.spokenSummary)
    }

    return .result(value: status)
  }
}
