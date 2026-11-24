import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

public struct SetDuckPostureIntent: AppIntent {
  public static let title: LocalizedStringResource = "Set Microduck Posture"
  public static let description = IntentDescription(
    "Changes Microduck's posture idempotently: Stand Up (also recovers if fallen), Sit Down, Stand Back Up (explicit fall recovery), or Home Pose."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Posture",
    description: "Target posture for Microduck: Stand Up, Sit Down, Stand Back Up (recover from a fall), or Home Pose.",
    default: .standUp
  )
  public var posture: DuckPostureAction

  public static var parameterSummary: some ParameterSummary {
    Summary("Have Microduck \(\.$posture)")
  }

  public init() {}

  public init(posture: DuckPostureAction) {
    self.posture = posture
  }

  public func perform() async throws -> some AppIntents.IntentResult & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let initial = await duckSession.currentSnapshot()
    let duckName: String
    if initial.controlOpen {
      duckName = initial.phase.connected?.name ?? "Microduck"
      await duckSession.refreshSkills()
    } else {
      let identity = try await duckSession.ensureConnected(.seconds(6))
      duckName = identity.name
    }

    let snapshot = await duckSession.currentSnapshot()
    let isFallen = snapshot.latestState?.safety?.fallen == true
    let isEnabled = snapshot.policies?.enabled == true
    let isSitting = snapshot.policies?.sitting == true

    switch posture {
    case .standUp:
      if isFallen {
        try await duckSession.standBackUp()
        return .result(dialog: "Recovered \(duckName) and stood it back up.")
      }
      if !isEnabled {
        try await duckSession.setEnabled(true)
        return .result(dialog: "\(duckName) is standing up.")
      }
      if isSitting {
        try await duckSession.performSkill("sit_toggle")
        return .result(dialog: "\(duckName) is standing up from its seat.")
      }
      return .result(dialog: "\(duckName) is already standing up.")

    case .sitDown:
      if isFallen {
        throw DuckSessionError.duckFallen
      }
      if !isEnabled || isSitting {
        return .result(dialog: "\(duckName) is already sitting down.")
      }
      try await duckSession.performSkill("sit_toggle")
      return .result(dialog: "\(duckName) is sitting down.")

    case .recoverFromFall:
      try await duckSession.standBackUp()
      return .result(dialog: "Standing \(duckName) back up.")

    case .initPose:
      try await duckSession.initPose()
      return .result(dialog: "Reset \(duckName) to its home pose.")
    }
  }
}

@available(iOS 27.3, macOS 27.3, *)
extension SetDuckPostureIntent: ToolIntent, LiveActivityIntent {}
