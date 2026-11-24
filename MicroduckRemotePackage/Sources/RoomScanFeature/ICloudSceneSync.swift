import Dependencies
import Foundation

public enum ICloudSceneSyncConstants {
  public static let recommendedFolderName = "Microduck Scenes"
  public static let containerIdentifier = "iCloud.dev.ajevans.microduckremote"
  public static let documentsDirectoryName = "Documents"
  public static let scenesDirectoryName = "Scenes"
  public static let localFallbackDirectoryName = "MicroduckSyncedScenes"
  public static let folderBookmarkDefaultsKey = "dev.ajevans.microduckremote.syncedScenesFolderBookmark"
}

public struct SyncedSceneMetadata: Codable, Sendable, Equatable, Hashable {
  public var slug: String
  public var displayName: String
  public var roomCount: Int
  public var obstacleCount: Int
  public var exportedAt: Date

  public init(
    slug: String,
    displayName: String,
    roomCount: Int,
    obstacleCount: Int,
    exportedAt: Date
  ) {
    self.slug = slug
    self.displayName = displayName
    self.roomCount = roomCount
    self.obstacleCount = obstacleCount
    self.exportedAt = exportedAt
  }

  public static func displayName(fromSceneName sceneName: String, slug: String) -> String {
    let trimmed = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty,
       !trimmed.hasPrefix("scene_"),
       !trimmed.hasSuffix(".xml"),
       trimmed.contains(" ") || trimmed.contains(where: \.isUppercase) {
      return trimmed
    }
    return slug
      .split(separator: "_")
      .map { segment in
        guard let first = segment.first else { return "" }
        return String(first).uppercased() + segment.dropFirst()
      }
      .joined(separator: " ")
  }
}

public enum SyncedSceneStorageLocation: String, Codable, Sendable, Equatable, Hashable {
  case syncedFolder
  case iCloudDrive
  case localFallback

  public var badgeLabel: String {
    switch self {
    case .syncedFolder:
      "iCloud Folder"
    case .iCloudDrive:
      "iCloud Drive"
    case .localFallback:
      "Local Only"
    }
  }
}

public struct SyncedSceneRecord: Identifiable, Sendable, Equatable, Hashable {
  public var id: String { metadata.slug }
  public var metadata: SyncedSceneMetadata
  public var xmlURL: URL
  public var metadataURL: URL?
  public var fileSizeBytes: Int64
  public var storageLocation: SyncedSceneStorageLocation

  public var fileName: String {
    "scene_\(metadata.slug).xml"
  }

  public init(
    metadata: SyncedSceneMetadata,
    xmlURL: URL,
    metadataURL: URL?,
    fileSizeBytes: Int64,
    storageLocation: SyncedSceneStorageLocation
  ) {
    self.metadata = metadata
    self.xmlURL = xmlURL
    self.metadataURL = metadataURL
    self.fileSizeBytes = fileSizeBytes
    self.storageLocation = storageLocation
  }
}

public enum ICloudSceneSyncAvailability: Sendable, Equatable {
  case folderConnected(folderName: String)
  case available
  case needsFolderSelection

  public var isConnected: Bool {
    switch self {
    case .folderConnected, .available:
      true
    case .needsFolderSelection:
      false
    }
  }

  public var connectedFolderName: String? {
    switch self {
    case let .folderConnected(folderName):
      folderName
    case .available:
      "iCloud Drive"
    case .needsFolderSelection:
      nil
    }
  }
}

public struct ICloudSceneSyncResult: Sendable, Equatable {
  public var record: SyncedSceneRecord
  public var usedLocalFallback: Bool
  public var statusMessage: String

  public init(
    record: SyncedSceneRecord,
    usedLocalFallback: Bool,
    statusMessage: String
  ) {
    self.record = record
    self.usedLocalFallback = usedLocalFallback
    self.statusMessage = statusMessage
  }
}

public struct CoordinatedSceneFileStore: Sendable {
  public let directoryURL: URL
  public let storageLocation: SyncedSceneStorageLocation

  public init(
    directoryURL: URL,
    storageLocation: SyncedSceneStorageLocation
  ) {
    self.directoryURL = directoryURL
    self.storageLocation = storageLocation
  }

