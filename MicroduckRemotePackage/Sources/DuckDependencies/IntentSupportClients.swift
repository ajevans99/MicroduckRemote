import Dependencies
import DuckProtocol
import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

extension UserDefaults {
  /// Returns the shared App Group defaults container when provisioned, falling back to `.standard`
  /// during local Simulator development so cross-target state readers always succeed.
  public static var microduckShared: UserDefaults {
    UserDefaults(suiteName: DuckConstants.appGroupID) ?? .standard
  }
}

extension DuckSharedSummary {
  public init(snapshot: DuckSessionSnapshot, updatedAt: Date) {
    let connectedIdentity = snapshot.phase.connected
    self.init(
      isConnected: snapshot.controlOpen,
      duckName: connectedIdentity?.name,
      peerID: connectedIdentity?.peerID,
      isSimulated: connectedIdentity?.isSimulated ?? false,
      isEnabled: snapshot.policies?.enabled == true,
      isSitting: snapshot.policies?.sitting == true,
      isFallen: snapshot.latestState?.safety?.fallen == true,
      isPickedUp: snapshot.latestState?.safety?.pickedUp == true,
      activePolicy: snapshot.latestState?.policy ?? snapshot.mode,
      batteryVolts: snapshot.health?.battery?.volts,
      batteryPercent: snapshot.health?.battery.map { Int($0.percent.rounded()) },
      maxMotorTempC: snapshot.health?.motors.map { Int($0.maxC.rounded()) },
      hottestMotor: snapshot.health?.motors?.hottest,
      installedSkillNames: snapshot.skillNames,
      updatedAt: updatedAt
    )
  }
}

public struct ConnectionPreferencesClient: Sendable {
  public var loadPreference: @Sendable () -> LastConnectionPreference?
  public var savePreference: @Sendable (LastConnectionPreference) -> Void
  public var clearPreference: @Sendable () -> Void

  public init(
    loadPreference: @escaping @Sendable () -> LastConnectionPreference?,
    savePreference: @escaping @Sendable (LastConnectionPreference) -> Void,
    clearPreference: @escaping @Sendable () -> Void
  ) {
    self.loadPreference = loadPreference
    self.savePreference = savePreference
    self.clearPreference = clearPreference
  }

  /// Resolves the target Siri / Shortcuts / Control Center should connect to on a cold start.
  public static func resolveColdStartTarget(
    preference: LastConnectionPreference?,
    huggingFaceSession: HuggingFaceSession?,
    isSimulator: Bool
  ) throws -> ConnectionTarget {
    switch preference {
    case let .localSimulator(url):
      return .localSimulator(url: url)

    case let .rendezvous(serverURL, preferredPeerID):
      guard let session = huggingFaceSession else {
        throw DuckSessionError.missingHuggingFaceAccount
      }
      return .rendezvous(
        serverURL: serverURL,
        token: session.token,
        username: session.username,
        preferredPeerID: preferredPeerID
      )

    case nil:
      if let session = huggingFaceSession {
        return .rendezvous(
          serverURL: DuckConstants.defaultRendezvousURL,
          token: session.token,
          username: session.username,
          preferredPeerID: nil
        )
      }
      if isSimulator {
        return .localSimulator(url: DuckConstants.defaultLocalSignallingURL)
      }
      throw DuckSessionError.missingHuggingFaceAccount
    }
  }
}

extension ConnectionPreferencesClient: DependencyKey {
  private static let storageKey = "microduck.connection.lastPreference.v1"

  public static var liveValue: ConnectionPreferencesClient {
    ConnectionPreferencesClient(
      loadPreference: {
        guard let data = UserDefaults.microduckShared.data(forKey: storageKey) else {
          return nil
        }
        return try? JSONDecoder().decode(LastConnectionPreference.self, from: data)
      },
      savePreference: { preference in
        if let data = try? JSONEncoder().encode(preference) {
          UserDefaults.microduckShared.set(data, forKey: storageKey)
        }
      },
      clearPreference: {
        UserDefaults.microduckShared.removeObject(forKey: storageKey)
      }
    )
  }

  public static var previewValue: ConnectionPreferencesClient {
    ConnectionPreferencesClient(
      loadPreference: { .localSimulator(url: DuckConstants.defaultLocalSignallingURL) },
      savePreference: { _ in },
      clearPreference: {}
    )
  }

  public static var testValue: ConnectionPreferencesClient {
    previewValue
  }
}

public struct DuckSharedStateClient: Sendable {
  public var loadSummary: @Sendable () -> DuckSharedSummary
  public var publishSummary: @Sendable (DuckSharedSummary) -> Void

  public init(
    loadSummary: @escaping @Sendable () -> DuckSharedSummary,
    publishSummary: @escaping @Sendable (DuckSharedSummary) -> Void
  ) {
    self.loadSummary = loadSummary
    self.publishSummary = publishSummary
  }
}

extension DuckSharedStateClient: DependencyKey {
  private static let storageKey = "microduck.shared.summary.v1"

