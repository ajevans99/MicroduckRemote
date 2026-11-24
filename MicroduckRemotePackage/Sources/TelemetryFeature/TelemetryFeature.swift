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
  public enum IntentFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case tools = "Siri Tools"
    case queries = "Queries"

    public var id: String { rawValue }
  }

  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.intentTelemetry) var intentTelemetry
  @ObservationIgnored @Dependency(\.haptics) var haptics

  public var snapshot = DuckSessionSnapshot()
  public var intentRecords: [IntentInvocationRecord] = []
  public var intentFilter: IntentFilter = .all
  public var showDegrees = true
  public var mapResolutionMeters = 0.10
  public var confirmWipePresented = false
  public var errorBanner: String?

  public init() {}

  public var filteredIntentRecords: [IntentInvocationRecord] {
    switch intentFilter {
    case .all:
      intentRecords
    case .tools:
      intentRecords.filter { $0.kind == .toolIntent }
    case .queries:
      intentRecords.filter { $0.kind == .entityQuery }
    }
  }

  public var toolCallCount: Int {
    intentRecords.filter { $0.kind == .toolIntent }.count
  }

  public func task() async {
    snapshot = await duckSession.currentSnapshot()
    intentRecords = intentTelemetry.loadRecords()
    if snapshot.controlOpen {
      await duckSession.subscribeTof()
      await duckSession.refreshMap(mapResolutionMeters)
    }
    async let sessionLoop: Void = observeSessionSnapshots()
    async let intentLoop: Void = observeIntentTelemetry()
    _ = await (sessionLoop, intentLoop)
  }

  private func observeSessionSnapshots() async {
    for await updated in duckSession.snapshots() {
      snapshot = updated
    }
  }

  private func observeIntentTelemetry() async {
    for await updated in intentTelemetry.recordsStream() {
      intentRecords = updated
    }
  }

  public func reloadIntentTelemetryButtonTapped() {
    intentRecords = intentTelemetry.loadRecords()
  }

  public func clearIntentTelemetryButtonTapped() {
    haptics.selectionChanged()
    intentTelemetry.clear()
    intentRecords = []
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
  @State private var showJoints = false
  @State private var showWireLog = false

  public init(model: TelemetryModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      List {
        Section("Overview") {
          healthSummaryGrid
        }

        siriAndIntentsSection

        Section {
          loopChartContent
        } header: {
          HStack {
            Text("Control Cadence")
            Spacer()
            Text(model.snapshot.latestState?.policy ?? "idle")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textCase(nil)
          }
        }

        Section {
          slamMapContent
        } header: {
          HStack {
            Text("SLAM Map")
            Spacer()
            Button {
              Task { await model.refreshMapButtonTapped() }
            } label: {
              Image(systemName: "arrow.clockwise")
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!model.snapshot.controlOpen)

            Button(role: .destructive) {
              model.wipeMapButtonTapped()
            } label: {
              Image(systemName: "trash")
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!model.snapshot.controlOpen)
          }
        }

        Section {
          DisclosureGroup(isExpanded: $showJoints) {
            jointTrackingRows
          } label: {
            HStack {
              Text("Servo Tracking")
              Spacer()
              Text("15 joints")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          DisclosureGroup(isExpanded: $showWireLog) {
            wireLogRows
          } label: {
            HStack {
              Text("Wire Log")
              Spacer()
              Text("\(model.snapshot.logs.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Diagnostics")
        }
      }
      #if canImport(UIKit)
      .listStyle(.insetGrouped)
      #else
      .listStyle(.inset)
      #endif
      .navigationTitle("Telemetry")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(model.showDegrees ? "deg" : "rad") {
            model.unitToggleTapped()
          }
          .font(.footnote.monospaced().weight(.medium))
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
      .onAppear {
        model.reloadIntentTelemetryButtonTapped()
      }
      .task {
        await model.task()
      }
    }
  }

  private var siriAndIntentsSection: some View {
    Section {
      if !model.intentRecords.isEmpty {
        Picker("Filter", selection: $model.intentFilter) {
          ForEach(TelemetryModel.IntentFilter.allCases) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }

      if model.filteredIntentRecords.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.intentRecords.isEmpty ? "No intent calls recorded yet." : "No matching calls.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          if model.intentRecords.isEmpty {
            Text("Trigger a Siri AI request or Shortcut to inspect tool names, parameters, generated routines, latency, and errors here.")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.vertical, 4)
      } else {
        ForEach(model.filteredIntentRecords.prefix(25)) { record in
          intentRecordRow(record)
        }
      }
    } header: {
      HStack {
        Text("Siri & App Intents")
        Spacer()
        if !model.intentRecords.isEmpty {
          Text("\(model.toolCallCount) tools")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
        Button {
          model.reloadIntentTelemetryButtonTapped()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        if !model.intentRecords.isEmpty {
          Button(role: .destructive) {
            model.clearIntentTelemetryButtonTapped()
          } label: {
            Image(systemName: "trash")
              .font(.caption)
          }
          .buttonStyle(.borderless)
        }
      }
    }
  }

  private func intentRecordRow(_ record: IntentInvocationRecord) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Type") {
          Text(record.intentName)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .font(.caption)

        if !record.connectionContext.isEmpty {
          LabeledContent("Session") {
            Text(record.connectionContext)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .font(.caption)
        }

        if !record.parameters.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Parameters")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            ForEach(record.parameters) { param in
              HStack(alignment: .top, spacing: 6) {
                Text(param.key)
                  .font(.caption.monospaced().weight(.medium))
                  .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(param.value)
                  .font(.caption.monospaced())
                  .multilineTextAlignment(.trailing)
                  .textSelection(.enabled)
              }
            }
          }
        } else {
          Text("No parameters")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(record.outcome.isSuccess ? "Result" : "Error")
            .font(.caption.weight(.semibold))
            .foregroundStyle(record.outcome.isSuccess ? Color.secondary : Color.red)
          Text(record.outcome.message)
            .font(.caption)
            .foregroundStyle(record.outcome.isSuccess ? Color.primary : Color.red)
            .textSelection(.enabled)
        }
      }
      .padding(.vertical, 4)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: record.outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .font(.subheadline)
          .foregroundStyle(record.outcome.isSuccess ? .green : .red)
          .padding(.top, 2)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(record.displayTitle)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)

            Text(record.kind == .toolIntent ? "Tool" : "Query")
              .font(.caption2.weight(.semibold))
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(
                (record.kind == .toolIntent ? Color.accentColor : Color.secondary).opacity(0.14),
                in: Capsule()
              )
              .foregroundStyle(record.kind == .toolIntent ? Color.accentColor : Color.secondary)
          }

          HStack(spacing: 6) {
            Text(record.timestamp, format: .dateTime.hour().minute().second())
            Text("·")
            Text("\(record.durationMs) ms")
            if !record.parameters.isEmpty {
              Text("·")
              Text("\(record.parameters.count) \(record.parameters.count == 1 ? "param" : "params")")
            }
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)

          Text(record.outcome.message)
            .font(.caption)
            .foregroundStyle(record.outcome.isSuccess ? Color.secondary : Color.red)
            .lineLimit(1)
        }
      }
    }
  }

  private var healthSummaryGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
      metricCell(
        title: "Loop",
        value: model.snapshot.latestState?.controlLoop?.hz.map { String(format: "%.1f Hz", $0) } ?? "–",
        subtitle: "\(model.snapshot.latestState?.controlLoop?.missed ?? 0) missed",
        tint: .green
      )
      metricCell(
        title: "Battery",
        value: model.snapshot.health?.battery.map { "\(Int($0.percent.rounded()))%" } ?? "–",
        subtitle: model.snapshot.health?.battery.map { String(format: "%.2f V", $0.volts) } ?? "Waiting",
        tint: .mint
      )
      metricCell(
        title: "Thermals",
        value: model.snapshot.health?.motors.map { String(format: "%.0f °C", $0.maxC) } ?? "–",
        subtitle: model.snapshot.health?.motors?.hottest.replacingOccurrences(of: "_", with: " ") ?? "15 servos",
        tint: .orange
      )
      metricCell(
        title: "Link",
        value: model.snapshot.linkStats.bitrateKbps.map { "\($0) kbps" } ?? "–",
        subtitle: model.snapshot.linkStats.rttMs.map { "\($0) ms · \(model.snapshot.linkStats.fps ?? 0) fps" } ?? "Idle",
        tint: .cyan
      )
    }
    .padding(.vertical, 6)
  }

  private func metricCell(
    title: String,
    value: String,
    subtitle: String,
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
      Text(value)
        .font(.title3.monospacedDigit().weight(.semibold))
      Text(subtitle)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var loopChartContent: some View {
    if model.snapshot.loopHistory.isEmpty {
      Text("Connect to stream 50 Hz loop cadence.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 12)
    } else {
      Chart(model.snapshot.loopHistory) { sample in
        AreaMark(
          x: .value("Sample", sample.id),
          yStart: .value("Floor", 40.0),
          yEnd: .value("Hz", sample.hz)
        )
        .foregroundStyle(Color.green.opacity(0.14).gradient)
        .interpolationMethod(.catmullRom)

        LineMark(
          x: .value("Sample", sample.id),
          y: .value("Hz", sample.hz)
        )
        .foregroundStyle(.green)
        .interpolationMethod(.catmullRom)

        RuleMark(y: .value("Gate", 45.0))
          .foregroundStyle(.orange.opacity(0.45))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }
      .chartYScale(domain: 40...55)
      .chartXAxis(.hidden)
      .frame(height: 110)
      .padding(.vertical, 4)
    }
  }

  @ViewBuilder
  private var slamMapContent: some View {
    if let grid = model.snapshot.mapGrid, grid.width > 0, grid.height > 0 {
      SlamGridCanvasView(grid: grid)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 4)
    } else {
      Text("Nothing mapped yet. The map grows as the duck stops and looks around.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
    }
  }

  @ViewBuilder
  private var jointTrackingRows: some View {
    let joints = model.snapshot.latestState?.joints ?? []
    let targets = model.snapshot.latestState?.targets ?? []

    ForEach(Array(DuckConstants.jointNames.enumerated()), id: \.offset) { index, name in
      let measured = index < joints.count ? joints[index] : 0
      let target = index < targets.count ? targets[index] : measured
      let errorRad = measured - target

      HStack(spacing: 8) {
        Text(name.replacingOccurrences(of: "_", with: " "))
          .font(.caption.monospaced())
          .frame(width: 112, alignment: .leading)
          .lineLimit(1)

        GeometryReader { barProxy in
          let mid = barProxy.size.width / 2
          let normalized = min(max(errorRad / DuckConstants.jointDeviationFullScaleRadians, -1), 1)
          let span = abs(CGFloat(normalized)) * mid

          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.primary.opacity(0.08))
            Rectangle()
              .fill(Color.primary.opacity(0.20))
              .frame(width: 1)
              .offset(x: mid)
            Capsule()
              .fill(abs(normalized) > 0.75 ? Color.orange : Color.accentColor)
              .frame(width: max(3, span))
              .offset(x: normalized >= 0 ? mid : mid - span)
          }
        }
        .frame(height: 6)

        Text(formattedAngle(measured))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 54, alignment: .trailing)
      }
    }
  }

  @ViewBuilder
  private var wireLogRows: some View {
    if model.snapshot.logs.isEmpty {
      Text("No messages recorded yet.")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      ForEach(model.snapshot.logs.suffix(12)) { entry in
        Text(entry.message)
          .font(.caption2.monospaced())
          .foregroundStyle(colorForLog(entry.level))
      }
    }
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
    $0.intentTelemetry = .previewValue
  }
) {
  TelemetryInspectorView(model: TelemetryModel())
}