  public func save(
    xml: String,
    metadata: SyncedSceneMetadata
  ) throws -> SyncedSceneRecord {
    try Self.withSecurityScopedAccess(to: directoryURL) { scopedDirectory in
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: scopedDirectory, withIntermediateDirectories: true)

      let xmlURL = scopedDirectory.appendingPathComponent("scene_\(metadata.slug).xml", isDirectory: false)
      let jsonURL = scopedDirectory.appendingPathComponent("scene_\(metadata.slug).json", isDirectory: false)
      let xmlData = Data(xml.utf8)
      let jsonData = try Self.makeEncoder().encode(metadata)

      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinatorError: NSError?
      var writeError: (any Error)?
      coordinator.coordinate(
        writingItemAt: xmlURL,
        options: .forReplacing,
        writingItemAt: jsonURL,
        options: .forReplacing,
        error: &coordinatorError
      ) { coordinatedXMLURL, coordinatedJSONURL in
        do {
          try xmlData.write(to: coordinatedXMLURL, options: .atomic)
          try jsonData.write(to: coordinatedJSONURL, options: .atomic)
        } catch {
          writeError = error
        }
      }
      if let coordinatorError {
        throw coordinatorError
      }
      if let writeError {
        throw writeError
      }

      return SyncedSceneRecord(
        metadata: metadata,
        xmlURL: xmlURL,
        metadataURL: jsonURL,
        fileSizeBytes: Int64(xmlData.count),
        storageLocation: storageLocation
      )
    }
  }

  public func listScenes() throws -> [SyncedSceneRecord] {
    try Self.withSecurityScopedAccess(to: directoryURL) { scopedDirectory in
      let fileManager = FileManager.default
      guard fileManager.fileExists(atPath: scopedDirectory.path) else {
        return []
      }

      let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
      let contents = try fileManager.contentsOfDirectory(
        at: scopedDirectory,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles]
      )

      var records: [SyncedSceneRecord] = []
      for url in contents {
        guard let slug = Self.sceneSlug(fromXMLFileName: url.lastPathComponent) else {
          continue
        }
        if storageLocation != .localFallback {
          try? fileManager.startDownloadingUbiquitousItem(at: url)
        }
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let fileSize = Int64(values?.fileSize ?? 0)
        let fallbackDate = values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)

        let jsonURL = scopedDirectory.appendingPathComponent("scene_\(slug).json", isDirectory: false)
        let loadedMetadata = readMetadataIfPresent(at: jsonURL)
        let metadata = loadedMetadata ?? SyncedSceneMetadata(
          slug: slug,
          displayName: SyncedSceneMetadata.displayName(fromSceneName: "", slug: slug),
          roomCount: 0,
          obstacleCount: 0,
          exportedAt: fallbackDate
        )
        records.append(
          SyncedSceneRecord(
            metadata: metadata,
            xmlURL: url,
            metadataURL: loadedMetadata == nil ? nil : jsonURL,
            fileSizeBytes: fileSize,
            storageLocation: storageLocation
          )
        )
      }

      return records.sorted { lhs, rhs in
        if lhs.metadata.exportedAt != rhs.metadata.exportedAt {
          return lhs.metadata.exportedAt > rhs.metadata.exportedAt
        }
        return lhs.metadata.slug < rhs.metadata.slug
      }
    }
  }

  public func readXML(slug: String) throws -> String {
    try Self.withSecurityScopedAccess(to: directoryURL) { scopedDirectory in
      let xmlURL = scopedDirectory.appendingPathComponent("scene_\(slug).xml", isDirectory: false)
      if storageLocation != .localFallback {
        try? FileManager.default.startDownloadingUbiquitousItem(at: xmlURL)
      }
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinatorError: NSError?
      var readError: (any Error)?
      var loadedString: String?
      coordinator.coordinate(
        readingItemAt: xmlURL,
        options: [],
        error: &coordinatorError
      ) { coordinatedURL in
        do {
          let data = try Data(contentsOf: coordinatedURL)
          loadedString = String(decoding: data, as: UTF8.self)
        } catch {
          readError = error
        }
      }
      if let coordinatorError {
        throw coordinatorError
      }
      if let readError {
        throw readError
      }
      return loadedString ?? ""
    }
  }

  public func delete(slug: String) throws {
    try Self.withSecurityScopedAccess(to: directoryURL) { scopedDirectory in
      let fileManager = FileManager.default
      let xmlURL = scopedDirectory.appendingPathComponent("scene_\(slug).xml", isDirectory: false)
      let jsonURL = scopedDirectory.appendingPathComponent("scene_\(slug).json", isDirectory: false)

      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinatorError: NSError?
      var deleteError: (any Error)?
      coordinator.coordinate(
        writingItemAt: xmlURL,
        options: .forDeleting,
        writingItemAt: jsonURL,
        options: .forDeleting,
        error: &coordinatorError
      ) { coordinatedXMLURL, coordinatedJSONURL in
        do {
          if fileManager.fileExists(atPath: coordinatedXMLURL.path) {
            try fileManager.removeItem(at: coordinatedXMLURL)
          }
          if fileManager.fileExists(atPath: coordinatedJSONURL.path) {
            try fileManager.removeItem(at: coordinatedJSONURL)
          }
        } catch {
          deleteError = error
        }
      }
      if let coordinatorError {
        throw coordinatorError
      }
      if let deleteError {
        throw deleteError
      }
    }
  }

  public static func withSecurityScopedAccess<T>(
    to url: URL,
    _ body: (URL) throws -> T
  ) rethrows -> T {
    let didStart = url.startAccessingSecurityScopedResource()
    defer {
      if didStart {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try body(url)
  }

  public func xmlFileURL(forSlug slug: String) -> URL {
    directoryURL.appendingPathComponent("scene_\(slug).xml", isDirectory: false)
  }

  public func metadataFileURL(forSlug slug: String) -> URL {
    directoryURL.appendingPathComponent("scene_\(slug).json", isDirectory: false)
  }

  public static func sceneSlug(fromXMLFileName fileName: String) -> String? {
    guard fileName.hasPrefix("scene_"), fileName.hasSuffix(".xml") else {
      return nil
    }
    let startIndex = fileName.index(fileName.startIndex, offsetBy: 6)
    let endIndex = fileName.index(fileName.endIndex, offsetBy: -4)
    guard startIndex < endIndex else {
      return nil
    }
    return String(fileName[startIndex..<endIndex])
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: raw) {
        return date
      }
      let standard = ISO8601DateFormatter()
      standard.formatOptions = [.withInternetDateTime]
      if let date = standard.date(from: raw) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(raw)"
      )
    }
    return decoder
  }

  private func readMetadataIfPresent(at url: URL) -> SyncedSceneMetadata? {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    if storageLocation != .localFallback {
      try? fileManager.startDownloadingUbiquitousItem(at: url)
    }
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinatorError: NSError?
    var decoded: SyncedSceneMetadata?
    coordinator.coordinate(
      readingItemAt: url,
      options: [],
      error: &coordinatorError
    ) { coordinatedURL in
      guard let data = try? Data(contentsOf: coordinatedURL) else {
        return
      }
      decoded = try? Self.makeDecoder().decode(SyncedSceneMetadata.self, from: data)
    }
    return decoded
  }
}

