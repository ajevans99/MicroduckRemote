import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckProtocol
import Foundation
import Testing

@Suite struct ClosedLoopMotionExecutorTests {
  @Test func moveDistanceStopsOnOdometryTargetWithDecelerationAndZeroStop() async throws {
    let state = LockIsolated<DuckSessionSnapshot>({
      var snap = DuckSessionSnapshot.previewConnected
      snap.latestState?.odom = OdomTelemetry(position: [0, 0, 0.116], yaw: 0)
      snap.tofFrame = TofFrame(seq: 1, rows: 8, cols: 8, distanceMm: Array(repeating: 1500, count: 64))
      return snap
    }())
    let sentMoves = LockIsolated<[RobotMoveParams]>([])

    let result = try await DuckClosedLoopMotionExecutor.execute(
      goal: .moveDistance(direction: .forward, meters: 0.50, speedPercent: 80, stopOnObstacle: true),
      clock: ImmediateClock(),
      currentSnapshot: { state.value },
      subscribeTof: {},
      sendMove: { move in
        sentMoves.withValue { $0.append(move) }
        if move.vx > 0 {
          state.withValue { snap in
            let x = (snap.latestState?.odom?.x ?? 0) + 0.10
            snap.latestState?.odom = OdomTelemetry(position: [x, 0, 0.116], yaw: 0)
          }
        }
      }
    )

    expectNoDifference(result.stopReason, .reachedTarget)
    expectNoDifference(result.usedClosedLoopFeedback, true)
    expectNoDifference(abs(result.distanceTraveledMeters - 0.50) < 0.02, true)
    expectNoDifference(sentMoves.value.last, .zero)
    // Verify proportional slowdown occurred before the final zero pulse:
    let nonZero = sentMoves.value.filter { $0.vx > 0 }
    #expect(nonZero.count == 5)
    #expect(nonZero.last!.vx < nonZero.first!.vx)
  }

  @Test func moveDistanceStopsEarlyWhenForwardToFSeesObstacle() async throws {
    let state = LockIsolated<DuckSessionSnapshot>({
      var snap = DuckSessionSnapshot.previewConnected
      snap.latestState?.odom = OdomTelemetry(position: [0, 0, 0.116], yaw: 0)
      snap.tofFrame = TofFrame(seq: 1, rows: 8, cols: 8, distanceMm: Array(repeating: 900, count: 64))
      return snap
    }())
    let moves = LockIsolated<[RobotMoveParams]>([])
    let ticks = LockIsolated(0)

    let result = try await DuckClosedLoopMotionExecutor.execute(
      goal: .moveDistance(direction: .forward, meters: 1.5, speedPercent: 60, stopOnObstacle: true, minObstacleDistanceMm: 220),
      clock: ImmediateClock(),
      currentSnapshot: { state.value },
      subscribeTof: {},
      sendMove: { move in
        moves.withValue { $0.append(move) }
        let n = ticks.withValue { $0 += 1; return $0 }
        if n == 2 {
          state.withValue {
            $0.tofFrame = TofFrame(seq: 2, rows: 8, cols: 8, distanceMm: Array(repeating: 175, count: 64))
          }
        }
      }
    )

    expectNoDifference(result.stopReason, .stoppedForObstacle(distanceMm: 175))
    expectNoDifference(moves.value.last, .zero)
  }

  @Test func moveDistanceFallsBackGracefullyWhenOdometryIsUnavailable() async throws {
    var snap = DuckSessionSnapshot.previewConnected
    snap.latestState?.odom = nil
    snap.tofFrame = TofFrame(seq: 1, rows: 8, cols: 8, distanceMm: Array(repeating: 1500, count: 64))
    let frozen = snap
    let moves = LockIsolated<[RobotMoveParams]>([])

    let result = try await DuckClosedLoopMotionExecutor.execute(
      goal: .moveDistance(direction: .forward, meters: 0.3, speedPercent: 100, stopOnObstacle: true),
      clock: ImmediateClock(),
      currentSnapshot: { frozen },
      subscribeTof: {},
      sendMove: { move in moves.withValue { $0.append(move) } }
    )

    expectNoDifference(result.stopReason, .reachedTarget)
    expectNoDifference(result.usedClosedLoopFeedback, false)
    expectNoDifference(moves.value.last, .zero)
  }

