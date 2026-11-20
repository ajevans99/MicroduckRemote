import SwiftUI

public struct ThumbstickPadView: View {
  public enum AxisMode {
    case omnidirectional
    case horizontalOnly
  }

  public let title: String
  public let subtitle: String
  public let mode: AxisMode
  public let normalizedX: Double
  public let normalizedY: Double
  public let isEnabled: Bool
  public let onMove: (Double, Double) -> Void
  public let onRelease: () -> Void

  public init(
    title: String,
    subtitle: String,
    mode: AxisMode,
    normalizedX: Double,
    normalizedY: Double,
    isEnabled: Bool,
    onMove: @escaping (Double, Double) -> Void,
    onRelease: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.mode = mode
    self.normalizedX = normalizedX
    self.normalizedY = normalizedY
    self.isEnabled = isEnabled
    self.onMove = onMove
    self.onRelease = onRelease
  }

  public var body: some View {
    VStack(spacing: 8) {
      GeometryReader { proxy in
        let diameter = min(proxy.size.width, proxy.size.height)
        let knobSize = max(44, diameter * 0.36)
        let travelRadius = max(1, (diameter - knobSize) / 2 - 6)
        let knobOffsetX = CGFloat(normalizedX) * travelRadius
        let knobOffsetY = CGFloat(mode == .horizontalOnly ? 0 : normalizedY) * travelRadius
        let isDeflected = abs(normalizedX) > 0.01 || abs(normalizedY) > 0.01

        ZStack {
          Circle()
            .fill(.ultraThinMaterial)
            .overlay(
              Circle()
                .strokeBorder(
                  isDeflected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.14),
                  lineWidth: isDeflected ? 1.75 : 1
                )
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)

          if mode == .omnidirectional {
            Circle()
              .strokeBorder(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .padding(diameter * 0.22)

            Path { path in
              path.move(to: CGPoint(x: diameter / 2, y: 14))
              path.addLine(to: CGPoint(x: diameter / 2, y: diameter - 14))
              path.move(to: CGPoint(x: 14, y: diameter / 2))
              path.addLine(to: CGPoint(x: diameter - 14, y: diameter / 2))
            }
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
          } else {
            Capsule()
              .fill(Color.primary.opacity(0.07))
              .frame(width: diameter - 28, height: 8)
            HStack {
              Image(systemName: "arrow.counterclockwise")
              Spacer()
              Image(systemName: "arrow.clockwise")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.7))
            .padding(.horizontal, 18)
          }

          Circle()
            .fill(
              LinearGradient(
                colors: isDeflected
                  ? [Color.accentColor, Color.accentColor.opacity(0.78)]
                  : [Color.white.opacity(0.92), Color.white.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .overlay(
              Circle()
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            .frame(width: knobSize, height: knobSize)
            .offset(x: knobOffsetX, y: knobOffsetY)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.75), value: normalizedX)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.75), value: normalizedY)
        }
        .frame(width: diameter, height: diameter)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        .contentShape(Circle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard isEnabled else { return }
              let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
              let dx = Double((value.location.x - center.x) / travelRadius)
              let dy = Double((value.location.y - center.y) / travelRadius)
              if mode == .horizontalOnly {
                onMove(min(max(dx, -1), 1), 0)
              } else {
                let mag = hypot(dx, dy)
                if mag > 1 {
                  onMove(dx / mag, dy / mag)
                } else {
                  onMove(dx, dy)
                }
              }
            }
            .onEnded { _ in
              onRelease()
            }
        )
      }
      .aspectRatio(1, contentMode: .fit)

      VStack(spacing: 1) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
    .opacity(isEnabled ? 1.0 : 0.48)
  }
}
