import Dependencies
import DuckDependencies
import Foundation
import IssueReporting
import Observation
import SwiftUI
import UniformTypeIdentifiers

public struct MJCFXMLDocument: FileDocument, Sendable, Equatable {
  public static let readableContentTypes: [UTType] = [.xml]

  public var xml: String

  public init(xml: String = "") {
    self.xml = xml
  }

  public init(configuration: ReadConfiguration) throws {
    if let data = configuration.file.regularFileContents,
       let string = String(data: data, encoding: .utf8) {
      xml = string
    } else {
      xml = ""
    }
  }

  public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(xml.utf8))
  }
}

public struct XMLInspectorSheetModel: Identifiable, Sendable, Equatable {
  public let id = UUID()
  public var fileName: String
  public var xml: String
  public var lineCount: Int
  public var byteCount: Int

  public init(fileName: String, xml: String) {
    self.fileName = fileName
    self.xml = xml
    self.lineCount = xml.split(separator: "\n", omittingEmptySubsequences: false).count
    self.byteCount = xml.utf8.count
  }
}

@Observable
@MainActor
public final class RoomScanModel {
  public enum Phase: Equatable {
    case idle
    case scanning
    case review
  }

  @ObservationIgnored @Dependency(\.roomScan) var roomScan
  @ObservationIgnored @Dependency(\.iCloudSceneSync) var iCloudSceneSync
  @ObservationIgnored @Dependency(\.haptics) var haptics
  @ObservationIgnored @Dependency(\.date.now) var now

  public var phase: Phase = .idle
  public var deviceSupport: RoomScanDeviceSupport = .supported
  public var cameraAuthorization: CameraAuthorizationState = .notDetermined
  public var isRequestingPermission = false
  public var liveProgress = RoomScanLiveProgress()
  public var currentCapture: ScannedSceneCapture?
  public var exportConfiguration = MJCFExportConfiguration() {
    didSet {
      guard exportConfiguration != oldValue else { return }
      rebuildExportResult()
    }
  }
  public var exportResult: MJCFExportResult?
  public var shareFileURL: URL?
  public var isFileExporterPresented = false
  public var isFolderImporterPresented = false
  public var xmlInspectorSheet: XMLInspectorSheetModel?
  public var iCloudAvailability: ICloudSceneSyncAvailability = .needsFolderSelection
  public var syncedScenes: [SyncedSceneRecord] = []
  public var isSyncingToICloud = false
  public var isLoadingSyncedScenes = false
  public var statusToast: String?
  public var errorMessage: String?

  @ObservationIgnored private var activeDriver: (any RoomCaptureDriver)?
  @ObservationIgnored private var pendingSaveAfterFolderSelection = false

  public init() {}

  public var canStartHardwareScan: Bool {
    deviceSupport.isSupported && cameraAuthorization == .authorized
  }

  public var needsPermissionRequest: Bool {
    deviceSupport.isSupported && cameraAuthorization == .notDetermined
  }

  public var isPermissionDeniedOrRestricted: Bool {
    deviceSupport.isSupported && (cameraAuthorization == .denied || cameraAuthorization == .restricted)
  }

  public var exportDocument: MJCFXMLDocument {
    MJCFXMLDocument(xml: exportResult?.xml ?? "")
  }

  public func onAppear() {
    refreshCapabilities()
  }

  public func refreshCapabilities() {
    deviceSupport = roomScan.deviceSupport()
    cameraAuthorization = roomScan.cameraAuthorization()
  }

  public func requestCameraPermissionButtonTapped() async {
    isRequestingPermission = true
    errorMessage = nil

    let granted = await roomScan.requestCameraAccess()
    isRequestingPermission = false
    cameraAuthorization = granted ? .authorized : roomScan.cameraAuthorization()
    if granted {
      haptics.success()
      await startScanButtonTapped()
    } else {
      haptics.warning()
    }
  }

  public func openSettingsButtonTapped() async {
    haptics.selectionChanged()
    await roomScan.openSystemSettings()
    refreshCapabilities()
  }

