import DuckDependencies
import DuckProtocol
import Observation
import SwiftUI
@preconcurrency import WebRTC

@Observable
@MainActor
public final class VideoTrackRegistry {
  public static let shared = VideoTrackRegistry()

  public var currentTrack: RTCVideoTrack?

  public init() {}
}

public struct LiveDuckVideoCanvas: View {
  public let videoInfo: VideoInfoFrame
  private let registry = VideoTrackRegistry.shared

  public init(videoInfo: VideoInfoFrame) {
    self.videoInfo = videoInfo
  }

  public var body: some View {
    Group {
      #if canImport(UIKit)
      if let track = registry.currentTrack {
        GeometryReader { proxy in
          let rotation = videoInfo.normalizedRotation
          let quarterTurn = rotation == 90 || rotation == 270
          let frameWidth = quarterTurn ? proxy.size.height : proxy.size.width
          let frameHeight = quarterTurn ? proxy.size.width : proxy.size.height
          MetalRTCVideoRepresentable(track: track)
            .frame(width: frameWidth, height: frameHeight)
            .rotationEffect(.degrees(Double(rotation)))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .clipped()
      } else {
        PreviewDuckCameraBackdrop(videoInfo: videoInfo)
      }
      #else
      PreviewDuckCameraBackdrop(videoInfo: videoInfo)
      #endif
    }
  }
}

#if canImport(UIKit)
import UIKit

private struct MetalRTCVideoRepresentable: UIViewRepresentable {
  let track: RTCVideoTrack

  final class Coordinator {
    var attachedTrack: RTCVideoTrack?
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> RTCMTLVideoView {
    let view = RTCMTLVideoView(frame: .zero)
    view.videoContentMode = .scaleAspectFill
    view.clipsToBounds = true
    track.add(view)
    context.coordinator.attachedTrack = track
    return view
  }

  func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
    if context.coordinator.attachedTrack !== track {
      context.coordinator.attachedTrack?.remove(uiView)
      track.add(uiView)
      context.coordinator.attachedTrack = track
    }
  }

  static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
    coordinator.attachedTrack?.remove(uiView)
    coordinator.attachedTrack = nil
  }
}
#endif
