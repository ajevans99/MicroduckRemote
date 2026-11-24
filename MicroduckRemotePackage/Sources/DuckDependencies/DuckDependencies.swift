import CasePaths
import Dependencies
import DuckProtocol
import Foundation
import IdentifiedCollections
import SwiftUI

@CasePathable
@dynamicMemberLookup
public enum ConnectionTarget: Codable, Equatable, Sendable {
  case localSimulator(url: String)
  case rendezvous(
    serverURL: String,
    token: String,
    username: String,
    preferredPeerID: String?
  )

  public var displayTitle: String {
    switch self {
    case let .localSimulator(url):
      url.replacingOccurrences(of: "ws://", with: "")
    case let .rendezvous(_, _, username, _):
      "Hugging Face (@\(username))"
    }
  }

  public var isRemote: Bool {
    self.is(\.rendezvous)
  }
}

public struct DuckIdentity: Codable, Equatable, Sendable {
  public var peerID: String
  public var name: String
  public var serial: String?
  public var release: String?
  public var apiVersion: Int?
  public var isSimulated: Bool

  public init(
    peerID: String,
    name: String,
    serial: String? = nil,
    release: String? = nil,
    apiVersion: Int? = nil,
    isSimulated: Bool = false
  ) {
    self.peerID = peerID
    self.name = name
    self.serial = serial
    self.release = release
    self.apiVersion = apiVersion
    self.isSimulated = isSimulated
  }
}

@CasePathable
@dynamicMemberLookup
public enum ConnectionPhase: Equatable, Sendable {
  case disconnected
  case connecting(step: String)
  case connected(DuckIdentity)
  case failed(String)

  public var isConnected: Bool {
    self.is(\.connected)
  }

  public var statusText: String {
    switch self {
    case .disconnected:
      "Disconnected"
    case let .connecting(step):
      step
    case let .connected(identity):
      identity.name
    case let .failed(reason):
      reason
    }
  }
}

public struct LinkStats: Equatable, Sendable {
  public var fps: Int?
  public var bitrateKbps: Int?
  public var packetLossPercent: Double?
  public var rttMs: Int?

  public init(
    fps: Int? = nil,
    bitrateKbps: Int? = nil,
    packetLossPercent: Double? = nil,
    rttMs: Int? = nil
  ) {
    self.fps = fps
    self.bitrateKbps = bitrateKbps
    self.packetLossPercent = packetLossPercent
    self.rttMs = rttMs
  }
}

public struct LoopSample: Equatable, Identifiable, Sendable {
  public var id: Int
  public var timestamp: Date
  public var hz: Double

  public init(id: Int, timestamp: Date, hz: Double) {
    self.id = id
    self.timestamp = timestamp
    self.hz = hz
  }
}

public struct RpcLogEntry: Equatable, Identifiable, Sendable {
  public enum Level: String, Equatable, Sendable {
    case inbound
    case outbound
    case info
    case warning
    case error
  }

  public var id: UUID
  public var timestamp: Date
  public var level: Level
  public var message: String

  public init(id: UUID = UUID(), timestamp: Date = Date(), level: Level, message: String) {
    self.id = id
    self.timestamp = timestamp
    self.level = level
    self.message = message
  }
}

@CasePathable
public enum TrickInstallStage: String, Equatable, Sendable {
  case downloading = "Downloading from Hub…"
  case installing = "Installing on duck…"
  case waitingForStand = "Waiting for stand…"
  case performing = "Performing trick!"
}

public struct DuckSessionSnapshot: Equatable, Sendable {
  public var target: ConnectionTarget
  public var phase: ConnectionPhase
  public var controlOpen: Bool
  public var availableDucks: IdentifiedArrayOf<ProducerInfo>
  public var videoInfo: VideoInfoFrame
  public var hasVideoTrack: Bool
  public var linkStats: LinkStats
  public var latestState: RobotStateFrame?
  public var loopHistory: [LoopSample]
  public var health: RobotHealthResult?
  public var mode: String?
  public var policies: RobotPoliciesResult?
  public var installedSkills: IdentifiedArrayOf<SkillSummary>
  public var detections: DetectionFrame?
  public var tofFrame: TofFrame?
  public var mapStatus: MapStatusResult?
  public var mapGrid: MapGridResult?
  public var apiSkewWarning: String?
  public var logs: [RpcLogEntry]

