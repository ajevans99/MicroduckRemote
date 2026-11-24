import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import Observation

@Observable
@MainActor
public final class SimulatorModel {
  @ObservationIgnored @Dependency(\.simulator) var simulator
  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.continuousClock) var clock

  public var config: SimulatorConfiguration
  public var runtimeStatus = SimulatorRuntimeStatus()
  public var phase: SimulatorLifecyclePhase = .stopped

  public var builtInScenes: [SimulatorScene] = []
  public var syncedScenes: [SimulatorScene] = []
  public var iCloudAvailable = false
  public var iCloudDirectoryURL: URL?
  public var iCloudStatusDetail = ""

  public var logs: [SimulatorLogEntry] = []
  public var selectedLogSource: SimulatorLogSource = .liveOutput
  public var daemonLogText = ""
  public var isFileImporterPresented = false
  public var isSelectingMicroduckRepo = false
  public var isSelectingRLRepo = false
  public var isSelectingSyncedFolder = false
  public var statusBanner: String?
  public var errorMessage: String?

  public var onOpenDriveTab: () -> Void

  public init(onOpenDriveTab: @escaping () -> Void = {}) {
    self.onOpenDriveTab = onOpenDriveTab
    @Dependency(\.simulator) var simulator
    self.config = simulator.loadConfiguration()
  }

  public var allScenes: [SimulatorScene] {
    syncedScenes + builtInScenes
  }

  public var selectedScene: SimulatorScene? {
    if let synced = syncedScenes.first(where: { $0.slug == config.selectedSceneSlug }) {
      return synced
    }
    return builtInScenes.first(where: { $0.slug == config.selectedSceneSlug })
  }

  public var canConnectCockpit: Bool {
    runtimeStatus.isWebRTCReady
  }

  public func task() async {
    await refreshEverything()
    while !Task.isCancelled {
      try? await clock.sleep(for: .milliseconds(2500))
      guard !Task.isCancelled else { break }
      await refreshStatusOnly()
      if selectedLogSource != .liveOutput {
        await refreshSelectedDaemonLog()
      }
    }
  }

  public func refreshEverything() async {
    async let statusTask = simulator.probeStatus(config)
    async let builtInTask = simulator.discoverBuiltInScenes(config)
    async let syncedTask = simulator.discoverSyncedScenes(config)

    let (status, builtIns, synced) = await (statusTask, builtInTask, syncedTask)
    applyRuntimeStatus(status)
    builtInScenes = builtIns
    syncedScenes = synced.scenes
    iCloudAvailable = synced.iCloudAvailable
    iCloudDirectoryURL = synced.directoryURL
    iCloudStatusDetail = synced.statusDetail

    if selectedScene == nil {
      if let playground = builtIns.first(where: { $0.slug == "playground" }) {
        config.selectedSceneSlug = playground.slug
      } else if let backlash = builtIns.first(where: { $0.slug == "backlash" }) {
        config.selectedSceneSlug = backlash.slug
      } else if let first = allScenes.first {
        config.selectedSceneSlug = first.slug
      }
    }

    if selectedLogSource != .liveOutput {
      await refreshSelectedDaemonLog()
    }
  }

  public func refreshStatusOnly() async {
    let status = await simulator.probeStatus(config)
    applyRuntimeStatus(status)
  }

  public func refreshScenesButtonTapped() async {
    async let builtInTask = simulator.discoverBuiltInScenes(config)
    async let syncedTask = simulator.discoverSyncedScenes(config)
    let (builtIns, synced) = await (builtInTask, syncedTask)
    builtInScenes = builtIns
    syncedScenes = synced.scenes
    iCloudAvailable = synced.iCloudAvailable
    iCloudDirectoryURL = synced.directoryURL
    iCloudStatusDetail = synced.statusDetail
  }

  public func configurationChanged() {
    config.duckCount = min(max(config.duckCount, 1), 4)
    simulator.saveConfiguration(config)
  }

  public func selectScene(_ scene: SimulatorScene) {
    config.selectedSceneSlug = scene.slug
    configurationChanged()
  }

  public func launchOrRestartButtonTapped() async {
    guard !phase.isBusy else { return }
    errorMessage = nil
    statusBanner = nil
    phase = .starting
    selectedLogSource = .liveOutput
    appendLog("Launching Microduck simulator (scene: \(config.selectedSceneSlug))…", isError: false)
    configurationChanged()

    do {
      var sceneSlugToLaunch = config.selectedSceneSlug
      if let chosen = selectedScene, chosen.source == .iCloud {
        appendLog("Staging synced LiDAR scene “\(chosen.displayName)” into microduck_rl…", isError: false)
        sceneSlugToLaunch = try await simulator.stageSceneForLaunch(chosen, config)
        await refreshScenesButtonTapped()
      }

      try await simulator.launchSimulator(config, sceneSlugToLaunch) { [weak self] line, isError in
        Task { @MainActor [weak self] in
          self?.appendLog(line, isError: isError)
        }
      }

      let status = await simulator.probeStatus(config)
      applyRuntimeStatus(status)
      if status.isRunning {
        phase = .running
        statusBanner = "Simulator is running with “\(SimulatorScene.prettyName(forSlug: sceneSlugToLaunch))”."
        if config.autoConnectCockpit, status.isWebRTCReady {
          await connectDriveCockpitButtonTapped(switchTab: false)
        }
      } else {
        phase = .stopped
      }
    } catch {
      let msg = error.localizedDescription
      errorMessage = msg
      phase = .failed(msg)
      appendLog(msg, isError: true)
    }
  }

  public func stopButtonTapped() async {
    guard !phase.isBusy else { return }
    errorMessage = nil
    statusBanner = nil
    phase = .stopping
    selectedLogSource = .liveOutput
    appendLog("Stopping simulator (`duck-sim down`)…", isError: false)

    do {
      let currentSnap = await duckSession.currentSnapshot()
      if case .localSimulator = currentSnap.target, currentSnap.phase.isConnected || currentSnap.controlOpen {
        await duckSession.disconnect()
      }

      try await simulator.stopSimulator(config) { [weak self] line, isError in
        Task { @MainActor [weak self] in
          self?.appendLog(line, isError: isError)
        }
      }

      let status = await simulator.probeStatus(config)
      applyRuntimeStatus(status)
      phase = status.isRunning ? .running : .stopped
      if !status.isRunning {
        statusBanner = "Simulator stopped."
      }
    } catch {
      let msg = error.localizedDescription
      errorMessage = msg
      phase = .failed(msg)
      appendLog(msg, isError: true)
    }
  }

  public func connectDriveCockpitButtonTapped(switchTab: Bool = true) async {
    await duckSession.connect(.localSimulator(url: DuckConstants.defaultLocalSignallingURL))
    if switchTab {
      onOpenDriveTab()
    }
  }

  public func importXMLCompleted(_ result: Result<URL, any Error>) async {
    switch result {
    case let .success(url):
      do {
        let imported = try await simulator.importXMLFile(url, config)
        await refreshScenesButtonTapped()
        config.selectedSceneSlug = imported.slug
        configurationChanged()
        statusBanner = "Imported “\(imported.displayName)” into synced scenes."
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
    case let .failure(error):
      errorMessage = error.localizedDescription
    }
  }

  public func updateSyncedScenesFolder(_ url: URL) async {
    config.customSyncedScenesPath = url.path
    configurationChanged()
    await refreshScenesButtonTapped()
  }

  public func resetSyncedScenesFolder() async {
    config.customSyncedScenesPath = nil
    configurationChanged()
    await refreshScenesButtonTapped()
  }

  public func updateMicroduckRepoPath(_ url: URL) async {
    config.microduckRepoPath = url.path
    configurationChanged()
    await refreshEverything()
  }

  public func updateRLRepoPath(_ url: URL) async {
    config.microduckRLRepoPath = url.path
    configurationChanged()
    await refreshEverything()
  }

  public func openSyncedFolderButtonTapped() {
    if let url = iCloudDirectoryURL {
      simulator.openInFinder(url)
    }
  }

  public func openBuiltInScenesFolderButtonTapped() {
    simulator.openInFinder(config.robotScenesDirectoryURL)
  }

  public func copyCommandButtonTapped() {
    simulator.copyToClipboard(config.shellPreviewCommand)
    statusBanner = "Copied launch command to clipboard."
  }

  public func clearLogsButtonTapped() {
    logs.removeAll()
  }

  public func logSourceChanged(_ source: SimulatorLogSource) async {
    selectedLogSource = source
    if source != .liveOutput {
      await refreshSelectedDaemonLog()
    }
  }

  private func refreshSelectedDaemonLog() async {
    guard let fileName = selectedLogSource.fileName else { return }
    daemonLogText = await simulator.readDaemonLog(config, fileName)
  }

  private func applyRuntimeStatus(_ status: SimulatorRuntimeStatus) {
    runtimeStatus = status
    if !phase.isBusy {
      if status.isRunning {
        phase = .running
      } else if case .failed = phase {
        // Keep last launch failure visible until next action
      } else {
        phase = .stopped
      }
    }
  }

  private func appendLog(_ text: String, isError: Bool) {
    logs.append(SimulatorLogEntry(isError: isError, text: text))
    if logs.count > 400 {
      logs.removeFirst(logs.count - 400)
    }
  }
}
