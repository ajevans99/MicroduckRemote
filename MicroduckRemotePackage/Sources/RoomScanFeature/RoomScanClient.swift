import Dependencies
import Foundation
import SwiftUI

public enum RoomScanDeviceSupport: String, Sendable, Equatable {
  case supported
  case unsupportedSimulator
  case unsupportedHardware
  case unsupportedPlatform

  public var isSupported: Bool {
    self == .supported
  }

  public var title: String {
    switch self {
    case .supported:
      "LiDAR + Camera Ready"
    case .unsupportedSimulator:
      "Physical LiDAR iPhone Required"
    case .unsupportedHardware:
      "LiDAR Scanner Not Available"
    case .unsupportedPlatform:
      "RoomPlan Requires iOS"
    }
  }

  public var message: String {
    switch self {
    case .supported:
      "This device supports on-device Apple RoomPlan capture with camera and LiDAR."
    case .unsupportedSimulator:
      "iOS Simulator cannot access a physical camera or LiDAR scanner. Run on a LiDAR-equipped iPhone Pro or iPad Pro to scan real rooms, or load the sample apartment below to preview and export MuJoCo XML."
    case .unsupportedHardware:
      "Apple RoomPlan requires both the rear camera and LiDAR scanner (iPhone 12 Pro or newer Pro models, or LiDAR iPad Pro). You can still preview and export the sample apartment scene."
    case .unsupportedPlatform:
      "Live RoomPlan capture runs on LiDAR-equipped iOS devices. Sample scenes can still be previewed and exported."
    }
  }
}

public enum CameraAuthorizationState: String, Sendable, Equatable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

public struct RoomScanLiveProgress: Sendable, Equatable {
  public var currentRoomNumber: Int
  public var completedRoomCount: Int
  public var liveWallCount: Int
  public var liveDoorwayCount: Int
  public var liveObjectCount: Int
  public var coachingInstruction: String?
  public var isProcessingRoom: Bool
  public var statusBanner: String?

  public init(
    currentRoomNumber: Int = 1,
    completedRoomCount: Int = 0,
    liveWallCount: Int = 0,
    liveDoorwayCount: Int = 0,
    liveObjectCount: Int = 0,
    coachingInstruction: String? = nil,
    isProcessingRoom: Bool = false,
    statusBanner: String? = nil
  ) {
    self.currentRoomNumber = currentRoomNumber
    self.completedRoomCount = completedRoomCount
    self.liveWallCount = liveWallCount
    self.liveDoorwayCount = liveDoorwayCount
    self.liveObjectCount = liveObjectCount
    self.coachingInstruction = coachingInstruction
    self.isProcessingRoom = isProcessingRoom
    self.statusBanner = statusBanner
  }
}

public enum RoomScanSessionEvent: Sendable, Equatable {
  case progressUpdated(RoomScanLiveProgress)
  case roomAdded(completedCount: Int)
  case completed(ScannedSceneCapture)
  case failed(String)
}

@MainActor
public protocol RoomCaptureDriver: AnyObject {
  func events() -> AsyncStream<RoomScanSessionEvent>
  func startNewSession()
  func finishCurrentRoomAndStartNext()
  func finishAllRoomsAndBuild()
  func cancel()
  func makeCaptureView() -> AnyView
}

public struct RoomScanClient: Sendable {
  public var deviceSupport: @Sendable () -> RoomScanDeviceSupport
  public var cameraAuthorization: @Sendable () -> CameraAuthorizationState
  public var requestCameraAccess: @Sendable () async -> Bool
  public var openSystemSettings: @Sendable @MainActor () async -> Void
  public var makeCaptureDriver: @Sendable @MainActor () -> any RoomCaptureDriver
  public var writeExportFile: @Sendable (_ fileName: String, _ xml: String) throws -> URL
  public var copyToClipboard: @Sendable @MainActor (_ text: String) -> Void