  public init(
    target: ConnectionTarget = .localSimulator(url: DuckConstants.defaultLocalSignallingURL),
    phase: ConnectionPhase = .disconnected,
    controlOpen: Bool = false,
    availableDucks: IdentifiedArrayOf<ProducerInfo> = [],
    videoInfo: VideoInfoFrame = VideoInfoFrame(width: 640, height: 360, rotate: 90),
    hasVideoTrack: Bool = false,
    linkStats: LinkStats = LinkStats(),
    latestState: RobotStateFrame? = nil,
    loopHistory: [LoopSample] = [],
    health: RobotHealthResult? = nil,
    mode: String? = nil,
    policies: RobotPoliciesResult? = nil,
    installedSkills: IdentifiedArrayOf<SkillSummary> = [],
    detections: DetectionFrame? = nil,
    tofFrame: TofFrame? = nil,
    mapStatus: MapStatusResult? = nil,
    mapGrid: MapGridResult? = nil,
    apiSkewWarning: String? = nil,
    logs: [RpcLogEntry] = []
  ) {
    self.target = target
    self.phase = phase
    self.controlOpen = controlOpen
    self.availableDucks = availableDucks
    self.videoInfo = videoInfo
    self.hasVideoTrack = hasVideoTrack
    self.linkStats = linkStats
    self.latestState = latestState
    self.loopHistory = loopHistory
    self.health = health
    self.mode = mode
    self.policies = policies
    self.installedSkills = installedSkills
    self.detections = detections
    self.tofFrame = tofFrame
    self.mapStatus = mapStatus
    self.mapGrid = mapGrid
    self.apiSkewWarning = apiSkewWarning
    self.logs = logs
  }

  public var skillNames: [String] {
    if !installedSkills.isEmpty {
      return installedSkills.map(\.name)
    }
    if let names = policies?.skills, !names.isEmpty {
      return names
    }
    return DuckConstants.builtInSkills
  }

