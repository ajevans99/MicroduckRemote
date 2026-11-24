import CockpitFeature
import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckProtocol
import Foundation
import Testing

@Suite struct CockpitFeatureTests {
  @Test @MainActor func thumbstickDeflectionAndReleaseSendScaledTwistAndZero() async {
    let recordedMoves = LockIsolated<[RobotMoveParams]>([])

    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendMove = { move in
        recordedMoves.withValue { $0.append(move) }
      }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected

      await model.leftThumbstickMoved(x: -0.5, y: -1.0)
      await model.rightThumbstickMoved(x: 1.0)
      await model.leftThumbstickReleased()
      await model.rightThumbstickReleased()

      expectNoDifference(
        recordedMoves.value,
        [
          RobotMoveParams(vx: 0.3, vy: 0.15, vyaw: 0.0),
          RobotMoveParams(vx: 0.3, vy: 0.15, vyaw: -1.5),
          RobotMoveParams(vx: 0.0, vy: 0.0, vyaw: 0.0),
        ]
      )
    }
  }

  @Test @MainActor func videoDragUpdatesGazeAndDetectsClampedIK() async {
    let recordedLooks = LockIsolated<[RobotLookParams]>([])

    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendLook = { look in
        recordedLooks.withValue { $0.append(look) }
        return RobotLookResult(accepted: true, clamped: true)
      }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected

      await model.videoStageDragged(normalizedX: 0.5, normalizedY: -0.5)
      expectNoDifference(model.isLooking, true)
      expectNoDifference(model.isGazeClamped, true)
      expectNoDifference(
        recordedLooks.value,
        [LookGeometry.lookTarget(normalizedX: 0.5, normalizedY: -0.5)]
      )

      model.videoStageDragEnded()
      expectNoDifference(model.isLooking, false)
      expectNoDifference(model.isGazeClamped, false)
    }
  }

  @Test @MainActor func standBackUpButtonTriggersRecoveryAction() async {
    let standCalls = LockIsolated(0)

    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.standBackUp = {
        standCalls.withValue { $0 += 1 }
      }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected
      model.snapshot.latestState?.safety?.fallen = true

      expectNoDifference(model.isFallen, true)
      await model.standBackUpButtonTapped()
      expectNoDifference(standCalls.value, 1)
      expectNoDifference(model.isStandingBackUp, false)
    }
  }

  @Test @MainActor func pullingLeftThumbstickDownMapsIntoBackwardBreakawayBand() async {
    let recordedMoves = LockIsolated<[RobotMoveParams]>([])

    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendMove = { move in
        recordedMoves.withValue { $0.append(move) }
      }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected

      // Pulling stick halfway down (y = +0.5 -> vxInput = -0.5) clears velstand's -0.42 dead zone:
      await model.leftThumbstickMoved(x: 0.0, y: 0.5)
      await model.leftThumbstickMoved(x: 0.0, y: 1.0)

      expectNoDifference(
        recordedMoves.value.map { ($0.vx * 1000).rounded() / 1000 },
        [-0.46, -0.50]
      )
    }
  }
}
