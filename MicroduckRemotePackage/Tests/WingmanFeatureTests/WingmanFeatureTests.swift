import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckProtocol
import Foundation
import Testing
import WingmanFeature

@Suite struct WingmanFeatureTests {
  @Test func contextBuilderReflectsPostureBatteryOdomToFAndSkills() {
    var snap = DuckSessionSnapshot.previewConnected
    snap.latestState?.safety?.fallen = true
    snap.health?.battery = BatteryHealth(volts: 6.95, percent: 15)
    snap.health?.motors = MotorsHealth(maxC: 58, hottest: "left_knee")

    expectNoDifference(WingmanContextBuilder.canDriveNow(snap), false)
    let instructions = WingmanContextBuilder.agentInstructions(for: snap, supportsVision: true)
    #expect(instructions.contains("FALLEN"))
    #expect(instructions.contains("LOW BATTERY"))
    #expect(instructions.contains("WARM"))
    #expect(instructions.contains("Odometry:"))
    #expect(instructions.contains("8x8 ToF Clearances:"))
    #expect(instructions.contains("polite-bow"))
    #expect(instructions.contains("Vision is enabled"))
  }

  @Test func missionExecutorRunsStepsAndCleansUpActuators() async throws {
    let events = LockIsolated<[String]>([])
    var session = DuckSessionClient.previewValue
    session.performMotion = { goal in
      switch goal {
      case let .moveDistance(dir, meters, _, _, _, _):
        events.withValue { $0.append("move:\(dir.rawValue):\(String(format: "%.2f", meters))") }
        return DuckMotionResult(goal: goal, stopReason: .reachedTarget, elapsedSeconds: 1.0, distanceTraveledMeters: meters)
      case let .turnAngle(deg, _, _):
        events.withValue { $0.append("turn:\(Int(deg))") }
        return DuckMotionResult(goal: goal, stopReason: .reachedTarget, elapsedSeconds: 1.0, angleTurnedDegrees: deg)
      case let .approachObstacle(mm, _, _):
        events.withValue { $0.append("approach:\(mm)") }
        return DuckMotionResult(goal: goal, stopReason: .reachedTarget, elapsedSeconds: 1.0, finalFrontClearanceMm: mm)
      case let .backUpUntilClear(mm, _, _):
        events.withValue { $0.append("backup:\(mm)") }
        return DuckMotionResult(goal: goal, stopReason: .reachedTarget, elapsedSeconds: 1.0, finalFrontClearanceMm: mm)
      }
    }
    session.sendMove = { move in
      if move == .zero { events.withValue { $0.append("move:zero") } }
    }
    session.sendMouth = { mouth in
      events.withValue { $0.append("mouth:\(Int((mouth.open * 100).rounded()))") }
    }
    session.sendPose = { pose in
      events.withValue { $0.append(pose.active ? "pose:crouch" : "pose:nominal") }
    }

    let plan = WingmanMissionPlan(
      title: "Scout & React",
      summary: "Walk 0.5m, turn right 90°, crouch, and close cleanly.",
      steps: [
        WingmanMissionStep(action: .walkForward, amount: 0.5, note: "Walk forward"),
        WingmanMissionStep(action: .turnRight, amount: 90, note: "Turn right"),
        WingmanMissionStep(action: .beak, amount: 100, note: "Open beak"),
        WingmanMissionStep(action: .crouch, amount: 80, note: "Crouch down"),
      ]
    )

    let startedIndices = LockIsolated<[Int]>([])
    try await WingmanMissionExecutor.execute(
      plan: plan,
      duckSession: session,
      clock: ImmediateClock(),
      onStepStarted: { index, _ in startedIndices.withValue { $0.append(index) } },
      onActivity: { _ in }
    )

    expectNoDifference(startedIndices.value, [0, 1, 2, 3])
    #expect(events.value.contains("move:forward:0.50"))
    #expect(events.value.contains("turn:-90"))
    #expect(events.value.contains("mouth:100"))
    #expect(events.value.contains("pose:crouch"))
    #expect(events.value.contains("move:zero"))
    #expect(events.value.last == "pose:nominal")
  }

