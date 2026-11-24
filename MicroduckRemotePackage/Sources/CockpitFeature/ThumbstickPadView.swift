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
            .fill(.regularMaterial)
            .overlay(
              Circle()
                .strokeBorder(
                  isDeflected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.10),
                  lineWidth: isDeflected ? 1.5 : 1
                )
            )

          if mode == .horizontalOnly {
            Capsule()
              .fill(Color.primary.opacity(0.08))
              .frame(width: diameter - 32, height: 6)
          } else {
            Circle()
              .fill(Color.primary.opacity(0.08))
              .frame(width: 6, height: 6)
          }

          Circle()
            .fill(isDeflected ? Color.accentColor : Color.white)
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            .frame(width: knobSize, height: knobSize)
            .offset(x: knobOffsetX, y: knobOffsetY)
            .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78), value: normalizedX)
            .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78), value: normalizedY)
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
