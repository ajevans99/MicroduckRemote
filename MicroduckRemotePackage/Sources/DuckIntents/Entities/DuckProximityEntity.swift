import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import SwiftUI

/// In-memory cache of recently captured `DuckProximityEntity` readings so Siri AI's
/// `EntityQuery` / `SnippetRepresentableEntity` pipeline can resolve returned entities
/// and render their `CardSnippet` archive.
public final class DuckProximityStore: @unchecked Sendable {
  public static let shared = DuckProximityStore()

  private let lock = NSLock()
  private var items: [String: DuckProximityEntity] = [:]
  private var order: [String] = []
  private let capacity = 12

  private init() {}

  public func save(_ entity: DuckProximityEntity) {
    lock.lock()
    defer { lock.unlock() }
    items[entity.id] = entity
    order.removeAll { $0 == entity.id }
    order.insert(entity.id, at: 0)
    if order.count > capacity {
      let dropped = order.removeLast()
      items.removeValue(forKey: dropped)
    }
  }

  public func entities(for ids: [String]) -> [DuckProximityEntity] {
    lock.lock()
    defer { lock.unlock() }
    return ids.compactMap { items[$0] }
  }

  public var recent: [DuckProximityEntity] {
    lock.lock()
    defer { lock.unlock() }
    return order.compactMap { items[$0] }
  }
}

public struct DuckProximityQuery: EntityQuery {
  public init() {}

  public func entities(for identifiers: [String]) async throws -> [DuckProximityEntity] {
    let cached = DuckProximityStore.shared.entities(for: identifiers)
    if cached.count == identifiers.count {
      return cached
    }
    let cachedByID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
    @Dependencies.Dependency(\.duckSession) var duckSession
    let liveSnapshot = await duckSession.currentSnapshot()
    return identifiers.map { id in
      if let found = cachedByID[id] { return found }
      return DuckProximityEntity(id: id, snapshot: liveSnapshot)
    }
  }

  public func suggestedEntities() async throws -> [DuckProximityEntity] {
    let recent = DuckProximityStore.shared.recent
    if !recent.isEmpty { return recent }
    @Dependencies.Dependency(\.duckSession) var duckSession
    let snapshot = await duckSession.currentSnapshot()
    guard snapshot.controlOpen else { return [] }
    return [DuckProximityEntity(snapshot: snapshot)]
  }
}

/// Structured 8×8 ToF proximity reading returned by `GetDuckProximityIntent` and rendered
/// inline in Siri AI via `CardSnippet`.
public struct DuckProximityEntity: AppEntity, SnippetRepresentableEntity, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Proximity")
  public static let defaultQuery = DuckProximityQuery()
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  public let id: String

  @Property(title: "Duck Name", description: "Display name of the connected Microduck robot or simulator.")
  public var duckName: String

  @Property(title: "Has Sensor Data", description: "True if a live 8x8 ToF depth frame was available.")
  public var hasSensorData: Bool

  @Property(title: "Front Clearance (mm)", description: "Minimum measured obstacle distance directly ahead in millimeters.")
  public var frontClearanceMm: Int?

  @Property(title: "Left Clearance (mm)", description: "Minimum measured obstacle distance on Microduck's left side in millimeters.")
  public var leftClearanceMm: Int?

  @Property(title: "Right Clearance (mm)", description: "Minimum measured obstacle distance on Microduck's right side in millimeters.")
  public var rightClearanceMm: Int?

  @Property(title: "Closest Obstacle (mm)", description: "Closest valid reading across left, front, and right zones in millimeters.")
  public var closestObstacleMm: Int?

  @Property(title: "Obstacle Warning", description: "True if an obstacle is close ahead or right beside Microduck.")
  public var obstacleWarning: Bool

  @Property(title: "Recommended Direction", description: "Suggested open travel direction based on left, front, and right clearances.")
  public var recommendedDirection: DuckProximityDirection

  @Property(title: "Summary", description: "Concise natural-language summary of Microduck's current clearances.")
  public var summary: String

  public var displayRepresentation: DisplayRepresentation {
    let subtitle: String
    if hasSensorData, let frontClearanceMm {
      subtitle = "Front \(frontClearanceMm) mm · \(recommendedDirection.label)"
    } else if hasSensorData {
      subtitle = recommendedDirection.label
    } else {
      subtitle = "No ToF frame yet"
    }
    return DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: "\(duckName) Proximity"),
      subtitle: LocalizedStringResource(stringLiteral: subtitle),
      image: .init(systemName: obstacleWarning ? "exclamationmark.triangle.fill" : "sensor.tag.radiowaves.forward.fill")
    )
  }

  public init(id: String = "proximity-\(UUID().uuidString)") {
    self.id = id
    self.duckName = "Microduck"
    self.hasSensorData = false
    self.frontClearanceMm = nil
    self.leftClearanceMm = nil
    self.rightClearanceMm = nil
    self.closestObstacleMm = nil
    self.obstacleWarning = false
    self.recommendedDirection = .clear
    self.summary = "No live ToF proximity frame received yet."
  }

  public init(
    id: String? = nil,
    snapshot: DuckSessionSnapshot,
    warningThresholdMm: Int = DuckConstants.defaultProximityWarningMm
  ) {
    let resolvedName = snapshot.phase.connected?.name ?? "Microduck"
    self.id = id ?? "proximity-\(resolvedName)-\(UUID().uuidString.prefix(8))"
    self.duckName = resolvedName

    if let analysis = snapshot.tofFrame?.analyzeZones(warningThresholdMm: warningThresholdMm) {
      self.hasSensorData = true
      self.frontClearanceMm = analysis.frontMm
      self.leftClearanceMm = analysis.leftMm
      self.rightClearanceMm = analysis.rightMm
      self.closestObstacleMm = analysis.closestMm
      self.obstacleWarning = analysis.obstacleWarning
      let direction = DuckProximityDirection(analysis.recommendedDirection)
      self.recommendedDirection = direction
      self.summary = Self.makeSummary(
        duckName: resolvedName,
        analysis: analysis,
        direction: direction
      )
    } else {
      self.hasSensorData = false
      self.frontClearanceMm = nil
      self.leftClearanceMm = nil
      self.rightClearanceMm = nil
      self.closestObstacleMm = nil
      self.obstacleWarning = false
      self.recommendedDirection = .clear
      self.summary = "\(resolvedName) has no live 8×8 ToF depth frame yet."
    }
  }

  private static func makeSummary(
    duckName: String,
    analysis: TofZoneAnalysis,
    direction: DuckProximityDirection
  ) -> String {
    let fmt: (Int?) -> String = { mm in
      guard let mm else { return "clear" }
      if mm >= DuckConstants.tofMaxRangeMm { return ">4.0 m" }
      return "\(mm) mm"
    }
    let warningText = analysis.obstacleWarning ? "Obstacle nearby" : "Path open"
    return "\(duckName): \(warningText) (left \(fmt(analysis.leftMm)), front \(fmt(analysis.frontMm)), right \(fmt(analysis.rightMm)); recommended: \(direction.label.lowercased()))."
  }

  public static func == (lhs: DuckProximityEntity, rhs: DuckProximityEntity) -> Bool {
    lhs.id == rhs.id
      && lhs.duckName == rhs.duckName
      && lhs.hasSensorData == rhs.hasSensorData
      && lhs.frontClearanceMm == rhs.frontClearanceMm
      && lhs.leftClearanceMm == rhs.leftClearanceMm
      && lhs.rightClearanceMm == rhs.rightClearanceMm
      && lhs.closestObstacleMm == rhs.closestObstacleMm
      && lhs.obstacleWarning == rhs.obstacleWarning
      && lhs.recommendedDirection == rhs.recommendedDirection
      && lhs.summary == rhs.summary
  }

  public static var snippet: some EntitySnippetContent<Self> {
    CardSnippet(supportedFamilies: [.standard, .compact]) { proximity, context in
      DuckProximityCardView(proximity: proximity, isCompact: context.family == .compact)
    }
  }
}

