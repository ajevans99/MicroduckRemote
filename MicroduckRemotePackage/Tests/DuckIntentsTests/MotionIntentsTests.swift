import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct MotionIntentsTests {
  @Test func emergencyStopImmediatelyZeroesVelocityAndHaltsWhenConnected() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.ensureConnected = { _ in
        events.withValue { $0.append("ensureConnected") }
        return DuckIdentity(peerID: "sim-duck-a", name: "duck-eb55", isSimulated: true)
      }
      session.sendMove = { move in
        events.withValue { $0.append("move:\(move.vx),\(move.vy),\(move.vyaw)") }
      }
      session.stop = {
        events.withValue { $0.append("stop") }
      }
      $0.duckSession = session
    } operation: {
      let intent = EmergencyStopDuckIntent()
      _ = try await intent.perform()
    }

    expectNoDifference(
      events.value,
      [
        "move:0.0,0.0,0.0",
        "stop",
      ]
    )
  }

  @Test func emergencyStopColdStartsConnectionWhenControlChannelIsClosed() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var disconnected = DuckSessionSnapshot.previewConnected
      disconnected.controlOpen = false
      disconnected.phase = .disconnected
      let snapshot = disconnected

      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { snapshot }
      session.ensureConnected = { _ in
        events.withValue { $0.append("ensureConnected") }
        return DuckIdentity(peerID: "hw-duck-1", name: "duck-01", isSimulated: false)
      }
      session.sendMove = { move in
        events.withValue { $0.append("move:\(move.vx),\(move.vy),\(move.vyaw)") }
      }
      session.stop = {
        events.withValue { $0.append("stop") }
      }
      $0.duckSession = session
    } operation: {
      let intent = EmergencyStopDuckIntent()
      _ = try await intent.perform()
    }

    expectNoDifference(
      events.value,
      [
        "ensureConnected",
        "move:0.0,0.0,0.0",
        "stop",
      ]
    )
  }

  @Test func setDuckPostureIsIdempotentAcrossStandingSittingDisabledAndFallen() async throws {
    let actions = LockIsolated<[String]>([])

    // 1. Fallen + standUp -> recovers via standBackUp
    try await withDependencies {
      var snap = DuckSessionSnapshot.previewConnected
      snap.latestState?.safety?.fallen = true
      let frozen = snap
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      session.standBackUp = { actions.withValue { $0.append("standBackUp") } }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await SetDuckPostureIntent(posture: .standUp).perform()
    }

    // 2. Disabled + standUp -> setEnabled(true)
    try await withDependencies {
      var snap = DuckSessionSnapshot.previewConnected
      snap.policies?.enabled = false
      let frozen = snap
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      session.setEnabled = { on in actions.withValue { $0.append("setEnabled:\(on)") } }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await SetDuckPostureIntent(posture: .standUp).perform()
    }

    // 3. Sitting + standUp -> performSkill("sit_toggle")
    try await withDependencies {
      let state = LockIsolated<DuckSessionSnapshot>({
        var snap = DuckSessionSnapshot.previewConnected
        snap.policies?.sitting = true
        return snap
      }())
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { state.value }
      session.performSkill = { name in
        actions.withValue { $0.append("skill:\(name)") }
        state.withValue { $0.policies?.sitting = false }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await SetDuckPostureIntent(posture: .standUp).perform()
    }

    // 4. Already standing + standUp -> no-op
    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.setEnabled = { on in actions.withValue { $0.append("setEnabled:\(on)") } }
      session.performSkill = { name in actions.withValue { $0.append("skill:\(name)") } }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await SetDuckPostureIntent(posture: .standUp).perform()
    }

    // 5. Standing + sitDown -> performSkill("sit_toggle")
    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.performSkill = { name in actions.withValue { $0.append("skill:\(name)") } }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await SetDuckPostureIntent(posture: .sitDown).perform()
    }

    expectNoDifference(
      actions.value,
      [
        "standBackUp",
        "setEnabled:true",
        "skill:sit_toggle",
        "skill:sit_toggle",
      ]
    )
  }

  @Test func moveDuckStepMapsDirectionAndSpeedPercentIntoBoundedRequest() async throws {
    let recorded = LockIsolated<[DuckMoveStepRequest]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.performMoveStep = { req in
        recorded.withValue { $0.append(req) }
        return DuckMoveStepResult(
          appliedTwist: req.clampedTwist,
          elapsedSeconds: 0.4,
          pulsesSent: 4,
          stopReason: .stoppedForObstacle(distanceMm: 150)
        )
      }
      $0.duckSession = session
    } operation: {
      let intent = MoveDuckStepIntent(
        direction: .forward,
        durationSeconds: 2.0,
        speedPercent: 50,
        stopOnObstacle: true
      )
      _ = try await intent.perform()
    }

    expectNoDifference(
      recorded.value,
      [
        DuckMoveStepRequest(
          vx: 0.15,
          vy: 0,
          vyaw: 0,
          durationSeconds: 2.0,
          stopOnObstacle: true
        )
      ]
    )

    let turnReq = DuckMoveDirection.turnRight.makeRequest(
      durationSeconds: 2.1,
      speedPercent: 100,
      stopOnObstacle: false
    )
    expectNoDifference(
      turnReq,
      DuckMoveStepRequest(
        vx: 0,
        vy: 0,
        vyaw: -DuckConstants.maxAngularVelocity,
        durationSeconds: 2.1,
        stopOnObstacle: false
      )
    )
  }

  @Test func standUpPollsUntilRiseTransitionCompletes() async throws {
    let state = LockIsolated<DuckSessionSnapshot>({
      var snap = DuckSessionSnapshot.previewConnected
      snap.policies?.sitting = true
      snap.latestState?.policy = "sit"
      return snap
    }())
    let refreshCount = LockIsolated(0)

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { state.value }
      session.performSkill = { _ in
        state.withValue {
          $0.policies?.sitting = false
          $0.latestState?.policy = "rise"
        }
      }
      session.refreshSkills = {
        let count = refreshCount.withValue {
          $0 += 1
          return $0
        }
        // First refresh is from ensureConnected (still sitting); second is still rising; third is standing.
        if count >= 3 {
          state.withValue {
            $0.policies?.sitting = false
            $0.latestState?.policy = "walk"
          }
        }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await SetDuckPostureIntent(posture: .standUp).perform()
    }

    expectNoDifference(refreshCount.value, 3)
    expectNoDifference(state.value.latestState?.policy, "walk")
    expectNoDifference(state.value.policies?.sitting, false)
  }

  @Test func moveDuckStepRefreshesLivePoliciesBeforeExecuting() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.refreshSkills = {
        events.withValue { $0.append("refreshSkills") }
      }
      session.performMoveStep = { req in
        events.withValue { $0.append("performMoveStep") }
        return DuckMoveStepResult(
          appliedTwist: req.clampedTwist,
          elapsedSeconds: req.durationSeconds,
          pulsesSent: 10,
          stopReason: .completed
        )
      }
      $0.duckSession = session
    } operation: {
      _ = try await MoveDuckStepIntent(direction: .forward, durationSeconds: 1.0, speedPercent: 60).perform()
    }

    expectNoDifference(events.value, ["refreshSkills", "performMoveStep"])
  }
}
