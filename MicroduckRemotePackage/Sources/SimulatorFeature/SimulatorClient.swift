import Dependencies
import DuckProtocol
import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(Darwin)
import Darwin
#endif

public enum SimulatorSceneScanner {
  public static func detectBacklashSupport(xml: String) -> Bool {
    xml.contains("robot_groundcontact_backlash.xml")
      || xml.contains("robot_walk_backlash.xml")
      || xml.contains("robot_allcollisions_backlash.xml")
  }

  public static func parseActiveSceneSlug(fromBodyCommandLine commandLine: String) -> String? {
    let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let flagIdx = tokens.firstIndex(of: "--scene"), flagIdx + 1 < tokens.count else {
      return nil
    }
    let path = tokens[flagIdx + 1]
    let filename = URL(fileURLWithPath: path).lastPathComponent
    return SimulatorScene.slug(fromFilename: filename) ?? filename
  }

  /// Scans a directory for `scene_<slug>.xml` (and optional `.icloud` placeholders + `scene_<slug>.json` sidecars).
  public static func scanDirectory(
    _ directoryURL: URL,
    source: SimulatorSceneSource,
    startDownloadIfNeeded: Bool = false
  ) -> [SimulatorScene] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [
        .contentModificationDateKey,
        .fileSizeKey,
        .isRegularFileKey,
      ],
      options: []
    ) else {
      return []
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var bySlug: [String: SimulatorScene] = [:]

    for url in entries {
      let filename = url.lastPathComponent
      let isCloudPlaceholder = filename.hasPrefix(".") && filename.hasSuffix(".icloud")
      guard let slug = SimulatorScene.slug(fromFilename: filename) else {
        continue
      }

      if isCloudPlaceholder, startDownloadIfNeeded {
        try? fm.startDownloadingUbiquitousItem(at: url)
      }

      let realXMLURL = directoryURL.appendingPathComponent("scene_\(slug).xml")
      let sidecarURL = directoryURL.appendingPathComponent("scene_\(slug).json")

      var metadata: SyncedSceneMetadata?
      if let sidecarData = try? Data(contentsOf: sidecarURL) {
        metadata = try? decoder.decode(SyncedSceneMetadata.self, from: sidecarData)
      }

      let isDownloaded = !isCloudPlaceholder && fm.fileExists(atPath: realXMLURL.path)
      var supportsBacklash = true
      var modifiedAt: Date?
      var fileSizeBytes: Int?

      if isDownloaded {
        let resourceValues = try? realXMLURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modifiedAt = metadata?.exportedAt ?? resourceValues?.contentModificationDate
        fileSizeBytes = resourceValues?.fileSize
        if let headData = try? Data(contentsOf: realXMLURL),
           let xmlText = String(data: headData.prefix(4096), encoding: .utf8)
        {
          supportsBacklash = detectBacklashSupport(xml: xmlText)
        }
      } else {
        modifiedAt = metadata?.exportedAt
      }

      let scene = SimulatorScene(
        slug: slug,
        displayName: metadata?.displayName,
        fileURL: isDownloaded ? realXMLURL : url,
        source: source,
        supportsBacklashWalking: supportsBacklash,
        isDownloaded: isDownloaded,
        roomCount: metadata?.roomCount,
        obstacleCount: metadata?.obstacleCount,
        modifiedAt: modifiedAt,
        fileSizeBytes: fileSizeBytes
      )

      if let existing = bySlug[slug] {
        // Prefer downloaded version over placeholder
        if !existing.isDownloaded && scene.isDownloaded {
          bySlug[slug] = scene
        }
      } else {
        bySlug[slug] = scene
      }
    }

    return bySlug.values.sorted { lhs, rhs in
      if source == .builtIn {
        let priority: (String) -> Int = { slug in
          switch slug {
          case "playground": 0
          case "backlash": 1
          case "walk_backlash": 2
          default: 3
          }
        }
        let lp = priority(lhs.slug)
        let rp = priority(rhs.slug)
        if lp != rp { return lp < rp }
        if lhs.supportsBacklashWalking != rhs.supportsBacklashWalking {
          return lhs.supportsBacklashWalking && !rhs.supportsBacklashWalking
        }
      } else if let lDate = lhs.modifiedAt, let rDate = rhs.modifiedAt, lDate != rDate {
        return lDate > rDate
      }
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
  }

  /// Copies an iCloud or external `scene_<slug>.xml` into the MuJoCo robot scene directory so
  /// relative `<include file="robot_groundcontact_backlash.xml"/>` references resolve cleanly.
  public static func stageScene(
    _ scene: SimulatorScene,
    intoRobotScenesDirectory robotScenesDir: URL
  ) throws -> String {
    guard scene.isDownloaded else {
      throw SimulatorError.sceneNotDownloaded(scene.displayName)
    }
    let fm = FileManager.default
    guard fm.fileExists(atPath: robotScenesDir.path) else {
      throw SimulatorError.missingRLRepository(robotScenesDir.path)
    }
    if scene.source == .builtIn {
      return scene.slug
    }

    let destination = robotScenesDir.appendingPathComponent("scene_\(scene.slug).xml")
    let sourceURL = scene.fileURL.standardizedFileURL
    let destURL = destination.standardizedFileURL
    if sourceURL != destURL {
      let data = try Data(contentsOf: sourceURL)
      try data.write(to: destURL, options: .atomic)
    }
    return scene.slug
  }

  /// Imports an arbitrary MJCF `.xml` file into the given scenes directory as `scene_<slug>.xml`.
  public static func importXML(
    from sourceURL: URL,
    intoScenesDirectory scenesDir: URL,
    sourceKind: SimulatorSceneSource = .iCloud
  ) throws -> SimulatorScene {
    let fm = FileManager.default
    try fm.createDirectory(at: scenesDir, withIntermediateDirectories: true)

    let rawStem = sourceURL.deletingPathExtension().lastPathComponent
    let slug = SimulatorScene.normalizedSlug(from: rawStem)
    let destURL = scenesDir.appendingPathComponent("scene_\(slug).xml")

    let data = try Data(contentsOf: sourceURL)
    guard let xmlText = String(data: data, encoding: .utf8), xmlText.contains("<mujoco") else {
      throw SimulatorError.importFailed("The selected file does not look like a valid MuJoCo MJCF XML scene.")
    }
    try data.write(to: destURL, options: .atomic)

    let metadata = SyncedSceneMetadata(
      slug: slug,
      displayName: SimulatorScene.prettyName(forSlug: slug),
      exportedAt: Date()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let metaData = try? encoder.encode(metadata) {
      let sidecarURL = scenesDir.appendingPathComponent("scene_\(slug).json")
      try? metaData.write(to: sidecarURL, options: .atomic)
    }

    return SimulatorScene(
      slug: slug,
      displayName: metadata.displayName,
      fileURL: destURL,
      source: sourceKind,
      supportsBacklashWalking: detectBacklashSupport(xml: xmlText),
      isDownloaded: true,
      modifiedAt: metadata.exportedAt,
      fileSizeBytes: data.count
    )
  }

  /// Strips ANSI escape sequences (such as `duck-sim`'s cyan `==` prefix) for clean native log output.
  public static func stripANSI(_ input: String) -> String {
    input.replacingOccurrences(
      of: #"\u{001B}\[[0-9;]*[A-Za-z]"#,
      with: "",
      options: .regularExpression
    )
  }
}

public struct SimulatorClient: Sendable {
  public var loadConfiguration: @Sendable () -> SimulatorConfiguration
  public var saveConfiguration: @Sendable (SimulatorConfiguration) -> Void
  public var probeStatus: @Sendable (SimulatorConfiguration) async -> SimulatorRuntimeStatus
  public var discoverBuiltInScenes: @Sendable (SimulatorConfiguration) async -> [SimulatorScene]
  public var discoverSyncedScenes: @Sendable (SimulatorConfiguration) async -> SyncedScenesSnapshot
  public var stageSceneForLaunch: @Sendable (SimulatorScene, SimulatorConfiguration) async throws -> String
  public var importXMLFile: @Sendable (URL, SimulatorConfiguration) async throws -> SimulatorScene
  public var launchSimulator: @Sendable (
    SimulatorConfiguration,
    String?,
    @escaping @Sendable (String, Bool) -> Void
  ) async throws -> Void
  public var stopSimulator: @Sendable (
    SimulatorConfiguration,
    @escaping @Sendable (String, Bool) -> Void
  ) async throws -> Void
  public var readDaemonLog: @Sendable (SimulatorConfiguration, String) async -> String
  public var openInFinder: @Sendable (URL) -> Void
  public var copyToClipboard: @Sendable (String) -> Void

  public init(
    loadConfiguration: @escaping @Sendable () -> SimulatorConfiguration,
    saveConfiguration: @escaping @Sendable (SimulatorConfiguration) -> Void,
    probeStatus: @escaping @Sendable (SimulatorConfiguration) async -> SimulatorRuntimeStatus,
    discoverBuiltInScenes: @escaping @Sendable (SimulatorConfiguration) async -> [SimulatorScene],
    discoverSyncedScenes: @escaping @Sendable (SimulatorConfiguration) async -> SyncedScenesSnapshot,
    stageSceneForLaunch: @escaping @Sendable (SimulatorScene, SimulatorConfiguration) async throws -> String,
    importXMLFile: @escaping @Sendable (URL, SimulatorConfiguration) async throws -> SimulatorScene,
    launchSimulator: @escaping @Sendable (
      SimulatorConfiguration,
      String?,
      @escaping @Sendable (String, Bool) -> Void
    ) async throws -> Void,
    stopSimulator: @escaping @Sendable (
      SimulatorConfiguration,
      @escaping @Sendable (String, Bool) -> Void
    ) async throws -> Void,
    readDaemonLog: @escaping @Sendable (SimulatorConfiguration, String) async -> String,
    openInFinder: @escaping @Sendable (URL) -> Void,
    copyToClipboard: @escaping @Sendable (String) -> Void
  ) {
    self.loadConfiguration = loadConfiguration
    self.saveConfiguration = saveConfiguration
    self.probeStatus = probeStatus
    self.discoverBuiltInScenes = discoverBuiltInScenes
    self.discoverSyncedScenes = discoverSyncedScenes
    self.stageSceneForLaunch = stageSceneForLaunch
    self.importXMLFile = importXMLFile
    self.launchSimulator = launchSimulator
    self.stopSimulator = stopSimulator
    self.readDaemonLog = readDaemonLog
    self.openInFinder = openInFinder
    self.copyToClipboard = copyToClipboard
  }
}

extension SimulatorClient: DependencyKey {
  private static let configDefaultsKey = "microduck.simulator.configuration.v1"

  public static var liveValue: SimulatorClient {
    SimulatorClient(
      loadConfiguration: {
        guard
          let data = UserDefaults.standard.data(forKey: configDefaultsKey),
          let decoded = try? JSONDecoder().decode(SimulatorConfiguration.self, from: data)
        else {
          return SimulatorConfiguration()
        }
        return decoded
      },
      saveConfiguration: { config in
        if let data = try? JSONEncoder().encode(config) {
          UserDefaults.standard.set(data, forKey: configDefaultsKey)
        }
      },
      probeStatus: { config in
        await Task.detached(priority: .utility) {
          LiveSimulatorRuntime.probeStatus(config: config)
        }.value
      },
      discoverBuiltInScenes: { config in
        await Task.detached(priority: .utility) {
          SimulatorSceneScanner.scanDirectory(
            config.robotScenesDirectoryURL,
            source: .builtIn
          )
        }.value
      },
      discoverSyncedScenes: { config in
        await Task.detached(priority: .utility) {
          LiveSimulatorRuntime.discoverSyncedScenes(config: config)
        }.value
      },
      stageSceneForLaunch: { scene, config in
        try await Task.detached(priority: .userInitiated) {
          try SimulatorSceneScanner.stageScene(scene, intoRobotScenesDirectory: config.robotScenesDirectoryURL)
        }.value
      },
      importXMLFile: { sourceURL, config in
        try await Task.detached(priority: .userInitiated) {
          let targetDir = LiveSimulatorRuntime.resolveSyncedScenesDirectory(config: config).directoryURL
          let didStartScope = sourceURL.startAccessingSecurityScopedResource()
          defer {
            if didStartScope {
              sourceURL.stopAccessingSecurityScopedResource()
            }
          }
          return try SimulatorSceneScanner.importXML(
            from: sourceURL,
            intoScenesDirectory: targetDir,
            sourceKind: .iCloud
          )
        }.value
      },
      launchSimulator: { config, sceneOverride, onOutput in
        try await LiveSimulatorRuntime.runDuckSim(
          config: config,
          arguments: [],
          sceneOverride: sceneOverride,
          onOutput: onOutput
        )
      },
      stopSimulator: { config, onOutput in
        try await LiveSimulatorRuntime.runDuckSim(
          config: config,
          arguments: ["down"],
          sceneOverride: nil,
          onOutput: onOutput
        )
      },
      readDaemonLog: { config, fileName in
        await Task.detached(priority: .utility) {
          let url = config.stateDirectoryURL.appendingPathComponent(fileName)
          guard let data = try? Data(contentsOf: url) else {
            return "No log output at \(url.path) yet."
          }
          let maxBytes = 24_000
          let tail = data.count > maxBytes ? data.suffix(maxBytes) : data
          return SimulatorSceneScanner.stripANSI(String(decoding: tail, as: UTF8.self))
        }.value
      },
      openInFinder: { url in
        #if os(macOS)
        Task { @MainActor in
          NSWorkspace.shared.open(url)
        }
        #endif
      },
      copyToClipboard: { text in
        #if os(macOS)
        Task { @MainActor in
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
        #endif
      }
    )
  }

  public static var previewValue: SimulatorClient {
    SimulatorClient(
      loadConfiguration: { SimulatorConfiguration() },
      saveConfiguration: { _ in },
      probeStatus: { _ in
        SimulatorRuntimeStatus(
          isBodyPortOpen: true,
          isMediaPortOpen: true,
          isWebConsolePortOpen: true,
          daemons: [
            SimulatorDaemonStatus(id: "body", name: "MuJoCo Body", pid: 41201, isRunning: true, logFileName: "body.log"),
            SimulatorDaemonStatus(id: "duck-a", name: "robotd (duck-a)", pid: 41214, isRunning: true, logFileName: "duck-a.log"),
            SimulatorDaemonStatus(id: "duck-a-tof", name: "tofd (8×8 ToF)", pid: 41218, isRunning: true, logFileName: "duck-a-tof.log"),
            SimulatorDaemonStatus(id: "duck-a-media", name: "mediad (WebRTC)", pid: 41222, isRunning: true, logFileName: "duck-a-media.log"),
          ],
          activeSceneSlug: "playground"
        )
      },
      discoverBuiltInScenes: { _ in
        [
          SimulatorScene(
            slug: "playground",
            fileURL: URL(fileURLWithPath: "/tmp/scene_playground.xml"),
            source: .builtIn,
            supportsBacklashWalking: true
          ),
          SimulatorScene(
            slug: "backlash",
            fileURL: URL(fileURLWithPath: "/tmp/scene_backlash.xml"),
            source: .builtIn,
            supportsBacklashWalking: true
          ),
          SimulatorScene(
            slug: "apartment",
            fileURL: URL(fileURLWithPath: "/tmp/scene_apartment.xml"),
            source: .builtIn,
            supportsBacklashWalking: false
          ),
        ]
      },
      discoverSyncedScenes: { _ in
        SyncedScenesSnapshot(
          scenes: [
            SimulatorScene(
              slug: "living_room",
              displayName: "Living Room",
              fileURL: URL(fileURLWithPath: "/tmp/scene_living_room.xml"),
              source: .iCloud,
              supportsBacklashWalking: true,
              isDownloaded: true,
              roomCount: 2,
              obstacleCount: 11,
              modifiedAt: Date(timeIntervalSince1970: 1_795_150_000)
            )
          ],
          iCloudAvailable: true,
          directoryURL: URL(fileURLWithPath: "/tmp/iCloudScenes"),
          statusDetail: "Synced via iCloud Drive/Microduck Scenes"
        )
      },
      stageSceneForLaunch: { scene, _ in scene.slug },
      importXMLFile: { url, _ in
        SimulatorScene(
          slug: SimulatorScene.normalizedSlug(from: url.deletingPathExtension().lastPathComponent),
          fileURL: url,
          source: .iCloud
        )
      },
      launchSimulator: { _, _, onOutput in
        onOutput("== starting the body from microduck_rl", false)
        onOutput("== duck-a: standing (trunk 0.116 m, gravity z -0.998)", false)
      },
      stopSimulator: { _, onOutput in
        onOutput("== down", false)
      },
      readDaemonLog: { _, fileName in "Sample log output for \(fileName)" },
      openInFinder: { _ in },
      copyToClipboard: { _ in }
    )
  }

  public static var testValue: SimulatorClient {
    previewValue
  }
}

extension DependencyValues {
  public var simulator: SimulatorClient {
    get { self[SimulatorClient.self] }
    set { self[SimulatorClient.self] = newValue }
  }
}

private enum LiveSimulatorRuntime {
  static func resolveSyncedScenesDirectory(config: SimulatorConfiguration) -> (directoryURL: URL, iCloudAvailable: Bool, detail: String) {
    let fm = FileManager.default

    // 1. User-chosen synced scenes folder override (e.g. a custom folder inside iCloud Drive)
    if let custom = config.customSyncedScenesPath, !custom.isEmpty {
      let url = URL(fileURLWithPath: custom, isDirectory: true)
      try? fm.createDirectory(at: url, withIntermediateDirectories: true)
      let inCloud = custom.contains("Mobile Documents")
      return (url, inCloud, inCloud ? "iCloud Drive: \(url.lastPathComponent)" : "Custom folder: \(custom)")
    }

    // 2. Official ubiquity container (when provisioned with a paid Apple Developer Team)
    if let containerURL = fm.url(forUbiquityContainerIdentifier: DuckConstants.iCloudContainerID) {
      let scenesDir = containerURL.appendingPathComponent(DuckConstants.syncedScenesSubdirectory, isDirectory: true)
      try? fm.createDirectory(at: scenesDir, withIntermediateDirectories: true)
      return (scenesDir, true, "iCloud Drive container (\(DuckConstants.iCloudContainerID))")
    }

    // 3. Standard user iCloud Drive folder (`iCloud Drive/Microduck Scenes`) — works with Personal Teams
    #if os(macOS)
    let cloudDocsRoot = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    if fm.fileExists(atPath: cloudDocsRoot.path) {
      let scenesDir = cloudDocsRoot.appendingPathComponent(DuckConstants.iCloudDriveScenesFolderName, isDirectory: true)
      try? fm.createDirectory(at: scenesDir, withIntermediateDirectories: true)
      return (scenesDir, true, "Synced via iCloud Drive → \(DuckConstants.iCloudDriveScenesFolderName)")
    }
    #endif

    // 4. Local Application Support fallback so importing scenes always works offline
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let localDir = appSupport.appendingPathComponent("MicroduckRemote/Scenes", isDirectory: true)
    try? fm.createDirectory(at: localDir, withIntermediateDirectories: true)
    return (localDir, false, "Local fallback folder (enable iCloud Drive to sync LiDAR scans from iPhone)")
  }

  static func discoverSyncedScenes(config: SimulatorConfiguration) -> SyncedScenesSnapshot {
    let resolved = resolveSyncedScenesDirectory(config: config)
    let scenes = SimulatorSceneScanner.scanDirectory(
      resolved.directoryURL,
      source: .iCloud,
      startDownloadIfNeeded: true
    )
    return SyncedScenesSnapshot(
      scenes: scenes,
      iCloudAvailable: resolved.iCloudAvailable,
      directoryURL: resolved.directoryURL,
      statusDetail: resolved.detail
    )
  }

  static func probeStatus(config: SimulatorConfiguration) -> SimulatorRuntimeStatus {
    let bodyOpen = isLocalPortOpen(7801)
    let mediaOpen = isLocalPortOpen(8443)
    let webOpen = isLocalPortOpen(8080)

    let specs: [(id: String, name: String, pidFile: String, logFile: String)] = [
      ("body", "MuJoCo Body", "body.pid", "body.log"),
      ("duck-a", "robotd (duck-a)", "duck-a.pid", "duck-a.log"),
      ("duck-a-tof", "tofd (8×8 ToF)", "duck-a-tof.pid", "duck-a-tof.log"),
      ("duck-a-media", "mediad (WebRTC)", "duck-a-media.pid", "duck-a-media.log"),
      ("duck-a-config", "configd", "duck-a-config.pid", "duck-a-config.log"),
      ("duck-a-updater", "updaterd", "duck-a-updater.pid", "duck-a-updater.log"),
      ("duck-a-auto", "autod", "duck-a-auto.pid", "duck-a-auto.log"),
    ]

    var daemons: [SimulatorDaemonStatus] = []
    var activeScene: String?

    for spec in specs {
      let pidURL = config.stateDirectoryURL.appendingPathComponent(spec.pidFile)
      var parsedPID: Int32?
      var alive = false

      if let raw = try? String(contentsOf: pidURL, encoding: .utf8) {
        let digits = raw.filter(\.isNumber)
        if let pid = Int32(digits), pid > 1 {
          parsedPID = pid
          alive = isProcessAlive(pid)
          if alive, spec.id == "body" {
            if let cmdline = commandLineOfProcess(pid) {
              activeScene = SimulatorSceneScanner.parseActiveSceneSlug(fromBodyCommandLine: cmdline)
            }
          }
        }
      }

      daemons.append(
        SimulatorDaemonStatus(
          id: spec.id,
          name: spec.name,
          pid: alive ? parsedPID : nil,
          isRunning: alive,
          logFileName: spec.logFile
        )
      )
    }

    return SimulatorRuntimeStatus(
      isBodyPortOpen: bodyOpen,
      isMediaPortOpen: mediaOpen,
      isWebConsolePortOpen: webOpen,
      daemons: daemons,
      activeSceneSlug: activeScene
    )
  }

  private static func isProcessAlive(_ pid: Int32) -> Bool {
    #if canImport(Darwin)
    return kill(pid, 0) == 0 || errno == EPERM
    #else
    return false
    #endif
  }

  private static func isLocalPortOpen(_ port: UInt16) -> Bool {
    #if canImport(Darwin)
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var timeout = timeval(tv_sec: 0, tv_usec: 150_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let result = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return result == 0
    #else
    return false
    #endif
  }

  private static func commandLineOfProcess(_ pid: Int32) -> String? {
    #if os(macOS)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", "\(pid)", "-o", "command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let str = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      return str.isEmpty ? nil : str
    } catch {
      return nil
    }
    #else
    return nil
    #endif
  }

  static func runDuckSim(
    config: SimulatorConfiguration,
    arguments: [String],
    sceneOverride: String?,
    onOutput: @escaping @Sendable (String, Bool) -> Void
  ) async throws {
    #if os(macOS)
    let scriptURL = config.duckSimScriptURL
    guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
      throw SimulatorError.missingScript(scriptURL.path)
    }
    if arguments.isEmpty && !FileManager.default.fileExists(atPath: config.microduckRLRepoPath) {
      throw SimulatorError.missingRLRepository(config.microduckRLRepoPath)
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments = [scriptURL.path] + arguments
      process.currentDirectoryURL = URL(fileURLWithPath: config.microduckRepoPath, isDirectory: true)

      var env = ProcessInfo.processInfo.environment
      let home = NSHomeDirectory()
      let extraPaths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "\(home)/.cargo/bin",
        "\(home)/.local/bin",
      ]
      let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
      env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
      env["HOME"] = home
      for (k, v) in config.launchEnvironment(sceneOverride: sceneOverride) {
        env[k] = v
      }
      process.environment = env

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      process.standardInput = FileHandle.nullDevice

      let errorLines = LockIsolated<[String]>([])
      let stdoutBuffer = LockIsolated("")
      let stderrBuffer = LockIsolated("")

      let consume: @Sendable (Data, Bool, LockIsolated<String>) -> Void = { data, isError, buffer in
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        let lines = buffer.withValue { pending -> [String] in
          pending += chunk
          var emitted: [String] = []
          while let nl = pending.firstIndex(of: "\n") {
            let line = String(pending[..<nl])
            pending.removeSubrange(...nl)
            emitted.append(line)
          }
          return emitted
        }
        for rawLine in lines {
          let clean = SimulatorSceneScanner.stripANSI(rawLine)
            .trimmingCharacters(in: CharacterSet.newlines)
          guard !clean.isEmpty else { continue }
          if isError {
            errorLines.withValue { $0.append(clean) }
          }
          onOutput(clean, isError)
        }
      }

      stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
        } else {
          consume(data, false, stdoutBuffer)
        }
      }

      stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
        } else {
          consume(data, true, stderrBuffer)
        }
      }

      process.terminationHandler = { terminated in
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let flushRemainder: (LockIsolated<String>, Bool) -> Void = { buf, isErr in
          let rest = buf.withValue { val -> String in
            let copy = val
            val = ""
            return copy
          }
          let clean = SimulatorSceneScanner.stripANSI(rest).trimmingCharacters(in: .whitespacesAndNewlines)
          if !clean.isEmpty {
            if isErr { errorLines.withValue { $0.append(clean) } }
            onOutput(clean, isErr)
          }
        }
        flushRemainder(stdoutBuffer, false)
        flushRemainder(stderrBuffer, true)

        if terminated.terminationStatus == 0 {
          continuation.resume(returning: ())
        } else {
          let detail = errorLines.value.suffix(6).joined(separator: "\n")
          continuation.resume(throwing: SimulatorError.commandFailed(terminated.terminationStatus, detail))
        }
      }

      do {
        try process.run()
      } catch {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        continuation.resume(throwing: error)
      }
    }
    #else
    throw SimulatorError.unsupportedPlatform
    #endif
  }
}
