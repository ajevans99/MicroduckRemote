import CoreTransferable
import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing
import UniformTypeIdentifiers

@Suite struct CameraIntentsTests {
  @Test func directDuckGazeMapsPercentagesToLookGeometry() async throws {
    let looks = LockIsolated<[RobotLookParams]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendLook = { target in
        looks.withValue { $0.append(target) }
        return RobotLookResult(accepted: true, clamped: false)
      }
      $0.duckSession = session
    } operation: {
      let intent = DirectDuckGazeIntent(horizontalPercent: -50, verticalPercent: -100)
      _ = try await intent.perform()
    }

    expectNoDifference(
      looks.value,
      [LookGeometry.lookTarget(normalizedX: -0.5, normalizedY: -1.0)]
    )
  }

  @Test func snapDuckPhotoCapturesFrameAndExportsTransferableJPEG() async throws {
    let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9])
    let capturedAt = Date(timeIntervalSince1970: 1_795_150_123)

    let entity = try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.capturePhoto = {
        DuckCapturedFrame(
          jpegData: fakeJPEG,
          width: 360,
          height: 640,
          capturedAt: capturedAt
        )
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let result = try await SnapDuckPhotoIntent().perform()
      return result.value
    }

    let unwrapped = try #require(entity)
    expectNoDifference(unwrapped.duckName, "duck-eb55")
    expectNoDifference(unwrapped.width, 360)
    expectNoDifference(unwrapped.height, 640)
    expectNoDifference(unwrapped.imageFile.data, fakeJPEG)

    let exportedJPEG = try await unwrapped.exported(as: .jpeg)
    expectNoDifference(exportedJPEG, fakeJPEG)
  }

  @Test func snapDuckPhotoWaitsForVideoTrackAfterColdStart() async throws {
    let reads = LockIsolated(0)
    let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])

    let entity = try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = {
        let count = reads.withValue { c -> Int in
          defer { c += 1 }
          return c
        }
        var snap = DuckSessionSnapshot.previewConnected
        // Initially disconnected (0), then controlOpen without video track (1), then track arrives (2)
        if count == 0 {
          snap.controlOpen = false
          snap.hasVideoTrack = false
          snap.phase = .disconnected
        } else if count == 1 {
          snap.hasVideoTrack = false
        }
        return snap
      }
      session.capturePhoto = {
        DuckCapturedFrame(jpegData: fakeJPEG, width: 640, height: 360, capturedAt: Date(timeIntervalSince1970: 1))
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let result = try await SnapDuckPhotoIntent().perform()
      return result.value
    }

    expectNoDifference(entity?.imageFile.data, fakeJPEG)
    expectNoDifference(reads.value >= 3, true)
  }
}