struct DuckProximityCardView: View {
  let proximity: DuckProximityEntity
  let isCompact: Bool

  private var statusTint: Color {
    if !proximity.hasSensorData { return .gray }
    return proximity.obstacleWarning ? .orange : .green
  }

  private func zoneColor(_ mm: Int?) -> Color {
    guard let mm else { return .secondary }
    if mm < DuckConstants.defaultMinObstacleDistanceMm { return .red }
    if mm < DuckConstants.defaultProximityWarningMm { return .orange }
    return .green
  }

  private func formatDistance(_ mm: Int?) -> String {
    guard let mm else { return "–" }
    if mm >= DuckConstants.tofMaxRangeMm { return ">4.0 m" }
    if mm >= 1000 {
      return String(format: "%.2f m", Double(mm) / 1000.0)
    }
    return "\(mm) mm"
  }

  var body: some View {
    if isCompact {
      compactBody
    } else {
      standardBody
    }
  }

  private var compactBody: some View {
    HStack(spacing: 10) {
      Image(systemName: proximity.recommendedDirection.systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(statusTint)
      VStack(alignment: .leading, spacing: 2) {
        Text(proximity.duckName)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Text(proximity.hasSensorData ? proximity.recommendedDirection.label : "Waiting for ToF")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      Text(formatDistance(proximity.frontClearanceMm))
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(zoneColor(proximity.frontClearanceMm))
        .fixedSize()
    }
    .padding(12)
  }

  private var standardBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 6) {
        Image(systemName: proximity.obstacleWarning ? "exclamationmark.triangle.fill" : "sensor.tag.radiowaves.forward.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(statusTint)
        Text("\(proximity.duckName) Proximity")
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .layoutPriority(1)
        Spacer(minLength: 4)
        Label(proximity.recommendedDirection.label, systemImage: proximity.recommendedDirection.systemImage)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(statusTint.opacity(0.18), in: Capsule())
          .foregroundStyle(statusTint)
          .fixedSize()
      }

      HStack(spacing: 8) {
        zoneTile(label: "Left", mm: proximity.leftClearanceMm)
        zoneTile(label: "Front", mm: proximity.frontClearanceMm)
        zoneTile(label: "Right", mm: proximity.rightClearanceMm)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
  }

  private func zoneTile(label: String, mm: Int?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Circle()
        .fill(zoneColor(mm))
        .frame(width: 8, height: 8)
      Text(formatDistance(mm))
        .font(.headline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
