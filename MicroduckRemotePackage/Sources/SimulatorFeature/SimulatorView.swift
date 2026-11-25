import Dependencies
import DuckDependencies
import DuckProtocol
import SwiftUI
import UniformTypeIdentifiers

public struct SimulatorView: View {
  @Bindable var model: SimulatorModel
  @Environment(\.openURL) private var openURL
  @State private var showPaths = false

  public init(model: SimulatorModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      Group {
        #if os(macOS)
        HSplitView {
          configurationForm
            .frame(minWidth: 360, idealWidth: 440, maxWidth: 540)
          consoleInspectorPane
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        #else
        configurationForm
        #endif
      }
      .navigationTitle("Simulator")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          if model.phase.isBusy {
            ProgressView()
              .controlSize(.small)
          }

          if model.runtimeStatus.isRunning {
            Button(role: .destructive) {
              Task { await model.stopButtonTapped() }
            } label: {
              Label("Stop", systemImage: "stop.fill")
            }
            .disabled(model.phase.isBusy)

            Button {
              Task { await model.launchOrRestartButtonTapped() }
            } label: {
              Label("Restart", systemImage: "arrow.trianglehead.2.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.phase.isBusy)
          } else {
            Button {
              Task { await model.launchOrRestartButtonTapped() }
            } label: {
              Label("Launch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.phase.isBusy)
          }

          if model.canConnectCockpit {
            Button {
              Task { await model.connectDriveCockpitButtonTapped(switchTab: true) }
            } label: {
              Label("Drive", systemImage: "gamecontroller.fill")
            }
          }

          Menu {
            Button {
              Task { await model.refreshEverything() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
              model.isFileImporterPresented = true
            } label: {
              Label("Import XML Scene…", systemImage: "square.and.arrow.down")
            }

            if model.runtimeStatus.isWebConsolePortOpen, let url = URL(string: "http://127.0.0.1:8080") {
              Button {
                openURL(url)
              } label: {
                Label("Open Web Console", systemImage: "safari")
              }
            }

            Divider()

            Button {
              model.copyCommandButtonTapped()
            } label: {
              Label("Copy Shell Command", systemImage: "doc.on.doc")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
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

  private func preflightRow(_ label: String, installed: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .foregroundStyle(installed ? .green : .orange)
        .font(.caption)
      Text(label)
        .font(.caption)
      Spacer()
      Text(installed ? "Ready" : "Missing")
        .font(.caption2.weight(.medium))
        .foregroundStyle(installed ? Color.secondary : Color.orange)
    }
  }

  private var configurationForm: some View {
    Form {
      if let error = model.errorMessage {
        Section {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(error)
              .font(.footnote)
            Spacer()
            Button {
              model.errorMessage = nil
            } label: {
              Image(systemName: "xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
      } else if let info = model.statusBanner {
        Section {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text(info)
              .font(.footnote)
            Spacer()
            Button {
              model.statusBanner = nil
            } label: {
              Image(systemName: "xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
      }

      Section {
        HStack(spacing: 10) {
          Circle()
            .fill(statusColor)
            .frame(width: 9, height: 9)
          VStack(alignment: .leading, spacing: 2) {
            Text(model.phase.label)
              .font(.subheadline.weight(.semibold))
            Text(headerSubtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let activeSlug = model.runtimeStatus.activeSceneSlug, model.runtimeStatus.isRunning {
            Text(SimulatorScene.prettyName(forSlug: activeSlug))
              .font(.caption.weight(.medium))
              .foregroundStyle(Color.accentColor)
          }
        }
      }

      if !model.environmentStatus.isReadyToLaunch {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("The local MuJoCo simulator requires the open-source Microduck repos plus Rust (`cargo`) and Python (`uv`). Connecting to a physical Microduck works without this.")
              .font(.caption)
              .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
              preflightRow("microduck repo (scripts/duck-sim)", installed: model.environmentStatus.hasMicroduckRepo)
              preflightRow("microduck_rl repo (MuJoCo scenes)", installed: model.environmentStatus.hasMicroduckRLRepo)
              preflightRow("Rust toolchain (cargo)", installed: model.environmentStatus.hasCargo)
              preflightRow("Python runner (uv)", installed: model.environmentStatus.hasUv)
            }

            if model.environmentStatus.needsRepoClone {
              Button {
                Task { await model.setupSimulatorReposButtonTapped() }
              } label: {
                HStack(spacing: 6) {
                  if model.isSettingUpRepos {
                    ProgressView().controlSize(.small)
                  } else {
                    Image(systemName: "arrow.down.circle.fill")
                  }
                  Text(model.isSettingUpRepos ? "Downloading Repositories…" : "Download Simulator Repos")
                }
              }
              .buttonStyle(.borderedProminent)
              .disabled(model.isSettingUpRepos || !model.environmentStatus.hasGit)
            }

            if let installCmd = model.environmentStatus.missingToolchainCommand {
              HStack(spacing: 8) {
                Text(installCmd)
                  .font(.caption2.monospaced())
                  .textSelection(.enabled)
                  .lineLimit(2)
                Spacer()
                Button {
                  model.copyToolchainInstallCommandButtonTapped()
                } label: {
                  Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy install command")
              }
              .padding(8)
              .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
          }
          .padding(.vertical, 2)
        } header: {
          Label("Simulator Setup", systemImage: "wrench.and.screwdriver")
        }
      }

      Section {
        if model.syncedScenes.isEmpty {
          Text("Scan a room on iPhone and save to iCloud Drive → \(DuckConstants.iCloudDriveScenesFolderName), or import an XML file.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.syncedScenes) { scene in
            sceneRow(scene)
          }
        }
      } header: {
        HStack {
          Text("iCloud LiDAR Scans")
          Spacer()
          Button("Choose…") {
            model.isSelectingSyncedFolder = true
          }
          .buttonStyle(.borderless)
          .font(.caption)
          if model.iCloudDirectoryURL != nil {
            Button("Reveal") {
              model.openSyncedFolderButtonTapped()
            }
            .buttonStyle(.borderless)
            .font(.caption)
          }
        }
      }

      Section {
        if model.builtInScenes.isEmpty {
          Text("No scene_*.xml files found in microduck_rl.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.builtInScenes) { scene in
            sceneRow(scene)
          }
        }
      } header: {
        HStack {
          Text("Scenes")
          Spacer()
          Button("Reveal") {
            model.openBuiltInScenesFolderButtonTapped()
          }
          .buttonStyle(.borderless)
          .font(.caption)
        }
      }

      Section("Launch Options") {
        Picker("Camera", selection: $model.config.cameraMode) {
          ForEach(SimulatorCameraMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .onChange(of: model.config.cameraMode) { _, _ in model.configurationChanged() }

        Stepper(value: $model.config.duckCount, in: 1...4) {
          LabeledContent("Ducks", value: "\(model.config.duckCount)")
        }
        .onChange(of: model.config.duckCount) { _, _ in model.configurationChanged() }

        Picker("Start Pose", selection: $model.config.keyframe) {
          ForEach(SimulatorKeyframe.allCases) { kf in
            Text(kf.title).tag(kf)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: model.config.keyframe) { _, _ in model.configurationChanged() }

        Toggle("Show 3D Viewer", isOn: $model.config.showMuJoCoViewer)
          .onChange(of: model.config.showMuJoCoViewer) { _, _ in model.configurationChanged() }

        Toggle("Auto-Connect Drive", isOn: $model.config.autoConnectCockpit)
          .onChange(of: model.config.autoConnectCockpit) { _, _ in model.configurationChanged() }
      }

      Section {
        DisclosureGroup("Paths & Command", isExpanded: $showPaths) {
          pathRow(title: "microduck", path: model.config.microduckRepoPath) {
            model.isSelectingMicroduckRepo = true
          }
          pathRow(title: "microduck_rl", path: model.config.microduckRLRepoPath) {
            model.isSelectingRLRepo = true
          }
          LabeledContent("State") {
            Text(model.config.stateDirPath)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          HStack {
            Text(model.config.shellPreviewCommand)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
            Spacer()
            Button {
              model.copyCommandButtonTapped()
            } label: {
              Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
          }
        }
      }
    }
    #if os(macOS)
    .formStyle(.grouped)
    #endif
  }

  private var consoleInspectorPane: some View {
    VStack(spacing: 0) {
      // Compact process status strip
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Processes")
            .font(.subheadline.weight(.semibold))
          Spacer()
          let runningCount = model.runtimeStatus.daemons.filter(\.isRunning).count
          Text("\(runningCount)/\(max(model.runtimeStatus.daemons.count, 7)) active")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if model.runtimeStatus.daemons.isEmpty {
          Text("Click Launch to start MuJoCo, robotd, tofd, and mediad.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 6) {
            ForEach(model.runtimeStatus.daemons) { daemon in
              HStack(spacing: 6) {
                Circle()
                  .fill(daemon.isRunning ? Color.green : Color.secondary.opacity(0.3))
                  .frame(width: 7, height: 7)
                Text(daemon.name)
                  .font(.caption)
                  .lineLimit(1)
                Spacer(minLength: 2)
                if let pid = daemon.pid {
                  Text("\(pid)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }
        }
      }
      .padding(14)

      Divider()

      // Log source bar
      HStack(spacing: 10) {
        Picker("Log Source", selection: $model.selectedLogSource) {
          ForEach(SimulatorLogSource.allCases) { source in
            Text(source.rawValue).tag(source)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: model.selectedLogSource) { _, next in
          Task { await model.logSourceChanged(next) }
        }

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
      .padding(.horizontal, 14)
      .padding(.vertical, 10)

      Divider()

      // Console output
      ScrollView {
        if model.selectedLogSource == .liveOutput {
          if model.logs.isEmpty {
            ContentUnavailableView(
              "No Output",
              systemImage: "terminal",
              description: Text("Launcher output will appear here.")
            )
            .frame(maxWidth: .infinity, minHeight: 260)
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
            .padding(12)
          }
        } else {
          Text(model.daemonLogText.isEmpty ? "No log output yet." : model.daemonLogText)
            .font(.caption.monospaced())
            .foregroundStyle(model.daemonLogText.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(12)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      if model.runtimeStatus.isWebConsolePortOpen { parts.append("Web :8080") }
      return parts.isEmpty ? "Daemons active" : parts.joined(separator: " · ")
    }
    return "Ready to launch duck-sim"
  }

  private func sceneRow(_ scene: SimulatorScene) -> some View {
    let isSelected = model.config.selectedSceneSlug == scene.slug
    let isActiveInSim = model.runtimeStatus.isRunning && model.runtimeStatus.activeSceneSlug == scene.slug

    return Button {
      model.selectScene(scene)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(scene.displayName)
              .foregroundStyle(.primary)
            if isActiveInSim {
              Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            }
            if !scene.supportsBacklashWalking {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Scene does not include backlash walking joints")
            }
            if scene.source == .iCloud && !scene.isDownloaded {
              Image(systemName: "icloud.and.arrow.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }

          HStack(spacing: 4) {
            Text("scene_\(scene.slug).xml")
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
            if let rooms = scene.roomCount {
              Text("· \(rooms)R")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text(path)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      Button("Choose…", action: action)
        .controlSize(.small)
    }
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
