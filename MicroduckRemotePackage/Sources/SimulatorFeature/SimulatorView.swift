import Dependencies
import DuckDependencies
import DuckProtocol
import SwiftUI
import UniformTypeIdentifiers

public struct SimulatorView: View {
  @Bindable var model: SimulatorModel
  @Environment(\.openURL) private var openURL

  public init(model: SimulatorModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          headerCard

          if let error = model.errorMessage {
            bannerView(text: error, isError: true) {
              model.errorMessage = nil
            }
          } else if let info = model.statusBanner {
            bannerView(text: info, isError: false) {
              model.statusBanner = nil
            }
          }

          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
              scenesCard
              launchOptionsCard
              repositoriesCard
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
              daemonsHealthCard
              logsCard
            }
            .frame(maxWidth: .infinity)
          }
        }
        .padding(20)
      }
      .navigationTitle("Simulator")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            Task { await model.refreshEverything() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .help("Refresh simulator status and iCloud LiDAR scenes")

          Button {
            model.isFileImporterPresented = true
          } label: {
            Label("Import XML…", systemImage: "square.and.arrow.down")
          }
          .help("Import a MuJoCo MJCF XML scene into synced scenes")

          if model.canConnectCockpit {
            Button {
              Task { await model.connectDriveCockpitButtonTapped(switchTab: true) }
            } label: {
              Label("Open in Drive", systemImage: "gamecontroller.fill")
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .fileImporter(
        isPresented: $model.isFileImporterPresented,
        allowedContentTypes: [.xml]
      ) { result in
        Task { await model.importXMLCompleted(result) }
      }
      .fileImporter(
        isPresented: $model.isSelectingMicroduckRepo,
        allowedContentTypes: [.folder]
      ) { result in
        if case let .success(url) = result {
          Task { await model.updateMicroduckRepoPath(url) }
        }
      }
      .fileImporter(
        isPresented: $model.isSelectingRLRepo,
        allowedContentTypes: [.folder]
      ) { result in
        if case let .success(url) = result {
          Task { await model.updateRLRepoPath(url) }
        }
      }
      .fileImporter(
        isPresented: $model.isSelectingSyncedFolder,
        allowedContentTypes: [.folder]
      ) { result in
        if case let .success(url) = result {
          Task { await model.updateSyncedScenesFolder(url) }
        }
      }
      .task {
        await model.task()
      }
    }
  }

  private var headerCard: some View {
    GroupBox {
      HStack(spacing: 16) {
        HStack(spacing: 12) {
          Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(
              Circle()
                .stroke(statusColor.opacity(0.35), lineWidth: model.phase == .running ? 5 : 0)
            )

          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
              Text(model.phase.label)
                .font(.headline)
              if let activeSlug = model.runtimeStatus.activeSceneSlug, model.runtimeStatus.isRunning {
                Text(SimulatorScene.prettyName(forSlug: activeSlug))
                  .font(.caption.weight(.semibold))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.accentColor.opacity(0.16), in: Capsule())
                  .foregroundStyle(Color.accentColor)
              }
            }
            Text(headerSubtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        if model.phase.isBusy {
          ProgressView()
            .controlSize(.small)
        }

        HStack(spacing: 8) {
          if model.runtimeStatus.isRunning {
            Button(role: .destructive) {
              Task { await model.stopButtonTapped() }
            } label: {
              Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(model.phase.isBusy)

            Button {
              Task { await model.launchOrRestartButtonTapped() }
            } label: {
              Label("Restart with Scene", systemImage: "arrow.trianglehead.2.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.phase.isBusy)
          } else {
            Button {
              Task { await model.launchOrRestartButtonTapped() }
            } label: {
              Label("Launch Simulator", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.phase.isBusy)
          }
        }
      }
      .padding(6)
    }
  }

  private var statusColor: Color {
    switch model.phase {
    case .running: .green
    case .starting, .stopping: .orange
    case .failed: .red
    case .stopped: .secondary
    }
  }

  private var headerSubtitle: String {
    if model.runtimeStatus.isRunning {
      var parts: [String] = []
      if model.runtimeStatus.isBodyPortOpen { parts.append("MuJoCo :7801") }
      if model.runtimeStatus.isMediaPortOpen { parts.append("WebRTC :8443") }
      if model.runtimeStatus.isWebConsolePortOpen { parts.append("Console :8080") }
      return parts.isEmpty ? "Daemons active" : parts.joined(separator: " · ")
    }
    return "Launch MuJoCo + robotd + mediad directly from Microduck."
  }

  private var scenesCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Label("Scenes & iCloud LiDAR Scans", systemImage: "cube.transparent")
            .font(.headline)
          Spacer()
          Button {
            Task { await model.refreshScenesButtonTapped() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .help("Rescan iCloud and local simulator scenes")
        }

        // iCloud LiDAR Scans section
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            Label("iCloud LiDAR Scans", systemImage: model.iCloudAvailable ? "icloud.fill" : "icloud.slash")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(model.iCloudAvailable ? Color.accentColor : .secondary)
            Spacer()
            Button("Choose Folder…") {
              model.isSelectingSyncedFolder = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
            if model.iCloudDirectoryURL != nil {
              Button("Open Folder") {
                model.openSyncedFolderButtonTapped()
              }
              .buttonStyle(.borderless)
              .font(.caption)
            }
          }

          if model.syncedScenes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("No LiDAR scans synced yet.")
                .font(.caption.weight(.medium))
              Text("Scan a room on iPhone and save to iCloud Drive → \(DuckConstants.iCloudDriveScenesFolderName), or click Import XML… to add a scene_<name>.xml file.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          } else {
            VStack(spacing: 6) {
              ForEach(model.syncedScenes) { scene in
                sceneRow(scene)
              }
            }
          }

          if !model.iCloudStatusDetail.isEmpty {
            Text(model.iCloudStatusDetail)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        Divider()

        // Built-in & microduck_rl scenes section
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label("Simulator Scenes (microduck_rl)", systemImage: "folder")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
            Spacer()
            Button("Open Folder") {
              model.openBuiltInScenesFolderButtonTapped()
            }
            .buttonStyle(.borderless)
            .font(.caption)
          }

          if model.builtInScenes.isEmpty {
            Text("No scene_*.xml files found in \(model.config.robotScenesDirectoryURL.path).")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            VStack(spacing: 6) {
              ForEach(model.builtInScenes) { scene in
                sceneRow(scene)
              }
            }
          }
        }
      }
      .padding(6)
    }
  }

  private func sceneRow(_ scene: SimulatorScene) -> some View {
    let isSelected = model.config.selectedSceneSlug == scene.slug
    let isActiveInSim = model.runtimeStatus.isRunning && model.runtimeStatus.activeSceneSlug == scene.slug

    return Button {
      model.selectScene(scene)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(scene.displayName)
              .font(.subheadline.weight(isSelected ? .semibold : .regular))
              .foregroundStyle(.primary)

            if isActiveInSim {
              badge("Active", tint: .green)
            }
            if scene.source == .iCloud {
              badge(scene.isDownloaded ? "iCloud" : "Downloading…", tint: .blue)
            }
            if scene.supportsBacklashWalking {
              badge("Walk Ready", tint: .teal)
            } else {
              badge("No Backlash", tint: .orange)
            }
          }

          HStack(spacing: 6) {
            Text("scene_\(scene.slug).xml")
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
            if let rooms = scene.roomCount {
              Text("· \(rooms) \(rooms == 1 ? "room" : "rooms")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if let obstacles = scene.obstacleCount {
              Text("· \(obstacles) obstacles")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }

        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private func badge(_ title: String, tint: Color) -> some View {
    Text(title)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(tint.opacity(0.16), in: Capsule())
      .foregroundStyle(tint)
  }

  private var launchOptionsCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Label("Launch Configuration", systemImage: "slider.horizontal.3")
          .font(.headline)

        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
          GridRow {
            Text("Camera Stream")
              .foregroundStyle(.secondary)
            Picker("", selection: $model.config.cameraMode) {
              ForEach(SimulatorCameraMode.allCases) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .labelsHidden()
            .onChange(of: model.config.cameraMode) { _, _ in model.configurationChanged() }
          }

          GridRow {
            Text("Duck Count")
              .foregroundStyle(.secondary)
            Stepper(value: $model.config.duckCount, in: 1...4) {
              Text("\(model.config.duckCount) \(model.config.duckCount == 1 ? "duck" : "ducks")")
                .monospacedDigit()
            }
            .onChange(of: model.config.duckCount) { _, _ in model.configurationChanged() }
          }

          GridRow {
            Text("Start Keyframe")
              .foregroundStyle(.secondary)
            Picker("", selection: $model.config.keyframe) {
              ForEach(SimulatorKeyframe.allCases) { kf in
                Text(kf.title).tag(kf)
              }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.config.keyframe) { _, _ in model.configurationChanged() }
          }
        }

        Toggle("Show MuJoCo 3D Viewer Window", isOn: $model.config.showMuJoCoViewer)
          .onChange(of: model.config.showMuJoCoViewer) { _, _ in model.configurationChanged() }

        Toggle("Auto-connect Drive tab when WebRTC is ready", isOn: $model.config.autoConnectCockpit)
          .onChange(of: model.config.autoConnectCockpit) { _, _ in model.configurationChanged() }

        HStack(spacing: 8) {
          Text(model.config.shellPreviewCommand)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
          Spacer()
          Button {
            model.copyCommandButtonTapped()
          } label: {
            Image(systemName: "doc.on.doc")
          }
          .buttonStyle(.borderless)
          .help("Copy shell command")
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .padding(6)
    }
  }

  private var repositoriesCard: some View {
    GroupBox {
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 10) {
          pathRow(
            title: "microduck repo",
            path: model.config.microduckRepoPath,
            action: { model.isSelectingMicroduckRepo = true }
          )
          pathRow(
            title: "microduck_rl repo",
            path: model.config.microduckRLRepoPath,
            action: { model.isSelectingRLRepo = true }
          )
          HStack {
            Text("State dir")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(width: 110, alignment: .leading)
            Text(model.config.stateDirPath)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        .padding(.top, 8)
      } label: {
        Label("Local Repository Paths", systemImage: "wrench.and.screwdriver")
          .font(.subheadline.weight(.semibold))
      }
      .padding(6)
    }
  }

  private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 110, alignment: .leading)
      Text(path)
        .font(.caption.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Choose…", action: action)
        .controlSize(.small)
    }
  }

  private var daemonsHealthCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Simulator Processes", systemImage: "cpu")
            .font(.headline)
          Spacer()
          if model.runtimeStatus.isWebConsolePortOpen, let url = URL(string: "http://127.0.0.1:8080") {
            Button {
              openURL(url)
            } label: {
              Label("Web Console", systemImage: "safari")
                .font(.caption)
            }
            .buttonStyle(.borderless)
          }
        }

        if model.runtimeStatus.daemons.isEmpty {
          Text("Press Launch Simulator to start MuJoCo, robotd, tofd, and mediad.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(model.runtimeStatus.daemons) { daemon in
              HStack(spacing: 8) {
                Circle()
                  .fill(daemon.isRunning ? Color.green : Color.secondary.opacity(0.35))
                  .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                  Text(daemon.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                  Text(daemon.pid.map { "PID \($0)" } ?? "Stopped")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
          }
        }
      }
      .padding(6)
    }
  }

  private var logsCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("Logs", systemImage: "terminal")
            .font(.headline)
          Spacer()
          Picker("Log Source", selection: Binding(
            get: { model.selectedLogSource },
            set: { next in Task { await model.logSourceChanged(next) } }
          )) {
            ForEach(SimulatorLogSource.allCases) { source in
              Text(source.rawValue).tag(source)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(maxWidth: 320)

          if model.selectedLogSource == .liveOutput {
            Button {
              model.clearLogsButtonTapped()
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(model.logs.isEmpty)
            .help("Clear launcher log")
          }
        }

        ScrollView {
          if model.selectedLogSource == .liveOutput {
            if model.logs.isEmpty {
              Text("Launcher output will stream here when you start or stop the simulator.")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } else {
              LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(model.logs) { entry in
                  Text(entry.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(entry.isError ? .red : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
              }
              .padding(8)
            }
          } else {
            Text(model.daemonLogText.isEmpty ? "Loading log…" : model.daemonLogText)
              .font(.caption.monospaced())
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
              .padding(8)
          }
        }
        .frame(minHeight: 280, maxHeight: 420)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .padding(6)
    }
  }

  private func bannerView(text: String, isError: Bool, onDismiss: @escaping () -> Void) -> some View {
    HStack(spacing: 10) {
      Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(isError ? .orange : .green)
      Text(text)
        .font(.footnote.weight(.medium))
      Spacer()
      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(
      (isError ? Color.orange : Color.green).opacity(0.14),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
  }
}

#Preview(
  traits: .dependencies {
    $0.simulator = .previewValue
    $0.duckSession = .previewValue
  }
) {
  SimulatorView(model: SimulatorModel())
    .frame(width: 1000, height: 720)
}
