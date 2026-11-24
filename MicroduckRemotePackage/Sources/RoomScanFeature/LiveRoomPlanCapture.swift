import Dependencies
import Foundation
import IssueReporting
import SwiftUI

#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(ARKit) && canImport(RoomPlan) && canImport(UIKit)
import ARKit
import RoomPlan

@Observable
@MainActor
final class LiveRoomPlanSessionState {
  var segmentToken = UUID()
  var isRunning = false
}

@MainActor
final class LiveRoomCaptureDriver: NSObject, RoomCaptureDriver {
  private enum StopIntent {
    case none
    case addNextRoom
    case finalizeAllRooms
    case cancelled
  }

  private let uiState = LiveRoomPlanSessionState()
  private var sharedARSession = ARSession()
  private weak var activeCaptureView: RoomCaptureView?
  private var sessionBridge: CaptureSessionDelegateBridge?
  private var viewBridge: CaptureViewDelegateBridge?
  private var continuation: AsyncStream<RoomScanSessionEvent>.Continuation?
  private var capturedRooms: [CapturedRoom] = []
  private var stopIntent: StopIntent = .none
  private var progress = RoomScanLiveProgress()

  override init() {
    super.init()
  }

  func events() -> AsyncStream<RoomScanSessionEvent> {
    AsyncStream { continuation in
      self.continuation = continuation
    }
  }

  func startNewSession() {
    sharedARSession.pause()
    sharedARSession = ARSession()
    capturedRooms.removeAll()
    stopIntent = .none
    progress = RoomScanLiveProgress(
      currentRoomNumber: 1,
      completedRoomCount: 0,
      coachingInstruction: "Pan slowly across walls, floors, and open doorways"
    )
    uiState.isRunning = true
    uiState.segmentToken = UUID()
    continuation?.yield(.progressUpdated(progress))
  }

  func finishCurrentRoomAndStartNext() {
    guard !progress.isProcessingRoom else { return }
    stopIntent = .addNextRoom
    progress.isProcessingRoom = true
    progress.statusBanner = "Saving Room \(progress.currentRoomNumber) — keep camera moving toward next room…"
    continuation?.yield(.progressUpdated(progress))
    activeCaptureView?.captureSession.stop(pauseARSession: false)
  }

  func finishAllRoomsAndBuild() {
    guard !progress.isProcessingRoom else { return }
    stopIntent = .finalizeAllRooms
    progress.isProcessingRoom = true
    progress.statusBanner = capturedRooms.isEmpty
      ? "Processing room geometry on-device…"
      : "Merging \(capturedRooms.count + 1) rooms with StructureBuilder…"
    continuation?.yield(.progressUpdated(progress))
    activeCaptureView?.captureSession.stop(pauseARSession: true)
  }

  func cancel() {
    stopIntent = .cancelled
    uiState.isRunning = false
    activeCaptureView?.captureSession.stop(pauseARSession: true)
    sharedARSession.pause()
    continuation?.finish()
  }

  func makeCaptureView() -> AnyView {
    AnyView(
      LiveRoomCaptureHostContainer(driver: self, uiState: uiState)
    )
  }

  fileprivate func mountCaptureView() -> RoomCaptureView {
    let view = RoomCaptureView(frame: .zero, arSession: sharedARSession)
    let sessionDelegate = CaptureSessionDelegateBridge(
      onLiveCounts: { [weak self] walls, doorways, objects in
        Task { @MainActor [weak self] in
          self?.handleLiveCounts(walls: walls, doorways: doorways, objects: objects)
        }
      },
      onInstruction: { [weak self] instructionText in
        Task { @MainActor [weak self] in
          self?.handleInstruction(instructionText)
        }
      },
      onDidEnd: { [weak self] data, errorDescription in
        Task { @MainActor [weak self] in
          await self?.handleCaptureEnded(data: data, errorDescription: errorDescription)
        }
      }
    )
    let viewDelegate = CaptureViewDelegateBridge()
    sessionBridge = sessionDelegate
    viewBridge = viewDelegate
    view.captureSession.delegate = sessionDelegate
    view.delegate = viewDelegate
    activeCaptureView = view

    if uiState.isRunning {
      var configuration = RoomCaptureSession.Configuration()
      configuration.isCoachingEnabled = true
      view.captureSession.run(configuration: configuration)
    }
    return view
  }

  private func handleLiveCounts(walls: Int, doorways: Int, objects: Int) {
    guard !progress.isProcessingRoom else { return }
    progress.liveWallCount = walls
    progress.liveDoorwayCount = doorways
    progress.liveObjectCount = objects
    continuation?.yield(.progressUpdated(progress))
  }

