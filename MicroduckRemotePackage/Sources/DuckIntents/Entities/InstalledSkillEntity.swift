import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

/// Represents a skill or `.onnx` trick currently installed on Microduck (both built-in
/// skills like `roulade` / `kick_left` and custom policies downloaded from Hugging Face).
public struct InstalledSkillEntity: AppEntity, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Duck Trick",
    numericFormat: "\(placeholder: .int) duck tricks"
  )

  public static let defaultQuery = InstalledSkillQuery()

  public let id: String

  #if os(iOS)
  @Property(
    title: "Name",
    description: "Human-readable name of the trick installed on Microduck."
  )
  public var name: String

  @Property(
    title: "Duration (Seconds)",
    description: "Approximate duration of the trick in seconds, when episodic."
  )
  public var durationSeconds: Double?

  @Property(
    title: "Custom Trick",
    description: "True if this trick was installed from Hugging Face rather than built into firmware."
  )
  public var isCustom: Bool
  #else
  @Property(title: "Name")
  public var name: String

  @Property(title: "Duration (Seconds)")
  public var durationSeconds: Double?

  @Property(title: "Custom Trick")
  public var isCustom: Bool
  #endif

  public var displayRepresentation: DisplayRepresentation {
    let subtitleText: String
    if let durationSeconds {
      let rounded = durationSeconds.formatted(.number.precision(.fractionLength(0...1)))
      subtitleText = isCustom ? "Custom trick · ~\(rounded)s" : "Built-in · ~\(rounded)s"
    } else {
      subtitleText = isCustom ? "Custom Hugging Face trick" : "Built-in Microduck skill"
    }

    return DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: name),
      subtitle: LocalizedStringResource(stringLiteral: subtitleText),
      image: .init(systemName: Self.systemImage(for: id, isCustom: isCustom))
    )
  }

  public init(id: String, name: String? = nil, durationSeconds: Double? = nil, isCustom: Bool = false) {
    self.id = id
    self.name = name ?? Self.prettyName(for: id)
    self.durationSeconds = durationSeconds
    self.isCustom = isCustom
  }

  public init(summary: SkillSummary) {
    self.init(
      id: summary.name,
      name: Self.prettyName(for: summary.name),
      durationSeconds: summary.duration,
      isCustom: summary.overridden == true
    )
  }

  public static func == (lhs: InstalledSkillEntity, rhs: InstalledSkillEntity) -> Bool {
    lhs.id == rhs.id
      && lhs.name == rhs.name
      && lhs.durationSeconds == rhs.durationSeconds
      && lhs.isCustom == rhs.isCustom
  }

  public static func prettyName(for skillID: String) -> String {
    skillID
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }

  private static func systemImage(for skillID: String, isCustom: Bool) -> String {
    switch skillID {
    case "roulade": "arrow.trianglehead.2.clockwise.rotate.90"
    case "kick_left", "kick_right": "figure.soccer"
    case "ground_pick": "hand.point.down.fill"
    default: isCustom ? "sparkles" : "figure.walk"
    }
  }
}

/// Dynamically resolves the tricks installed on Microduck for Siri AI and Shortcuts.
/// Reads live WebRTC state when connected, and falls back to the cached App Group summary
/// when offline so browsing Shortcuts never forces an unwanted background WebRTC connection.
public struct InstalledSkillQuery: EnumerableEntityQuery, EntityStringQuery {
  /// Posture switching has its own dedicated `SetDuckPostureIntent`; exclude `sit_toggle`
  /// from trick discovery so Siri AI never confuses "sit down" with "perform a trick".
  private static let excludedFromTricks: Set<String> = ["sit_toggle"]

  public init() {}

  public func allEntities() async throws -> [InstalledSkillEntity] {
    @Dependencies.Dependency(\.duckSession) var duckSession
    @Dependencies.Dependency(\.duckSharedState) var duckSharedState

    let snapshot = await duckSession.currentSnapshot()
    if snapshot.controlOpen {
      if !snapshot.installedSkills.isEmpty {
        return snapshot.installedSkills
          .filter { !Self.excludedFromTricks.contains($0.name) }
          .map(InstalledSkillEntity.init(summary:))
      }
      return snapshot.skillNames
        .filter { !Self.excludedFromTricks.contains($0) }
        .map { InstalledSkillEntity(id: $0) }
    }

    let cachedNames = duckSharedState.loadSummary().installedSkillNames
    let names = cachedNames.isEmpty ? DuckConstants.builtInSkills : cachedNames
    return names
      .filter { !Self.excludedFromTricks.contains($0) }
      .map { InstalledSkillEntity(id: $0) }
  }

  public func entities(for identifiers: [InstalledSkillEntity.ID]) async throws -> [InstalledSkillEntity] {
    let available = try await allEntities()
    let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
    return identifiers.compactMap { id in
      if let found = byID[id] {
        return found
      }
      guard !Self.excludedFromTricks.contains(id) else { return nil }
      return InstalledSkillEntity(id: id)
    }
  }

  public func entities(matching string: String) async throws -> [InstalledSkillEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let available = try await allEntities()
    guard !query.isEmpty else { return available }

    let normalizedTokens = query
      .lowercased()
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ")
      .map(String.init)

    return available.filter { entity in
      let haystack = "\(entity.id) \(entity.name)"
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
      return normalizedTokens.allSatisfy { haystack.contains($0) }
    }
  }
}
