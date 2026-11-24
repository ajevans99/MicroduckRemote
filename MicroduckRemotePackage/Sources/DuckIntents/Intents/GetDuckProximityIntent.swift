import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct GetDuckProximityIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Get Microduck Proximity"
  public static let description = IntentDescription(
    "Reads Microduck's live 8x8 ToF depth sensor to report front, left, and right obstacle clearances in millimeters, whether an obstacle is close, and the recommended open direction to travel."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  public static var parameterSummary: some ParameterSummary {
    Summary("Check obstacle proximity around Microduck")
  }

  public init() {}

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckProximityEntity> {
    @Dependencies.Dependency(\.continuousClock) var clock

    let proximity = try await DuckIntentRunner.runConnectedTool(
      intentName: "GetDuckProximityIntent",
      displayTitle: "Get Microduck Proximity"
    ) { _, duckSession in
      var snapshot = await duckSession.currentSnapshot()
      await duckSession.subscribeTof()

      if snapshot.tofFrame == nil {
        for _ in 0..<6 {
          try Task.checkCancellation()
          try await clock.sleep(for: .milliseconds(100))
          snapshot = await duckSession.currentSnapshot()
          if snapshot.tofFrame != nil { break }
        }
      }

      let entity = DuckProximityEntity(snapshot: snapshot)
      DuckProximityStore.shared.save(entity)
      return (entity, entity.summary)
    }

    return .result(value: proximity)
  }
}
