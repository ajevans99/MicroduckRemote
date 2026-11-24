import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

public struct PerformTrickIntent: AppIntent {
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

  public func perform() async throws -> some AppIntents.IntentResult & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let initial = await duckSession.currentSnapshot()
    let duckName: String
    if initial.controlOpen {
      duckName = initial.phase.connected?.name ?? "Microduck"
    } else {
      let identity = try await duckSession.ensureConnected(.seconds(6))
      duckName = identity.name
    }

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
    return .result(dialog: "\(duckName) is performing \(trick.name).")
  }
}

@available(iOS 27.3, macOS 27.3, *)
extension PerformTrickIntent: ToolIntent, LiveActivityIntent {}