  public static var previewConnected: DuckSessionSnapshot {
    let now = Date(timeIntervalSince1970: 1_795_150_000)
    let samples = (0..<30).map { index in
      LoopSample(
        id: index,
        timestamp: now.addingTimeInterval(Double(index - 30)),
        hz: 49.8 + Double(index % 4) * 0.1
      )
    }
    let tofDistances = (0..<64).map { idx in
      let row = idx / 8
      let col = idx % 8
      return 350 + (row * 140) + abs(col - 3) * 90
    }
    return DuckSessionSnapshot(
      target: .localSimulator(url: DuckConstants.defaultLocalSignallingURL),
      phase: .connected(
        DuckIdentity(
          peerID: "sim-duck-a",
          name: "duck-eb55",
          serial: "sim-duck-a",
          release: "0.23.0",
          apiVersion: DuckConstants.apiVersion,
          isSimulated: true
        )
      ),
      controlOpen: true,
      availableDucks: [
        ProducerInfo(
          id: "sim-duck-a",
          meta: ProducerMeta(
            name: "duck-eb55",
            kind: "microduck",
            release: "0.23.0",
            apiVersion: DuckConstants.apiVersion,
            simulated: true
          )
        )
      ],
      videoInfo: VideoInfoFrame(width: 640, height: 360, rotate: 90),
      hasVideoTrack: true,
      linkStats: LinkStats(fps: 30, bitrateKbps: 5840, packetLossPercent: 0.0, rttMs: 1),
      latestState: RobotStateFrame(
        t: 48.2,
        movement: MoveTelemetry(
          requested: [0.0, 0.0, 0.0],
          applied: [0.0, 0.0, 0.0],
          limitedBy: ["deadman"]
        ),
        head: [0.0, 0.05, 0.0, 0.0],
        policy: "walk",
        safety: SafetyTelemetry(fallen: false, pickedUp: false, limp: false),
        controlLoop: LoopTelemetry(hz: 50.0, missed: 0),
        joints: [0.01, -0.04, 0.52, -1.04, 0.51, 0.12, -0.08, 0.02, 0.0, 0.0, -0.01, 0.04, -0.52, 1.04, -0.51],
        targets: [0.0, -0.05, 0.50, -1.02, 0.50, 0.12, -0.08, 0.0, 0.0, 0.0, 0.0, 0.05, -0.50, 1.02, -0.50]
      ),
      loopHistory: samples,
      health: RobotHealthResult(
        healthy: true,
        degraded: false,
        battery: BatteryHealth(volts: 7.42, percent: 54),
        motors: MotorsHealth(maxC: 32, hottest: "left_hip_yaw")
      ),
      mode: "walk",
      policies: RobotPoliciesResult(
        enabled: true,
        sitting: false,
        homed: true,
        skills: ["roulade", "kick_left", "kick_right", "polite-bow"]
      ),
      installedSkills: [
        SkillSummary(name: "roulade", duration: 1.8, overridden: false),
        SkillSummary(name: "kick_left", duration: 1.4, overridden: false),
        SkillSummary(name: "kick_right", duration: 1.4, overridden: false),
        SkillSummary(name: "polite-bow", duration: 4.0, overridden: true),
      ],
      tofFrame: TofFrame(seq: 120, rows: 8, cols: 8, distanceMm: tofDistances),
      mapStatus: MapStatusResult(loops: 2, relocalizations: 0, islandKeyframes: 0, path: "/var/lib/robot/map.bin"),
      mapGrid: MapGridResult(
        resM: 0.1,
        origin: [-1.2, -1.2],
        width: 16,
        height: 16,
        cells: String(repeating: "################", count: 1)
          + String(repeating: "#..............#", count: 14)
          + String(repeating: "################", count: 1),
        keyframes: [MapPose(x: -0.4, y: -0.3, yaw: 0), MapPose(x: 0.1, y: 0.2, yaw: 0.6)],
        pose: MapPose(x: 0.15, y: 0.2, yaw: 0.65)
      )
    )
  }
}

public struct DuckSessionClient: Sendable {
  public var currentSnapshot: @Sendable () async -> DuckSessionSnapshot
  public var snapshots: @Sendable () -> AsyncStream<DuckSessionSnapshot>
  public var connect: @Sendable (ConnectionTarget) async -> Void
  public var disconnect: @Sendable () async -> Void
  public var selectDuck: @Sendable (String) async -> Void
  public var sendMove: @Sendable (RobotMoveParams) async -> Void
  public var sendLook: @Sendable (RobotLookParams) async -> RobotLookResult?
  public var setEnabled: @Sendable (Bool) async throws -> Void
  public var toggleEnable: @Sendable () async throws -> Void
  public var standBackUp: @Sendable () async throws -> Void
  public var stop: @Sendable () async throws -> Void
  public var initPose: @Sendable () async throws -> Void
  public var relax: @Sendable () async throws -> Void
  public var rebootMotors: @Sendable () async throws -> Void
  public var performSkill: @Sendable (String) async throws -> Void
  public var playSound: @Sendable (SoundTag, Bool?) async -> Void
  public var setAutonomous: @Sendable (Bool) async throws -> Void
  public var setFlashlight: @Sendable (Bool) async throws -> Void
  public var setFlashlightColor: @Sendable (Bool, String) async throws -> Void
  public var setLaserTrack: @Sendable (Bool) async throws -> Void
  public var setSoccer: @Sendable (Bool) async throws -> Void
  public var subscribeTof: @Sendable () async -> Void
  public var refreshMap: @Sendable (Double) async -> Void
  public var wipeMap: @Sendable () async throws -> Void
  public var refreshSkills: @Sendable () async -> Void
  public var installPolicy: @Sendable (
    HubPolicy,
    Double,
    @Sendable (TrickInstallStage) -> Void
  ) async throws -> String
  public var removeSkill: @Sendable (String) async throws -> Void
  public var ensureConnected: @Sendable (Duration) async throws -> DuckIdentity
  public var setForegroundActive: @Sendable (Bool) async -> Void
  public var performMoveStep: @Sendable (DuckMoveStepRequest) async throws -> DuckMoveStepResult
  public var capturePhoto: @Sendable () async throws -> DuckCapturedFrame

