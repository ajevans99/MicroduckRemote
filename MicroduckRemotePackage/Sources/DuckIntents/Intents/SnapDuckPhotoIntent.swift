import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import SwiftUI

@AppIntent(.tool)
public struct SnapDuckPhotoIntent: LiveActivityIntent {
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

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckPhotoEntity> & ProvidesDialog & ShowsSnippetView {
    @Dependencies.Dependency(\.duckSession) var duckSession
    @Dependencies.Dependency(\.continuousClock) var clock

    let (photo, dialogText) = try await IntentTelemetryTracer.traceTool(
      intentName: "SnapDuckPhotoIntent",
      displayTitle: "Snap Microduck Photo"
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(timeout: .seconds(6))
      setContext(connection.contextLabel)

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
      let entity = DuckPhotoEntity(duckName: connection.duckName, frame: frame)
      let message = "Snapped a photo from \(connection.duckName)'s head camera (\(frame.width)×\(frame.height))."
      return ((entity, message), message)
    }

    return .result(
      value: photo,
      dialog: IntentDialog(stringLiteral: dialogText),
      view: DuckPhotoCardView(photo: photo, isCompact: false)
    )
  }
}
