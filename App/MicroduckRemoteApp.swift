import AppFeature
import AppIntents
import Dependencies
import DuckDependencies
import DuckIntents
import DuckWebRTC
import RoomScanFeature
import SwiftUI

struct MicroduckAppIntentsRegistration: AppIntentsPackage {
  static var includedPackages: [any AppIntentsPackage.Type] {
    [MicroduckIntentsPackage.self]
  }
}

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
      $0.haptics = .liveValue
      $0.gamepad = .liveValue
      $0.roomScan = .liveValue
    }
    _model = State(initialValue: AppModel())
  }

  var body: some Scene {
    WindowGroup {
      RootAppView(model: model)
        .environment(\.duckVideoRenderer) { info in
          AnyView(LiveDuckVideoCanvas(videoInfo: info))
        }
    }
  }
}