  public init(
    currentSnapshot: @escaping @Sendable () async -> DuckSessionSnapshot,
    snapshots: @escaping @Sendable () -> AsyncStream<DuckSessionSnapshot>,
    connect: @escaping @Sendable (ConnectionTarget) async -> Void,
    disconnect: @escaping @Sendable () async -> Void,
    selectDuck: @escaping @Sendable (String) async -> Void,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void,
    sendLook: @escaping @Sendable (RobotLookParams) async -> RobotLookResult?,
    setEnabled: @escaping @Sendable (Bool) async throws -> Void = { _ in },
    toggleEnable: @escaping @Sendable () async throws -> Void,
    standBackUp: @escaping @Sendable () async throws -> Void = {},
    stop: @escaping @Sendable () async throws -> Void,
    initPose: @escaping @Sendable () async throws -> Void,
    relax: @escaping @Sendable () async throws -> Void,
    rebootMotors: @escaping @Sendable () async throws -> Void,
    performSkill: @escaping @Sendable (String) async throws -> Void,
    playSound: @escaping @Sendable (SoundTag, Bool?) async -> Void,
    setAutonomous: @escaping @Sendable (Bool) async throws -> Void,
    setFlashlight: @escaping @Sendable (Bool) async throws -> Void,
    setFlashlightColor: @escaping @Sendable (Bool, String) async throws -> Void = { _, _ in },
    setLaserTrack: @escaping @Sendable (Bool) async throws -> Void,
    setSoccer: @escaping @Sendable (Bool) async throws -> Void,
    subscribeTof: @escaping @Sendable () async -> Void,
    refreshMap: @escaping @Sendable (Double) async -> Void,
    wipeMap: @escaping @Sendable () async throws -> Void,
    refreshSkills: @escaping @Sendable () async -> Void,
    installPolicy: @escaping @Sendable (
      HubPolicy,
      Double,
      @Sendable (TrickInstallStage) -> Void
    ) async throws -> String,
    removeSkill: @escaping @Sendable (String) async throws -> Void,
    ensureConnected: @escaping @Sendable (Duration) async throws -> DuckIdentity = { _ in
      DuckIdentity(peerID: "sim-duck-a", name: "duck-eb55", isSimulated: true)
    },
    setForegroundActive: @escaping @Sendable (Bool) async -> Void = { _ in },
    performMoveStep: @escaping @Sendable (DuckMoveStepRequest) async throws -> DuckMoveStepResult = { req in
      DuckMoveStepResult(
        appliedTwist: req.clampedTwist,
        elapsedSeconds: req.clampedDurationSeconds,
        pulsesSent: max(1, Int((req.clampedDurationSeconds * Double(DuckConstants.intentHz)).rounded())),
        stopReason: .completed
      )
    },
    capturePhoto: @escaping @Sendable () async throws -> DuckCapturedFrame = {
      DuckCapturedFrame(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 360, height: 640, capturedAt: Date(timeIntervalSince1970: 1_795_150_000))
    }
  ) {
    self.currentSnapshot = currentSnapshot
    self.snapshots = snapshots
    self.connect = connect
    self.disconnect = disconnect
    self.selectDuck = selectDuck
    self.sendMove = sendMove
    self.sendLook = sendLook
    self.setEnabled = setEnabled
    self.toggleEnable = toggleEnable
    self.standBackUp = standBackUp
    self.stop = stop
    self.initPose = initPose
    self.relax = relax
    self.rebootMotors = rebootMotors
    self.performSkill = performSkill
    self.playSound = playSound
    self.setAutonomous = setAutonomous
    self.setFlashlight = setFlashlight
    self.setFlashlightColor = setFlashlightColor
    self.setLaserTrack = setLaserTrack
    self.setSoccer = setSoccer
    self.subscribeTof = subscribeTof
    self.refreshMap = refreshMap
    self.wipeMap = wipeMap
    self.refreshSkills = refreshSkills
    self.installPolicy = installPolicy
    self.removeSkill = removeSkill
    self.ensureConnected = ensureConnected
    self.setForegroundActive = setForegroundActive
    self.performMoveStep = performMoveStep
    self.capturePhoto = capturePhoto
  }
}