  private func handleInstruction(_ text: String?) {
    guard !progress.isProcessingRoom else { return }
    progress.coachingInstruction = text
    continuation?.yield(.progressUpdated(progress))
  }

  private func handleCaptureEnded(data: CapturedRoomData, errorDescription: String?) async {
    let intent = stopIntent
    stopIntent = .none

    if intent == .cancelled {
      return
    }

    if let errorDescription, capturedRooms.isEmpty {
      sharedARSession.pause()
      uiState.isRunning = false
      continuation?.yield(.failed("RoomPlan capture stopped with an error: \(errorDescription)"))
      continuation?.finish()
      return
    }

    let builder = RoomBuilder(options: [.beautifyObjects])
    var builtRoom: CapturedRoom?
    var roomBuildError: String?
    do {
      builtRoom = try await builder.capturedRoom(from: data)
    } catch {
      roomBuildError = error.localizedDescription
    }

    if let builtRoom {
      capturedRooms.append(builtRoom)
    }

    switch intent {
    case .addNextRoom:
      if builtRoom == nil {
        progress.isProcessingRoom = false
        progress.statusBanner = "Could not finalize room yet (\(roomBuildError ?? "scan more walls")). Keep scanning."
        uiState.segmentToken = UUID()
        continuation?.yield(.progressUpdated(progress))
        return
      }
      let completedCount = capturedRooms.count
      progress = RoomScanLiveProgress(
        currentRoomNumber: completedCount + 1,
        completedRoomCount: completedCount,
        liveWallCount: 0,
        liveDoorwayCount: 0,
        liveObjectCount: 0,
        coachingInstruction: "Walk through an open doorway into Room \(completedCount + 1) on the same floor",
        isProcessingRoom: false,
        statusBanner: "Room \(completedCount) saved. Shared AR tracking active."
      )
      continuation?.yield(.roomAdded(completedCount: completedCount))
      continuation?.yield(.progressUpdated(progress))
      uiState.segmentToken = UUID()

    case .finalizeAllRooms, .none:
      sharedARSession.pause()
      uiState.isRunning = false

      guard !capturedRooms.isEmpty else {
        let message = roomBuildError ?? errorDescription ?? "Not enough room geometry was captured. Sweep walls and floors slowly under good lighting."
        continuation?.yield(.failed(message))
        continuation?.finish()
        return
      }

      var notes: [String] = []
      if builtRoom == nil, let roomBuildError {
        notes.append("Skipped trailing incomplete room segment (\(roomBuildError)); kept \(capturedRooms.count) completed room(s).")
      }

      let capture = await buildSceneCapture(from: capturedRooms, extraNotes: notes)
      continuation?.yield(.completed(capture))
      continuation?.finish()

    case .cancelled:
      break
    }
  }

  private func buildSceneCapture(
    from rooms: [CapturedRoom],
    extraNotes: [String]
  ) async -> ScannedSceneCapture {
    let convertedRooms = rooms.enumerated().map { index, room in
      RoomPlanAdapter.convertRoom(room, index: index)
    }

    if rooms.count == 1 {
      return ScannedSceneCapture(
        capturedAt: Date(),
        rooms: convertedRooms,
        mergedSurfaces: nil,
        mergedObjects: nil,
        source: .singleRoom,
        notes: extraNotes
      )
    }

    let structureBuilder = StructureBuilder(options: [.beautifyObjects])
    do {
      let structure = try await structureBuilder.capturedStructure(from: rooms)
      return RoomPlanAdapter.convertStructure(
        structure,
        fallbackRooms: convertedRooms,
        notes: extraNotes
      )
    } catch {
      var fallbackNotes = extraNotes
      fallbackNotes.append(
        "StructureBuilder merge fell back to shared-ARSession alignment (\(error.localizedDescription))."
      )
      return ScannedSceneCapture(
        capturedAt: Date(),
        rooms: convertedRooms,
        mergedSurfaces: nil,
        mergedObjects: nil,
        source: .fallbackMultiRoomUnion,
        notes: fallbackNotes
      )
    }
  }
}

private struct LiveRoomCaptureHostContainer: View {
  let driver: LiveRoomCaptureDriver
  var uiState: LiveRoomPlanSessionState

  var body: some View {
    LiveRoomCaptureRepresentable(driver: driver)
      .id(uiState.segmentToken)
      .ignoresSafeArea()
  }
}

