import CoreImage
import CoreVideo
import DuckDependencies
import DuckProtocol
import Foundation
import ImageIO
import Observation
import SwiftUI
@preconcurrency import WebRTC

@Observable
@MainActor
public final class VideoTrackRegistry {
  public static let shared = VideoTrackRegistry()

  public var currentTrack: RTCVideoTrack?

  public init() {}

  /// Captures a single decoded frame from the active WebRTC video track, rotates it upright
  /// according to `videoInfo.normalizedRotation`, and encodes it as JPEG data for App Intents.
  public func captureNextFrame(
    videoInfo: VideoInfoFrame,
    timeout: Duration = .seconds(3)
  ) async throws -> DuckCapturedFrame {
    guard let track = currentTrack, track.isEnabled else {
      throw DuckSessionError.noActiveVideoStream
    }

    let sink = OneShotVideoFrameSink(rotationDegrees: videoInfo.normalizedRotation)
    track.add(sink)
    defer {
      track.remove(sink)
    }

    return try await withThrowingTaskGroup(of: DuckCapturedFrame.self) { group in
      group.addTask {
        try await sink.waitForFrame()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw DuckSessionError.frameCaptureTimedOut
      }
      guard let first = try await group.next() else {
        throw DuckSessionError.frameCaptureTimedOut
      }
      group.cancelAll()
      return first
    }
  }
}

private final class OneShotVideoFrameSink: NSObject, RTCVideoRenderer, @unchecked Sendable {
  private let lock = NSLock()
  private let rotationDegrees: Int
  private var continuation: CheckedContinuation<DuckCapturedFrame, any Error>?
  private var bufferedResult: Result<DuckCapturedFrame, any Error>?
  private var didComplete = false

  init(rotationDegrees: Int) {
    self.rotationDegrees = ((rotationDegrees % 360) + 360) % 360
    super.init()
  }

  func waitForFrame() async throws -> DuckCapturedFrame {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { cont in
        lock.lock()
        if let bufferedResult {
          lock.unlock()
          cont.resume(with: bufferedResult)
          return
        }
        continuation = cont
        lock.unlock()
      }
    } onCancel: {
      finish(with: .failure(CancellationError()))
    }
  }

  func setSize(_ size: CGSize) {}

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame else { return }
    lock.lock()
    if didComplete {
      lock.unlock()
      return
    }
    didComplete = true
    lock.unlock()

    let capturedAt = Date()
    guard let ciImage = Self.makeCIImage(from: frame, extraRotationDegrees: rotationDegrees) else {
      finish(with: .failure(DuckSessionError.noActiveVideoStream))
      return
    }

    let context = CIContext(options: [.useSoftwareRenderer: false])
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let jpegData = context.jpegRepresentation(
        of: ciImage,
        colorSpace: colorSpace,
        options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
      )
    else {
      finish(with: .failure(DuckSessionError.noActiveVideoStream))
      return
    }

    let extent = ciImage.extent.integral
    let result = DuckCapturedFrame(
      jpegData: jpegData,
      width: max(1, Int(extent.width)),
      height: max(1, Int(extent.height)),
      capturedAt: capturedAt
    )
    finish(with: .success(result))
  }

  private func finish(with result: Result<DuckCapturedFrame, any Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    if pending == nil && bufferedResult == nil {
      bufferedResult = result
    }
    didComplete = true
    lock.unlock()
    pending?.resume(with: result)
  }

  private static func makeCIImage(from frame: RTCVideoFrame, extraRotationDegrees: Int) -> CIImage? {
    let baseImage: CIImage?
    if let rtcPixelBuffer = frame.buffer as? RTCCVPixelBuffer {
      baseImage = CIImage(cvPixelBuffer: rtcPixelBuffer.pixelBuffer)
    } else {
      let i420 = frame.buffer.toI420()
      baseImage = makeCIImageFromI420(i420)
    }
    guard let image = baseImage else { return nil }

    let frameRotation = Int(frame.rotation.rawValue)
    let totalClockwise = ((extraRotationDegrees + frameRotation) % 360 + 360) % 360
    let orientation: CGImagePropertyOrientation = switch totalClockwise {
    case 90: .right
    case 180: .down
    case 270: .left
    default: .up
    }
    return orientation == .up ? image : image.oriented(orientation)
  }

  private static func makeCIImageFromI420(_ i420: any RTCI420BufferProtocol) -> CIImage? {
    let width = Int(i420.width)
    let height = Int(i420.height)
    guard width > 0, height > 0 else { return nil }

    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8Planar,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }

    copyPlane(src: i420.dataY, srcStride: Int(i420.strideY), dst: pb, plane: 0, rows: height, rowBytes: width)
    let chromaRows = (height + 1) / 2
    let chromaBytes = (width + 1) / 2
    copyPlane(src: i420.dataU, srcStride: Int(i420.strideU), dst: pb, plane: 1, rows: chromaRows, rowBytes: chromaBytes)
    copyPlane(src: i420.dataV, srcStride: Int(i420.strideV), dst: pb, plane: 2, rows: chromaRows, rowBytes: chromaBytes)

    return CIImage(cvPixelBuffer: pb)
  }

  private static func copyPlane(
    src: UnsafePointer<UInt8>,
    srcStride: Int,
    dst: CVPixelBuffer,
    plane: Int,
    rows: Int,
    rowBytes: Int
  ) {
    guard let dstBase = CVPixelBufferGetBaseAddressOfPlane(dst, plane) else { return }
    let dstStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
    let dstPtr = dstBase.assumingMemoryBound(to: UInt8.self)
    let copyCount = min(rowBytes, min(srcStride, dstStride))
    for row in 0..<rows {
      memcpy(dstPtr.advanced(by: row * dstStride), src.advanced(by: row * srcStride), copyCount)
    }
  }
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