extension DuckSessionClient: TestDependencyKey {
  public static var previewValue: DuckSessionClient {
    let snapshot = DuckSessionSnapshot.previewConnected
    return DuckSessionClient(
      currentSnapshot: { snapshot },
      snapshots: {
        AsyncStream { continuation in
          continuation.yield(snapshot)
        }
      },
      connect: { _ in },
      disconnect: {},
      selectDuck: { _ in },
      sendMove: { _ in },
      sendLook: { _ in RobotLookResult(accepted: true, clamped: false) },
      toggleEnable: {},
      standBackUp: {},
      stop: {},
      initPose: {},
      relax: {},
      rebootMotors: {},
      performSkill: { _ in },
      playSound: { _, _ in },
      setAutonomous: { _ in },
      setFlashlight: { _ in },
      setLaserTrack: { _ in },
      setSoccer: { _ in },
      subscribeTof: {},
      refreshMap: { _ in },
      wipeMap: {},
      refreshSkills: {},
      installPolicy: { policy, _, onStage in
        onStage(.downloading)
        onStage(.installing)
        return policy.name.lowercased().replacingOccurrences(of: " ", with: "-")
      },
      removeSkill: { _ in }
    )
  }

  public static var testValue: DuckSessionClient {
    previewValue
  }
}

public struct HubCatalogResult: Equatable, Sendable {
  public var policies: IdentifiedArrayOf<HubPolicy>
  public var warningMessage: String?

  public init(policies: IdentifiedArrayOf<HubPolicy> = [], warningMessage: String? = nil) {
    self.policies = policies
    self.warningMessage = warningMessage
  }
}

public struct HubCatalogClient: Sendable {
  public var fetchCatalog: @Sendable (HuggingFaceSession?) async -> HubCatalogResult

  public init(fetchCatalog: @escaping @Sendable (HuggingFaceSession?) async -> HubCatalogResult) {
    self.fetchCatalog = fetchCatalog
  }
}

extension HubCatalogClient: TestDependencyKey {
  public static var previewValue: HubCatalogClient {
    HubCatalogClient { session in
      var items: IdentifiedArrayOf<HubPolicy> = []
      if let session {
        items.append(
          HubPolicy(
            key: "\(session.username)/microduck-custom-wave",
            repo: "\(session.username)/microduck-custom-wave",
            name: "Custom Wave",
            description: "Personal trick published under @\(session.username).",
            kind: "episodic",
            durationS: 3.0,
            official: false,
            likes: 1
          )
        )
      }
      items.append(contentsOf: [
        HubPolicy(
          key: "pollen-robotics/microduck-policies:roulade.onnx",
          repo: "pollen-robotics/microduck-policies",
          file: "roulade.onnx",
          name: "Roulade",
          description: "Forward roll over the head and land back on both feet.",
          kind: "episodic",
          durationS: 1.8,
          official: true,
          likes: 24
        ),
        HubPolicy(
          key: "neil-jo/microduck-polite-bow",
          repo: "neil-jo/microduck-polite-bow",
          name: "Polite Bow",
          description: "Bows from a two-foot stand and comes back up cleanly.",
          kind: "episodic",
          durationS: 4.0,
          official: false,
          likes: 14
        ),
        HubPolicy(
          key: "joanfox/microduck-happy-hop",
          repo: "joanfox/microduck-happy-hop",
          name: "Happy Hop",
          description: "Short vertical two-foot hop and soft knee-absorbed landing.",
          kind: "episodic",
          durationS: 3.0,
          official: false,
          likes: 19
        ),
      ])
      return HubCatalogResult(policies: items)
    }
  }

