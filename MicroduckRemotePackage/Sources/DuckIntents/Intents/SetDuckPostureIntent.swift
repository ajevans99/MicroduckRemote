import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct SetDuckPostureIntent: LiveActivityIntent {
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

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckStatusEntity> {
    @Dependencies.Dependency(\.continuousClock) var clock

    let status = try await DuckIntentRunner.runConnectedTool(
      intentName: "SetDuckPostureIntent",
      displayTitle: "Set Microduck Posture",
      parameters: [.init(key: "posture", value: posture.rawValue)],
      refreshIfOpen: true
    ) { connection, duckSession in
      let snapshot = await duckSession.currentSnapshot()
      let isFallen = snapshot.latestState?.safety?.fallen == true
      let isEnabled = snapshot.policies?.enabled == true
      let isSitting = snapshot.policies?.sitting == true

      let message: String
      switch posture {
      case .standUp:
        if isFallen {
          try await duckSession.standBackUp()
          await Self.waitUntilStanding(duckSession: duckSession, clock: clock)
          message = "Recovered \(connection.duckName) and stood it back up."
        } else if !isEnabled {
          try await duckSession.setEnabled(true)
          await Self.waitUntilStanding(duckSession: duckSession, clock: clock)
          message = "\(connection.duckName) is standing up."
        } else if isSitting {
          try await duckSession.performSkill("sit_toggle")
          await Self.waitUntilStanding(
            duckSession: duckSession,
            clock: clock,
            retrySitToggleIfStillSitting: true
          )
          message = "\(connection.duckName) is standing up from its seat."
        } else {
          message = "\(connection.duckName) is already standing up."
        }

      case .sitDown:
        if isFallen {
          throw DuckSessionError.duckFallen
        }
        if !isEnabled || isSitting {
          message = "\(connection.duckName) is already sitting down."
        } else {
          try await duckSession.performSkill("sit_toggle")
          // `robotd` enforces a 2.0 s `sitstand_ramp_s` settle timer before `sit_toggle`
          // can be reversed, so wait for the seat to settle before returning to a chained tool.
          try? await clock.sleep(for: .milliseconds(2200))
          await duckSession.refreshSkills()
          message = "\(connection.duckName) is sitting down."
        }

      case .recoverFromFall:
        try await duckSession.standBackUp()
        await Self.waitUntilStanding(duckSession: duckSession, clock: clock)
        message = "Standing \(connection.duckName) back up."

      case .initPose:
        try await duckSession.initPose()
        message = "Reset \(connection.duckName) to its home pose."
      }

      let updatedStatus = DuckStatusEntity(snapshot: await duckSession.currentSnapshot())
      DuckStatusStore.shared.save(updatedStatus)
      return (updatedStatus, message)
    }

    return .result(value: status)
  }

  /// Polls `robot.policies` until Microduck finishes its rise/enable transition so a
  /// chained `MoveDuckStepIntent` sees a standing robot immediately.
  private static func waitUntilStanding(
    duckSession: DuckSessionClient,
    clock: any Clock<Duration>,
    retrySitToggleIfStillSitting: Bool = false,
    maxAttempts: Int = 18,
    pollInterval: Duration = .milliseconds(200)
  ) async {
    var didRetryToggle = false
    for attempt in 0..<maxAttempts {
      if Task.isCancelled { return }
      await duckSession.refreshSkills()
      let current = await duckSession.currentSnapshot()
      let policies = current.policies
      let activePolicy = current.latestState?.policy
      let isReadyToWalk = policies?.enabled == true
        && policies?.sitting != true
        && activePolicy != "rise"
        && activePolicy != "sit"
      if isReadyToWalk {
        return
      }
      if retrySitToggleIfStillSitting, !didRetryToggle, attempt == 4, policies?.sitting == true {
        didRetryToggle = true
        try? await duckSession.performSkill("sit_toggle")
      }
      if attempt + 1 < maxAttempts {
        try? await clock.sleep(for: pollInterval)
      }
    }
  }
}
