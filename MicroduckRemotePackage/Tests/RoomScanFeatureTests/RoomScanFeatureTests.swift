import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import Foundation
import RoomScanFeature
import SwiftUI
import Testing
import simd

@Suite struct RoomScanFeatureTests {
  @Test func arKitCoordinatesFloorOffsetAndHalfExtentsConvertToMuJoCo() {
    let room = ScannedRoom(
      name: "Test Room",
      surfaces: [
        ScannedSurface(
          category: .floor,
          transform: .translationAndYaw(x: 0, y: -0.85, z: 0),
          dimensions: SIMD3<Float>(4.0, 0.0, 4.0)
        ),
        ScannedSurface(
          category: .wall,
          transform: .translationAndYaw(x: 0, y: 0.35, z: -2.0),
          dimensions: SIMD3<Float>(3.0, 2.4, 0.0)
        ),
      ]
    )
    let capture = ScannedSceneCapture(rooms: [room], source: .singleRoom)
    let result = MJCFSceneExporter.export(
      capture: capture,
      configuration: MJCFExportConfiguration(
        sceneName: "coord_check",
        includeFloorOverlays: false,
        alignDominantWallAxis: false,
        autoClearSpawnOrigin: false,
        minimumWallThickness: 0.10
      )
    )

    expectNoDifference(abs(result.summary.floorElevationOffsetMeters - (-0.85)) < 1e-5, true)
    expectNoDifference(result.geoms.count, 1)

    let wall = result.geoms[0]
    expectNoDifference(wall.name, "scan_wall_01")
    expectNoDifference(wall.kind, .wall)
    expectNoDifference(abs(wall.position.x - 0.0) < 1e-4, true)
    expectNoDifference(abs(wall.position.y - 2.0) < 1e-4, true)
    expectNoDifference(abs(wall.position.z - 1.2) < 1e-4, true)
    expectNoDifference(
      wall.shape,
      .box(halfExtents: SIMD3<Double>(1.5, 0.05, 1.2))
    )
    expectNoDifference(result.xml.contains("<include file=\"robot_groundcontact_backlash.xml\" />"), true)
    expectNoDifference(result.xml.contains("pos=\"0 2 1.2\" size=\"1.5 0.05 1.2\""), true)
  }

  @Test func doorwayCarvingLeavesOpenPassagesAndRespectsDoorPolicy() {
    let northWallID = UUID()
    let southWallID = UUID()
    let room = ScannedRoom(
      name: "Hall",
      surfaces: [
        ScannedSurface(
          category: .floor,
          transform: .translationAndYaw(x: 0, y: 0, z: 0),
          dimensions: SIMD3<Float>(4.0, 0, 4.0)
        ),
        ScannedSurface(
          id: northWallID,
          category: .wall,
          transform: .translationAndYaw(x: 0, y: 1.2, z: -2.0),
          dimensions: SIMD3<Float>(4.0, 2.4, 0.12)
        ),
        ScannedSurface(
          category: .opening,
          transform: .translationAndYaw(x: 0, y: 1.0, z: -2.0),
          dimensions: SIMD3<Float>(1.0, 2.0, 0.12),
          parentIdentifier: northWallID
        ),
        ScannedSurface(
          id: southWallID,
          category: .wall,
          transform: .translationAndYaw(x: 0, y: 1.2, z: 2.0),
          dimensions: SIMD3<Float>(4.0, 2.4, 0.12)
        ),
        ScannedSurface(
          category: .door(isOpen: false),
          transform: .translationAndYaw(x: 0.5, y: 1.0, z: 2.0),
          dimensions: SIMD3<Float>(0.9, 2.0, 0.06),
          parentIdentifier: southWallID
        ),
      ]
    )
    let capture = ScannedSceneCapture(rooms: [room], source: .singleRoom)

    let defaultExport = MJCFSceneExporter.export(
      capture: capture,
      configuration: MJCFExportConfiguration(
        doorPolicy: .openDoorwaysOnly,
        includeFloorOverlays: false,
        autoClearSpawnOrigin: false
      )
    )

    expectNoDifference(defaultExport.summary.wallSegmentCount, 4)
    expectNoDifference(defaultExport.summary.openDoorwayCount, 1)
    expectNoDifference(defaultExport.summary.closedDoorCount, 1)

    let northLowBlocking = defaultExport.geoms.filter { geom in
      geom.hasCollision &&
      geom.bottomZ < 1.5 &&
      abs(geom.position.y - 2.0) < 0.2 &&
      abs(geom.position.x) < 0.4
    }
    expectNoDifference(northLowBlocking.isEmpty, true)

    let northLintel = defaultExport.geoms.filter { $0.kind == .lintel && abs($0.position.y - 2.0) < 0.2 }
    expectNoDifference(northLintel.count, 1)
    expectNoDifference(northLintel.first.map { $0.bottomZ >= 1.99 }, true)

    let allOpenExport = MJCFSceneExporter.export(
      capture: capture,
      configuration: MJCFExportConfiguration(
        doorPolicy: .allDoorsOpen,
        includeFloorOverlays: false,
        autoClearSpawnOrigin: false
      )
    )
    expectNoDifference(allOpenExport.summary.openDoorwayCount, 2)
    expectNoDifference(allOpenExport.summary.closedDoorCount, 0)
  }

