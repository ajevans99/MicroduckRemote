import AppIntents
import DuckDependencies
import DuckProtocol
import Foundation
import SwiftUI

/// Transient telemetry snapshot returned by `GetDuckStatusIntent` and rendered inside Siri
/// via `CardSnippet` (`SnippetRepresentableEntity`).
public struct DuckStatusEntity: TransientAppEntity, SnippetRepresentableEntity, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Status")
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

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

  public init() {
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

  public init(snapshot: DuckSessionSnapshot) {
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

    self.duckName = identity?.name ?? "Microduck"
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
    lhs.duckName == rhs.duckName
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

private struct DuckStatusCardView: View {
  let status: DuckStatusEntity
  let isCompact: Bool

  private var postureColor: Color {
    if !status.isConnected { return .gray }
    if status.isFallen || status.isPickedUp { return .red }
    if status.postureSummary == "Sitting" || status.postureSummary == "Disabled" { return .orange }
    return .green
  }

  private var thermalColor: Color {
    guard let temp = status.maxMotorTempC else { return .secondary }
    if temp >= 55 { return .red }
    if temp >= 45 { return .orange }
    return .mint
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
      Spacer()
      if let pct = status.batteryPercent {
        Label("\(pct)%", systemImage: "battery.75percent")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(.green)
      }
      if let temp = status.maxMotorTempC {
        Text("\(temp)°C")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(thermalColor)
      }
    }
    .padding(12)
  }

  private var standardBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 8) {
        Circle()
          .fill(postureColor)
          .frame(width: 10, height: 10)
        Text(status.duckName)
          .font(.headline)
        if status.isSimulated {
          Text("SIM")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.teal.opacity(0.22), in: Capsule())
            .foregroundStyle(.teal)
        }
        Spacer()
        Text(status.postureSummary)
          .font(.caption.weight(.bold))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(postureColor.opacity(0.18), in: Capsule())
          .foregroundStyle(postureColor)
      }

      HStack(spacing: 10) {
        metricTile(
          icon: "battery.75percent",
          tint: .green,
          title: "Battery",
          value: status.batteryPercent.map { "\($0)%" } ?? "–",
          detail: status.batteryVolts.map { String(format: "%.2f V", $0) } ?? "Waiting"
        )
        metricTile(
          icon: "thermometer.medium",
          tint: thermalColor,
          title: "Thermals",
          value: status.maxMotorTempC.map { "\($0)°C" } ?? "–",
          detail: status.hottestMotor?.replacingOccurrences(of: "_", with: " ") ?? "15 servos"
        )
        metricTile(
          icon: "waveform.path.ecg",
          tint: .cyan,
          title: "Loop",
          value: status.controlLoopHz.map { String(format: "%.0f Hz", $0) } ?? "–",
          detail: status.activePolicy
        )
      }

      if let limiter = status.movementLimitReason {
        Label("Limiter: \(limiter)", systemImage: "exclamationmark.shield.fill")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.orange)
      }
    }
    .padding(14)
  }

  private func metricTile(
    icon: String,
    tint: Color,
    title: String,
    value: String,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(title, systemImage: icon)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
      Text(value)
        .font(.subheadline.monospacedDigit().weight(.bold))
      Text(detail)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