  @Test func turnAngleIntegratesAcrossPiWrapSeamWithoutWrappingBackward() async throws {
    let startYaw = 150.0 * .pi / 180.0
    let state = LockIsolated<DuckSessionSnapshot>({
      var snap = DuckSessionSnapshot.previewConnected
      snap.latestState?.odom = OdomTelemetry(position: [0, 0, 0.116], yaw: startYaw)
      return snap
    }())
    let moves = LockIsolated<[RobotMoveParams]>([])

    let result = try await DuckClosedLoopMotionExecutor.execute(
      goal: .turnAngle(degrees: 90.0, speedPercent: 80),
      clock: ImmediateClock(),
      currentSnapshot: { state.value },
      subscribeTof: {},
      sendMove: { move in
        moves.withValue { $0.append(move) }
        if move.vyaw > 0 {
          state.withValue { snap in
            let current = snap.latestState?.odom?.yaw ?? 0
            let next = DuckGeometry.normalizedAngleRadians(current + 15.0 * .pi / 180.0)
            snap.latestState?.odom = OdomTelemetry(position: [0, 0, 0.116], yaw: next)
          }
        }
      }
    )

    expectNoDifference(result.stopReason, .reachedTarget)
    expectNoDifference(result.usedClosedLoopFeedback, true)
    expectNoDifference(abs(result.angleTurnedDegrees - 90.0) <= 5.1, true)
    expectNoDifference(moves.value.last, .zero)
  }

  @Test func approachObstacleAndBackUpUntilClearRespondToLiveToF() async throws {
    let frontMm = LockIsolated(650)
    let state = LockIsolated<DuckSessionSnapshot>(DuckSessionSnapshot.previewConnected)
    let moves = LockIsolated<[RobotMoveParams]>([])

    let makeSnap: @Sendable () -> DuckSessionSnapshot = {
      var snap = state.value
      snap.tofFrame = TofFrame(seq: 1, rows: 8, cols: 8, distanceMm: Array(repeating: frontMm.value, count: 64))
      return snap
    }

    let approach = try await DuckClosedLoopMotionExecutor.execute(
      goal: .approachObstacle(targetClearanceMm: 300, speedPercent: 55),
      clock: ImmediateClock(),
      currentSnapshot: { makeSnap() },
      subscribeTof: {},
      sendMove: { move in
        moves.withValue { $0.append(move) }
        if move.vx > 0 {
          frontMm.withValue { $0 = max(250, $0 - 90) }
        }
      }
    )

    expectNoDifference(approach.stopReason, .reachedTarget)
    #expect((approach.finalFrontClearanceMm ?? 999) <= 300)
    expectNoDifference(moves.value.last, .zero)

    moves.withValue { $0.removeAll() }
    let backUp = try await DuckClosedLoopMotionExecutor.execute(
      goal: .backUpUntilClear(targetClearanceMm: 600, speedPercent: 60),
      clock: ImmediateClock(),
      currentSnapshot: { makeSnap() },
      subscribeTof: {},
      sendMove: { move in
        moves.withValue { $0.append(move) }
        if move.vx < 0 {
          frontMm.withValue { $0 += 110 }
        }
      }
    )

    expectNoDifference(backUp.stopReason, .reachedTarget)
    #expect((backUp.finalFrontClearanceMm ?? 0) >= 600)
    #expect(moves.value.first!.vx <= -DuckConstants.minBackwardBreakawayVelocity)
    expectNoDifference(moves.value.last, .zero)
  }
}
