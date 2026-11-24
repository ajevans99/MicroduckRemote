import DuckProtocol
import Foundation

/// Optional sidecar metadata written alongside `scene_<slug>.xml` by the iOS LiDAR scanner
/// (`RoomScanFeature`) inside the shared iCloud Drive `Documents/Scenes/` folder.
public struct SyncedSceneMetadata: Codable, Equatable, Sendable {
  public var slug: String
  public var displayName: String
  public var roomCount: Int?
  public var obstacleCount: Int?
  public var exportedAt: Date?

  public init(
    slug: String,
    displayName: String,
    roomCount: Int? = nil,
    obstacleCount: Int? = nil,
    exportedAt: Date? = nil
  ) {
    self.slug = slug
    self.displayName = displayName
    self.roomCount = roomCount
    self.obstacleCount = obstacleCount
    self.exportedAt = exportedAt
  }
}

public enum SimulatorSceneSource: String, Codable, Equatable, Sendable {
  case builtIn
  case iCloud
}

public struct SimulatorScene: Identifiable, Equatable, Sendable {
  public var id: String
  public var slug: String
  public var displayName: String
  public var fileURL: URL
  public var source: SimulatorSceneSource
  public var supportsBacklashWalking: Bool
  public var isDownloaded: Bool
  public var roomCount: Int?
  public var obstacleCount: Int?
  public var modifiedAt: Date?
  public var fileSizeBytes: Int?

  public init(
    slug: String,
    displayName: String? = nil,
    fileURL: URL,
    source: SimulatorSceneSource,
    supportsBacklashWalking: Bool = true,
    isDownloaded: Bool = true,
    roomCount: Int? = nil,
    obstacleCount: Int? = nil,
    modifiedAt: Date? = nil,
    fileSizeBytes: Int? = nil
  ) {
    self.id = "\(source.rawValue):\(slug)"
    self.slug = slug
    self.displayName = displayName ?? Self.prettyName(forSlug: slug)
    self.fileURL = fileURL
    self.source = source
    self.supportsBacklashWalking = supportsBacklashWalking
    self.isDownloaded = isDownloaded
    self.roomCount = roomCount
    self.obstacleCount = obstacleCount
    self.modifiedAt = modifiedAt
    self.fileSizeBytes = fileSizeBytes
  }

  /// Extracts `<slug>` from `scene_<slug>.xml` or `.scene_<slug>.xml.icloud`.
  public static func slug(fromFilename filename: String) -> String? {
    var normalized = filename
    if normalized.hasPrefix("."), normalized.hasSuffix(".icloud") {
      normalized.removeFirst()
      normalized.removeLast(".icloud".count)
    }
    guard normalized.hasPrefix("scene_"), normalized.hasSuffix(".xml") else {
      return nil
    }
    let start = normalized.index(normalized.startIndex, offsetBy: "scene_".count)
    let end = normalized.index(normalized.endIndex, offsetBy: -".xml".count)
    let slug = String(normalized[start..<end])
    return slug.isEmpty ? nil : slug
  }

  /// Normalizes any arbitrary filename or label into a safe `scene_<slug>.xml` slug.
  public static func normalizedSlug(from raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.hasSuffix(".xml") {
      trimmed.removeLast(".xml".count)
    }
    if trimmed.hasPrefix("scene_") {
      trimmed.removeFirst("scene_".count)
    }
    var result = ""
    var lastWasUnderscore = false
    for scalar in trimmed.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        result.unicodeScalars.append(scalar)
        lastWasUnderscore = false
      } else if !lastWasUnderscore && !result.isEmpty {
        result.append("_")
        lastWasUnderscore = true
      }
    }
    while result.hasSuffix("_") {
      result.removeLast()
    }
    return result.isEmpty ? "custom_room" : result
  }

  public static func prettyName(forSlug slug: String) -> String {
    switch slug {
    case "backlash":
      return "Empty Floor (Backlash)"
    case "playground":
      return "Playground (Props & Ball)"
    case "walk_backlash":
      return "Walk Floor (Backlash)"
    case "vslam":
      return "VSLAM Room"
    default:
      return slug
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
    }
  }
}

public enum SimulatorCameraMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case duckA = "a"
  case all = "all"
  case none = ""

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .duckA: "Duck A (360p30 WebRTC)"
    case .all: "All Ducks"
    case .none: "Disabled (No Video)"
    }
  }
}

