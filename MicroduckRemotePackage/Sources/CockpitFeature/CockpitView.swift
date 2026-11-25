import Dependencies
import DuckDependencies
import DuckProtocol
import SwiftUI
import SwiftUINavigation
import WingmanFeature

public struct CockpitView: View {
  @Bindable var model: CockpitModel
  @Environment(\.duckVideoRenderer) private var duckVideoRenderer
  @State private var showControllerLegend = false

  public init(model: CockpitModel) {
    self.model = model
  }

  public var body: some View {
    GeometryReader { proxy in
      let isCompactLandscape = proxy.size.width > proxy.size.height && proxy.size.height < 520
      let isWideFlightDeck = proxy.size.width >= 820 && !isCompactLandscape
      if isCompactLandscape {
        landscapeCockpit(size: proxy.size)
          .background(.black)
      } else {
        NavigationStack {
          Group {
            if isWideFlightDeck {
              wideFlightDeck(size: proxy.size)
            } else {
              portraitCockpit(size: proxy.size)
            }
          }
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
            if isWideFlightDeck {
              ToolbarItem(placement: .automatic) {
                Button {
                  withAnimation(.snappy(duration: 0.22)) {
                    model.wingmanButtonTapped(isWideLayout: true)
                  }
                } label: {
                  Label("Wingman", systemImage: "sidebar.right")
                }
                .tint(model.showWingmanInspector ? .accentColor : .primary)
                .help("Toggle Wingman Side Panel")
              }
            }
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
    .sheet(isPresented: $model.showWingmanSheet) {
      WingmanView(model: model.wingmanModel, isEmbedded: false)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        #elseif os(macOS)
        .frame(minWidth: 440, minHeight: 560)
        #endif
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

  private func wideFlightDeck(size: CGSize) -> some View {
    HStack(spacing: 0) {
      ScrollView(showsIndicators: false) {
        VStack(spacing: 14) {
          wideCameraStage(availableHeight: size.height)

          postureAndSoundsRow(isWide: true)

          QuickMotionDeckView(
            isEnabled: model.snapshot.controlOpen && model.isEnabled && !model.isSitting && !model.isFallen,
            activeLabel: model.activeQuickMotionLabel,
            onAction: { label, goal in
              model.quickMotionButtonTapped(label: label, goal: goal)
            }
          )

          if model.showSoundDrawer {
            soundboardStrip
              .transition(.opacity.combined(with: .move(edge: .top)))
          }

          if model.showExpressiveDrawer {
            expressiveDrawerCard
              .transition(.opacity.combined(with: .move(edge: .top)))
          }

          if model.showManualPads {
            thumbsticksDeck
              .frame(height: 176)
              .padding(.top, 2)
              .transition(.opacity.combined(with: .move(edge: .top)))
          }

          quickSkillsStrip
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
      }

      if model.showWingmanInspector {
        Divider()
        WingmanView(model: model.wingmanModel, isEmbedded: true)
          .frame(width: min(max(size.width * 0.38, 360), 430))
          .background(.background.secondary)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
  }

  private func wideCameraStage(availableHeight: CGFloat) -> some View {
    let stageHeight = min(max(availableHeight * 0.56, 380), 560)
    let isPortraitCamera = model.snapshot.videoInfo.uprightAspectRatio < 0.9
    return ZStack {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(white: 0.08), Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      if isPortraitCamera {
        let feedHeight = stageHeight - 24
        let feedWidth = min(feedHeight * CGFloat(model.snapshot.videoInfo.uprightAspectRatio), 360)
        cameraFeedSurface(cornerRadius: 18)
          .frame(width: feedWidth, height: feedHeight)
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .strokeBorder(.white.opacity(0.14), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.65), radius: 20, y: 8)
      } else {
        cameraFeedSurface(cornerRadius: 24)
      }

      cameraHUDOverlay
    }
    .frame(height: stageHeight)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(
          isWingmanActive ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.10),
          lineWidth: isWingmanActive ? 2 : 1
        )
    )
    .shadow(color: isWingmanActive ? Color.accentColor.opacity(0.22) : .clear, radius: 16)
    .animation(.easeInOut(duration: 0.25), value: isWingmanActive)
  }

  private var isWingmanActive: Bool {
    model.wingmanModel.isRunning || model.wingmanModel.isExecutingPlan || model.activeQuickMotionLabel != nil
  }

  private func portraitCockpit(size: CGSize) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: 14) {
        videoStageCard(cornerRadius: 22)
          .frame(height: min(max(size.height * 0.36, 240), 400))

        postureAndSoundsRow(isWide: false)

        QuickMotionDeckView(
          isEnabled: model.snapshot.controlOpen && model.isEnabled && !model.isSitting && !model.isFallen,
          activeLabel: model.activeQuickMotionLabel,
          onAction: { label, goal in
            model.quickMotionButtonTapped(label: label, goal: goal)
          }
        )

        if model.showSoundDrawer {
          soundboardStrip
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if model.showExpressiveDrawer {
          expressiveDrawerCard
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        quickSkillsStrip

        thumbsticksDeck
          .frame(height: 182)
          .padding(.top, 2)
      }
      .padding(.horizontal, 16)
      .padding(.top, 10)
      .padding(.bottom, 16)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .safeAreaInset(edge: .bottom) {
      compactWingmanDockBar
    }
  }

  private var compactWingmanDockBar: some View {
    HStack(spacing: 8) {
      Button {
        model.wingmanButtonTapped(isWideLayout: false)
      } label: {
        Image(systemName: "bird.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.tint)
          .frame(width: 32, height: 32)
          .background(.tint.opacity(0.15), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open Wingman")

      TextField("Ask Wingman to move, look, or chomp…", text: $model.inlineWingmanPrompt)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .onSubmit {
          model.inlineWingmanSubmitted(isWideLayout: false)
        }

      if isWingmanActive {
        Button {
          Task { await model.stopButtonTapped() }
        } label: {
          Image(systemName: "stop.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.red, in: Circle())
        }
        .buttonStyle(.plain)
      } else {
        Button {
          model.inlineWingmanSubmitted(isWideLayout: false)
        } label: {
          Image(systemName: "arrow.up")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
              model.inlineWingmanPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Color.secondary.opacity(0.35)
                : Color.accentColor,
              in: Circle()
            )
        }
        .buttonStyle(.plain)
        .disabled(
          model.inlineWingmanPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !model.snapshot.controlOpen
        )
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }

  private func landscapeCockpit(size: CGSize) -> some View {
    ZStack {
      videoStageCard(cornerRadius: 0)
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

        if model.showExpressiveDrawer {
          expressiveDrawerCard
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

          postureAndSoundsRow(isWide: false)

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

  private func videoStageCard(cornerRadius: CGFloat) -> some View {
    ZStack {
      cameraFeedSurface(cornerRadius: cornerRadius)
      cameraHUDOverlay
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private func cameraFeedSurface(cornerRadius: CGFloat) -> some View {
    GeometryReader { stageProxy in
      ZStack {
        Color.black

        duckVideoRenderer(model.snapshot.videoInfo)
          .frame(width: stageProxy.size.width, height: stageProxy.size.height)

        detectionBoxesOverlay(in: stageProxy.size)

        if model.isLooking {
          gazeReticle(in: stageProxy.size)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

  private var cameraHUDOverlay: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        safetyBadge
        if model.gamepadState.isConnected, let name = model.gamepadState.controllerName {
          Button {
            showControllerLegend.toggle()
          } label: {
            Label(name, systemImage: "gamecontroller.fill")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.black.opacity(0.45), in: Capsule())
              .overlay(Capsule().strokeBorder(.green.opacity(0.55), lineWidth: 1))
          }
          .buttonStyle(.plain)
          .popover(isPresented: $showControllerLegend) {
            ControllerMappingPopover(
              controllerName: name,
              family: model.gamepadState.family
            )
          }
          .help("Show controller button mapping")
        }
        Spacer(minLength: 4)
        HStack(spacing: 6) {
          if model.snapshot.latestState?.odom != nil {
            Button {
              withAnimation(.snappy(duration: 0.2)) {
                model.compassHUDToggleTapped()
              }
            } label: {
              Image(systemName: model.showCompassHUD ? "location.north.circle.fill" : "location.north.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Compass & Trail")
          }

          Button {
            Task { await model.tofOverlayButtonTapped() }
          } label: {
            Image(systemName: model.showTofOverlay ? "square.grid.3x3.fill" : "square.grid.3x3")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: 30, height: 30)
              .background(.black.opacity(0.45), in: Circle())
              .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Toggle 8x8 Depth Overlay")
        }
      }
      .padding(12)

      if let liveLabel = activeOverlayLabel {
        HStack(spacing: 7) {
          ProgressView()
            .controlSize(.mini)
            .tint(.white)
          Image(systemName: "bird.fill")
            .font(.caption2.weight(.bold))
          Text(liveLabel)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
          Button {
            Task { await model.stopButtonTapped() }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.9))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel Active Motion")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.88), in: Capsule())
        .shadow(color: Color.accentColor.opacity(0.4), radius: 8)
        .transition(.scale.combined(with: .opacity))
      }

      Spacer()

      HStack(alignment: .bottom, spacing: 10) {
        if model.showCompassHUD, let odom = model.snapshot.latestState?.odom {
          OdometryCompassTrailHUD(
            odom: odom,
            trail: model.odomTrail,
            onResetTrail: { model.resetOdomTrailTapped() }
          )
          .transition(.scale.combined(with: .opacity))
        }

        Spacer(minLength: 4)

        VStack(alignment: .trailing, spacing: 8) {
          if model.showTofOverlay, let tof = model.snapshot.tofFrame {
            TofMiniHeatmapView(frame: tof)
              .frame(width: 78, height: 78)
              .transition(.scale.combined(with: .opacity))
          }

          if let zones = model.snapshot.tofFrame?.analyzeZones() {
            TofProximityArcHUD(analysis: zones)
              .transition(.scale.combined(with: .opacity))
          }
        }

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

  private var activeOverlayLabel: String? {
    if let wingmanStatus = model.wingmanModel.activeStatusSummary {
      return "Wingman · \(wingmanStatus)"
    }
    if let quickLabel = model.activeQuickMotionLabel {
      return "Driving · \(quickLabel)"
    }
    return nil
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

  private func postureAndSoundsRow(isWide: Bool) -> some View {
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

      Button {
        withAnimation(.snappy(duration: 0.25)) {
          model.expressiveDrawerToggleTapped()
        }
      } label: {
        Image(systemName: model.showExpressiveDrawer || model.hasActiveExpression ? "face.smiling.inverse" : "face.smiling")
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.circle)
      .tint(model.showExpressiveDrawer || model.hasActiveExpression ? .accentColor : .primary)
      .controlSize(.large)
      .disabled(!model.snapshot.controlOpen)
      .accessibilityLabel("Expressive Controls")

      if isWide {
        Button {
          withAnimation(.snappy(duration: 0.25)) {
            model.manualPadsToggleTapped()
          }
        } label: {
          Image(systemName: model.showManualPads ? "gamecontroller.fill" : "gamecontroller")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(model.showManualPads ? .accentColor : .primary)
        .controlSize(.large)
        .disabled(!model.snapshot.controlOpen)
        .accessibilityLabel("Manual Joysticks")
      } else {
        Button {
          withAnimation(.snappy(duration: 0.22)) {
            model.wingmanButtonTapped(isWideLayout: false)
          }
        } label: {
          Image(systemName: "bird.fill")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(model.showWingmanSheet || isWingmanActive ? .accentColor : .primary)
        .controlSize(.large)
        .disabled(!model.snapshot.controlOpen)
        .accessibilityLabel("Wingman")
      }
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
        Button {
          Task { await model.thereminToggleTapped() }
        } label: {
          Label(
            model.thereminEnabled ? "Stop Theremin" : "Theremin",
            systemImage: "music.note"
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

  private var expressiveDrawerCard: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Label("Hold Chomp", systemImage: "mouth.fill")
          .font(.footnote.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(
            model.isHoldingChomp ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.08),
            in: Capsule()
          )
          .foregroundStyle(model.isHoldingChomp ? Color.accentColor : .primary)
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { _ in
                Task { await model.chompHoldChanged(isPressed: true) }
              }
              .onEnded { _ in
                Task { await model.chompHoldChanged(isPressed: false) }
              }
          )

        Slider(
          value: Binding(
            get: { model.beakOpening },
            set: { value in Task { await model.beakOpeningChanged(value) } }
          ),
          in: 0...1
        )
        .accessibilityLabel("Beak Opening")

        Text("\(Int((model.beakOpening * 100).rounded()))%")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 34, alignment: .trailing)

        Button("Reset") {
          Task { await model.resetExpressionTapped() }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .disabled(!model.hasActiveExpression)
      }

      HStack(spacing: 14) {
        HStack(spacing: 6) {
          Text("Tilt")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          Slider(
            value: Binding(
              get: { model.headTilt },
              set: { value in Task { await model.headTiltChanged(value) } }
            ),
            in: -1...1
          )
          .accessibilityLabel("Head Tilt")
          Text("\(Int((model.headTilt * 100).rounded()))%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
        }

        HStack(spacing: 6) {
          Text("Crouch")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          Slider(
            value: Binding(
              get: { model.crouchDepth },
              set: { value in Task { await model.crouchDepthChanged(value) } }
            ),
            in: 0...1
          )
          .disabled(!model.isEnabled || model.isSitting)
          .accessibilityLabel("Crouch Depth")
          Text("\(Int((model.crouchDepth * 100).rounded()))%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
