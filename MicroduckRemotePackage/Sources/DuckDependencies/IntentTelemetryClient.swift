import Dependencies
import DuckProtocol
import Foundation

public struct IntentTelemetryClient: Sendable {
  public var loadRecords: @Sendable () -> [IntentInvocationRecord]
  public var recordsStream: @Sendable () -> AsyncStream<[IntentInvocationRecord]>
  public var record: @Sendable (IntentInvocationRecord) -> Void
  public var clear: @Sendable () -> Void

  public init(
    loadRecords: @escaping @Sendable () -> [IntentInvocationRecord],
    recordsStream: @escaping @Sendable () -> AsyncStream<[IntentInvocationRecord]>,
    record: @escaping @Sendable (IntentInvocationRecord) -> Void,
    clear: @escaping @Sendable () -> Void
  ) {
    self.loadRecords = loadRecords
    self.recordsStream = recordsStream
    self.record = record
    self.clear = clear
  }
}

private final class LiveIntentTelemetryStore: @unchecked Sendable {
  static let shared = LiveIntentTelemetryStore()
  private static let storageKey = "microduck.intent.telemetry.v1"
  private static let maxEntries = 100

  private let lock = NSLock()
  private var records: [IntentInvocationRecord]
  private var subscribers: [UUID: AsyncStream<[IntentInvocationRecord]>.Continuation] = [:]

  private init() {
    self.records = Self.readFromDefaults()
  }

  private static func readFromDefaults() -> [IntentInvocationRecord] {
    guard
      let data = UserDefaults.microduckShared.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([IntentInvocationRecord].self, from: data)
    else {
      return []
    }
    return decoded
  }

  private static func writeToDefaults(_ records: [IntentInvocationRecord]) {
    if let data = try? JSONEncoder().encode(records) {
      UserDefaults.microduckShared.set(data, forKey: storageKey)
    }
  }

  func currentRecords() -> [IntentInvocationRecord] {
    lock.lock()
    defer { lock.unlock() }
    let persisted = Self.readFromDefaults()
    if !persisted.isEmpty || records.isEmpty {
      records = persisted
    }
    return records
  }

  func stream() -> AsyncStream<[IntentInvocationRecord]> {
    let id = UUID()
    let initial = currentRecords()
    return AsyncStream { continuation in
      lock.lock()
      subscribers[id] = continuation
      lock.unlock()

      continuation.yield(initial)
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.lock()
        self.subscribers.removeValue(forKey: id)
        self.lock.unlock()
      }
    }
  }

  func append(_ entry: IntentInvocationRecord) {
    lock.lock()
    var updated = Self.readFromDefaults()
    if updated.isEmpty && !records.isEmpty {
      updated = records
    }
    updated.insert(entry, at: 0)
    if updated.count > Self.maxEntries {
      updated.removeLast(updated.count - Self.maxEntries)
    }
    records = updated
    Self.writeToDefaults(updated)
    let continuations = Array(subscribers.values)
    lock.unlock()

    for continuation in continuations {
      continuation.yield(updated)
    }
  }

  func clearAll() {
    lock.lock()
    records = []
    UserDefaults.microduckShared.removeObject(forKey: Self.storageKey)
    let continuations = Array(subscribers.values)
    lock.unlock()

    for continuation in continuations {
      continuation.yield([])
    }
  }
}

extension IntentTelemetryClient: DependencyKey {
  public static var liveValue: IntentTelemetryClient {
    IntentTelemetryClient(
      loadRecords: {
        LiveIntentTelemetryStore.shared.currentRecords()
      },
      recordsStream: {
        LiveIntentTelemetryStore.shared.stream()
      },
      record: { entry in
        LiveIntentTelemetryStore.shared.append(entry)
      },
      clear: {
        LiveIntentTelemetryStore.shared.clearAll()
      }
    )
  }

  public static var previewValue: IntentTelemetryClient {
    let now = Date(timeIntervalSince1970: 1_795_150_000)
    let sampleRecords: [IntentInvocationRecord] = [
      IntentInvocationRecord(
        timestamp: now.addingTimeInterval(-12),
        kind: .toolIntent,
        intentName: "PerformDuckRoutineIntent",
        displayTitle: "Perform Duck Routine",
        isToolIntent: true,
        parameters: [
          .init(key: "title", value: "Suspicious Peek"),
          .init(key: "mood", value: "Suspicious"),
          .init(key: "step 1", value: "Peek left — Inquire · Look (-80%, -10%) · Yellow light · 0.6s"),
          .init(key: "step 2", value: "Back away — Backward · 0.8s"),
        ],
        connectionContext: "Warm (duck-eb55)",
        durationMs: 1480,
        outcome: .succeeded(summary: "duck-eb55 performed “Suspicious Peek” (2 steps).")
      ),
      IntentInvocationRecord(
        timestamp: now.addingTimeInterval(-45),
        kind: .entityQuery,
        intentName: "InstalledSkillQuery.matching",
        displayTitle: "Search Installed Tricks",
        isToolIntent: false,
        parameters: [.init(key: "query", value: "roll")],
        connectionContext: "Live (duck-eb55)",
        durationMs: 3,
        outcome: .succeeded(summary: "Matched 1 trick: roulade")
      ),
      IntentInvocationRecord(
        timestamp: now.addingTimeInterval(-95),
        kind: .toolIntent,
        intentName: "GetDuckStatusIntent",
        displayTitle: "Get Microduck Status",
        isToolIntent: true,
        parameters: [],
        connectionContext: "Cold start (duck-eb55)",
        durationMs: 620,
        outcome: .succeeded(summary: "duck-eb55 is standing, at 54% battery, motors at 32°C, running at 50 Hz.")
      ),
    ]
    return IntentTelemetryClient(
      loadRecords: { sampleRecords },
      recordsStream: {
        AsyncStream { continuation in
          continuation.yield(sampleRecords)
        }
      },
      record: { _ in },
      clear: {}
    )
  }

  public static var testValue: IntentTelemetryClient {
    IntentTelemetryClient(
      loadRecords: { [] },
      recordsStream: {
        AsyncStream { continuation in
          continuation.yield([])
          continuation.finish()
        }
      },
      record: { _ in },
      clear: {}
    )
  }
}

extension DependencyValues {
  public var intentTelemetry: IntentTelemetryClient {
    get { self[IntentTelemetryClient.self] }
    set { self[IntentTelemetryClient.self] = newValue }
  }
}