  public func startScanButtonTapped() async {
    refreshCapabilities()
    errorMessage = nil
    statusToast = nil

    guard deviceSupport.isSupported else {
      errorMessage = deviceSupport.message
      haptics.warning()
      return
    }

    if cameraAuthorization == .notDetermined {
      await requestCameraPermissionButtonTapped()
      return
    }

    guard cameraAuthorization == .authorized else {
      errorMessage = "Camera permission is required for RoomPlan scanning. Enable Camera access in Settings."
      haptics.warning()
      return
    }

    activeDriver?.cancel()
    let driver = roomScan.makeCaptureDriver()
    activeDriver = driver
    liveProgress = RoomScanLiveProgress()
    phase = .scanning
    haptics.impactMedium()

    let stream = driver.events()
    driver.startNewSession()

    for await event in stream {
      guard !Task.isCancelled else { break }
      handleDriverEvent(event)
    }
  }

  public func addNextRoomButtonTapped() {
    guard phase == .scanning, !liveProgress.isProcessingRoom else { return }
    haptics.selectionChanged()
    activeDriver?.finishCurrentRoomAndStartNext()
  }

  public func finishScanButtonTapped() {
    guard phase == .scanning, !liveProgress.isProcessingRoom else { return }
    haptics.impactMedium()
    activeDriver?.finishAllRoomsAndBuild()
  }

  public func cancelScanButtonTapped() {
    haptics.selectionChanged()
    activeDriver?.cancel()
    activeDriver = nil
    phase = currentCapture == nil ? .idle : .review
  }

  public func loadSampleApartmentButtonTapped() {
    haptics.selectionChanged()
    errorMessage = nil
    statusToast = nil
    let sample = ScannedSceneCapture.sampleTwoRoomApartment
    if exportConfiguration.sceneName == "scanned_room" {
      exportConfiguration.sceneName = "my_apartment"
    }
    applyCapture(sample)
  }

  public func newScanButtonTapped() async {
    haptics.selectionChanged()
    statusToast = nil
    errorMessage = nil
    if canStartHardwareScan {
      await startScanButtonTapped()
    } else {
      phase = .idle
      refreshCapabilities()
    }
  }

  public func exportToFilesButtonTapped() {
    guard exportResult != nil else { return }
    haptics.selectionChanged()
    statusToast = nil
    errorMessage = nil
    isFileExporterPresented = true
  }

  public func fileExporterCompleted(_ result: Result<URL, any Error>) {
    switch result {
    case let .success(url):
      haptics.success()
      statusToast = "Saved \(url.lastPathComponent)"
    case let .failure(error):
      haptics.warning()
      errorMessage = "Could not save XML file: \(error.localizedDescription)"
    }
  }

  public func inspectXMLButtonTapped() {
    guard let exportResult else { return }
    haptics.selectionChanged()
    xmlInspectorSheet = XMLInspectorSheetModel(
      fileName: exportResult.configuration.fileName,
      xml: exportResult.xml
    )
  }

  public func copyLaunchCommandButtonTapped() {
    guard let command = exportResult?.configuration.duckSimCommand else { return }
    roomScan.copyToClipboard(command)
    haptics.success()
    statusToast = "Copied duck-sim command"
  }

  public func copyRawXMLButtonTapped() {
    guard let xml = exportResult?.xml else { return }
    roomScan.copyToClipboard(xml)
    haptics.success()
    statusToast = "Copied MJCF XML to clipboard"
  }

  public func refreshSyncedScenes() async {
    isLoadingSyncedScenes = true
    defer { isLoadingSyncedScenes = false }
    iCloudAvailability = await iCloudSceneSync.checkAvailability()
    do {
      syncedScenes = try await iCloudSceneSync.listScenes()
    } catch {
      errorMessage = "Could not list synced scenes: \(error.localizedDescription)"
    }
  }

  public func chooseSyncedFolderButtonTapped() {
    haptics.selectionChanged()
    errorMessage = nil
    pendingSaveAfterFolderSelection = false
    isFolderImporterPresented = true
  }

  public func clearSyncedFolderButtonTapped() async {
    haptics.selectionChanged()
    errorMessage = nil
    await iCloudSceneSync.clearSyncedFolder()
    await refreshSyncedScenes()
    statusToast = "Disconnected synced folder"
  }

