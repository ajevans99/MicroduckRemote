import AppFeature
import Dependencies
import DuckDependencies
import DuckWebRTC
import SwiftUI

@main
struct MicroduckRemoteApp: App {
  @State private var model: AppModel

  init() {
    prepareDependencies {
      $0.duckSession = .liveValue
      $0.hubCatalog = .liveValue
      $0.huggingFaceAuth = .liveValue
      $0.haptics = .liveValue
      $0.gamepad = .liveValue
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
