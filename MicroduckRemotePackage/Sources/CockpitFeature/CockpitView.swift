import Dependencies
import DuckDependencies
import DuckProtocol
import SwiftUI
import SwiftUINavigation

public struct CockpitView: View {
  @Bindable var model: CockpitModel
  @Environment(\.duckVideoRenderer) private var duckVideoRenderer
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  public init(model: CockpitModel) {
    self.model = model
  }

  public var body: some View {
    GeometryReader { proxy in
      let isLandscape = proxy.size.width > proxy.size.height && proxy.size.height < 560
      ZStack {
        Color(white: 0.06).ignoresSafeArea()
        if isLandscape {
          landscapeCockpit(size: proxy.size)
        } else {
          portraitCockpit(size: proxy.size)
        }
      }
    }
    .preferredColorScheme(.dark)
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
      VStack(spacing: 14) {
        statusCapsuleHeader
        videoStageCard
          .frame(height: min(max(size.height * 0.36, 230), 360))
        quickSkillsStrip
        postureAndModesRow
        if model.showSoundDrawer {
          soundboardCard
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        thumbsticksDeck
          .frame(height: 195)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
  }

  private func landscapeCockpit(size: CGSize) -> some View {
    ZStack {
      videoStageCard
        .ignoresSafeArea()

      VStack {
        HStack {
          statusCapsuleHeader
          Spacer()
          quickSkillsStrip
            .frame(maxWidth: size.width * 0.46)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)

        Spacer()

        if model.showSoundDrawer {
          soundboardCard
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
          .frame(width: 150, height: 175)

          Spacer()

          postureAndModesRow

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
          .frame(width: 150, height: 175)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
      }
    }
  }

  private var statusCapsuleHeader: some View {
    Button {
      model.connectionHeaderTapped()
    } label: {
      HStack(spacing: 6) {
        Circle()
          .fill(statusDotColor)
          .frame(width: 9, height: 9)

        Text(model.snapshot.phase.statusText)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .layoutPriority(1)

        if case let .connected(identity) = model.snapshot.phase, identity.isSimulated {
          Text("SIM")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.teal.opacity(0.25), in: Capsule())
            .foregroundStyle(.teal)
        }

        Spacer(minLength: 4)

        if let hz = model.snapshot.latestState?.controlLoop?.hz {
          Label(String(format: "%.0f Hz", hz), systemImage: "waveform.path.ecg")
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
        }

        if let fps = model.snapshot.linkStats.fps {
          Text("\(fps) fps")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
        }

        if let battery = model.snapshot.health?.battery {
          Label(String(format: "%.1fV", battery.volts), systemImage: "battery.75percent")
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.green)
            .fixedSize(horizontal: true, vertical: false)
        }

        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial, in: Capsule())
      .overlay(
        Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
      )
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
      return .gray
    }
  }

  private var videoStageCard: some View {
    GeometryReader { stageProxy in
      ZStack {
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
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            Button {
              Task { await model.tofOverlayButtonTapped() }
            } label: {
              Label("ToF 8×8", systemImage: model.showTofOverlay ? "square.grid.3x3.fill" : "square.grid.3x3")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
          }
          .padding(12)

          Spacer()

          HStack(alignment: .bottom) {
            if model.showTofOverlay, let tof = model.snapshot.tofFrame {
              TofMiniHeatmapView(frame: tof)
                .frame(width: 96, height: 96)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if !model.snapshot.controlOpen {
              Button {
                model.connectionHeaderTapped()
              } label: {
                Label("Connect to Duck", systemImage: "antenna.radiowaves.left.and.right")
                  .font(.footnote.weight(.semibold))
                  .padding(.horizontal, 14)
                  .padding(.vertical, 8)
                  .background(.regularMaterial, in: Capsule())
              }
              .buttonStyle(.plain)
            } else {
              Text("Drag video to aim head IK")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())
            }
          }
          .padding(12)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(.white.opacity(0.14), lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

  private var safetyBadge: some View {
    let safety = model.snapshot.latestState?.safety
    let nominal = safety?.isNominal ?? true
    let text = safety?.statusLabel ?? (model.snapshot.mode?.capitalized ?? "Standby")
    return Group {
      if model.isFallen {
        Button {
          Task { await model.standBackUpButtonTapped() }
        } label: {
          Label(
            model.isStandingBackUp ? "Standing Up…" : "Fallen · Tap to Stand",
            systemImage: "arrow.up.circle.fill"
          )
          .font(.caption2.weight(.bold))
          .foregroundStyle(.black)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Color.orange, in: Capsule())
        }
        .buttonStyle(.plain)
      } else {
        Label(text, systemImage: nominal ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(nominal ? Color.white : Color.orange)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.ultraThinMaterial, in: Capsule())
      }
    }
  }

  private func gazeReticle(in size: CGSize) -> some View {
    let x = CGFloat((model.gazeNormalizedX + 1) * 0.5) * size.width
    let y = CGFloat((model.gazeNormalizedY + 1) * 0.5) * size.height
    let tint: Color = model.isGazeClamped ? .orange : .cyan
    return ZStack {
      Circle()
        .strokeBorder(tint, lineWidth: 2)
        .frame(width: 38, height: 38)
      Circle()
        .fill(tint)
        .frame(width: 6, height: 6)
      if model.isGazeClamped {
        Text("IK Limit")
          .font(.system(size: 10, weight: .bold))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.orange.opacity(0.85), in: Capsule())
          .offset(y: -30)
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
            .overlay(alignment: .topLeading) {
              Text("duck")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.yellow, in: Capsule())
                .offset(y: -18)
            }
            .position(x: cx, y: cy)
        }
      }
    }
  }

  private var quickSkillsStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(model.snapshot.skillNames, id: \.self) { skill in
          let isRunning = model.activeSkillName == skill
          Button {
            Task { await model.quickSkillButtonTapped(skill) }
          } label: {
            HStack(spacing: 6) {
              if isRunning {
                ProgressView()
                  .controlSize(.mini)
              } else {
                Image(systemName: iconForSkill(skill))
                  .font(.caption.weight(.semibold))
              }
              Text(prettySkillName(skill))
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
              Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
          .disabled(!model.snapshot.controlOpen)
        }
      }
    }
  }