public enum SimulatorKeyframe: String, CaseIterable, Identifiable, Codable, Sendable {
  case sit = "SIT"
  case stand = "STAND"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .sit: "Sit (Recommended)"
    case .stand: "Stand"
    }
  }
}

public struct SimulatorConfiguration: Codable, Equatable, Sendable {
  public var microduckRepoPath: String
  public var microduckRLRepoPath: String
  public var stateDirPath: String
  public var customSyncedScenesPath: String?
  public var selectedSceneSlug: String
  public var cameraMode: SimulatorCameraMode
  public var duckCount: Int
  public var showMuJoCoViewer: Bool
  public var keyframe: SimulatorKeyframe
  public var autoConnectCockpit: Bool

  public init(
    microduckRepoPath: String = SimulatorConfiguration.defaultMicroduckRepoPath(),
    microduckRLRepoPath: String = SimulatorConfiguration.defaultMicroduckRLRepoPath(),
    stateDirPath: String = SimulatorConfiguration.defaultStateDirPath(),
    customSyncedScenesPath: String? = nil,
    selectedSceneSlug: String = "playground",
    cameraMode: SimulatorCameraMode = .duckA,
    duckCount: Int = 1,
    showMuJoCoViewer: Bool = true,
    keyframe: SimulatorKeyframe = .sit,
    autoConnectCockpit: Bool = true
  ) {
    self.microduckRepoPath = microduckRepoPath
    self.microduckRLRepoPath = microduckRLRepoPath
    self.stateDirPath = stateDirPath
    self.customSyncedScenesPath = customSyncedScenesPath
    self.selectedSceneSlug = selectedSceneSlug
    self.cameraMode = cameraMode
    self.duckCount = min(max(duckCount, 1), 4)
    self.showMuJoCoViewer = showMuJoCoViewer
    self.keyframe = keyframe
    self.autoConnectCockpit = autoConnectCockpit
  }

  public static func defaultMicroduckRepoPath() -> String {
    let home = NSHomeDirectory()
    let candidates = [
      "\(home)/.copilot/repos/microduck",
      "\(home)/Pollen/microduck",
      "\(home)/Code/microduck",
      "\(home)/Developer/microduck",
    ]
    for path in candidates where FileManager.default.isExecutableFile(atPath: "\(path)/scripts/duck-sim") {
      return path
    }
    return candidates[0]
  }

  public static func defaultMicroduckRLRepoPath() -> String {
    let home = NSHomeDirectory()
    let candidates = [
      "\(home)/Pollen/microduck_rl",
      "\(home)/.copilot/repos/microduck_rl",
    ]
    for path in candidates where FileManager.default.fileExists(atPath: path) {
      return path
    }
    return candidates[0]
  }

  public static func defaultStateDirPath() -> String {
    "\(NSHomeDirectory())/.cache/duck-sim"
  }

  public var duckSimScriptURL: URL {
    URL(fileURLWithPath: microduckRepoPath)
      .appendingPathComponent("scripts/duck-sim")
  }

  public var robotScenesDirectoryURL: URL {
    URL(fileURLWithPath: microduckRLRepoPath)
      .appendingPathComponent("src/mjlab_microduck/robot/microduck", isDirectory: true)
  }

  public var stateDirectoryURL: URL {
    URL(fileURLWithPath: stateDirPath, isDirectory: true)
  }

  public func launchEnvironment(sceneOverride: String? = nil) -> [String: String] {
    let scene = sceneOverride ?? selectedSceneSlug
    var env: [String: String] = [
      "DUCK_SIM_RL": microduckRLRepoPath,
      "DUCK_SIM_STATE": stateDirPath,
      "DUCK_SIM_SCENE": scene,
      "DUCK_SIM_DUCKS": "\(min(max(duckCount, 1), 4))",
      "DUCK_SIM_VIEWER": showMuJoCoViewer ? "1" : "0",
      "DUCK_SIM_KEYFRAME": keyframe.rawValue,
    ]
    if !cameraMode.rawValue.isEmpty {
      env["DUCK_SIM_CAMERAS"] = cameraMode.rawValue
    } else {
      env["DUCK_SIM_CAMERAS"] = ""
    }
    return env
  }

