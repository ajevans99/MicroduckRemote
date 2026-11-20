import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

/// Exposes App Intents, App Entities, and App Shortcuts defined inside `DuckIntents`
/// to the main `MicroduckRemote` app bundle (and future lightweight widget/control extensions)
/// without linking `WebRTC.xcframework` into extension processes.
public struct MicroduckIntentsPackage: AppIntentsPackage {
  public init() {}
}
