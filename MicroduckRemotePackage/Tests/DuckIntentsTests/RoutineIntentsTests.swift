import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct RoutineIntentsTests {
  @Test func performDuckRoutineExecutesStepsInOrderAndCleansUpLightsAndVelocity() async throws {
    let trace = LockIsolated<[String]>([])

    let routine = DuckRoutine(
      title: "Suspicious Peek",
      mood: "Suspicious",
      steps: [
        DuckRoutineStep(
          caption: "Peek left",
          sound: .inquire,
          lookHorizontalPercent: -80,
          lookVerticalPercent: -20,
          durationSeconds: 0.4,
          lightColor: .yellow
        ),
        DuckRoutineStep(
          caption: "Back away",
          moveDirection: .backward,
          durationSeconds: 0.5,
          speedPercent: 40
        ),
        DuckRoutineStep(
          caption: "Victory roll",
          sound: .chirp,
          durationSeconds: 0.5,
          builtInTrick: .roulade,
          lightColor: .green
        ),
      ]
    )

    let returned = try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.setFlashlightColor = { on, color in
        trace.withValue { $0.append("light:\(on):\(color)") }
      }
      session.sendLook = { look in
        trace.withValue { $0.append("look:\(String(format: "%.2f", look.y))") }
        return RobotLookResult(accepted: true, clamped: false)
      }
      session.playSound = { tag, hold in
        trace.withValue { $0.append("sound:\(tag.rawValue):\(hold.map(String.init) ?? "nil")") }
      }
      session.performMoveStep = { req in
        trace.withValue { $0.append("move:\(String(format: "%.2f", req.vx))") }
        return DuckMoveStepResult(
          appliedTwist: req.clampedTwist,
          elapsedSeconds: req.clampedDurationSeconds,
          pulsesSent: 5,
          stopReason: .completed
        )
      }
      session.performSkill = { skill in
        trace.withValue { $0.append("skill:\(skill)") }
      }
      session.sendMove = { move in
        trace.withValue { $0.append("zero:\(move.vx == 0 && move.vy == 0 && move.vyaw == 0)") }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let result = try await PerformDuckRoutineIntent(routine: routine).perform()
      return result.value
    }

    expectNoDifference(returned?.title, "Suspicious Peek")
    expectNoDifference(returned?.steps.count, 3)
    expectNoDifference(
      trace.value,
      [
        "light:true:yellow",
        "look:0.56",
        "sound:inquire:nil",
        "move:-0.45",
        "light:true:green",
        "sound:chirp:nil",
        "skill:roulade",
        "zero:true",
        "light:false:white",
      ]
    )
  }

  @Test func performDuckRoutineStopsEarlyWhenDuckFallsAndCapsAtSixSteps() async throws {
    let soundsPlayed = LockIsolated<[SoundTag]>([])
    let reads = LockIsolated(0)

    let steps = (0..<8).map { i in
      DuckRoutineStep(caption: "Beat \(i)", sound: .chirp, durationSeconds: 0.3)
    }
    let routine = DuckRoutine(title: "Long Dance", mood: "Wild", steps: steps)

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = {
        let count = reads.withValue { c -> Int in
          defer { c += 1 }
          return c
        }
        var snap = DuckSessionSnapshot.previewConnected
        // Initial connection check (0), step 0 (1), step 1 (2) upright; step 2 (3) fallen!
        if count >= 3 {
          snap.latestState?.safety?.fallen = true
        }
        return snap
      }
      session.playSound = { tag, _ in
        soundsPlayed.withValue { $0.append(tag) }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await PerformDuckRoutineIntent(routine: routine).perform()
    }

    expectNoDifference(soundsPlayed.value, [.chirp, .chirp])
  }

  @Test func performDuckRoutineReleasesHeldWheeeAndResetsLightsOnCancellation() async {
    let trace = LockIsolated<[String]>([])
    let firstHold = AsyncStream.makeStream(of: Void.self)

    let routine = DuckRoutine(
      title: "Big Cheer",
      mood: "Excited",
      steps: [
        DuckRoutineStep(
          caption: "Celebrate",
          sound: .wheee,
          durationSeconds: 2.0,
          lightColor: .cyan
        )
      ]
    )

    let task = Task {
      try await withDependencies {
        var session = DuckSessionClient.previewValue
        session.setFlashlightColor = { on, color in
          trace.withValue { $0.append("light:\(on):\(color)") }
        }
        session.playSound = { tag, hold in
          trace.withValue { $0.append("sound:\(tag.rawValue):\(hold.map(String.init) ?? "nil")") }
          if hold == true {
            firstHold.continuation.yield()
          }
        }
        session.sendMove = { _ in
          trace.withValue { $0.append("zero") }
        }
        $0.duckSession = session
        $0.continuousClock = ContinuousClock()
      } operation: {
        _ = try await PerformDuckRoutineIntent(routine: routine).perform()
      }
    }

    var iterator = firstHold.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }

    expectNoDifference(
      trace.value,
      [
        "light:true:cyan",
        "sound:wheee:true",
        "sound:wheee:false",
        "zero",
        "light:false:white",
      ]
    )
  }

  @Test func performDuckRoutineDrivesBeakHeadTiltAndCrouchWithClampingAndReset() async throws {
    let trace = LockIsolated<[String]>([])

    let step = DuckRoutineStep(
      caption: "Curious gasp",
      sound: .inquire,
      lookHorizontalPercent: -50,
      lookVerticalPercent: -20,
      durationSeconds: 0.4,
      beakOpenPercent: 140,
      headTiltPercent: -150,
      crouchPercent: 120
    )
    expectNoDifference(step.clampedBeakOpenPercent, 100)
    expectNoDifference(step.clampedHeadTiltPercent, -100)
    expectNoDifference(step.clampedCrouchPercent, 100)
    expectNoDifference(step.summarySubtitle.contains("Beak 100%"), true)
    expectNoDifference(step.summarySubtitle.contains("Tilt -100%"), true)
    expectNoDifference(step.summarySubtitle.contains("Crouch 100%"), true)

    let routine = DuckRoutine(
      title: "Curious Crouch",
      mood: "Curious",
      steps: [
        step,
        DuckRoutineStep(
          caption: "Stand tall & tilt right",
          durationSeconds: 0.4,
          beakOpenPercent: 0,
          headTiltPercent: 50,
          crouchPercent: 0
        ),
      ]
    )

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendLook = { _ in
        trace.withValue { $0.append("look") }
        return RobotLookResult(
          head: RobotHeadParams(neckPitch: 0.0, headPitch: -0.15, headYaw: 0.35, headRoll: 0.0),
          accepted: true,
          clamped: false
        )
      }
      session.sendHead = { head in
        trace.withValue {
          $0.append(
            "head:\(String(format: "%.2f", head.headYaw)):\(String(format: "%.2f", head.headRoll))"
          )
        }
      }
      session.sendMouth = { mouth in
        trace.withValue { $0.append("mouth:\(String(format: "%.2f", mouth.open))") }
      }
      session.sendPose = { pose in
        trace.withValue { $0.append("pose:\(pose.active):\(String(format: "%.3f", pose.z))") }
      }
      session.playSound = { tag, _ in
        trace.withValue { $0.append("sound:\(tag.rawValue)") }
      }
      session.sendMove = { _ in
        trace.withValue { $0.append("zero") }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await PerformDuckRoutineIntent(routine: routine).perform()
    }

    expectNoDifference(
      trace.value,
      [
        "look",
        "head:0.35:-0.43",
        "mouth:1.00",
        "pose:true:-0.025",
        "sound:inquire",
        "head:0.00:0.21",
        "mouth:0.00",
        "pose:false:0.000",
        "zero",
        "mouth:0.00",
        "pose:false:0.000",
        "head:0.00:0.00",
      ]
    )
  }

  @Test func performDuckRoutineResetsBeakPoseAndHeadTiltOnCancellation() async {
    let trace = LockIsolated<[String]>([])
    let poseSent = AsyncStream.makeStream(of: Void.self)

    let routine = DuckRoutine(
      title: "Sneaky Peek",
      mood: "Sneaky",
      steps: [
        DuckRoutineStep(
          caption: "Crouch and open beak",
          durationSeconds: 2.0,
          beakOpenPercent: 75,
          headTiltPercent: 60,
          crouchPercent: 80
        )
      ]
    )

    let task = Task {
      try await withDependencies {
        var session = DuckSessionClient.previewValue
        session.sendHead = { head in
          trace.withValue { $0.append("head:\(String(format: "%.2f", head.headRoll))") }
        }
        session.sendMouth = { mouth in
          trace.withValue { $0.append("mouth:\(String(format: "%.2f", mouth.open))") }
        }
        session.sendPose = { pose in
          trace.withValue { $0.append("pose:\(pose.active)") }
          if pose.active {
            poseSent.continuation.yield()
          }
        }
        session.sendMove = { _ in
          trace.withValue { $0.append("zero") }
        }
        $0.duckSession = session
        $0.continuousClock = ContinuousClock()
      } operation: {
        _ = try await PerformDuckRoutineIntent(routine: routine).perform()
      }
    }

    var iterator = poseSent.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }

    expectNoDifference(
      trace.value,
      [
        "head:0.26",
        "mouth:0.75",
        "pose:true",
        "zero",
        "mouth:0.00",
        "pose:false",
        "head:0.00",
      ]
    )
  }
}
