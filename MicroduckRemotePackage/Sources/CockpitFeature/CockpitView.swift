import Dependencies
import DuckDependencies
import DuckProtocol
import SwiftUI
import SwiftUINavigation

public struct CockpitView: View {
  @Bindable var model: CockpitModel
  @Environment(\.duckVideoRenderer) private var duckVideoRenderer

  public init(model: CockpitModel) {
    self.model = model
  }

  public var body: some View {
    GeometryReader { proxy in
      let isCompactLandscape = proxy.size.width > proxy.size.height && proxy.size.height < 520
      if isCompactLandscape {
        landscapeCockpit(size: proxy.size)
          .background(.black)
      } else {
        NavigationStack {
          portraitCockpit(size: proxy.size)
            #if canImport(UIKit)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
              #if os(macOS)
              ToolbarItem(placement: .navigation) {
                connectionToolbarButton
              }
              #else
              ToolbarItem(placement: .principal) {
                connectionToolbarButton
              }
              #endif
              ToolbarItem(placement: .primaryAction) {
                modesMenu
              }
            }
        }
      }
    }
    .task {
      await model.task()
    }
    .alert(item: $model.alert) { destination in
      switch destination {
      case .confirmRelax:
        Alert(
          title: Text("Relax All Servos?"),
          message: Text("Motor torque will turn off immediately and the duck will collapse onto the floor."),
          primaryButton: .destructive(Text("Relax Motors")) {
            Task { await model.relaxConfirmedButtonTapped() }
          },
          secondaryButton: .cancel()
        )
      case let .errorMessage(message):
        Alert(
          title: Text("Duck Refused Action"),
          message: Text(message),
          dismissButton: .default(Text("OK"))
        )
      }
    }
  }

  private func portraitCockpit(size: CGSize) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: 16) {
        videoStageCard
          .frame(height: min(max(size.height * 0.36, 220), 380))

        postureAndSoundsRow

        if model.showSoundDrawer {
          soundboardStrip
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        quickSkillsStrip

        thumbsticksDeck
          .frame(height: 188)
          .padding(.top, 4)
      }
      .padding(.horizontal, 16)
      .padding(.top, 10)
      .padding(.bottom, 24)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
  }

  private func landscapeCockpit(size: CGSize) -> some View {
    ZStack {
      videoStageCard
        .ignoresSafeArea()

      VStack {
        HStack {
          connectionToolbarButton
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
          Spacer()
          quickSkillsStrip
            .frame(maxWidth: size.width * 0.44)
          modesMenu
            .padding(8)
            .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)

        Spacer()

        if model.showSoundDrawer {
          soundboardStrip
            .padding(.horizontal, 24)
        }

        HStack(alignment: .bottom, spacing: 20) {
          ThumbstickPadView(
            title: "Move",
            subtitle: String(format: "%+.2f m/s", model.currentTwist.vx),
            mode: .omnidirectional,
            normalizedX: model.leftStickX,
            normalizedY: model.leftStickY,
            isEnabled: model.snapshot.controlOpen,
            onMove: { x, y in Task { await model.leftThumbstickMoved(x: x, y: y) } },
            onRelease: { Task { await model.leftThumbstickReleased() } }
          )
          .frame(width: 148, height: 172)

          Spacer()

          postureAndSoundsRow

          Spacer()

          ThumbstickPadView(
            title: "Turn",
            subtitle: String(format: "%+.2f rad/s", model.currentTwist.vyaw),
            mode: .horizontalOnly,
            normalizedX: model.rightStickX,
            normalizedY: 0,
            isEnabled: model.snapshot.controlOpen,
            onMove: { x, _ in Task { await model.rightThumbstickMoved(x: x) } },
            onRelease: { Task { await model.rightThumbstickReleased() } }
          )
          .frame(width: 148, height: 172)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
      }
    }
  }

  private var connectionToolbarButton: some View {
    Button {
      model.connectionHeaderTapped()
    } label: {
      HStack(spacing: 6) {
        Circle()
          .fill(statusDotColor)
          .frame(width: 8, height: 8)

        Text(model.snapshot.phase.statusText)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)

        if let battery = model.snapshot.health?.battery {
          Text("· \(Int(battery.percent.rounded()))%")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        } else if case let .connected(identity) = model.snapshot.phase, identity.isSimulated {
          Text("· Sim")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Image(systemName: "chevron.down")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
  }

  private var statusDotColor: Color {
    if model.snapshot.controlOpen {
      return .green
    }
    switch model.snapshot.phase {
    case .connecting:
      return .orange
    case .failed:
      return .red
    case .disconnected, .connected:
      return .secondary
    }
  }

  private var videoStageCard: some View {
    GeometryReader { stageProxy in
      ZStack {
        Color.black

        duckVideoRenderer(model.snapshot.videoInfo)
          .frame(width: stageProxy.size.width, height: stageProxy.size.height)

        detectionBoxesOverlay(in: stageProxy.size)

        if model.isLooking {
          gazeReticle(in: stageProxy.size)
        }

        VStack {
          HStack {
            safetyBadge
            if model.gamepadState.isConnected, let name = model.gamepadState.controllerName {
              Label(name, systemImage: "gamecontroller.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            Button {
              Task { await model.tofOverlayButtonTapped() }
            } label: {
              Image(systemName: model.showTofOverlay ? "square.grid.3x3.fill" : "square.grid.3x3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle 8x8 Depth Overlay")
          }
          .padding(12)

          Spacer()

          HStack(alignment: .bottom) {
            if model.showTofOverlay, let tof = model.snapshot.tofFrame {
              TofMiniHeatmapView(frame: tof)
                .frame(width: 88, height: 88)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if !model.snapshot.controlOpen {
              Button("Connect") {
                model.connectionHeaderTapped()
              }
              .buttonStyle(.borderedProminent)
              .buttonBorderShape(.capsule)
              .controlSize(.small)
            }
          }
          .padding(12)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { gesture in
            guard stageProxy.size.width > 0, stageProxy.size.height > 0 else { return }
            let nx = (2.0 * Double(gesture.location.x) / Double(stageProxy.size.width)) - 1.0
            let ny = (2.0 * Double(gesture.location.y) / Double(stageProxy.size.height)) - 1.0
            Task { await model.videoStageDragged(normalizedX: nx, normalizedY: ny) }
          }
          .onEnded { _ in
            model.videoStageDragEnded()
          }
      )
    }
  }

  @ViewBuilder
  private var safetyBadge: some View {
    let safety = model.snapshot.latestState?.safety
    if model.isFallen {
      Button {
        Task { await model.standBackUpButtonTapped() }
      } label: {
        Label(
          model.isStandingBackUp ? "Standing Up…" : "Fallen · Stand Up",
          systemImage: "arrow.up.circle.fill"
        )
        .font(.caption.weight(.semibold))
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .tint(.orange)
      .controlSize(.small)
    } else if let safety, !safety.isNominal {
      Label(safety.statusLabel, systemImage: "exclamationmark.triangle.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    } else if let fps = model.snapshot.linkStats.fps, model.snapshot.controlOpen {
      Text("\(fps) fps")
        .font(.caption2.monospacedDigit().weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
    }
  }

  private func gazeReticle(in size: CGSize) -> some View {
    let x = CGFloat((model.gazeNormalizedX + 1) * 0.5) * size.width
    let y = CGFloat((model.gazeNormalizedY + 1) * 0.5) * size.height
    let tint: Color = model.isGazeClamped ? .orange : .white
    return ZStack {
      Circle()
        .strokeBorder(tint, lineWidth: 1.5)
        .frame(width: 34, height: 34)
      Circle()
        .fill(tint)
        .frame(width: 5, height: 5)
      if model.isGazeClamped {
        Text("Limit")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.orange, in: Capsule())
          .offset(y: -26)
      }
    }
    .position(x: x, y: y)
  }

  private func detectionBoxesOverlay(in size: CGSize) -> some View {
    Group {
      if let det = model.snapshot.detections, det.width > 0, det.height > 0 {
        ForEach(det.boxes) { box in
          let scaleX = size.width / CGFloat(det.width)
          let scaleY = size.height / CGFloat(det.height)
          let w = max(0, CGFloat(box.x1 - box.x0) * scaleX)
          let h = max(0, CGFloat(box.y1 - box.y0) * scaleY)
          let cx = CGFloat(box.x0) * scaleX + w / 2
          let cy = CGFloat(box.y0) * scaleY + h / 2

          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(.yellow, lineWidth: 2)
            .frame(width: w, height: h)
            .position(x: cx, y: cy)
        }
      }
    }
  }

  private var postureAndSoundsRow: some View {
    HStack(spacing: 10) {
      if model.isFallen {
        Button {
          Task { await model.standBackUpButtonTapped() }
        } label: {
          HStack(spacing: 6) {
            if model.isStandingBackUp {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.up.circle.fill")
            }
            Text(model.isStandingBackUp ? "Standing Up…" : "Stand Back Up")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.orange)
        .controlSize(.large)
        .disabled(!model.snapshot.controlOpen || model.isStandingBackUp)
      } else {
        Button {
          Task { await model.standToggleButtonTapped() }
        } label: {
          Label(
            model.isEnabled ? "Balancing" : "Stand",
            systemImage: model.isEnabled ? "figure.stand" : "play.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(model.isEnabled ? .green : .accentColor)
        .controlSize(.large)
        .disabled(!model.snapshot.controlOpen)
      }

      Button {
        Task { await model.stopButtonTapped() }
      } label: {
        Label("Stop", systemImage: "stop.fill")
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .tint(.red)
      .controlSize(.large)
      .disabled(!model.snapshot.controlOpen)

      Button {
        withAnimation(.snappy(duration: 0.25)) {
          model.soundDrawerToggleTapped()
        }
      } label: {
        Image(systemName: model.showSoundDrawer ? "speaker.wave.3.fill" : "speaker.wave.2")
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.circle)
      .tint(model.showSoundDrawer ? .accentColor : .primary)
      .controlSize(.large)
      .disabled(!model.snapshot.controlOpen)
      .accessibilityLabel("Sounds")
    }
  }

  private var modesMenu: some View {
    Menu {
      Section("Modes") {
        Button {
          Task { await model.autonomousToggleTapped() }
        } label: {
          Label(
            model.autonomousEnabled ? "Disable Autonomous" : "Autonomous Mode",
            systemImage: "sparkles"
          )
        }
        Button {
          Task { await model.flashlightToggleTapped() }
        } label: {
          Label(
            model.flashlightEnabled ? "Turn Off Flashlight" : "Flashlight",
            systemImage: "flashlight.on.fill"
          )
        }
        Button {
          Task { await model.laserTrackToggleTapped() }
        } label: {
          Label(
            model.laserTrackEnabled ? "Stop Laser Tracking" : "Laser Tracking",
            systemImage: "scope"
          )
        }
        Button {
          Task { await model.soccerToggleTapped() }
        } label: {
          Label(
            model.soccerEnabled ? "Stop Soccer Mode" : "Soccer Mode",
            systemImage: "soccerball"
          )
        }
      }

      Section("Motors") {
        Button {
          Task { await model.initPoseButtonTapped() }
        } label: {
          Label("Home Pose", systemImage: "arrow.uturn.backward.circle")
        }
        Button {
          Task { await model.rebootMotorsButtonTapped() }
        } label: {
          Label("Reboot Motors", systemImage: "bolt.arrow.trianglehead.counterclockwise")
        }
        Button(role: .destructive) {
          model.relaxMenuButtonTapped()
        } label: {
          Label("Relax Motors…", systemImage: "poweroff")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .disabled(!model.snapshot.controlOpen)
  }

  private var quickSkillsStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(model.snapshot.skillNames, id: \.self) { skill in
          let isRunning = model.activeSkillName == skill
          Button {
            Task { await model.quickSkillButtonTapped(skill) }
          } label: {
            HStack(spacing: 5) {
              if isRunning {
                ProgressView()
                  .controlSize(.mini)
              } else {
                Image(systemName: iconForSkill(skill))
              }
              Text(prettySkillName(skill))
            }
            .font(.footnote.weight(.medium))
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .controlSize(.small)
          .disabled(!model.snapshot.controlOpen)
        }
      }
    }
  }

  private var soundboardStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(SoundTag.allCases) { sound in
          if sound.isHoldable {
            Label("Hold Wheee", systemImage: sound.systemImage)
              .font(.footnote.weight(.medium))
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(
                model.isHoldingWheee ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.08),
                in: Capsule()
              )
              .foregroundStyle(model.isHoldingWheee ? Color.accentColor : .primary)
              .gesture(
                DragGesture(minimumDistance: 0)
                  .onChanged { _ in
                    Task { await model.wheeeHoldChanged(isPressed: true) }
                  }
                  .onEnded { _ in
                    Task { await model.wheeeHoldChanged(isPressed: false) }
                  }
              )
          } else {
            Button {
              Task { await model.soundButtonTapped(sound) }
            } label: {
              Label(sound.displayName, systemImage: sound.systemImage)
                .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
          }
        }
      }
    }
  }

  private var thumbsticksDeck: some View {
    HStack(spacing: 24) {
      ThumbstickPadView(
        title: "Move",
        subtitle: String(format: "%+.2f, %+.2f", model.currentTwist.vx, model.currentTwist.vy),
        mode: .omnidirectional,
        normalizedX: model.leftStickX,
        normalizedY: model.leftStickY,
        isEnabled: model.snapshot.controlOpen,
        onMove: { x, y in Task { await model.leftThumbstickMoved(x: x, y: y) } },
        onRelease: { Task { await model.leftThumbstickReleased() } }
      )

      ThumbstickPadView(
        title: "Turn",
        subtitle: String(format: "%+.2f rad/s", model.currentTwist.vyaw),
        mode: .horizontalOnly,
        normalizedX: model.rightStickX,
        normalizedY: 0,
        isEnabled: model.snapshot.controlOpen,
        onMove: { x, _ in Task { await model.rightThumbstickMoved(x: x) } },
        onRelease: { Task { await model.rightThumbstickReleased() } }
      )
    }
    .padding(.horizontal, 8)
  }

  private func prettySkillName(_ raw: String) -> String {
    switch raw {
    case "sit_toggle": "Sit"
    case "ground_pick": "Pick"
    case "kick_left": "Kick Left"
    case "kick_right": "Kick Right"
    default:
      raw
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .capitalized
    }
  }

  private func iconForSkill(_ raw: String) -> String {
    switch raw {
    case "roulade": "arrow.clockwise"
    case "kick_left", "kick_right": "figure.soccer"
    case "ground_pick": "arrow.down.to.line.compact"
    case "sit_toggle": "figure.seated.side"
    default: "sparkles"
    }
  }
}

public struct TofMiniHeatmapView: View {
  public let frame: TofFrame

  public init(frame: TofFrame) {
    self.frame = frame
  }

  public var body: some View {
    let rows = max(1, frame.rows)
    let cols = max(1, frame.cols)
    VStack(spacing: 2) {
      ForEach(0..<rows, id: \.self) { r in
        HStack(spacing: 2) {
          ForEach(0..<cols, id: \.self) { c in
            let index = r * cols + c
            let mm = index < frame.distanceMm.count ? frame.distanceMm[index] : -1
            RoundedRectangle(cornerRadius: 2)
              .fill(colorForDistance(mm))
          }
        }
      }
    }
    .padding(6)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func colorForDistance(_ mm: Int) -> Color {
    guard mm > 0 else { return .white.opacity(0.08) }
    let normalized = min(max(Double(mm) / 2000.0, 0), 1)
    return Color(hue: 0.02 + normalized * 0.55, saturation: 0.85, brightness: 0.95)
  }
}

#Preview(
  traits: .dependencies {
    $0.duckSession = .previewValue
  }
) {
  CockpitView(model: CockpitModel())
}