  @Test func furnitureApproximatesCylindersAngledBoxesAndElevatedWallItems() {
    let yaw: Float = 35.0 * .pi / 180.0
    let room = ScannedRoom(
      name: "Living",
      surfaces: [
        ScannedSurface(
          category: .floor,
          transform: .translationAndYaw(x: 0, y: 0, z: 0),
          dimensions: SIMD3<Float>(5.0, 0, 5.0)
        ),
      ],
      objects: [
        ScannedObject(
          category: .table,
          shapeHint: .circularCylinder,
          transform: .translationAndYaw(x: 1.2, y: 0.23, z: -1.0),
          dimensions: SIMD3<Float>(0.80, 0.46, 0.80)
        ),
        ScannedObject(
          category: .chair,
          shapeHint: .box,
          transform: .translationAndYaw(x: -1.3, y: 0.40, z: 0.8, yawRadians: yaw),
          dimensions: SIMD3<Float>(0.70, 0.80, 0.64)
        ),
        ScannedObject(
          category: .television,
          shapeHint: .box,
          transform: .translationAndYaw(x: 0, y: 1.40, z: -2.4),
          dimensions: SIMD3<Float>(1.20, 0.68, 0.08)
        ),
      ]
    )

    let result = MJCFSceneExporter.export(
      capture: ScannedSceneCapture(rooms: [room], source: .singleRoom),
      configuration: MJCFExportConfiguration(
        includeFloorOverlays: false,
        alignDominantWallAxis: false,
        autoClearSpawnOrigin: false
      )
    )

    expectNoDifference(result.summary.furnitureCount, 3)

    let table = result.geoms[0]
    expectNoDifference(table.shape, .cylinder(radius: 0.4, halfHeight: 0.23))
    expectNoDifference(abs(table.position.z - 0.23) < 1e-4, true)

    let chair = result.geoms[1]
    expectNoDifference(chair.shape, .box(halfExtents: SIMD3<Double>(0.35, 0.32, 0.40)))
    expectNoDifference(abs(chair.quaternion.x - cos(Double(yaw) * 0.5)) < 1e-4, true)
    expectNoDifference(abs(chair.quaternion.w - sin(Double(yaw) * 0.5)) < 1e-4, true)

    let tv = result.geoms[2]
    expectNoDifference(tv.bottomZ > 1.0, true)
  }

  @Test func spawnSolverAvoidsCentralObstacleInsideLShapedFloor() {
    let lShapeCorners: [SIMD3<Float>] = [
      SIMD3<Float>(-2.0, 0, -2.0),
      SIMD3<Float>(2.0, 0, -2.0),
      SIMD3<Float>(2.0, 0, 0.0),
      SIMD3<Float>(0.0, 0, 0.0),
      SIMD3<Float>(0.0, 0, 2.0),
      SIMD3<Float>(-2.0, 0, 2.0),
    ]
    let room = ScannedRoom(
      name: "L-Room",
      surfaces: [
        ScannedSurface(
          category: .floor,
          transform: .identity,
          dimensions: SIMD3<Float>(4.0, 0, 4.0),
          polygonCorners: lShapeCorners
        ),
      ],
      objects: [
        ScannedObject(
          category: .sofa,
          transform: .translationAndYaw(x: -0.65, y: 0.45, z: 0.35),
          dimensions: SIMD3<Float>(1.4, 0.9, 1.2)
        ),
      ]
    )

    let result = MJCFSceneExporter.export(
      capture: ScannedSceneCapture(rooms: [room], source: .singleRoom),
      configuration: MJCFExportConfiguration(
        includeFloorOverlays: false,
        alignDominantWallAxis: false,
        autoClearSpawnOrigin: true
      )
    )

    expectNoDifference(result.summary.spawnClearanceMeters >= 0.35, true)
    expectNoDifference(result.preview.spawnPoint, .zero)
  }

