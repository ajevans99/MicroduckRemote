import SwiftUI
import simd

public struct FloorPlanPreviewCanvas: View {
  public let preview: FloorPlanPreview

  public init(preview: FloorPlanPreview) {
    self.preview = preview
  }

  public var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size)
      context.fill(
        Path(roundedRect: rect, cornerRadius: 16),
        with: .color(Color(red: 0.07, green: 0.09, blue: 0.13))
      )

      let padding: CGFloat = 24
      let usableWidth = max(size.width - padding * 2, 20)
      let usableHeight = max(size.height - padding * 2, 20)

      let spanX = max(preview.boundsMax.x - preview.boundsMin.x, 1.0)
      let spanY = max(preview.boundsMax.y - preview.boundsMin.y, 1.0)
      let pixelsPerMeter = min(usableWidth / spanX, usableHeight / spanY)

      let worldMidX = (preview.boundsMin.x + preview.boundsMax.x) * 0.5
      let worldMidY = (preview.boundsMin.y + preview.boundsMax.y) * 0.5

      func toScreen(_ world: SIMD2<Double>) -> CGPoint {
        CGPoint(
          x: size.width * 0.5 + (world.x - worldMidX) * pixelsPerMeter,
          y: size.height * 0.5 - (world.y - worldMidY) * pixelsPerMeter
        )
      }

      let gridStartX = floor(preview.boundsMin.x - 1)
      let gridEndX = ceil(preview.boundsMax.x + 1)
      var gx = gridStartX
      while gx <= gridEndX {
        var gridLine = Path()
        gridLine.move(to: CGPoint(x: toScreen(SIMD2(gx, 0)).x, y: 0))
        gridLine.addLine(to: CGPoint(x: toScreen(SIMD2(gx, 0)).x, y: size.height))
        let isAxis = abs(gx) < 1e-4
        context.stroke(
          gridLine,
          with: .color(.white.opacity(isAxis ? 0.16 : 0.06)),
          lineWidth: isAxis ? 1.2 : 0.6
        )
        gx += 1.0
      }

      let gridStartY = floor(preview.boundsMin.y - 1)
      let gridEndY = ceil(preview.boundsMax.y + 1)
      var gy = gridStartY
      while gy <= gridEndY {
        var gridLine = Path()
        gridLine.move(to: CGPoint(x: 0, y: toScreen(SIMD2(0, gy)).y))
        gridLine.addLine(to: CGPoint(x: size.width, y: toScreen(SIMD2(0, gy)).y))
        let isAxis = abs(gy) < 1e-4
        context.stroke(
          gridLine,
          with: .color(.white.opacity(isAxis ? 0.16 : 0.06)),
          lineWidth: isAxis ? 1.2 : 0.6
        )
        gy += 1.0
      }

      for polygon in preview.floorPolygons where polygon.count >= 3 {
        var polyPath = Path()
        polyPath.move(to: toScreen(polygon[0]))
        for pt in polygon.dropFirst() {
          polyPath.addLine(to: toScreen(pt))
        }
        polyPath.closeSubpath()
        context.fill(polyPath, with: .color(Color.cyan.opacity(0.08)))
      }

      for geom in preview.geoms {
        guard geom.kind != .floorOverlay, geom.kind != .lintel else { continue }
        let center2D = SIMD2<Double>(geom.position.x, geom.position.y)

        switch geom.shape {
        case let .cylinder(radius, _):
          let screenCenter = toScreen(center2D)
          let rPx = max(radius * pixelsPerMeter, 3)
          let ellipseRect = CGRect(
            x: screenCenter.x - rPx,
            y: screenCenter.y - rPx,
            width: rPx * 2,
            height: rPx * 2
          )
          let circlePath = Path(ellipseIn: ellipseRect)
          context.fill(circlePath, with: .color(fillColor(for: geom.kind)))
          context.stroke(circlePath, with: .color(strokeColor(for: geom.kind)), lineWidth: 1.2)

        case let .box(halfExtents):
          let c = cos(geom.yawRadians)
          let s = sin(geom.yawRadians)
          let ux = SIMD2<Double>(c, s) * halfExtents.x
          let uy = SIMD2<Double>(-s, c) * halfExtents.y
          let worldCorners = [
            center2D - ux - uy,
            center2D + ux - uy,
            center2D + ux + uy,
            center2D - ux + uy,
          ]
          var boxPath = Path()
          boxPath.move(to: toScreen(worldCorners[0]))
          for corner in worldCorners.dropFirst() {
            boxPath.addLine(to: toScreen(corner))
          }
          boxPath.closeSubpath()
          context.fill(boxPath, with: .color(fillColor(for: geom.kind)))
          context.stroke(boxPath, with: .color(strokeColor(for: geom.kind)), lineWidth: 1.2)
        }
      }

      for doorway in preview.openDoorways {
        let halfSpan = doorway.tangent * (doorway.width * 0.5)
        let p0 = toScreen(doorway.center - halfSpan)
        let p1 = toScreen(doorway.center + halfSpan)
        var gapPath = Path()
        gapPath.move(to: p0)
        gapPath.addLine(to: p1)
        context.stroke(
          gapPath,
          with: .color(.green.opacity(0.85)),
          style: StrokeStyle(lineWidth: 3.0, lineCap: .round, dash: [5, 4])
        )
      }

      let spawnScreen = toScreen(preview.spawnPoint)
      if preview.spawnClearanceMeters > 0.05 {
        let clearRadiusPx = min(preview.spawnClearanceMeters, 0.45) * pixelsPerMeter
        let clearRect = CGRect(
          x: spawnScreen.x - clearRadiusPx,
          y: spawnScreen.y - clearRadiusPx,
          width: clearRadiusPx * 2,
          height: clearRadiusPx * 2
        )
        context.stroke(
          Path(ellipseIn: clearRect),
          with: .color(.yellow.opacity(0.45)),
          style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
        )
      }

      var headingPath = Path()
      headingPath.move(to: spawnScreen)
      headingPath.addLine(to: CGPoint(x: spawnScreen.x + 16, y: spawnScreen.y))
      context.stroke(headingPath, with: .color(.yellow), lineWidth: 2.2)

      let duckDotRect = CGRect(
        x: spawnScreen.x - 5.5,
        y: spawnScreen.y - 5.5,
        width: 11,
        height: 11
      )
      context.fill(Path(ellipseIn: duckDotRect), with: .color(.yellow))
      context.stroke(Path(ellipseIn: duckDotRect), with: .color(.black), lineWidth: 1.5)
    }
    .overlay(alignment: .bottomLeading) {
      HStack(spacing: 12) {
        legendDot(color: .white.opacity(0.9), label: "Wall")
        legendDot(color: .green, label: "Open Doorway")
        legendDot(color: .orange, label: "Furniture")
        legendDot(color: .yellow, label: "Duck (0,0)")
      }
      .font(.caption2.weight(.medium))
      .foregroundStyle(.white.opacity(0.85))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(.black.opacity(0.55), in: Capsule())
      .padding(10)
    }
    .overlay(alignment: .topTrailing) {
      Text("1 m grid · +X → · +Y ↑")
        .font(.caption2.monospaced())
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(10)
    }
  }

  private func fillColor(for kind: MJCFGeomKind) -> Color {
    switch kind {
    case .wall, .lintel:
      .white.opacity(0.88)
    case .closedDoor:
      Color(red: 0.78, green: 0.52, blue: 0.30).opacity(0.90)
    case .floorOverlay:
      .clear
    case .furniture:
      Color.orange.opacity(0.45)
    }
  }

  private func strokeColor(for kind: MJCFGeomKind) -> Color {
    switch kind {
    case .wall, .lintel:
      .white
    case .closedDoor:
      Color(red: 0.92, green: 0.68, blue: 0.42)
    case .floorOverlay:
      .clear
    case .furniture:
      Color.orange.opacity(0.90)
    }
  }

  @ViewBuilder
  private func legendDot(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(label)
    }
  }
}