  public static var liveValue: DuckSharedStateClient {
    let lastPublished = LockIsolated<DuckSharedSummary?>(nil)
    return DuckSharedStateClient(
      loadSummary: {
        guard
          let data = UserDefaults.microduckShared.data(forKey: storageKey),
          let decoded = try? JSONDecoder().decode(DuckSharedSummary.self, from: data)
        else {
          return DuckSharedSummary()
        }
        return decoded
      },
      publishSummary: { next in
        let shouldReloadControls = lastPublished.withValue { previous in
          let changed = previous.map { !$0.hasSameControlSurfaceState(as: next) } ?? true
          previous = next
          return changed
        }
        if let data = try? JSONEncoder().encode(next) {
          UserDefaults.microduckShared.set(data, forKey: storageKey)
        }
        if shouldReloadControls {
          #if canImport(WidgetKit)
          if #available(iOS 18.0, macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
          }
          WidgetCenter.shared.reloadAllTimelines()
          #endif
        }
      }
    )
  }

  public static var previewValue: DuckSharedStateClient {
    let summary = DuckSharedSummary(
      snapshot: .previewConnected,
      updatedAt: Date(timeIntervalSince1970: 1_795_150_000)
    )
    return DuckSharedStateClient(
      loadSummary: { summary },
      publishSummary: { _ in }
    )
  }

  public static var testValue: DuckSharedStateClient {
    previewValue
  }
}

extension DependencyValues {
  public var connectionPreferences: ConnectionPreferencesClient {
    get { self[ConnectionPreferencesClient.self] }
    set { self[ConnectionPreferencesClient.self] = newValue }
  }

  public var duckSharedState: DuckSharedStateClient {
    get { self[DuckSharedStateClient.self] }
    set { self[DuckSharedStateClient.self] = newValue }
  }
}

/// Runs bounded 10 Hz (`100 ms`) `robot.move` pulses required by Microduck's onboard deadman
/// timer, checking upright safety and forward 8×8 ToF clearance on every tick and guaranteeing
/// a terminal `RobotMoveParams.zero` command even on task cancellation.
public enum DuckMoveStepExecutor {
  public static func execute(
    request: DuckMoveStepRequest,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    subscribeTof: @Sendable () async -> Void,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void
  ) async throws -> DuckMoveStepResult {
    let initial = await currentSnapshot()
    guard initial.controlOpen else {
      throw RpcErrorPayload(code: -32000, message: "Not connected to duck control channel.")
    }
    if initial.latestState?.safety?.fallen == true {
      throw DuckSessionError.duckFallen
    }
    if initial.latestState?.safety?.pickedUp == true {
      throw DuckSessionError.duckPickedUp
    }
    if initial.policies?.enabled == false || initial.policies?.sitting == true {
      throw DuckSessionError.duckNotStanding
    }

    let twist = request.clampedTwist
    let duration = request.clampedDurationSeconds
    let hz = DuckConstants.intentHz
    let tickInterval = Duration.milliseconds(1000 / hz)
    let totalTicks = max(1, Int((duration * Double(hz)).rounded()))

    if request.stopOnObstacle, twist.vx > 0, initial.tofFrame == nil {
      await subscribeTof()
    }

    var pulsesSent = 0
    var completedTicks = 0

    do {
      for _ in 0..<totalTicks {
        try Task.checkCancellation()

        let snapshot = await currentSnapshot()
        if !snapshot.controlOpen {
          throw RpcErrorPayload(code: -32000, message: "Duck disconnected during move.")
        }
        if snapshot.latestState?.safety?.fallen == true {
          await sendMove(.zero)
          return DuckMoveStepResult(
            appliedTwist: twist,
            elapsedSeconds: Double(completedTicks) / Double(hz),
            pulsesSent: pulsesSent,
            stopReason: .interruptedBySafety("Duck fell over")
          )
        }
        if snapshot.latestState?.safety?.pickedUp == true {
          await sendMove(.zero)
          return DuckMoveStepResult(
            appliedTwist: twist,
            elapsedSeconds: Double(completedTicks) / Double(hz),
            pulsesSent: pulsesSent,
            stopReason: .interruptedBySafety("Duck was picked up")
          )
        }
        if
          request.stopOnObstacle,
          twist.vx > 0,
          let distanceMm = snapshot.tofFrame?.frontObstacleDistanceMm,
          distanceMm < request.minObstacleDistanceMm
        {
          await sendMove(.zero)
          return DuckMoveStepResult(
            appliedTwist: twist,
            elapsedSeconds: Double(completedTicks) / Double(hz),
            pulsesSent: pulsesSent,
            stopReason: .stoppedForObstacle(distanceMm: distanceMm)
          )
        }

        await sendMove(twist)
        pulsesSent += 1
        try await clock.sleep(for: tickInterval)
        completedTicks += 1
      }

      await sendMove(.zero)
      return DuckMoveStepResult(
        appliedTwist: twist,
        elapsedSeconds: Double(completedTicks) / Double(hz),
        pulsesSent: pulsesSent,
        stopReason: .completed
      )
    } catch {
      await sendMove(.zero)
      throw error
    }
  }
}

/// Connection metadata returned when an App Intent ensures a live WebRTC session.
public struct IntentConnection: Equatable, Sendable {
  public var duckName: String
  public var wasColdStart: Bool

  public init(duckName: String, wasColdStart: Bool) {
    self.duckName = duckName
    self.wasColdStart = wasColdStart
  }

  public var telemetryLabel: String {
    wasColdStart ? "Cold start (\(duckName))" : "Warm (\(duckName))"
  }
}

extension DuckSessionClient {
  /// Reuses an open WebRTC control channel (optionally refreshing live skills/policies) or
  /// performs a cold-start connection up to `timeout`.
  public func connectForIntent(
    timeout: Duration = .seconds(6),
    refreshIfOpen: Bool = false
  ) async throws -> IntentConnection {
    let initial = await currentSnapshot()
    if initial.controlOpen {
      if refreshIfOpen {
        await refreshSkills()
      }
      let name = initial.phase.connected?.name ?? "Microduck"
      return IntentConnection(duckName: name, wasColdStart: false)
    }

    let identity = try await ensureConnected(timeout)
    return IntentConnection(duckName: identity.name, wasColdStart: true)
  }
}