private struct LiveRoomCaptureRepresentable: UIViewRepresentable {
  let driver: LiveRoomCaptureDriver

  func makeUIView(context: Context) -> RoomCaptureView {
    driver.mountCaptureView()
  }

  func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

@objc(MicroduckRoomCaptureViewDelegateBridge)
private final class CaptureViewDelegateBridge: NSObject, RoomCaptureViewDelegate, @unchecked Sendable {
  override init() {
    super.init()
  }

  required init?(coder: NSCoder) {
    super.init()
  }

  func encode(with coder: NSCoder) {}

  nonisolated func captureView(
    shouldPresent roomDataForProcessing: CapturedRoomData,
    error: (any Error)?
  ) -> Bool {
    false
  }

  nonisolated func captureView(
    didPresent processedResult: CapturedRoom,
    error: (any Error)?
  ) {}
}

private final class CaptureSessionDelegateBridge: NSObject, RoomCaptureSessionDelegate, @unchecked Sendable {
  let onLiveCounts: @Sendable (Int, Int, Int) -> Void
  let onInstruction: @Sendable (String?) -> Void
  let onDidEnd: @Sendable (CapturedRoomData, String?) -> Void

  init(
    onLiveCounts: @escaping @Sendable (Int, Int, Int) -> Void,
    onInstruction: @escaping @Sendable (String?) -> Void,
    onDidEnd: @escaping @Sendable (CapturedRoomData, String?) -> Void
  ) {
    self.onLiveCounts = onLiveCounts
    self.onInstruction = onInstruction
    self.onDidEnd = onDidEnd
  }

  nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
    let walls = room.walls.count
    let doorways = room.doors.count + room.openings.count
    let objects = room.objects.count
    onLiveCounts(walls, doorways, objects)
  }

  nonisolated func captureSession(
    _ session: RoomCaptureSession,
    didProvide instruction: RoomCaptureSession.Instruction
  ) {
    let text: String?
    switch instruction {
    case .moveCloseToWall:
      text = "Move closer to the wall"
    case .moveAwayFromWall:
      text = "Step slightly back from the wall"
    case .slowDown:
      text = "Move your iPhone more slowly"
    case .turnOnLight:
      text = "Turn on more light for LiDAR + camera tracking"
    case .lowTexture:
      text = "Aim toward edges, corners, or textured surfaces"
    case .normal:
      text = nil
    @unknown default:
      text = nil
    }
    onInstruction(text)
  }

  nonisolated func captureSession(
    _ session: RoomCaptureSession,
    didEndWith data: CapturedRoomData,
    error: (any Error)?
  ) {
    onDidEnd(data, error?.localizedDescription)
  }
}

enum RoomPlanAdapter {
  static func convertRoom(_ room: CapturedRoom, index: Int) -> ScannedRoom {
    let sectionLabel = room.sections.first.map { String(describing: $0.label) }
    let displayName: String
    if let sectionLabel, !sectionLabel.isEmpty, sectionLabel != "unidentified" {
      displayName = sectionLabel.capitalized
    } else {
      displayName = "Room \(index + 1)"
    }

    let surfaces = convertSurfaces(
      walls: room.walls,
      doors: room.doors,
      openings: room.openings,
      windows: room.windows,
      floors: room.floors
    )
    let objects = room.objects.map(convertObject)
    let roomStory = surfaces.compactMap(\.story).first

    return ScannedRoom(
      id: room.identifier,
      name: displayName,
      story: roomStory,
      surfaces: surfaces,
      objects: objects
    )
  }

  static func convertStructure(
    _ structure: CapturedStructure,
    fallbackRooms: [ScannedRoom],
    notes: [String]
  ) -> ScannedSceneCapture {
    let convertedRooms: [ScannedRoom]
    if structure.rooms.isEmpty {
      convertedRooms = fallbackRooms
    } else {
      convertedRooms = structure.rooms.enumerated().map { idx, room in
        convertRoom(room, index: idx)
      }
    }

    let mergedSurfaces = convertSurfaces(
      walls: structure.walls,
      doors: structure.doors,
      openings: structure.openings,
      windows: structure.windows,
      floors: structure.floors
    )
    let mergedObjects = structure.objects.map(convertObject)

    return ScannedSceneCapture(
      id: structure.identifier,
      capturedAt: Date(),
      rooms: convertedRooms,
      mergedSurfaces: mergedSurfaces,
      mergedObjects: mergedObjects,
      source: .mergedStructure,
      notes: notes
    )
  }