  private var postureAndModesRow: some View {
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
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Color.orange.opacity(0.28), in: Capsule())
          .overlay(Capsule().strokeBorder(Color.orange, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!model.snapshot.controlOpen || model.isStandingBackUp)
      } else {
        Button {
          Task { await model.standToggleButtonTapped() }
        } label: {
          Label(
            model.isEnabled ? "Balancing" : "Stand & Balance",
            systemImage: model.isEnabled ? "figure.stand" : "play.fill"
          )
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
            model.isEnabled ? Color.green.opacity(0.24) : Color.accentColor.opacity(0.28),
            in: Capsule()
          )
          .overlay(
            Capsule().strokeBorder(model.isEnabled ? Color.green : Color.accentColor, lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
        .disabled(!model.snapshot.controlOpen)
      }

      Button {
        Task { await model.stopButtonTapped() }
      } label: {
        Label("Stop", systemImage: "hand.raised.fill")
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Color.red.opacity(0.22), in: Capsule())
          .overlay(Capsule().strokeBorder(Color.red.opacity(0.65), lineWidth: 1))
      }
      .buttonStyle(.plain)
      .disabled(!model.snapshot.controlOpen)

      Button {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
          model.soundDrawerToggleTapped()
        }
      } label: {
        Image(systemName: model.showSoundDrawer ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
          .font(.subheadline.weight(.semibold))
          .frame(width: 40, height: 40)
          .background(.ultraThinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(!model.snapshot.controlOpen)

      Menu {
        Button {
          Task { await model.autonomousToggleTapped() }
        } label: {
          Label(
            model.autonomousEnabled ? "Disable Autonomous Brain" : "Enable Autonomous Brain",
            systemImage: "sparkles"
          )
        }
        Button {
          Task { await model.flashlightToggleTapped() }
        } label: {
          Label(
            model.flashlightEnabled ? "Turn Off Flashlight" : "Turn On Flashlight",
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
        Divider()
        Button {
          Task { await model.initPoseButtonTapped() }
        } label: {
          Label("Home Pose (Init)", systemImage: "arrow.uturn.backward.circle")
        }
        Button {
          Task { await model.rebootMotorsButtonTapped() }
        } label: {
          Label("Reboot Overloaded Motors", systemImage: "bolt.arrow.trianglehead.counterclockwise")
        }
        Button(role: .destructive) {
          model.relaxMenuButtonTapped()
        } label: {
          Label("Relax Motors…", systemImage: "poweroff")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.subheadline.weight(.semibold))
          .frame(width: 40, height: 40)
          .background(.ultraThinMaterial, in: Circle())
      }
      .disabled(!model.snapshot.controlOpen)
    }
  }

  private var soundboardCard: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(SoundTag.allCases) { sound in
          if sound.isHoldable {
            Label("Hold Wheee", systemImage: sound.systemImage)
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                model.isHoldingWheee ? Color.cyan.opacity(0.35) : Color.white.opacity(0.09),
                in: Capsule()
              )
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
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(10)
    }
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var thumbsticksDeck: some View {
    HStack(spacing: 24) {
      ThumbstickPadView(
        title: "Walk & Strafe",
        subtitle: String(format: "vx %+.2f · vy %+.2f", model.currentTwist.vx, model.currentTwist.vy),
        mode: .omnidirectional,
        normalizedX: model.leftStickX,
        normalizedY: model.leftStickY,
        isEnabled: model.snapshot.controlOpen,
        onMove: { x, y in Task { await model.leftThumbstickMoved(x: x, y: y) } },
        onRelease: { Task { await model.leftThumbstickReleased() } }
      )

      ThumbstickPadView(
        title: "Turn",
        subtitle: String(format: "vyaw %+.2f rad/s", model.currentTwist.vyaw),
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
    case "sit_toggle": "Sit ⇄ Stand"
    case "ground_pick": "Ground Pick"
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
    case "roulade": "arrow.clockwise.circle.fill"
    case "kick_left", "kick_right": "figure.soccer"
    case "ground_pick": "arrow.down.to.line.compact"
    case "sit_toggle": "chair.lounge.fill"
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
