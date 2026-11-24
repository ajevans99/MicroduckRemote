import AppFeature
import Dependencies
import DuckDependencies
import DuckIntents
import DuckWebRTC
import RoomScanFeature
import SwiftUI

@main
struct MicroduckRemoteApp: App {
  @State private var model: AppModel

  init() {
    prepareDependencies {
      $0.duckSession = .liveValue
      $0.hubCatalog = .liveValue
      $0.huggingFaceAuth = .liveValue
      $0.connectionPreferences = .liveValue
      $0.duckSharedState = .liveValue
      $0.intentTelemetry = .liveValue
      $0.haptics = .liveValue
      $0.gamepad = .liveValue
      $0.roomScan = .liveValue
      $0.iCloudSceneSync = .liveValue
    }
    _model = State(initialValue: AppModel())
    MicroduckShortcuts.updateAppShortcutParameters()
  }

  var body: some Scene {
    WindowGroup {
      RootAppView(model: model)
        .environment(\.duckVideoRenderer) { info in
          AnyView(LiveDuckVideoCanvas(videoInfo: info))
        }
    }
    #if os(macOS)
    .defaultSize(width: 1100, height: 760)
    .commands {
      CommandMenu("Duck") {
        Button("Connect to Duck…") {
          model.presentConnectionSheet()
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Divider()

        Button(model.cockpitModel.isEnabled ? "Disable Balance" : "Stand & Balance") {
          Task { await model.cockpitModel.standToggleButtonTapped() }
        }
        .keyboardShortcut("b", modifiers: [.command])
        .disabled(!model.cockpitModel.snapshot.controlOpen)

        Button("Emergency Stop") {
          Task { await model.cockpitModel.stopButtonTapped() }
        }
        .keyboardShortcut(".", modifiers: [.command])
        .disabled(!model.cockpitModel.snapshot.controlOpen)

        Divider()

        Button(model.cockpitModel.showSoundDrawer ? "Hide Soundboard" : "Show Soundboard") {
          model.cockpitModel.soundDrawerToggleTapped()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(!model.cockpitModel.snapshot.controlOpen)

        Button(model.cockpitModel.showTofOverlay ? "Hide 8×8 Depth Overlay" : "Show 8×8 Depth Overlay") {
          Task { await model.cockpitModel.tofOverlayButtonTapped() }
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(!model.cockpitModel.snapshot.controlOpen)
      }

      CommandGroup(after: .toolbar) {
        Button("Drive") {
          model.selectedTab = .cockpit
        }
        .keyboardShortcut("1", modifiers: [.command])

        Button("Tricks") {
          model.selectedTab = .tricks
        }
        .keyboardShortcut("2", modifiers: [.command])

        Button("Telemetry & Map") {
          model.selectedTab = .telemetry
        }
        .keyboardShortcut("3", modifiers: [.command])

        Button("Simulator") {
          model.selectedTab = .simulator
        }
        .keyboardShortcut("4", modifiers: [.command])
      }
    }
    #endif
  }
}
