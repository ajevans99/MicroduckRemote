import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct PerformTrickIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Perform Duck Trick"
  public static let description = IntentDescription(
    "Performs a built-in skill or custom Hugging Face trick currently installed on Microduck (such as Roulade, Kick Left, Kick Right, Ground Pick, or Polite Bow). Microduck must be standing upright."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Trick",
    description: "The installed skill or trick on Microduck to perform."
  )
  public var trick: InstalledSkillEntity

  public static var parameterSummary: some ParameterSummary {
    Summary("Make Microduck perform \(\.$trick)")
  }

  public init() {}

  public init(trick: InstalledSkillEntity) {
    self.trick = trick
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    let dialogText = try await DuckIntentRunner.runConnectedTool(
      intentName: "PerformTrickIntent",
      displayTitle: "Perform Duck Trick",
      parameters: [
        .init(key: "trick", value: "\(trick.name) (\(trick.id))"),
      ],
      refreshIfOpen: true
    ) { connection, duckSession in
      let snapshot = await duckSession.currentSnapshot()
      if snapshot.latestState?.safety?.fallen == true {
        throw DuckSessionError.duckFallen
      }
      if snapshot.latestState?.safety?.pickedUp == true {
        throw DuckSessionError.duckPickedUp
      }
      if snapshot.policies?.enabled == false || snapshot.policies?.sitting == true {
        throw DuckSessionError.duckNotStanding
      }

      try await duckSession.performSkill(trick.id)
      return "\(connection.duckName) is performing \(trick.name)."
    }

    return .result(value: dialogText)
  }
}
