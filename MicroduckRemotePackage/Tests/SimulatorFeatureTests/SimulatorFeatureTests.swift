import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckProtocol
import Foundation
import SimulatorFeature
import Testing

@Suite struct SimulatorFeatureTests {
  @Test func extractsSlugsFromSceneFilenamesAndCloudPlaceholders() {
    expectNoDifference(SimulatorScene.slug(fromFilename: "scene_playground.xml"), "playground")
    expectNoDifference(SimulatorScene.slug(fromFilename: ".scene_living_room.xml.icloud"), "living_room")
    expectNoDifference(SimulatorScene.slug(fromFilename: "robot_groundcontact_backlash.xml"), nil)
    expectNoDifference(SimulatorScene.slug(fromFilename: "scene_.xml"), nil)
    expectNoDifference(SimulatorScene.normalizedSlug(from: "scene_My Living Room!.xml"), "my_living_room")
    expectNoDifference(SimulatorScene.normalizedSlug(from: "Kitchen Scan 2"), "kitchen_scan_2")
  }

  @Test func scansDirectoryReadsSidecarMetadataBacklashFlagAndCloudPlaceholders() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("microduck-sim-scan-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let livingXML = """
    <mujoco model="living_room">
      <include file="robot_groundcontact_backlash.xml" />
    </mujoco>
    """
    try livingXML.write(to: tempDir.appendingPathComponent("scene_living_room.xml"), atomically: true, encoding: .utf8)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let meta = SyncedSceneMetadata(
      slug: "living_room",
      displayName: "Downstairs Living Room",
      roomCount: 2,
      obstacleCount: 14,
      exportedAt: Date(timeIntervalSince1970: 1_795_200_000)
    )
    try encoder.encode(meta).write(to: tempDir.appendingPathComponent("scene_living_room.json"))

    // Non-backlash scene without sidecar
    let bareXML = "<mujoco model=\"office\"><include file=\"robot_allcollisions.xml\"/></mujoco>"
    try bareXML.write(to: tempDir.appendingPathComponent("scene_office.xml"), atomically: true, encoding: .utf8)

    // Evicted iCloud placeholder
    try Data().write(to: tempDir.appendingPathComponent(".scene_kitchen.xml.icloud"))

    let scenes = SimulatorSceneScanner.scanDirectory(tempDir, source: .iCloud)
    expectNoDifference(scenes.count, 3)

    let living = try #require(scenes.first(where: { $0.slug == "living_room" }))
    expectNoDifference(living.displayName, "Downstairs Living Room")
    expectNoDifference(living.roomCount, 2)
    expectNoDifference(living.obstacleCount, 14)
    expectNoDifference(living.supportsBacklashWalking, true)
    expectNoDifference(living.isDownloaded, true)

    let office = try #require(scenes.first(where: { $0.slug == "office" }))
    expectNoDifference(office.displayName, "Office")
    expectNoDifference(office.supportsBacklashWalking, false)

    let kitchen = try #require(scenes.first(where: { $0.slug == "kitchen" }))
    expectNoDifference(kitchen.isDownloaded, false)
  }

  @Test func stagesSyncedSceneIntoRobotDirectoryAndRejectsUndownloadedCloudFile() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("microduck-sim-stage-\(UUID().uuidString)", isDirectory: true)
    let cloudDir = root.appendingPathComponent("cloud", isDirectory: true)
    let robotDir = root.appendingPathComponent("robot", isDirectory: true)
    try FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: robotDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let xml = "<mujoco><include file=\"robot_groundcontact_backlash.xml\"/></mujoco>"
    let sourceURL = cloudDir.appendingPathComponent("scene_bedroom.xml")
    try xml.write(to: sourceURL, atomically: true, encoding: .utf8)

    let syncedScene = SimulatorScene(
      slug: "bedroom",
      fileURL: sourceURL,
      source: .iCloud,
      supportsBacklashWalking: true,
      isDownloaded: true
    )

    let stagedSlug = try SimulatorSceneScanner.stageScene(syncedScene, intoRobotScenesDirectory: robotDir)
    expectNoDifference(stagedSlug, "bedroom")

    let stagedURL = robotDir.appendingPathComponent("scene_bedroom.xml")
    let stagedContent = try String(contentsOf: stagedURL, encoding: .utf8)
    expectNoDifference(stagedContent, xml)

    let pendingScene = SimulatorScene(
      slug: "attic",
      fileURL: cloudDir.appendingPathComponent(".scene_attic.xml.icloud"),
      source: .iCloud,
      isDownloaded: false
    )
    #expect(throws: SimulatorError.sceneNotDownloaded("Attic")) {
      try SimulatorSceneScanner.stageScene(pendingScene, intoRobotScenesDirectory: robotDir)
    }
  }

  @Test func importsValidMJCFAndRejectsInvalidXML() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("microduck-sim-import-\(UUID().uuidString)", isDirectory: true)
    let destDir = root.appendingPathComponent("scenes", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let validInput = root.appendingPathComponent("My Den.xml")
    try "<mujoco model=\"den\"><include file=\"robot_groundcontact_backlash.xml\"/></mujoco>"
      .write(to: validInput, atomically: true, encoding: .utf8)

    let imported = try SimulatorSceneScanner.importXML(from: validInput, intoScenesDirectory: destDir)
    expectNoDifference(imported.slug, "my_den")
    expectNoDifference(imported.supportsBacklashWalking, true)
    #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("scene_my_den.xml").path))
    #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("scene_my_den.json").path))

    let invalidInput = root.appendingPathComponent("notes.xml")
    try "<notes>hello</notes>".write(to: invalidInput, atomically: true, encoding: .utf8)
    #expect(throws: SimulatorError.self) {
      try SimulatorSceneScanner.importXML(from: invalidInput, intoScenesDirectory: destDir)
    }
  }

  @Test func parsesActiveSceneSlugAndBuildsLaunchEnvironment() {
    let cmd = "/Users/dev/Pollen/microduck_rl/.venv/bin/mjpython -m mjlab_microduck.sim.body_server --port 7801 --ducks 2 --keyframe SIT --scene /Users/dev/Pollen/microduck_rl/src/mjlab_microduck/robot/microduck/scene_playground.xml --cameras a"
    expectNoDifference(SimulatorSceneScanner.parseActiveSceneSlug(fromBodyCommandLine: cmd), "playground")

    let config = SimulatorConfiguration(
      microduckRepoPath: "/tmp/microduck",
      microduckRLRepoPath: "/tmp/microduck_rl",
      stateDirPath: "/tmp/duck-sim",
      selectedSceneSlug: "playground",
      cameraMode: .duckA,
      duckCount: 2,
      showMuJoCoViewer: false,
      keyframe: .stand,
      autoConnectCockpit: true
    )

    let env = config.launchEnvironment()
    expectNoDifference(env["DUCK_SIM_SCENE"], "playground")
    expectNoDifference(env["DUCK_SIM_CAMERAS"], "a")
    expectNoDifference(env["DUCK_SIM_DUCKS"], "2")
    expectNoDifference(env["DUCK_SIM_VIEWER"], "0")
    expectNoDifference(env["DUCK_SIM_KEYFRAME"], "STAND")
    expectNoDifference(
      config.shellPreviewCommand,
      "DUCK_SIM_SCENE=playground DUCK_SIM_CAMERAS=a DUCK_SIM_DUCKS=2 DUCK_SIM_VIEWER=0 DUCK_SIM_KEYFRAME=STAND ./scripts/duck-sim"
    )
  }

  @Test func enrichesPathWithHomebrewRustupCargoAndStripsANSIColors() {
    let enriched = SimulatorConfiguration.enrichedPATH(
      existing: "/usr/bin:/bin:/opt/homebrew/bin",
      home: "/Users/tester"
    )
    let entries = enriched.split(separator: ":").map(String.init)
    expectNoDifference(entries.contains("/opt/homebrew/opt/rustup/bin"), true)
    expectNoDifference(entries.contains("/Users/tester/.cargo/bin"), true)
    expectNoDifference(entries.contains("/Users/tester/.local/share/mise/shims"), true)
    expectNoDifference(entries.filter { $0 == "/opt/homebrew/bin" }.count, 1)

    let raw = "\u{001B}[36m==\u{001B}[0m building the daemons from main"
    expectNoDifference(SimulatorSceneScanner.stripANSI(raw), "== building the daemons from main")
  }

  @Test @MainActor func modelStagesICloudSceneLaunchesAndAutoConnectsDrive() async {
    let stagedSlugs = LockIsolated<[String]>([])
    let launchedScenes = LockIsolated<[String?]>([])
    let connectedTargets = LockIsolated<[ConnectionTarget]>([])

    let syncedScene = SimulatorScene(
      slug: "living_room",
      displayName: "Living Room",
      fileURL: URL(fileURLWithPath: "/tmp/iCloud/scene_living_room.xml"),
      source: .iCloud,
      supportsBacklashWalking: true,
      isDownloaded: true,
      roomCount: 1,
      obstacleCount: 8
    )

    let model = withDependencies {
      var sim = SimulatorClient.previewValue
      sim.loadConfiguration = {
        SimulatorConfiguration(selectedSceneSlug: "living_room", autoConnectCockpit: true)
      }
      sim.discoverSyncedScenes = { _ in
        SyncedScenesSnapshot(scenes: [syncedScene], iCloudAvailable: true)
      }
      sim.stageSceneForLaunch = { scene, _ in
        stagedSlugs.withValue { $0.append(scene.slug) }
        return scene.slug
      }
      sim.launchSimulator = { _, sceneOverride, onOutput in
        launchedScenes.withValue { $0.append(sceneOverride) }
        onOutput("== duck-a: standing", false)
      }
      sim.probeStatus = { _ in
        SimulatorRuntimeStatus(
          isBodyPortOpen: true,
          isMediaPortOpen: true,
          isWebConsolePortOpen: true,
          activeSceneSlug: "living_room"
        )
      }
      $0.simulator = sim

      var session = DuckSessionClient.previewValue
      session.connect = { target in
        connectedTargets.withValue { $0.append(target) }
      }
      $0.duckSession = session
    } operation: {
      SimulatorModel()
    }

    await model.refreshEverything()
    await model.launchOrRestartButtonTapped()

    expectNoDifference(stagedSlugs.value, ["living_room"])
    expectNoDifference(launchedScenes.value, ["living_room"])
    expectNoDifference(model.phase, .running)
    expectNoDifference(
      connectedTargets.value,
      [.localSimulator(url: DuckConstants.defaultLocalSignallingURL)]
    )
  }
}