  @Test func wingmanToolsDispatchMotionAndRecordActivity() async throws {
    let activities = LockIsolated<[WingmanActivityItem]>([])
    let goals = LockIsolated<[DuckMotionGoal]>([])

    var session = DuckSessionClient.previewValue
    session.performMotion = { goal in
      goals.withValue { $0.append(goal) }
      return DuckMotionResult(
        goal: goal,
        stopReason: .reachedTarget,
        elapsedSeconds: 1.0,
        distanceTraveledMeters: 0.6,
        angleTurnedDegrees: -45,
        finalFrontClearanceMm: 300
      )
    }

    let walkTool = WalkDuckDistanceTool(duckSession: session) { item in
      activities.withValue { $0.append(item) }
    }
    let walkOut = try await walkTool.call(
      arguments: .init(direction: "forward", meters: 0.6, stopOnObstacle: true)
    )
    #expect(walkOut.contains("0.60 m"))

    let turnTool = TurnDuckAngleTool(duckSession: session) { item in
      activities.withValue { $0.append(item) }
    }
    let turnOut = try await turnTool.call(arguments: .init(direction: "right", degrees: 45))
    #expect(turnOut.contains("right 45°"))

    let clearanceTool = ClearanceMoveDuckTool(duckSession: session) { item in
      activities.withValue { $0.append(item) }
    }
    let clearanceOut = try await clearanceTool.call(
      arguments: .init(mode: "approach", targetClearanceCm: 30)
    )
    #expect(clearanceOut.contains("30 cm"))

    expectNoDifference(goals.value.count, 3)
    #expect(activities.value.contains { $0.status == .succeeded && $0.title == "Walk Forward" })
  }

  @Test func toolSerializerPreventsConcurrentRobotMoveCollisions() async throws {
    let serializer = WingmanToolSerializer()
    let activeCount = LockIsolated(0)
    let maxConcurrency = LockIsolated(0)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<3 {
        group.addTask {
          try await serializer.perform {
            let current = activeCount.withValue { count -> Int in
              count += 1
              return count
            }
            maxConcurrency.withValue { $0 = max($0, current) }
            try await Task.sleep(for: .milliseconds(15))
            activeCount.withValue { $0 -= 1 }
          }
        }
      }
      try await group.waitForAll()
    }

    expectNoDifference(maxConcurrency.value, 1)
  }

  @Test func scanSurroundingsPhysicallyRotatesBodyAndCapturesEachHeading() async throws {
    let turns = LockIsolated<[Double]>([])
    let photoCount = LockIsolated(0)
    let activities = LockIsolated<[WingmanActivityItem]>([])

    var session = DuckSessionClient.previewValue
    session.performMotion = { goal in
      if case let .turnAngle(degrees, _, _) = goal {
        turns.withValue { $0.append(degrees) }
      }
      return DuckMotionResult(
        goal: goal,
        stopReason: .reachedTarget,
        elapsedSeconds: 1.0,
        angleTurnedDegrees: 90
      )
    }
    session.capturePhoto = {
      photoCount.withValue { $0 += 1 }
      return DuckCapturedFrame(
        jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
        width: 360,
        height: 640,
        capturedAt: Date(timeIntervalSince1970: 1_795_150_000)
      )
    }

    let scanTool = ScanSurroundingsDuckTool(duckSession: session, supportsVision: true) { item in
      activities.withValue { $0.append(item) }
    }
    _ = try await scanTool.call(arguments: .init(views: 4, direction: "left"))

    // 4 views = initial heading + 3 × 90° body turns + 4 captured camera frames
    expectNoDifference(turns.value, [90, 90, 90])
    expectNoDifference(photoCount.value, 4)
    #expect(activities.value.last?.status == .succeeded)
    #expect(activities.value.last?.title == "360° Body Scan")
  }

  @Test @MainActor func wingmanModelStreamsMissionPlanAndExecutes() async throws {
    let executedGoals = LockIsolated<[DuckMotionGoal]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.performMotion = { goal in
        executedGoals.withValue { $0.append(goal) }
        return DuckMotionResult(goal: goal, stopReason: .reachedTarget, elapsedSeconds: 0.5, distanceTraveledMeters: 0.5, angleTurnedDegrees: 90)
      }
      $0.duckSession = session
      $0.wingman = .previewValue
      $0.continuousClock = ImmediateClock()
    } operation: {
      let model = WingmanModel()
      model.snapshot = .previewConnected
      model.refreshBackendStatus()
      model.mode = .missionPlan
      model.promptText = "Walk forward half a meter and turn left"
      model.runButtonTapped()

      // Wait for async streaming task to settle:
      for _ in 0..<40 where model.isRunning {
        try await Task.sleep(for: .milliseconds(10))
      }

      expectNoDifference(model.finalizedPlan?.title, "Scout & Greet")
      expectNoDifference(model.streamingSteps.count, 3)
      expectNoDifference(model.turns.count, 1)
      expectNoDifference(model.turns[0].planTitle, "Scout & Greet")

      model.runPlanButtonTapped()
      for _ in 0..<40 where model.isExecutingPlan {
        try await Task.sleep(for: .milliseconds(10))
      }

      expectNoDifference(model.isExecutingPlan, false)
      expectNoDifference(model.activeStatusSummary, nil)
      #expect(executedGoals.value.count == 2)
      #expect(model.turns[0].replyText?.contains("Scout & Greet") == true)
    }
  }
}