public struct SecurityScopedFolderBookmarkStore: Sendable {
  public let defaultsKey: String

  public init(defaultsKey: String = ICloudSceneSyncConstants.folderBookmarkDefaultsKey) {
    self.defaultsKey = defaultsKey
  }

  public func saveBookmark(for folderURL: URL, defaults: UserDefaults = .standard) throws -> String {
    try CoordinatedSceneFileStore.withSecurityScopedAccess(to: folderURL) { scopedURL in
      #if os(macOS)
      let options: URL.BookmarkCreationOptions = [.withSecurityScope]
      #else
      let options: URL.BookmarkCreationOptions = [.minimalBookmark]
      #endif
      let data = try scopedURL.bookmarkData(
        options: options,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      defaults.set(data, forKey: defaultsKey)
      return scopedURL.lastPathComponent
    }
  }

  public func resolveBookmarkedFolder(defaults: UserDefaults = .standard) -> URL? {
    guard let data = defaults.data(forKey: defaultsKey) else {
      return nil
    }
    var isStale = false
    #if os(macOS)
    let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    let options: URL.BookmarkResolutionOptions = []
    #endif
    guard let resolvedURL = try? URL(
      resolvingBookmarkData: data,
      options: options,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      return nil
    }
    if isStale {
      _ = try? saveBookmark(for: resolvedURL, defaults: defaults)
    }
    return resolvedURL
  }

  public func clearBookmark(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: defaultsKey)
  }
}