  public func folderImporterCompleted(_ result: Result<[URL], any Error>) async {
    let shouldSaveAfter = pendingSaveAfterFolderSelection
    pendingSaveAfterFolderSelection = false
    switch result {
    case let .success(urls):
      guard let folderURL = urls.first else { return }
      do {
        let folderName = try await iCloudSceneSync.setSyncedFolder(folderURL)
        await refreshSyncedScenes()
        haptics.success()
        if shouldSaveAfter {
          await performSaveToICloud()
        } else {
          statusToast = "Connected iCloud Drive folder: \(folderName)"
        }
      } catch {
        haptics.warning()
        errorMessage = "Could not connect folder: \(error.localizedDescription)"
      }
    case let .failure(error):
      haptics.warning()
      errorMessage = "Could not select iCloud Drive folder: \(error.localizedDescription)"
    }
  }

  public func saveToICloudButtonTapped() async {
    guard exportResult != nil else { return }
    errorMessage = nil
    statusToast = nil
    iCloudAvailability = await iCloudSceneSync.checkAvailability()
    if !iCloudAvailability.isConnected {
      pendingSaveAfterFolderSelection = true
      isFolderImporterPresented = true
      return
    }
    await performSaveToICloud()
  }

  private func performSaveToICloud() async {
    guard let exportResult else { return }
    isSyncingToICloud = true
    errorMessage = nil
    statusToast = nil
    defer { isSyncingToICloud = false }

    let metadata = SyncedSceneMetadata(
      slug: exportResult.configuration.sceneSlug,
      displayName: SyncedSceneMetadata.displayName(
        fromSceneName: exportResult.configuration.sceneName,
        slug: exportResult.configuration.sceneSlug
      ),
      roomCount: exportResult.summary.roomCount,
      obstacleCount: exportResult.geoms.count(where: \.hasCollision),
      exportedAt: now
    )

    do {
      let syncResult = try await iCloudSceneSync.saveScene(exportResult.xml, metadata)
      iCloudAvailability = await iCloudSceneSync.checkAvailability()
      syncedScenes = try await iCloudSceneSync.listScenes()
      if syncResult.usedLocalFallback {
        haptics.warning()
      } else {
        haptics.success()
      }
      statusToast = syncResult.statusMessage
    } catch {
      haptics.warning()
      errorMessage = "Could not sync scene to iCloud Drive: \(error.localizedDescription)"
    }
  }

  public func inspectSyncedSceneButtonTapped(_ record: SyncedSceneRecord) async {
    errorMessage = nil
    do {
      let xml = try await iCloudSceneSync.readSceneXML(record)
      haptics.selectionChanged()
      xmlInspectorSheet = XMLInspectorSheetModel(fileName: record.fileName, xml: xml)
    } catch {
      haptics.warning()
      errorMessage = "Could not read \(record.fileName): \(error.localizedDescription)"
    }
  }

  public func deleteSyncedSceneButtonTapped(_ record: SyncedSceneRecord) async {
    errorMessage = nil
    statusToast = nil
    do {
      try await iCloudSceneSync.deleteScene(record)
      syncedScenes.removeAll { $0.id == record.id }
      haptics.selectionChanged()
      statusToast = "Deleted \(record.fileName)"
    } catch {
      haptics.warning()
      errorMessage = "Could not delete \(record.fileName): \(error.localizedDescription)"
    }
  }

  public func makeActiveCaptureView() -> AnyView {
    if let activeDriver {
      return activeDriver.makeCaptureView()
    }
    return AnyView(Color.black)
  }

  private func handleDriverEvent(_ event: RoomScanSessionEvent) {
    switch event {
    case let .progressUpdated(updated):
      liveProgress = updated
    case .roomAdded:
      haptics.success()
    case let .completed(capture):
      haptics.success()
      activeDriver = nil
      if exportConfiguration.sceneName == "scanned_room", capture.rooms.count > 1 {
        exportConfiguration.sceneName = "scanned_apartment"
      }
      applyCapture(capture)
    case let .failed(message):
      haptics.warning()
      activeDriver = nil
      errorMessage = message
      phase = currentCapture == nil ? .idle : .review
    }
  }

  private func applyCapture(_ capture: ScannedSceneCapture) {
    currentCapture = capture
    phase = .review
    rebuildExportResult()
  }

  private func rebuildExportResult() {
    guard let currentCapture else {
      exportResult = nil
      shareFileURL = nil
      return
    }
    let result = MJCFSceneExporter.export(
      capture: currentCapture,
      configuration: exportConfiguration
    )
    exportResult = result
    shareFileURL = withErrorReporting {
      try roomScan.writeExportFile(result.configuration.fileName, result.xml)
    }
  }
}