  @Test func multiRoomFallbackDeduplicatesSharedWallAndFiltersOtherStories() {
    let roomA = ScannedRoom(
      name: "Kitchen",
      story: 0,
      surfaces: [
        ScannedSurface(
          category: .floor,
          transform: .translationAndYaw(x: -1.5, y: 0, z: 0),
          dimensions: SIMD3<Float>(3.0, 0, 3.0),
          story: 0
        ),
        ScannedSurface(
          category: .wall,
          transform: .translationAndYaw(x: 0.0, y: 1.2, z: 0, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(3.0, 2.4, 0.10),
          story: 0
        ),
        ScannedSurface(
          category: .door(isOpen: true),
          transform: .translationAndYaw(x: 0.0, y: 1.0, z: 0, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(0.9, 2.0, 0.12),
          story: 0
        ),
      ]
    )
    let roomB = ScannedRoom(
      name: "Dining",
      story: 0,
      surfaces: [
        ScannedSurface(
          category: .floor,
          transform: .translationAndYaw(x: 1.5, y: 0, z: 0),
          dimensions: SIMD3<Float>(3.0, 0, 3.0),
          story: 0
        ),
        ScannedSurface(
          category: .wall,
          transform: .translationAndYaw(x: 0.06, y: 1.2, z: 0, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(3.0, 2.4, 0.10),
          story: 0
        ),
        ScannedSurface(
          category: .wall,
          transform: .translationAndYaw(x: 1.5, y: 3.8, z: 0),
          dimensions: SIMD3<Float>(3.0, 2.4, 0.10),
          story: 1
        ),
      ]
    )

    let capture = ScannedSceneCapture(
      rooms: [roomA, roomB],
      mergedSurfaces: nil,
      mergedObjects: nil,
      source: .fallbackMultiRoomUnion
    )
    let result = MJCFSceneExporter.export(
      capture: capture,
      configuration: MJCFExportConfiguration(
        sceneName: "scene_Upstairs Test.xml",
        includeFloorOverlays: false
      )
    )

    expectNoDifference(result.configuration.sceneSlug, "upstairs_test")
    expectNoDifference(result.configuration.fileName, "scene_upstairs_test.xml")
    expectNoDifference(result.summary.wallSegmentCount, 2)
    expectNoDifference(result.summary.openDoorwayCount, 1)
    expectNoDifference(result.summary.warnings.contains { $0.contains("story") }, true)
  }

  @Test @MainActor func modelHandlesUnsupportedPermissionAndMultiRoomFlow() async {
    let permissionRequested = LockIsolated(false)
    let settingsOpened = LockIsolated(false)
    let copiedCommands = LockIsolated<[String]>([])
    let driver = ControlledCaptureDriver()

    await withDependencies {
      $0.haptics = .previewValue
      $0.roomScan = RoomScanClient(
        deviceSupport: { .unsupportedHardware },
        cameraAuthorization: { .notDetermined },
        requestCameraAccess: { true },
        openSystemSettings: {},
        makeCaptureDriver: { driver },
        writeExportFile: RoomScanClient.previewValue.writeExportFile,
        copyToClipboard: { _ in }
      )
    } operation: {
      let unsupportedModel = RoomScanModel()
      unsupportedModel.onAppear()
      expectNoDifference(unsupportedModel.canStartHardwareScan, false)
      await unsupportedModel.startScanButtonTapped()
      expectNoDifference(unsupportedModel.phase, .idle)
      expectNoDifference(unsupportedModel.errorMessage != nil, true)
    }

    let authState = LockIsolated<CameraAuthorizationState>(.denied)
    await withDependencies {
      $0.haptics = .previewValue
      $0.roomScan = RoomScanClient(
        deviceSupport: { .supported },
        cameraAuthorization: { authState.value },
        requestCameraAccess: {
          permissionRequested.setValue(true)
          authState.setValue(.authorized)
          return true
        },
        openSystemSettings: {
          settingsOpened.setValue(true)
        },
        makeCaptureDriver: { driver },
        writeExportFile: RoomScanClient.previewValue.writeExportFile,
        copyToClipboard: { text in
          copiedCommands.withValue { $0.append(text) }
        }
      )
    } operation: {
      let model = RoomScanModel()
      model.onAppear()
      expectNoDifference(model.isPermissionDeniedOrRestricted, true)
      await model.openSettingsButtonTapped()
      expectNoDifference(settingsOpened.value, true)

      authState.setValue(.notDetermined)
      model.refreshCapabilities()
      expectNoDifference(model.needsPermissionRequest, true)

      let scanTask = Task {
        await model.requestCameraPermissionButtonTapped()
      }
      await driver.waitForStart()
      expectNoDifference(permissionRequested.value, true)
      expectNoDifference(model.phase, .scanning)

      model.addNextRoomButtonTapped()
      expectNoDifference(driver.addedNextRoomCount, 1)

      model.finishScanButtonTapped()
      await scanTask.value

      expectNoDifference(model.phase, .review)
      expectNoDifference(model.exportResult?.configuration.fileName, "scene_scanned_apartment.xml")
      expectNoDifference(model.shareFileURL != nil, true)

      model.copyLaunchCommandButtonTapped()
      expectNoDifference(
        copiedCommands.value,
        ["DUCK_SIM_SCENE=scanned_apartment DUCK_SIM_CAMERAS=a scripts/duck-sim"]
      )
    }
  }

  @Test
  func coordinatedSceneFileStorePersistsXMLSidecarLoadsBareXMLAndDeletes() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RoomScanICloudStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = CoordinatedSceneFileStore(directoryURL: tempDir, storageLocation: .iCloudDrive)
    let exportDate = Date(timeIntervalSince1970: 1_763_942_400)
    let metadata = SyncedSceneMetadata(
      slug: "living_room",
      displayName: "Living Room",
      roomCount: 2,
      obstacleCount: 14,
      exportedAt: exportDate
    )
    let xml = "<mujoco model=\"scene_living_room\"><worldbody/></mujoco>"

    let saved = try store.save(xml: xml, metadata: metadata)
    expectNoDifference(saved.fileName, "scene_living_room.xml")
    expectNoDifference(saved.xmlURL.lastPathComponent, "scene_living_room.xml")
    expectNoDifference(saved.metadataURL?.lastPathComponent, "scene_living_room.json")
    expectNoDifference(saved.storageLocation, .iCloudDrive)

    let rawJSON = try String(contentsOf: store.metadataFileURL(forSlug: "living_room"), encoding: .utf8)
    expectNoDifference(rawJSON.contains("\"exportedAt\" : \"2025-11-24T00:00:00Z\""), true)
    expectNoDifference(rawJSON.contains("\"slug\" : \"living_room\""), true)
    expectNoDifference(rawJSON.contains("\"displayName\" : \"Living Room\""), true)
    expectNoDifference(rawJSON.contains("\"roomCount\" : 2"), true)
    expectNoDifference(rawJSON.contains("\"obstacleCount\" : 14"), true)

    let bareXMLURL = tempDir.appendingPathComponent("scene_studio_loft.xml")
    try Data("<mujoco model=\"scene_studio_loft\"/>".utf8).write(to: bareXMLURL)

    let scenes = try store.listScenes()
    expectNoDifference(scenes.count, 2)
    let loadedPrimary = try #require(scenes.first(where: { $0.metadata.slug == "living_room" }))
    expectNoDifference(loadedPrimary.metadata, metadata)
    expectNoDifference(try store.readXML(slug: "living_room"), xml)

    let loadedBare = try #require(scenes.first(where: { $0.metadata.slug == "studio_loft" }))
    expectNoDifference(loadedBare.metadata.displayName, "Studio Loft")
    expectNoDifference(loadedBare.metadataURL, nil)

    try store.delete(slug: "living_room")
    expectNoDifference(FileManager.default.fileExists(atPath: saved.xmlURL.path), false)
    expectNoDifference(FileManager.default.fileExists(atPath: store.metadataFileURL(forSlug: "living_room").path), false)
    expectNoDifference(try store.listScenes().map(\.metadata.slug), ["studio_loft"])
  }

  @Test
  @MainActor
  func modelConnectsICloudFolderSavesInspectsAndDeletesScenes() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RoomScanModelICloudTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("Microduck Scenes", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

    let selectedFolder = LockIsolated<URL?>(nil)
    let fixedDate = Date(timeIntervalSince1970: 1_763_942_400)

    try await withDependencies {
      $0.haptics = .previewValue
      $0.roomScan = .previewValue
      $0.date.now = fixedDate
      $0.iCloudSceneSync = ICloudSceneSyncClient(
        checkAvailability: {
          if let folder = selectedFolder.value {
            return .folderConnected(folderName: folder.lastPathComponent)
          }
          return .needsFolderSelection
        },
        setSyncedFolder: { url in
          selectedFolder.setValue(url)
          return url.lastPathComponent
        },
        clearSyncedFolder: {
          selectedFolder.setValue(nil)
        },
        saveScene: { xml, metadata in
          let dir = selectedFolder.value ?? tempDir
          let store = CoordinatedSceneFileStore(directoryURL: dir, storageLocation: .syncedFolder)
          let record = try store.save(xml: xml, metadata: metadata)
          return ICloudSceneSyncResult(
            record: record,
            usedLocalFallback: false,
            statusMessage: "Saved \(record.fileName) to \(dir.lastPathComponent)"
          )
        },
        listScenes: {
          guard let dir = selectedFolder.value else { return [] }
          return try CoordinatedSceneFileStore(directoryURL: dir, storageLocation: .syncedFolder).listScenes()
        },
        readSceneXML: { record in
          let dir = selectedFolder.value ?? record.xmlURL.deletingLastPathComponent()
          return try CoordinatedSceneFileStore(directoryURL: dir, storageLocation: .syncedFolder)
            .readXML(slug: record.metadata.slug)
        },
        deleteScene: { record in
          let dir = selectedFolder.value ?? record.xmlURL.deletingLastPathComponent()
          try CoordinatedSceneFileStore(directoryURL: dir, storageLocation: .syncedFolder)
            .delete(slug: record.metadata.slug)
        }
      )
    } operation: {
      let model = RoomScanModel()
      model.loadSampleApartmentButtonTapped()

      await model.saveToICloudButtonTapped()
      expectNoDifference(model.isFolderImporterPresented, true)
      expectNoDifference(model.syncedScenes, [])

      await model.folderImporterCompleted(.success([tempDir]))
      expectNoDifference(model.iCloudAvailability, .folderConnected(folderName: "Microduck Scenes"))
      expectNoDifference(model.statusToast, "Saved scene_my_apartment.xml to Microduck Scenes")
      expectNoDifference(model.syncedScenes.count, 1)

      let record = try #require(model.syncedScenes.first)
      expectNoDifference(record.metadata.slug, "my_apartment")
      expectNoDifference(record.metadata.displayName, "My Apartment")
      expectNoDifference(record.metadata.roomCount, 2)
      expectNoDifference(record.metadata.obstacleCount > 0, true)
      expectNoDifference(record.metadata.exportedAt, fixedDate)

      await model.inspectSyncedSceneButtonTapped(record)
      expectNoDifference(model.xmlInspectorSheet?.fileName, "scene_my_apartment.xml")
      expectNoDifference(model.xmlInspectorSheet?.xml.contains("robot_groundcontact_backlash.xml"), true)

      await model.deleteSyncedSceneButtonTapped(record)
      expectNoDifference(model.syncedScenes, [])
      expectNoDifference(model.statusToast, "Deleted scene_my_apartment.xml")
    }
  }
}

@MainActor
private final class ControlledCaptureDriver: RoomCaptureDriver {
  private var continuation: AsyncStream<RoomScanSessionEvent>.Continuation?
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var didStart = false
  var addedNextRoomCount = 0

  func events() -> AsyncStream<RoomScanSessionEvent> {
    AsyncStream { continuation in
      self.continuation = continuation
    }
  }

  func startNewSession() {
    didStart = true
    continuation?.yield(.progressUpdated(RoomScanLiveProgress(currentRoomNumber: 1)))
    startedContinuation?.resume()
    startedContinuation = nil
  }

  func waitForStart() async {
    if didStart { return }
    await withCheckedContinuation { cont in
      self.startedContinuation = cont
    }
  }

  func finishCurrentRoomAndStartNext() {
    addedNextRoomCount += 1
    continuation?.yield(.roomAdded(completedCount: addedNextRoomCount))
    continuation?.yield(
      .progressUpdated(
        RoomScanLiveProgress(
          currentRoomNumber: addedNextRoomCount + 1,
          completedRoomCount: addedNextRoomCount
        )
      )
    )
  }

  func finishAllRoomsAndBuild() {
    continuation?.yield(.completed(.sampleTwoRoomApartment))
    continuation?.finish()
  }

  func cancel() {
    continuation?.finish()
  }

  func makeCaptureView() -> AnyView {
    AnyView(EmptyView())
  }
}