public struct ICloudSceneSyncClient: Sendable {
  public var checkAvailability: @Sendable () async -> ICloudSceneSyncAvailability
  public var setSyncedFolder: @Sendable (_ folderURL: URL) async throws -> String
  public var clearSyncedFolder: @Sendable () async -> Void
  public var saveScene: @Sendable (_ xml: String, _ metadata: SyncedSceneMetadata) async throws -> ICloudSceneSyncResult
  public var listScenes: @Sendable () async throws -> [SyncedSceneRecord]
  public var readSceneXML: @Sendable (_ record: SyncedSceneRecord) async throws -> String
  public var deleteScene: @Sendable (_ record: SyncedSceneRecord) async throws -> Void

  public init(
    checkAvailability: @escaping @Sendable () async -> ICloudSceneSyncAvailability,
    setSyncedFolder: @escaping @Sendable (_ folderURL: URL) async throws -> String,
    clearSyncedFolder: @escaping @Sendable () async -> Void,
    saveScene: @escaping @Sendable (_ xml: String, _ metadata: SyncedSceneMetadata) async throws -> ICloudSceneSyncResult,
    listScenes: @escaping @Sendable () async throws -> [SyncedSceneRecord],
    readSceneXML: @escaping @Sendable (_ record: SyncedSceneRecord) async throws -> String,
    deleteScene: @escaping @Sendable (_ record: SyncedSceneRecord) async throws -> Void
  ) {
    self.checkAvailability = checkAvailability
    self.setSyncedFolder = setSyncedFolder
    self.clearSyncedFolder = clearSyncedFolder
    self.saveScene = saveScene
    self.listScenes = listScenes
    self.readSceneXML = readSceneXML
    self.deleteScene = deleteScene
  }
}

private enum LiveICloudSceneDirectoryResolver {
  static let bookmarkStore = SecurityScopedFolderBookmarkStore()

  static func resolveScenesStore() -> CoordinatedSceneFileStore {
    if let bookmarkedURL = bookmarkStore.resolveBookmarkedFolder() {
      return CoordinatedSceneFileStore(directoryURL: bookmarkedURL, storageLocation: .syncedFolder)
    }
    if let containerURL = FileManager.default.url(
      forUbiquityContainerIdentifier: ICloudSceneSyncConstants.containerIdentifier
    ) {
      let scenesURL = containerURL
        .appendingPathComponent(ICloudSceneSyncConstants.documentsDirectoryName, isDirectory: true)
        .appendingPathComponent(ICloudSceneSyncConstants.scenesDirectoryName, isDirectory: true)
      return CoordinatedSceneFileStore(directoryURL: scenesURL, storageLocation: .iCloudDrive)
    }
    return localFallbackStore()
  }

  static func store(for record: SyncedSceneRecord) -> CoordinatedSceneFileStore {
    switch record.storageLocation {
    case .syncedFolder:
      if let bookmarkedURL = bookmarkStore.resolveBookmarkedFolder() {
        return CoordinatedSceneFileStore(directoryURL: bookmarkedURL, storageLocation: .syncedFolder)
      }
      return CoordinatedSceneFileStore(
        directoryURL: record.xmlURL.deletingLastPathComponent(),
        storageLocation: .syncedFolder
      )
    case .iCloudDrive, .localFallback:
      return CoordinatedSceneFileStore(
        directoryURL: record.xmlURL.deletingLastPathComponent(),
        storageLocation: record.storageLocation
      )
    }
  }

  static func localFallbackStore() -> CoordinatedSceneFileStore {
    let baseURL =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let scenesURL = baseURL.appendingPathComponent(
      ICloudSceneSyncConstants.localFallbackDirectoryName,
      isDirectory: true
    )
    return CoordinatedSceneFileStore(directoryURL: scenesURL, storageLocation: .localFallback)
  }
}

