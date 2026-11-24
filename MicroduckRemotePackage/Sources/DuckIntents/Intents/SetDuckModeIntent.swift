import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct SetDuckModeIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Set Microduck Mode"
  public static let description = IntentDescription(
    "Turns an autonomous behavior mode on or off on Microduck: Autonomous Roaming, Soccer (chasing and kicking a ball), or Laser Tracking."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Mode",
    description: "The autonomous behavior mode to toggle: Autonomous Roaming, Soccer, or Laser Tracking.",
    default: .autonomous
  )
  public var mode: DuckAutonomousMode

  @Parameter(
    title: "Enabled",
    description: "Whether to turn the mode on (true) or off (false).",
    default: true
  )
  public var enabled: Bool

  public static var parameterSummary: some ParameterSummary {
    Switch(\.$enabled) {
      Case(true) {
        Summary("Turn on \(\.$mode) on Microduck")
      }
      DefaultCase {
        Summary("Turn off \(\.$mode) on Microduck")
      }
    }
  }

  public init() {}

  public init(mode: DuckAutonomousMode, enabled: Bool = true) {
    self.mode = mode
    self.enabled = enabled
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    let dialogText = try await DuckIntentRunner.runConnectedTool(
      intentName: "SetDuckModeIntent",
      displayTitle: "Set Microduck Mode",
      parameters: [
        .init(key: "mode", value: mode.rawValue),
        .init(key: "enabled", value: enabled ? "true" : "false"),
      ],
      refreshIfOpen: true
    ) { connection, duckSession in
      if enabled {
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
      }

      switch mode {
      case .autonomous:
        try await duckSession.setAutonomous(enabled)
      case .soccer:
        try await duckSession.setSoccer(enabled)
      case .laserTrack:
        try await duckSession.setLaserTrack(enabled)
      }

      let stateWord = enabled ? "on" : "off"
      return "Turned \(stateWord) \(mode.spokenLabel) on \(connection.duckName)."
    }

    return .result(value: dialogText)
  }
}