  private static func convertSurfaces(
    walls: [CapturedRoom.Surface],
    doors: [CapturedRoom.Surface],
    openings: [CapturedRoom.Surface],
    windows: [CapturedRoom.Surface],
    floors: [CapturedRoom.Surface]
  ) -> [ScannedSurface] {
    (walls + doors + openings + windows + floors).compactMap(convertSurface)
  }

  private static func convertSurface(_ surface: CapturedRoom.Surface) -> ScannedSurface? {
    let category: ScannedSurfaceCategory
    switch surface.category {
    case .wall:
      category = .wall
    case .opening:
      category = .opening
    case let .door(isOpen):
      category = .door(isOpen: isOpen)
    case .window:
      category = .window
    case .floor:
      category = .floor
    @unknown default:
      return nil
    }

    let arcCurve = surface.curve.map { curve in
      ScannedArcCurve(
        radius: curve.radius,
        startAngleRadians: Float(curve.startAngle.converted(to: .radians).value),
        endAngleRadians: Float(curve.endAngle.converted(to: .radians).value)
      )
    }

    return ScannedSurface(
      id: surface.identifier,
      category: category,
      transform: RoomTransform(surface.transform),
      dimensions: surface.dimensions,
      polygonCorners: surface.polygonCorners,
      parentIdentifier: surface.parentIdentifier,
      curve: arcCurve,
      story: surface.story,
      confidence: convertConfidence(surface.confidence)
    )
  }

  private static func convertObject(_ object: CapturedRoom.Object) -> ScannedObject {
    let category: ScannedObjectCategory
    switch object.category {
    case .storage: category = .storage
    case .refrigerator: category = .refrigerator
    case .stove: category = .stove
    case .bed: category = .bed
    case .sink: category = .sink
    case .washerDryer: category = .washerDryer
    case .toilet: category = .toilet
    case .bathtub: category = .bathtub
    case .oven: category = .oven
    case .dishwasher: category = .dishwasher
    case .table: category = .table
    case .sofa: category = .sofa
    case .chair: category = .chair
    case .fireplace: category = .fireplace
    case .television: category = .television
    case .stairs: category = .stairs
    @unknown default: category = .other
    }

    var shapeHint: ScannedObjectShape = .box
    if object.attribute(of: TableShapeType.self) == .circularElliptic {
      shapeHint = .circularCylinder
    } else if object.attribute(of: ChairType.self) == .stool {
      shapeHint = .circularCylinder
    }

    return ScannedObject(
      id: object.identifier,
      category: category,
      shapeHint: shapeHint,
      transform: RoomTransform(object.transform),
      dimensions: object.dimensions,
      story: object.story,
      confidence: convertConfidence(object.confidence)
    )
  }

  private static func convertConfidence(_ confidence: CapturedRoom.Confidence) -> ScannedConfidence {
    switch confidence {
    case .low:
      .low
    case .medium:
      .medium
    case .high:
      .high
    @unknown default:
      .medium
    }
  }
}
#endif

extension RoomScanClient: DependencyKey {
  public static var liveValue: RoomScanClient {
    RoomScanClient(
      deviceSupport: {
        #if targetEnvironment(simulator)
        return .unsupportedSimulator
        #elseif canImport(RoomPlan) && os(iOS)
        return RoomCaptureSession.isSupported ? .supported : .unsupportedHardware
        #else
        return .unsupportedPlatform
        #endif
      },
      cameraAuthorization: {
        #if canImport(AVFoundation) && os(iOS)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
          return .notDetermined
        case .authorized:
          return .authorized
        case .denied:
          return .denied
        case .restricted:
          return .restricted
        @unknown default:
          return .denied
        }
        #else
        return .authorized
        #endif
      },
      requestCameraAccess: {
        #if canImport(AVFoundation) && os(iOS)
        return await AVCaptureDevice.requestAccess(for: .video)
        #else
        return true
        #endif
      },
      openSystemSettings: {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        _ = await UIApplication.shared.open(url)
        #endif
      },
      makeCaptureDriver: {
        #if canImport(ARKit) && canImport(RoomPlan) && canImport(UIKit)
        return LiveRoomCaptureDriver()
        #else
        return PreviewRoomCaptureDriver()
        #endif
      },
      writeExportFile: { fileName, xml in
        let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("MicroduckScenes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(fileName)
        try Data(xml.utf8).write(to: fileURL, options: .atomic)
        return fileURL
      },
      copyToClipboard: { text in
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
      }
    )
  }
}
