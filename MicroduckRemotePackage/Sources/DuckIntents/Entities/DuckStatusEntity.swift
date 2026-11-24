import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import SwiftUI

/// In-memory cache of recently captured `DuckStatusEntity` instances so Siri AI's
/// `EntityQuery` / `SnippetRepresentableEntity` pipeline can resolve returned entities
/// and render their `CardSnippet` archive.
public final class DuckStatusStore: @unchecked Sendable {
  public static let shared = DuckStatusStore()

  private let lock = NSLock()
  private var items: [String: DuckStatusEntity] = [:]
  private var order: [String] = []
  private let capacity = 12

  private init() {}

  public func save(_ entity: DuckStatusEntity) {
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

  public func entities(for ids: [String]) -> [DuckStatusEntity] {
    lock.lock()
    defer { lock.unlock() }
    return ids.compactMap { items[$0] }
  }

  public var recent: [DuckStatusEntity] {
    lock.lock()
    defer { lock.unlock() }
    return order.compactMap { items[$0] }
  }
}

public struct DuckStatusQuery: EntityQuery {
  public init() {}

  public func entities(for identifiers: [String]) async throws -> [DuckStatusEntity] {
    let cached = DuckStatusStore.shared.entities(for: identifiers)
    if cached.count == identifiers.count {
      return cached
    }
    let cachedByID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
    @Dependencies.Dependency(\.duckSession) var duckSession
    let liveSnapshot = await duckSession.currentSnapshot()
    return identifiers.map { id in
      if let found = cachedByID[id] { return found }
      return DuckStatusEntity(id: id, snapshot: liveSnapshot)
    }
  }

  public func suggestedEntities() async throws -> [DuckStatusEntity] {
    let recent = DuckStatusStore.shared.recent
    if !recent.isEmpty { return recent }
    @Dependencies.Dependency(\.duckSession) var duckSession
    let snapshot = await duckSession.currentSnapshot()
    guard snapshot.controlOpen else { return [] }
    return [DuckStatusEntity(snapshot: snapshot)]
  }
}

/// Telemetry snapshot entity returned by `GetDuckStatusIntent` and `SetDuckPostureIntent`,
/// rendered inline in Siri AI via `CardSnippet` (`SnippetRepresentableEntity`).
public struct DuckStatusEntity: AppEntity, SnippetRepresentableEntity, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Status")
  public static let defaultQuery = DuckStatusQuery()
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  public let id: String

  @Property(title: "Duck Name", description: "Display name of the connected Microduck robot or simulator.")
  public var duckName: String

  @Property(title: "Connected", description: "Whether the WebRTC control channel is currently open.")
  public var isConnected: Bool

  @Property(title: "Simulated", description: "True if this duck is running in the MuJoCo simulator rather than physical hardware.")
  public var isSimulated: Bool

  @Property(title: "Posture", description: "Current physical posture or safety state: Standing, Sitting, Fallen, Picked Up, Limp, Disabled, or Offline.")
  public var postureSummary: String

  @Property(title: "Active Policy", description: "Currently active control policy on the duck (for example walk or idle).")
  public var activePolicy: String

  @Property(title: "Fallen", description: "True if the duck has fallen over and needs recovery before walking or doing tricks.")
  public var isFallen: Bool

  @Property(title: "Picked Up", description: "True if the duck's feet are off the ground.")
  public var isPickedUp: Bool

  @Property(title: "Battery Voltage", description: "Battery pack voltage in volts.")
  public var batteryVolts: Double?

  @Property(title: "Battery Percent", description: "Estimated remaining battery percentage from 0 to 100.")
  public var batteryPercent: Int?

  @Property(title: "Max Motor Temperature (°C)", description: "Highest servo temperature across all 15 joints in degrees Celsius.")
  public var maxMotorTempC: Int?

  @Property(title: "Hottest Servo", description: "Name of the warmest servo joint.")
  public var hottestMotor: String?

  @Property(title: "Control Loop (Hz)", description: "Measured frequency of the onboard 50 Hz balance control loop.")
  public var controlLoopHz: Double?

  @Property(title: "Movement Limiter", description: "Active safety or deadman limiter preventing movement, if any.")
  public var movementLimitReason: String?

  @Property(title: "Installed Tricks", description: "Number of tricks currently installed on the duck.")
  public var installedTrickCount: Int

