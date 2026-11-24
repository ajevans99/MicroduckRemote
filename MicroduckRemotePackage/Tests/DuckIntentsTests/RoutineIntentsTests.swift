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
        "move:-0.12",
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
}