  public init(
    deviceSupport: @escaping @Sendable () -> RoomScanDeviceSupport,
    cameraAuthorization: @escaping @Sendable () -> CameraAuthorizationState,
    requestCameraAccess: @escaping @Sendable () async -> Bool,
    openSystemSettings: @escaping @Sendable @MainActor () async -> Void,
    makeCaptureDriver: @escaping @Sendable @MainActor () -> any RoomCaptureDriver,
    writeExportFile: @escaping @Sendable (_ fileName: String, _ xml: String) throws -> URL,
    copyToClipboard: @escaping @Sendable @MainActor (_ text: String) -> Void
  ) {
    self.deviceSupport = deviceSupport
    self.cameraAuthorization = cameraAuthorization
    self.requestCameraAccess = requestCameraAccess
    self.openSystemSettings = openSystemSettings
    self.makeCaptureDriver = makeCaptureDriver
    self.writeExportFile = writeExportFile
    self.copyToClipboard = copyToClipboard
  }
}

@MainActor
public final class PreviewRoomCaptureDriver: RoomCaptureDriver {
  private var continuation: AsyncStream<RoomScanSessionEvent>.Continuation?
  private var completedCount = 0

  public init() {}

  public func events() -> AsyncStream<RoomScanSessionEvent> {
    AsyncStream { continuation in
      self.continuation = continuation
    }
  }

  public func startNewSession() {
    completedCount = 0
    continuation?.yield(
      .progressUpdated(
        RoomScanLiveProgress(
          currentRoomNumber: 1,
          completedRoomCount: 0,
          liveWallCount: 4,
          liveDoorwayCount: 1,
          liveObjectCount: 2,
          coachingInstruction: "Sweep walls, floors, and open doorways slowly"
        )
      )
    )
  }

  public func finishCurrentRoomAndStartNext() {
    completedCount += 1
    continuation?.yield(.roomAdded(completedCount: completedCount))
    continuation?.yield(
      .progressUpdated(
        RoomScanLiveProgress(
          currentRoomNumber: completedCount + 1,
          completedRoomCount: completedCount,
          liveWallCount: 3,
          liveDoorwayCount: 1,
          liveObjectCount: 3,
          coachingInstruction: "Walk through the open doorway to scan Room \(completedCount + 1)",
          statusBanner: "Room \(completedCount) saved in shared AR world frame"
        )
      )
    )
  }

  public func finishAllRoomsAndBuild() {
    continuation?.yield(.completed(.sampleTwoRoomApartment))
    continuation?.finish()
  }

  public func cancel() {
    continuation?.finish()
  }

  public func makeCaptureView() -> AnyView {
    AnyView(
      ZStack {
        LinearGradient(
          colors: [Color(red: 0.08, green: 0.13, blue: 0.20), Color(red: 0.04, green: 0.07, blue: 0.11)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        VStack(spacing: 12) {
          Image(systemName: "camera.metering.matrix")
            .font(.system(size: 48, weight: .light))
            .foregroundStyle(.cyan)
          Text("RoomPlan Preview Feed")
            .font(.headline)
            .foregroundStyle(.white)
          Text("Shared ARSession active")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
      }
    )
  }
}

extension RoomScanClient: TestDependencyKey {
  public static var previewValue: RoomScanClient {
    RoomScanClient(
      deviceSupport: { .supported },
      cameraAuthorization: { .authorized },
      requestCameraAccess: { true },
      openSystemSettings: {},
      makeCaptureDriver: { PreviewRoomCaptureDriver() },
      writeExportFile: { fileName, xml in
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MicroduckScenes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(fileName)
        try Data(xml.utf8).write(to: fileURL, options: .atomic)
        return fileURL
      },
      copyToClipboard: { _ in }
    )
  }

  public static var testValue: RoomScanClient {
    previewValue
  }
}

extension DependencyValues {
  public var roomScan: RoomScanClient {
    get { self[RoomScanClient.self] }
    set { self[RoomScanClient.self] = newValue }
  }
}