  public var displayRepresentation: DisplayRepresentation {
    var parts = [postureSummary]
    if let batteryPercent {
      parts.append("\(batteryPercent)% battery")
    }
    if let maxMotorTempC {
      parts.append("\(maxMotorTempC)°C")
    }
    return DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: duckName),
      subtitle: LocalizedStringResource(stringLiteral: parts.joined(separator: " · ")),
      image: .init(systemName: isFallen ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
    )
  }

  public init(id: String = "status-\(UUID().uuidString)") {
    self.id = id
    self.duckName = "Microduck"
    self.isConnected = false
    self.isSimulated = false
    self.postureSummary = "Offline"
    self.activePolicy = "idle"
    self.isFallen = false
    self.isPickedUp = false
    self.batteryVolts = nil
    self.batteryPercent = nil
    self.maxMotorTempC = nil
    self.hottestMotor = nil
    self.controlLoopHz = nil
    self.movementLimitReason = nil
    self.installedTrickCount = 0
  }

  public init(id: String? = nil, snapshot: DuckSessionSnapshot) {
    let identity = snapshot.phase.connected
    let safety = snapshot.latestState?.safety
    let fallen = safety?.fallen == true
    let pickedUp = safety?.pickedUp == true
    let limp = safety?.limp == true
    let enabled = snapshot.policies?.enabled == true
    let sitting = snapshot.policies?.sitting == true

    let posture: String
    if !snapshot.controlOpen {
      posture = "Offline"
    } else if fallen {
      posture = "Fallen"
    } else if pickedUp {
      posture = "Picked Up"
    } else if limp {
      posture = "Limp"
    } else if !enabled {
      posture = "Disabled"
    } else if sitting {
      posture = "Sitting"
    } else {
      posture = "Standing"
    }

    let limiters = snapshot.latestState?.movement?.limitedBy ?? []
    let trickCount = snapshot.skillNames.filter { $0 != "sit_toggle" }.count

    let resolvedName = identity?.name ?? "Microduck"
    self.id = id ?? "status-\(resolvedName)-\(UUID().uuidString.prefix(8))"
    self.duckName = resolvedName
    self.isConnected = snapshot.controlOpen
    self.isSimulated = identity?.isSimulated ?? false
    self.postureSummary = posture
    self.activePolicy = snapshot.latestState?.policy ?? snapshot.mode ?? "idle"
    self.isFallen = fallen
    self.isPickedUp = pickedUp
    self.batteryVolts = snapshot.health?.battery?.volts
    self.batteryPercent = snapshot.health?.battery.map { Int($0.percent.rounded()) }
    self.maxMotorTempC = snapshot.health?.motors.map { Int($0.maxC.rounded()) }
    self.hottestMotor = snapshot.health?.motors?.hottest
    self.controlLoopHz = snapshot.latestState?.controlLoop?.hz
    self.movementLimitReason = limiters.isEmpty ? nil : limiters.joined(separator: ", ")
    self.installedTrickCount = trickCount
  }

  public var spokenSummary: String {
    guard isConnected else {
      return "\(duckName) is currently offline."
    }
    var segments: [String] = ["\(duckName) is \(postureSummary.lowercased())"]
    if let batteryPercent {
      segments.append("at \(batteryPercent)% battery")
    }
    if let maxMotorTempC {
      if let hottestMotor, maxMotorTempC >= 50 {
        segments.append("motors warm at \(maxMotorTempC)°C (\(hottestMotor.replacingOccurrences(of: "_", with: " ")))")
      } else {
        segments.append("motors at \(maxMotorTempC)°C")
      }
    }
    if let controlLoopHz {
      segments.append("running at \(Int(controlLoopHz.rounded())) Hz")
    }
    if isFallen {
      segments.append("Ask me to stand it back up before walking.")
    }
    return segments.joined(separator: ", ") + "."
  }

  public static func == (lhs: DuckStatusEntity, rhs: DuckStatusEntity) -> Bool {
    lhs.id == rhs.id
      && lhs.duckName == rhs.duckName
      && lhs.isConnected == rhs.isConnected
      && lhs.isSimulated == rhs.isSimulated
      && lhs.postureSummary == rhs.postureSummary
      && lhs.activePolicy == rhs.activePolicy
      && lhs.isFallen == rhs.isFallen
      && lhs.isPickedUp == rhs.isPickedUp
      && lhs.batteryVolts == rhs.batteryVolts
      && lhs.batteryPercent == rhs.batteryPercent
      && lhs.maxMotorTempC == rhs.maxMotorTempC
      && lhs.hottestMotor == rhs.hottestMotor
      && lhs.controlLoopHz == rhs.controlLoopHz
      && lhs.movementLimitReason == rhs.movementLimitReason
      && lhs.installedTrickCount == rhs.installedTrickCount
  }

  public static var snippet: some EntitySnippetContent<Self> {
    CardSnippet(supportedFamilies: [.standard, .compact]) { status, context in
      DuckStatusCardView(status: status, isCompact: context.family == .compact)
    }
  }
}

struct DuckStatusCardView: View {
  let status: DuckStatusEntity
  let isCompact: Bool

  private var postureColor: Color {
    if !status.isConnected { return .gray }
    if status.isFallen || status.isPickedUp { return .red }
    if status.postureSummary == "Sitting" || status.postureSummary == "Disabled" { return .orange }
    return .green
  }

