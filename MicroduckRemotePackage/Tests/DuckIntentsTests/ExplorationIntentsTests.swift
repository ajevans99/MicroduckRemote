import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct ExplorationIntentsTests {
  @Test func getDuckProximitySubscribesAndReturnsZoneClearancesAndRecommendedDirection() async throws {
    let subscriptions = LockIsolated(0)
    let pollReads = LockIsolated(0)

    var distances = Array(repeating: 1200, count: 64)
    // Obstacle ahead at 220 mm, obstacle on left at 280 mm, right open at 1200 mm:
    distances[3 * 8 + 3] = 220
    distances[3 * 8 + 0] = 280
    let populatedTof = TofFrame(
      seq: 42,
      rows: 8,
      cols: 8,
      distanceMm: distances,
      status: Array(repeating: 5, count: 64)
    )

    let entity = try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.subscribeTof = {
        subscriptions.withValue { $0 += 1 }
      }
      session.currentSnapshot = {
        let count = pollReads.withValue { current -> Int in
          defer { current += 1 }
          return current
        }
        var snap = DuckSessionSnapshot.previewConnected
        // First read after connectForIntent (count 0, 1) has nil tofFrame; arrives on poll (count 2):
        snap.tofFrame = count >= 2 ? populatedTof : nil
        return snap
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let result = try await GetDuckProximityIntent().perform()
      return result.value
    }

    let proximity = try #require(entity)
    expectNoDifference(subscriptions.value, 1)
    expectNoDifference(proximity.hasSensorData, true)
    expectNoDifference(proximity.frontClearanceMm, 220)
    expectNoDifference(proximity.leftClearanceMm, 280)
    expectNoDifference(proximity.rightClearanceMm, 1200)
    expectNoDifference(proximity.closestObstacleMm, 220)
    expectNoDifference(proximity.obstacleWarning, true)
    expectNoDifference(proximity.recommendedDirection, .turnRight)

    let resolved = try await DuckProximityQuery().entities(for: [proximity.id])
    expectNoDifference(resolved, [proximity])
  }

  @Test func exploreApartmentSteersAroundObstaclesAndAlwaysZeroesVelocity() async throws {
    let moves = LockIsolated<[DuckMoveStepRequest]>([])
    let zeroes = LockIsolated(0)
    let sounds = LockIsolated<[SoundTag]>([])
    let lights = LockIsolated<[String]>([])
    let legRead = LockIsolated(0)

    // Leg 0: obstacle straight ahead + closer on left -> should turn right.
    var blockedLeft = Array(repeating: 1200, count: 64)
    blockedLeft[3 * 8 + 3] = 240
    blockedLeft[3 * 8 + 0] = 260
    let blockedLeftFrame = TofFrame(seq: 1, rows: 8, cols: 8, distanceMm: blockedLeft, status: Array(repeating: 5, count: 64))

    // Leg 1: wide open ahead -> should walk forward with obstacle detection enabled.
    let clearFrame = TofFrame(seq: 2, rows: 8, cols: 8, distanceMm: Array(repeating: 1500, count: 64), status: Array(repeating: 5, count: 64))

    let summary = try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = {
        let count = legRead.withValue { current -> Int in
          defer { current += 1 }
          return current
        }
        var snap = DuckSessionSnapshot.previewConnected
        // count 0: connectForIntent, count 1: initial pre-check, count 2: leg 0 -> blockedLeft; count >= 3: clearFrame
        snap.tofFrame = count <= 2 ? blockedLeftFrame : clearFrame
        return snap
      }
      session.performMoveStep = { req in
        moves.withValue { $0.append(req) }
        return DuckMoveStepResult(
          appliedTwist: req.clampedTwist,
          elapsedSeconds: req.clampedDurationSeconds,
          pulsesSent: 5,
          stopReason: .completed
        )
      }
      session.sendMove = { move in
        if move == .zero {
          zeroes.withValue { $0 += 1 }
        }
      }
      session.playSound = { tag, _ in
        sounds.withValue { $0.append(tag) }
      }
      session.setFlashlightColor = { on, color in
        lights.withValue { $0.append("\(on):\(color)") }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let result = try await ExploreApartmentIntent(
        durationSeconds: 10.0,
        maxSteps: 2,
        playfulReactions: true
      ).perform()
      return result.value
    }

    expectNoDifference(moves.value.count, 2)
    // Leg 0 turned right (negative vyaw, stopOnObstacle == false):
    expectNoDifference(moves.value[0].vx, 0)
    expectNoDifference(moves.value[0].vyaw < 0, true)
    expectNoDifference(moves.value[0].stopOnObstacle, false)
    // Leg 1 walked forward (positive vx, stopOnObstacle == true):
    expectNoDifference(moves.value[1].vx > 0, true)
    expectNoDifference(moves.value[1].stopOnObstacle, true)
    // Guaranteed cleanup:
    expectNoDifference(zeroes.value >= 1, true)
    expectNoDifference(lights.value.last, "false:white")
    expectNoDifference(sounds.value.contains(.inquire), true)
    expectNoDifference(summary?.contains("1 obstacle avoided"), true)
  }

  @Test func exploreApartmentReactsPlayfullyToCloseLowFloorObject() async throws {
    let triggeredSkills = LockIsolated<[String]>([])
    let looks = LockIsolated<[RobotLookParams]>([])

    var ballDistances = Array(repeating: 1500, count: 64)
    ballDistances[5 * 8 + 3] = 240
    let ballFrame = TofFrame(seq: 7, rows: 8, cols: 8, distanceMm: ballDistances, status: Array(repeating: 5, count: 64))

    let summary = try await withDependencies {
      var snap = DuckSessionSnapshot.previewConnected
      snap.tofFrame = ballFrame
      let frozen = snap

      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      session.performSkill = { skill in
        triggeredSkills.withValue { $0.append(skill) }
      }
      session.sendLook = { look in
        looks.withValue { $0.append(look) }
        return RobotLookResult(accepted: true, clamped: false)
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let result = try await ExploreApartmentIntent(
        durationSeconds: 8.0,
        maxSteps: 1,
        playfulReactions: true
      ).perform()
      return result.value
    }

    expectNoDifference(triggeredSkills.value, ["kick_right"])
    expectNoDifference(looks.value.count >= 2, true)
    expectNoDifference(summary?.contains("playful reaction"), true)
  }

  @Test func exploreApartmentStopsSafelyWhenDuckFallsOrTaskIsCancelled() async throws {
    // 1. Refuses to start if already fallen:
    await withDependencies {
      var fallen = DuckSessionSnapshot.previewConnected
      fallen.latestState?.safety?.fallen = true
      let frozen = fallen
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      await #expect(throws: DuckSessionError.duckFallen) {
        _ = try await ExploreApartmentIntent(durationSeconds: 6.0, maxSteps: 3).perform()
      }
    }

    // 2. Task cancellation mid-exploration always sends RobotMoveParams.zero and resets face light:
    let cleanupTrace = LockIsolated<[String]>([])
    let startedWalking = AsyncStream.makeStream(of: Void.self)

    let exploreTask = Task {
      try await withDependencies {
        var snap = DuckSessionSnapshot.previewConnected
        snap.tofFrame = TofFrame(
          seq: 1,
          rows: 8,
          cols: 8,
          distanceMm: Array(repeating: 1600, count: 64),
          status: Array(repeating: 5, count: 64)
        )
        let frozen = snap

        var session = DuckSessionClient.previewValue
        session.currentSnapshot = { frozen }
        session.performMoveStep = { req in
          startedWalking.continuation.yield()
          try await Task.sleep(for: .seconds(5))
          return DuckMoveStepResult(
            appliedTwist: req.clampedTwist,
            elapsedSeconds: req.clampedDurationSeconds,
            pulsesSent: 10,
            stopReason: .completed
          )
        }
        session.sendMove = { move in
          if move == .zero {
            cleanupTrace.withValue { $0.append("zero") }
          }
        }
        session.setFlashlightColor = { on, color in
          cleanupTrace.withValue { $0.append("light:\(on):\(color)") }
        }
        $0.duckSession = session
        $0.continuousClock = ContinuousClock()
      } operation: {
        _ = try await ExploreApartmentIntent(
          durationSeconds: 12.0,
          maxSteps: 4,
          playfulReactions: true
        ).perform()
      }
    }

    var iterator = startedWalking.stream.makeAsyncIterator()
    _ = await iterator.next()
    exploreTask.cancel()

    await #expect(throws: CancellationError.self) {
      try await exploreTask.value
    }

    expectNoDifference(cleanupTrace.value.contains("zero"), true)
  }
}
