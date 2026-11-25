import DuckProtocol
import SwiftUI

/// Lightweight 2D planar odometry breadcrumb point recorded as Microduck walks.
public struct OdomBreadcrumb: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// 3-zone curved ToF proximity radar (Left / Front / Right) that shifts smoothly
/// from emerald (>60 cm) → amber (30–60 cm) → crimson (<30 cm).
public struct TofProximityArcHUD: View {
  public let analysis: TofZoneAnalysis

  public init(analysis: TofZoneAnalysis) {
    self.analysis = analysis
  }

  public var body: some View {
    VStack(spacing: 4) {
      ZStack {
        // Left arc (-148° to -114°)
        arcSegment(startDeg: -148, endDeg: -114, color: color(for: analysis.leftMm))
        // Front arc (-108° to -72°)
        arcSegment(startDeg: -108, endDeg: -72, color: color(for: analysis.frontMm))
        // Right arc (-66° to -32°)
        arcSegment(startDeg: -66, endDeg: -32, color: color(for: analysis.rightMm))

        // Tiny robot chevron below the radar arc
        Image(systemName: "location.north.fill")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.white.opacity(0.9))
          .offset(y: 12)
      }
      .frame(width: 112, height: 36)

      HStack(spacing: 8) {
        zoneLabel("L", mm: analysis.leftMm)
        zoneLabel("F", mm: analysis.frontMm)
        zoneLabel("R", mm: analysis.rightMm)
      }
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .monospacedDigit()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
    )
  }

  private func arcSegment(startDeg: Double, endDeg: Double, color: Color) -> some View {
    Path { path in
      path.addArc(
        center: CGPoint(x: 56, y: 46),
        radius: 36,
        startAngle: .degrees(startDeg),
        endAngle: .degrees(endDeg),
        clockwise: false
      )
    }
    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
    .shadow(color: color.opacity(0.45), radius: 3)
  }

  private func zoneLabel(_ tag: String, mm: Int?) -> some View {
    let text: String = if let mm {
      mm >= DuckConstants.tofMaxRangeMm ? "4m+" : "\(mm / 10)cm"
    } else {
      "—"
    }
    return HStack(spacing: 2) {
      Text(tag)
        .foregroundStyle(.white.opacity(0.55))
      Text(text)
        .foregroundStyle(color(for: mm))
        .frame(width: 34, alignment: .leading)
        .lineLimit(1)
    }
  }

  private func color(for mm: Int?) -> Color {
    guard let mm else { return .white.opacity(0.35) }
    if mm < 300 { return .red }
    if mm < 600 { return .orange }
    return .green
  }
}

/// Compact glass heading compass + recent odometry breadcrumb path trail.
public struct OdometryCompassTrailHUD: View {
  public let odom: OdomTelemetry
  public let trail: [OdomBreadcrumb]
  public let onResetTrail: () -> Void

  public init(
    odom: OdomTelemetry,
    trail: [OdomBreadcrumb],
    onResetTrail: @escaping () -> Void
  ) {
    self.odom = odom
    self.trail = trail
    self.onResetTrail = onResetTrail
  }

  public var body: some View {
    Button(action: onResetTrail) {
      HStack(spacing: 8) {
        Canvas { context, size in
          let center = CGPoint(x: size.width / 2, y: size.height / 2)
          let radius = min(size.width, size.height) / 2 - 4

          // Subtle radar ring
          context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.white.opacity(0.18)),
            lineWidth: 1
          )

          // Breadcrumb trail centered around current odom position (auto-scaled to >= 0.8 m span)
          if trail.count >= 2 {
            let maxOffset = max(
              0.8,
              trail.reduce(0.0) { acc, pt in
                max(acc, hypot(pt.x - odom.x, pt.y - odom.y))
              } * 1.15
            )
            var path = Path()
            for (idx, pt) in trail.enumerated() {
              // Map robot world +X up, +Y left onto canvas
              let dx = -(pt.y - odom.y) / maxOffset * radius
              let dy = -(pt.x - odom.x) / maxOffset * radius
              let p = CGPoint(x: center.x + dx, y: center.y + dy)
              if idx == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(
              path,
              with: .color(.cyan.opacity(0.85)),
              style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
          }

          // Live heading arrow at center
          let headingRad = odom.yaw
          let tip = CGPoint(
            x: center.x - sin(headingRad) * 9,
            y: center.y - cos(headingRad) * 9
          )
          var arrow = Path()
          arrow.move(to: center)
          arrow.addLine(to: tip)
          context.stroke(
            arrow,
            with: .color(.orange),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
          )
          context.fill(
            Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
            with: .color(.white)
          )
        }
        .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 2) {
          Text("\(Int(odom.yawDegrees.rounded()))°")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text(String(format: "%.2f, %.2fm", odom.x, odom.y))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
        }
        .frame(width: 86, alignment: .leading)
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(.white.opacity(0.14), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .help("Live heading & odometry trail (click to clear trail)")
  }
}

/// 1-click closed-loop odometry & ToF motion pills for effortless desktop & touch driving.
public struct QuickMotionDeckView: View {
  public let isEnabled: Bool
  public let activeLabel: String?
  public let onAction: (String, DuckMotionGoal) -> Void

  public init(
    isEnabled: Bool,
    activeLabel: String?,
    onAction: @escaping (String, DuckMotionGoal) -> Void
  ) {
    self.isEnabled = isEnabled
    self.activeLabel = activeLabel
    self.onAction = onAction
  }

  public var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        motionPill(
          label: "Left 90°",
          systemImage: "arrow.counterclockwise",
          goal: .turnAngle(degrees: 90, speedPercent: 85)
        )
        motionPill(
          label: "+0.5 m",
          systemImage: "arrow.up",
          goal: .moveDistance(direction: .forward, meters: 0.5, speedPercent: 65, stopOnObstacle: true)
        )
        motionPill(
          label: "Approach 30cm",
          systemImage: "arrow.up.to.line",
          goal: .approachObstacle(targetClearanceMm: 300, speedPercent: 55)
        )
        motionPill(
          label: "−0.3 m",
          systemImage: "arrow.down",
          goal: .moveDistance(direction: .backward, meters: 0.3, speedPercent: 60, stopOnObstacle: false)
        )
        motionPill(
          label: "Right 90°",
          systemImage: "arrow.clockwise",
          goal: .turnAngle(degrees: -90, speedPercent: 85)
        )
      }
    }
  }

  private func motionPill(label: String, systemImage: String, goal: DuckMotionGoal) -> some View {
    let isRunning = activeLabel == label
    return Button {
      onAction(label, goal)
    } label: {
      HStack(spacing: 5) {
        if isRunning {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: systemImage)
        }
        Text(label)
      }
      .font(.caption.weight(.semibold))
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .controlSize(.small)
    .tint(isRunning ? .orange : .primary)
    .disabled(!isEnabled || (activeLabel != nil && !isRunning))
  }
}