  private var batteryIcon: String {
    guard let pct = status.batteryPercent else { return "battery.50percent" }
    switch pct {
    case 88...: return "battery.100percent"
    case 63..<88: return "battery.75percent"
    case 38..<63: return "battery.50percent"
    case 13..<38: return "battery.25percent"
    default: return "battery.0percent"
    }
  }

  private var batteryColor: Color {
    guard let pct = status.batteryPercent else { return .secondary }
    if pct < 20 { return .red }
    if pct < 40 { return .orange }
    return .green
  }

  private var thermalColor: Color {
    guard let temp = status.maxMotorTempC else { return .secondary }
    if temp >= 55 { return .red }
    if temp >= 45 { return .orange }
    return .mint
  }

  private var notableAlert: (icon: String, text: String, tint: Color)? {
    if status.isFallen {
      return ("exclamationmark.triangle.fill", "Fallen — stand back up to walk", .red)
    }
    if status.isPickedUp {
      return ("hand.raised.fill", "Picked up", .red)
    }
    guard let raw = status.movementLimitReason else { return nil }
    let notable = raw
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0 != "deadman" }
      .map { limiter -> String in
        switch limiter {
        case "joint_range": return "Joint travel clamped"
        case "not_finite": return "Invalid command clamped"
        default: return limiter.replacingOccurrences(of: "_", with: " ")
        }
      }
    guard !notable.isEmpty else { return nil }
    return ("exclamationmark.shield.fill", notable.joined(separator: " · "), .orange)
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
      Circle()
        .fill(postureColor)
        .frame(width: 9, height: 9)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(status.duckName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          if status.isSimulated {
            Text("SIM")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.teal.opacity(0.22), in: Capsule())
              .foregroundStyle(.teal)
          }
        }
        Text(status.postureSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      if let pct = status.batteryPercent {
        HStack(spacing: 3) {
          Image(systemName: batteryIcon)
          Text("\(pct)%")
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(batteryColor)
        .fixedSize()
      }
      if let temp = status.maxMotorTempC {
        Text("\(temp)°C")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(thermalColor)
          .fixedSize()
      }
    }
    .padding(12)
  }

  private var standardBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 6) {
        Circle()
          .fill(postureColor)
          .frame(width: 9, height: 9)
        Text(status.duckName)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .layoutPriority(1)
        if status.isSimulated {
          Text("SIM")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.teal.opacity(0.22), in: Capsule())
            .foregroundStyle(.teal)
            .fixedSize()
        }
        Spacer(minLength: 4)
        Text(status.postureSummary)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(postureColor.opacity(0.18), in: Capsule())
          .foregroundStyle(postureColor)
          .fixedSize()
      }

      HStack(spacing: 8) {
        metricTile(
          icon: batteryIcon,
          tint: batteryColor,
          value: status.batteryPercent.map { "\($0)%" } ?? "–",
          detail: status.batteryVolts.map { String(format: "%.2f V", $0) } ?? "Battery"
        )
        metricTile(
          icon: "thermometer.medium",
          tint: thermalColor,
          value: status.maxMotorTempC.map { "\($0)°C" } ?? "–",
          detail: "Motors"
        )
        metricTile(
          icon: "waveform.path.ecg",
          tint: .cyan,
          value: status.controlLoopHz.map { String(format: "%.0f Hz", $0) } ?? "–",
          detail: status.activePolicy
        )
      }
      .fixedSize(horizontal: false, vertical: true)

      if let alert = notableAlert {
        Label(alert.text, systemImage: alert.icon)
          .font(.caption.weight(.medium))
          .foregroundStyle(alert.tint)
      }

      if status.isConnected {
        quickActionsRow
      }
    }
    .padding(14)
  }

  private var needsStandUp: Bool {
    status.isFallen || status.postureSummary == "Sitting" || status.postureSummary == "Disabled"
  }

  private var quickActionsRow: some View {
    HStack(spacing: 8) {
      if needsStandUp {
        Button(intent: SetDuckPostureIntent(posture: .standUp)) {
          Label("Stand Up", systemImage: "figure.stand")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.green.opacity(0.18), in: Capsule())
            .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
      } else {
        Button(intent: SetDuckPostureIntent(posture: .sitDown)) {
          Label("Sit", systemImage: "figure.seated.side.right")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
      }

      Button(intent: EmergencyStopDuckIntent()) {
        Label("Stop", systemImage: "octagon.fill")
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 7)
          .background(.red.opacity(0.18), in: Capsule())
          .foregroundStyle(.red)
      }
      .buttonStyle(.plain)
    }
  }

  private func metricTile(
    icon: String,
    tint: Color,
    value: String,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: icon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .frame(height: 14)
      Text(value)
        .font(.headline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text(detail)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