  public static var testValue: HubCatalogClient {
    previewValue
  }
}

public struct HuggingFaceDeviceCode: Codable, Equatable, Sendable {
  public var deviceCode: String
  public var userCode: String
  public var verificationURI: String
  public var expiresIn: Int
  public var interval: Int

  public init(
    deviceCode: String,
    userCode: String,
    verificationURI: String = "https://hf.co/oauth/device",
    expiresIn: Int = 300,
    interval: Int = 5
  ) {
    self.deviceCode = deviceCode
    self.userCode = userCode
    self.verificationURI = verificationURI
    self.expiresIn = expiresIn
    self.interval = interval
  }
}

public struct HuggingFaceSession: Codable, Equatable, Sendable {
  public var token: String
  public var username: String
  public var expiresAt: Date?

  public init(token: String, username: String, expiresAt: Date? = nil) {
    self.token = token
    self.username = username
    self.expiresAt = expiresAt
  }

  public func isValid(at now: Date) -> Bool {
    guard !token.isEmpty else { return false }
    if let expiresAt {
      return expiresAt > now
    }
    return true
  }
}

public extension Notification.Name {
  static let microduckHuggingFaceSessionChanged = Notification.Name("microduck.hf.sessionChanged")
}

public struct HuggingFaceAuthClient: Sendable {
  public var loadSession: @Sendable () -> HuggingFaceSession?
  public var saveSession: @Sendable (HuggingFaceSession) -> Void
  public var clearSession: @Sendable () -> Void
  public var resolveUsername: @Sendable (String) async throws -> String
  public var startDeviceLogin: @Sendable () async throws -> HuggingFaceDeviceCode
  public var awaitDeviceLogin: @Sendable (HuggingFaceDeviceCode) async throws -> HuggingFaceSession
  public var signInWithPKCE: @Sendable (String) async throws -> HuggingFaceSession

  public init(
    loadSession: @escaping @Sendable () -> HuggingFaceSession?,
    saveSession: @escaping @Sendable (HuggingFaceSession) -> Void,
    clearSession: @escaping @Sendable () -> Void,
    resolveUsername: @escaping @Sendable (String) async throws -> String,
    startDeviceLogin: @escaping @Sendable () async throws -> HuggingFaceDeviceCode,
    awaitDeviceLogin: @escaping @Sendable (HuggingFaceDeviceCode) async throws -> HuggingFaceSession,
    signInWithPKCE: @escaping @Sendable (String) async throws -> HuggingFaceSession
  ) {
    self.loadSession = loadSession
    self.saveSession = saveSession
    self.clearSession = clearSession
    self.resolveUsername = resolveUsername
    self.startDeviceLogin = startDeviceLogin
    self.awaitDeviceLogin = awaitDeviceLogin
    self.signInWithPKCE = signInWithPKCE
  }
}

extension HuggingFaceAuthClient: TestDependencyKey {
  public static var previewValue: HuggingFaceAuthClient {
    HuggingFaceAuthClient(
      loadSession: { nil },
      saveSession: { _ in },
      clearSession: {},
      resolveUsername: { _ in "ajevans99" },
      startDeviceLogin: {
        HuggingFaceDeviceCode(deviceCode: "dev-123", userCode: "DUCK-4242")
      },
      awaitDeviceLogin: { _ in
        HuggingFaceSession(token: "hf_oauth_preview", username: "ajevans99")
      },
      signInWithPKCE: { _ in HuggingFaceSession(token: "hf_preview", username: "ajevans99") }
    )
  }

  public static var testValue: HuggingFaceAuthClient {
    previewValue
  }
}

public struct HapticsClient: Sendable {
  public var impactLight: @Sendable @MainActor () -> Void
  public var impactMedium: @Sendable @MainActor () -> Void
  public var selectionChanged: @Sendable @MainActor () -> Void
  public var success: @Sendable @MainActor () -> Void
  public var warning: @Sendable @MainActor () -> Void

