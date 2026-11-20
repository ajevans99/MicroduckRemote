import Charts
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class TelemetryModel {
  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.haptics) var haptics

  public var snapshot = DuckSessionSnapshot()
  public var showDegrees = true
  public var mapResolutionMeters = 0.10
  public var confirmWipePresented = false
  public var errorBanner: String?

  public init() {}

  public func task() async {
    snapshot = await duckSession.currentSnapshot()
    if snapshot.controlOpen {
      await duckSession.subscribeTof()
      await duckSession.refreshMap(mapResolutionMeters)
    }
    for await updated in duckSession.snapshots() {
      snapshot = updated
    }
  }

  public func unitToggleTapped() {
    haptics.selectionChanged()
    showDegrees.toggle()
  }

  public func refreshMapButtonTapped() async {
    haptics.selectionChanged()
    await duckSession.refreshMap(mapResolutionMeters)
  }

  public func wipeMapButtonTapped() {
    confirmWipePresented = true
  }

  public func wipeMapConfirmedTapped() async {
    confirmWipePresented = false
    do {
      try await duckSession.wipeMap()
      haptics.success()
    } catch {
      errorBanner = error.localizedDescription
    }
  }
}

public struct TelemetryInspectorView: View {
  @Bindable var model: TelemetryModel

  public init(model: TelemetryModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          healthSummaryGrid
          loopSparklineCard
          jointTrackingCard
          slamMapCard
          logsCard
        }
        .padding(16)
      }
      .navigationTitle("Telemetry & Map")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(model.showDegrees ? "deg" : "rad") {
            model.unitToggleTapped()
          }
          .font(.footnote.monospaced().weight(.semibold))
        }
      }
      .confirmationDialog(
        "Wipe Onboard SLAM Map?",
        isPresented: $model.confirmWipePresented,
        titleVisibility: .visible
      ) {
        Button("Wipe Map", role: .destructive) {
          Task { await model.wipeMapConfirmedTapped() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("The duck will forget its current room map and start fresh on its next stop.")
      }
      .task {
        await model.task()
      }
    }
  }

  private var healthSummaryGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      metricTile(
        title: "Control Loop",
        value: model.snapshot.latestState?.controlLoop?.hz.map { String(format: "%.1f Hz", $0) } ?? "–",
        subtitle: "\(model.snapshot.latestState?.controlLoop?.missed ?? 0) missed ticks",
        icon: "metronome.fill",
        tint: .green
      )
      metricTile(
        title: "Battery",
        value: model.snapshot.health?.battery.map { String(format: "%.2f V", $0.volts) } ?? "–",
        subtitle: model.snapshot.health?.battery.map { "\(Int($0.percent.rounded()))% charge" } ?? "Waiting",
        icon: "battery.75percent",
        tint: .mint
      )
      metricTile(
        title: "Thermals",
        value: model.snapshot.health?.motors.map { String(format: "%.0f °C", $0.maxC) } ?? "–",
        subtitle: model.snapshot.health?.motors?.hottest ?? "15 servos",
        icon: "thermometer.medium",
        tint: .orange
      )
      metricTile(
        title: "WebRTC Link",
        value: model.snapshot.linkStats.bitrateKbps.map { "\($0) kbps" } ?? "–",
        subtitle: model.snapshot.linkStats.rttMs.map { "\($0) ms RTT · \(model.snapshot.linkStats.fps ?? 0) fps" } ?? "Idle",
        icon: "wifi",
        tint: .cyan
      )
    }
  }

  private func metricTile(
    title: String,
    value: String,
    subtitle: String,
    icon: String,
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: icon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
      Text(value)
        .font(.title3.monospacedDigit().weight(.bold))
      Text(subtitle)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var loopSparklineCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("50 Hz Control Cadence")
          .font(.headline)
        Spacer()
        Text(model.snapshot.latestState?.policy ?? "idle")
          .font(.caption.monospaced().weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Color.accentColor.opacity(0.16), in: Capsule())
      }

      if model.snapshot.loopHistory.isEmpty {
        Text("Connect to stream real-time loop cadence.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(height: 90)
      } else {
        Chart(model.snapshot.loopHistory) { sample in
          LineMark(
            x: .value("Sample", sample.id),
            y: .value("Hz", sample.hz)
          )
          .foregroundStyle(Color.green.gradient)
          .interpolationMethod(.catmullRom)

          RuleMark(y: .value("Gate", 45.0))
            .foregroundStyle(.orange.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: 40...55)
        .chartXAxis(.hidden)
        .frame(height: 110)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var jointTrackingCard: some View {
    let joints = model.snapshot.latestState?.joints ?? []
    let targets = model.snapshot.latestState?.targets ?? []

    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("15-Joint Servo Tracking")
          .font(.headline)
        Spacer()
        Text("±0.20 rad scale")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      ForEach(Array(DuckConstants.jointNames.enumerated()), id: \.offset) { index, name in
        let measured = index < joints.count ? joints[index] : 0
        let target = index < targets.count ? targets[index] : measured
        let errorRad = measured - target

        HStack(spacing: 8) {
          Text(name.replacingOccurrences(of: "_", with: " "))
            .font(.caption.monospaced())
            .frame(width: 118, alignment: .leading)
            .lineLimit(1)

          GeometryReader { barProxy in
            let mid = barProxy.size.width / 2
            let normalized = min(max(errorRad / DuckConstants.jointDeviationFullScaleRadians, -1), 1)
            let span = abs(CGFloat(normalized)) * mid

            ZStack(alignment: .leading) {
              Capsule()
                .fill(Color.primary.opacity(0.08))
              Rectangle()
                .fill(Color.primary.opacity(0.25))
                .frame(width: 1)
                .offset(x: mid)
              Capsule()
                .fill(abs(normalized) > 0.75 ? Color.orange : Color.accentColor)
                .frame(width: max(3, span))
                .offset(x: normalized >= 0 ? mid : mid - span)
            }
          }
          .frame(height: 8)

          Text(formattedAngle(measured))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 58, alignment: .trailing)
        }
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var slamMapCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Onboard SLAM Map")
          .font(.headline)
        Spacer()
        Button {
          Task { await model.refreshMapButtonTapped() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .font(.caption.weight(.semibold))
        }
        .disabled(!model.snapshot.controlOpen)

        Button(role: .destructive) {
          model.wipeMapButtonTapped()
        } label: {
          Image(systemName: "trash")
            .font(.caption)
        }
        .disabled(!model.snapshot.controlOpen)
      }

      if let grid = model.snapshot.mapGrid, grid.width > 0, grid.height > 0 {
        SlamGridCanvasView(grid: grid)
          .frame(height: 220)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      } else {
        Text("Nothing mapped yet — the map grows as the duck stops and looks around.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var logsCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Wire Log")
        .font(.headline)
      if model.snapshot.logs.isEmpty {
        Text("No messages recorded yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.snapshot.logs.suffix(12)) { entry in
          Text(entry.message)
            .font(.caption2.monospaced())
            .foregroundStyle(colorForLog(entry.level))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func formattedAngle(_ radians: Double) -> String {
    if model.showDegrees {
      return String(format: "%+5.1f°", radians * 180.0 / .pi)
    }
    return String(format: "%+5.2fr", radians)
  }

  private func colorForLog(_ level: RpcLogEntry.Level) -> Color {
    switch level {
    case .inbound: .green
    case .outbound: .cyan
    case .info: .secondary
    case .warning: .orange
    case .error: .red
    }
  }
}

public struct SlamGridCanvasView: View {
  public let grid: MapGridResult

  public init(grid: MapGridResult) {
    self.grid = grid
  }

  public var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
      let cellW = size.width / CGFloat(max(1, grid.width))
      let cellH = size.height / CGFloat(max(1, grid.height))
      let cellSide = min(cellW, cellH)
      let offsetX = (size.width - cellSide * CGFloat(grid.width)) / 2
      let offsetY = (size.height - cellSide * CGFloat(grid.height)) / 2

      let chars = Array(grid.cells)
      for row in 0..<grid.height {
        for col in 0..<grid.width {
          let idx = row * grid.width + col
          guard idx < chars.count else { continue }
          let ch = chars[idx]
          guard ch == "." || ch == "#" else { continue }
          let rect = CGRect(
            x: offsetX + CGFloat(col) * cellSide,
            y: offsetY + CGFloat(grid.height - 1 - row) * cellSide,
            width: cellSide + 0.5,
            height: cellSide + 0.5
          )
          context.fill(
            Path(rect),
            with: .color(ch == "#" ? .white : Color.teal.opacity(0.28))
          )
        }
      }

      if let pose = grid.pose, grid.origin.count >= 2, grid.resM > 0 {
        let gx = (pose.x - grid.origin[0]) / grid.resM
        let gy = (pose.y - grid.origin[1]) / grid.resM
        let px = offsetX + CGFloat(gx) * cellSide
        let py = offsetY + CGFloat(Double(grid.height) - gy) * cellSide
        let dot = CGRect(x: px - 5, y: py - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: dot), with: .color(.yellow))
      }
    }
  }
}

#Preview(
  traits: .dependencies {
    $0.duckSession = .previewValue
  }
) {
  TelemetryInspectorView(model: TelemetryModel())
}
