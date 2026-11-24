import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

public struct SnapDuckPhotoIntent: AppIntent {
  public static let title: LocalizedStringResource = "Snap Microduck Photo"
  public static let description = IntentDescription(
    "Captures a live JPEG photo from Microduck's first-person head camera and returns it as a transferable image that can be shared in Messages, saved to Photos, or analyzed in Shortcuts."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  public static var parameterSummary: some ParameterSummary {
    Summary("Take a photo from Microduck's head camera")
  }

  public init() {}

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckPhotoEntity> & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession
    @Dependencies.Dependency(\.continuousClock) var clock

    let initial = await duckSession.currentSnapshot()
    let duckName: String
    if initial.controlOpen {
      duckName = initial.phase.connected?.name ?? "Microduck"
    } else {
      let identity = try await duckSession.ensureConnected(.seconds(6))
      duckName = identity.name
    }

    // Right after a cold start, the H.264 video track can trail controlChannel open by ~200-800 ms.
    var latest = await duckSession.currentSnapshot()
    if !latest.hasVideoTrack {
      for _ in 0..<8 {
        try await clock.sleep(for: .milliseconds(200))
        latest = await duckSession.currentSnapshot()
        if latest.hasVideoTrack { break }
      }
    }

    let frame = try await duckSession.capturePhoto()
    let photo = DuckPhotoEntity(duckName: duckName, frame: frame)
    return .result(
      value: photo,
      dialog: "Snapped a photo from \(duckName)'s head camera."
    )
  }
}

@available(iOS 27.3, macOS 27.3, *)
extension SnapDuckPhotoIntent: ToolIntent, LiveActivityIntent {}