extension ICloudSceneSyncClient: DependencyKey {
  public static var liveValue: ICloudSceneSyncClient {
    ICloudSceneSyncClient(
      checkAvailability: {
        await Task.detached(priority: .utility) {
          let store = LiveICloudSceneDirectoryResolver.resolveScenesStore()
          switch store.storageLocation {
          case .syncedFolder:
            return .folderConnected(folderName: store.directoryURL.lastPathComponent)
          case .iCloudDrive:
            return .available
          case .localFallback:
            return .needsFolderSelection
          }
        }.value
      },
      setSyncedFolder: { folderURL in
        try await Task.detached(priority: .userInitiated) {
          try LiveICloudSceneDirectoryResolver.bookmarkStore.saveBookmark(for: folderURL)
        }.value
      },
      clearSyncedFolder: {
        await Task.detached(priority: .utility) {
          LiveICloudSceneDirectoryResolver.bookmarkStore.clearBookmark()
        }.value
      },
      saveScene: { xml, metadata in
        try await Task.detached(priority: .userInitiated) {
          let store = LiveICloudSceneDirectoryResolver.resolveScenesStore()
          let record = try store.save(xml: xml, metadata: metadata)
          let usedFallback = store.storageLocation == .localFallback
          let statusMessage: String
          switch store.storageLocation {
          case .syncedFolder:
            statusMessage = "Saved \(record.fileName) to \(store.directoryURL.lastPathComponent)"
          case .iCloudDrive:
            statusMessage = "Synced \(record.fileName) to iCloud Drive"
          case .localFallback:
            statusMessage = "Saved \(record.fileName) locally"
          }
          return ICloudSceneSyncResult(
            record: record,
            usedLocalFallback: usedFallback,
            statusMessage: statusMessage
          )
        }.value
      },
      listScenes: {
        try await Task.detached(priority: .utility) {
          let primaryStore = LiveICloudSceneDirectoryResolver.resolveScenesStore()
          var combined = try primaryStore.listScenes()
          if primaryStore.storageLocation != .localFallback {
            let localRecords = (try? LiveICloudSceneDirectoryResolver.localFallbackStore().listScenes()) ?? []
            let primarySlugs = Set(combined.map(\.metadata.slug))
            combined.append(contentsOf: localRecords.filter { !primarySlugs.contains($0.metadata.slug) })
            combined.sort { lhs, rhs in
              if lhs.metadata.exportedAt != rhs.metadata.exportedAt {
                return lhs.metadata.exportedAt > rhs.metadata.exportedAt
              }
              return lhs.metadata.slug < rhs.metadata.slug
            }
          }
          return combined
        }.value
      },
      readSceneXML: { record in
        try await Task.detached(priority: .userInitiated) {
          let store = LiveICloudSceneDirectoryResolver.store(for: record)
          return try store.readXML(slug: record.metadata.slug)
        }.value
      },
      deleteScene: { record in
        try await Task.detached(priority: .userInitiated) {
          let store = LiveICloudSceneDirectoryResolver.store(for: record)
          try store.delete(slug: record.metadata.slug)
        }.value
      }
    )
  }

  public static var previewValue: ICloudSceneSyncClient {
    let previewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MicroduckPreviewICloudScenes",
      isDirectory: true
    )
    let store = CoordinatedSceneFileStore(directoryURL: previewDirectory, storageLocation: .syncedFolder)
    return ICloudSceneSyncClient(
      checkAvailability: { .folderConnected(folderName: ICloudSceneSyncConstants.recommendedFolderName) },
      setSyncedFolder: { url in url.lastPathComponent },
      clearSyncedFolder: {},
      saveScene: { xml, metadata in
        let record = try store.save(xml: xml, metadata: metadata)
        return ICloudSceneSyncResult(
          record: record,
          usedLocalFallback: false,
          statusMessage: "Saved \(record.fileName) to \(ICloudSceneSyncConstants.recommendedFolderName)"
        )
      },
      listScenes: {
        try store.listScenes()
      },
      readSceneXML: { record in
        try store.readXML(slug: record.metadata.slug)
      },
      deleteScene: { record in
        try store.delete(slug: record.metadata.slug)
      }
    )
  }

  public static var testValue: ICloudSceneSyncClient {
    previewValue
  }
}

extension DependencyValues {
  public var iCloudSceneSync: ICloudSceneSyncClient {
    get { self[ICloudSceneSyncClient.self] }
    set { self[ICloudSceneSyncClient.self] = newValue }
  }
}