  public var shellPreviewCommand: String {
    var parts: [String] = []
    if !selectedSceneSlug.isEmpty {
      parts.append("DUCK_SIM_SCENE=\(selectedSceneSlug)")
    }
    if !cameraMode.rawValue.isEmpty {
      parts.append("DUCK_SIM_CAMERAS=\(cameraMode.rawValue)")
    }
    if duckCount > 1 {
      parts.append("DUCK_SIM_DUCKS=\(duckCount)")
    }
    if !showMuJoCoViewer {
      parts.append("DUCK_SIM_VIEWER=0")
    }
    if keyframe != .sit {
      parts.append("DUCK_SIM_KEYFRAME=\(keyframe.rawValue)")
    }
    parts.append("./scripts/duck-sim")
    return parts.joined(separator: " ")
  }
}

public struct SimulatorDaemonStatus: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var pid: Int32?
  public var isRunning: Bool
  public var logFileName: String?

  public init(
    id: String,
    name: String,
    pid: Int32? = nil,
    isRunning: Bool = false,
    logFileName: String? = nil
  ) {
    self.id = id
    self.name = name
    self.pid = pid
    self.isRunning = isRunning
    self.logFileName = logFileName
  }
}

public struct SimulatorRuntimeStatus: Equatable, Sendable {
  public var isBodyPortOpen: Bool
  public var isMediaPortOpen: Bool
  public var isWebConsolePortOpen: Bool
  public var daemons: [SimulatorDaemonStatus]
  public var activeSceneSlug: String?

  public init(
    isBodyPortOpen: Bool = false,
    isMediaPortOpen: Bool = false,
    isWebConsolePortOpen: Bool = false,
    daemons: [SimulatorDaemonStatus] = [],
    activeSceneSlug: String? = nil
  ) {
    self.isBodyPortOpen = isBodyPortOpen
    self.isMediaPortOpen = isMediaPortOpen
    self.isWebConsolePortOpen = isWebConsolePortOpen
    self.daemons = daemons
    self.activeSceneSlug = activeSceneSlug
  }

  public var isRunning: Bool {
    isBodyPortOpen || daemons.contains(where: \.isRunning)
  }

  public var isWebRTCReady: Bool {
    isMediaPortOpen
  }
}

public enum SimulatorLifecyclePhase: Equatable, Sendable {
  case stopped
  case starting
  case running
  case stopping
  case failed(String)

  public var isBusy: Bool {
    self == .starting || self == .stopping
  }

  public var label: String {
    switch self {
    case .stopped: "Stopped"
    case .starting: "Starting Simulator…"
    case .running: "Running"
    case .stopping: "Stopping Simulator…"
    case .failed: "Launch Error"
    }
  }
}

public struct SimulatorLogEntry: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var timestamp: Date
  public var isError: Bool
  public var text: String

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    isError: Bool = false,
    text: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.isError = isError
    self.text = text
  }
}

public enum SimulatorLogSource: String, CaseIterable, Identifiable, Sendable {
  case liveOutput = "Launcher"
  case body = "MuJoCo Body"
  case robotd = "robotd"
  case mediad = "mediad"

  public var id: String { rawValue }

  public var fileName: String? {
    switch self {
    case .liveOutput: nil
    case .body: "body.log"
    case .robotd: "duck-a.log"
    case .mediad: "duck-a-media.log"
    }
  }
}

public struct SyncedScenesSnapshot: Equatable, Sendable {
  public var scenes: [SimulatorScene]
  public var iCloudAvailable: Bool
  public var directoryURL: URL?
  public var statusDetail: String

  public init(
    scenes: [SimulatorScene] = [],
    iCloudAvailable: Bool = false,
    directoryURL: URL? = nil,
    statusDetail: String = ""
  ) {
    self.scenes = scenes
    self.iCloudAvailable = iCloudAvailable
    self.directoryURL = directoryURL
    self.statusDetail = statusDetail
  }
}

public enum SimulatorError: LocalizedError, Equatable, Sendable {
  case unsupportedPlatform
  case missingScript(String)
  case missingRLRepository(String)
  case sceneNotDownloaded(String)
  case commandFailed(Int32, String)
  case importFailed(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      "The local MuJoCo simulator can only be launched on macOS."
    case let .missingScript(path):
      "Could not find executable duck-sim launcher at \(path). Check the microduck repository path."
    case let .missingRLRepository(path):
      "Could not find microduck_rl repository at \(path). Check the microduck_rl repository path."
    case let .sceneNotDownloaded(name):
      "“\(name)” is still downloading from iCloud Drive. Try again in a moment."
    case let .commandFailed(code, detail):
      detail.isEmpty ? "duck-sim exited with status \(code)." : detail
    case let .importFailed(reason):
      reason
    }
  }
}