  public init(
    impactLight: @escaping @Sendable @MainActor () -> Void,
    impactMedium: @escaping @Sendable @MainActor () -> Void,
    selectionChanged: @escaping @Sendable @MainActor () -> Void,
    success: @escaping @Sendable @MainActor () -> Void,
    warning: @escaping @Sendable @MainActor () -> Void
  ) {
    self.impactLight = impactLight
    self.impactMedium = impactMedium
    self.selectionChanged = selectionChanged
    self.success = success
    self.warning = warning
  }
}

extension HapticsClient: TestDependencyKey {
  public static var previewValue: HapticsClient {
    HapticsClient(
      impactLight: {},
      impactMedium: {},
      selectionChanged: {},
      success: {},
      warning: {}
    )
  }

  public static var testValue: HapticsClient {
    previewValue
  }
}

public struct GamepadInputState: Equatable, Sendable {
  public var controllerName: String?
  public var leftX: Double
  public var leftY: Double
  public var rightX: Double
  public var buttonAPressed: Bool
  public var buttonBPressed: Bool

  public init(
    controllerName: String? = nil,
    leftX: Double = 0,
    leftY: Double = 0,
    rightX: Double = 0,
    buttonAPressed: Bool = false,
    buttonBPressed: Bool = false
  ) {
    self.controllerName = controllerName
    self.leftX = leftX
    self.leftY = leftY
    self.rightX = rightX
    self.buttonAPressed = buttonAPressed
    self.buttonBPressed = buttonBPressed
  }

  public var isConnected: Bool { controllerName != nil }
}

public struct GamepadClient: Sendable {
  public var states: @Sendable () -> AsyncStream<GamepadInputState>

  public init(states: @escaping @Sendable () -> AsyncStream<GamepadInputState>) {
    self.states = states
  }
}

extension GamepadClient: TestDependencyKey {
  public static var previewValue: GamepadClient {
    GamepadClient {
      AsyncStream { continuation in
        continuation.yield(GamepadInputState())
        continuation.finish()
      }
    }
  }

  public static var testValue: GamepadClient {
    previewValue
  }
}

extension DependencyValues {
  public var duckSession: DuckSessionClient {
    get { self[DuckSessionClient.self] }
    set { self[DuckSessionClient.self] = newValue }
  }

  public var hubCatalog: HubCatalogClient {
    get { self[HubCatalogClient.self] }
    set { self[HubCatalogClient.self] = newValue }
  }

  public var huggingFaceAuth: HuggingFaceAuthClient {
    get { self[HuggingFaceAuthClient.self] }
    set { self[HuggingFaceAuthClient.self] = newValue }
  }

  public var haptics: HapticsClient {
    get { self[HapticsClient.self] }
    set { self[HapticsClient.self] = newValue }
  }

  public var gamepad: GamepadClient {
    get { self[GamepadClient.self] }
    set { self[GamepadClient.self] = newValue }
  }
}

private struct DuckVideoRendererKey: EnvironmentKey {
  static let defaultValue: @Sendable @MainActor (VideoInfoFrame) -> AnyView = { info in
    AnyView(PreviewDuckCameraBackdrop(videoInfo: info))
  }
}

extension EnvironmentValues {
  public var duckVideoRenderer: @Sendable @MainActor (VideoInfoFrame) -> AnyView {
    get { self[DuckVideoRendererKey.self] }
    set { self[DuckVideoRendererKey.self] = newValue }
  }
}

public struct PreviewDuckCameraBackdrop: View {
  public let videoInfo: VideoInfoFrame

  public init(videoInfo: VideoInfoFrame) {
    self.videoInfo = videoInfo
  }

  public var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.08, green: 0.11, blue: 0.16),
          Color(red: 0.14, green: 0.20, blue: 0.28),
          Color(red: 0.09, green: 0.12, blue: 0.15),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      VStack(spacing: 10) {
        Image(systemName: "video.fill")
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(.white.opacity(0.65))
        Text("MuJoCo Head Camera · \(videoInfo.width)×\(videoInfo.height)")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.white.opacity(0.75))
      }
    }
  }
}
