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

  @Test @MainActor func expressiveControlsSendClampedMouthHeadPoseAndReset() async {
    let recordedMouths = LockIsolated<[RobotMouthParams]>([])
    let recordedHeads = LockIsolated<[RobotHeadParams]>([])
    let recordedPoses = LockIsolated<[RobotPoseParams]>([])
    let thereminToggles = LockIsolated<[Bool]>([])

    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendMouth = { mouth in recordedMouths.withValue { $0.append(mouth) } }
      session.sendHead = { head in recordedHeads.withValue { $0.append(head) } }
      session.sendPose = { pose in recordedPoses.withValue { $0.append(pose) } }
      session.setTheremin = { on in thereminToggles.withValue { $0.append(on) } }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected

      model.expressiveDrawerToggleTapped()
      expectNoDifference(model.showExpressiveDrawer, true)
      expectNoDifference(model.showSoundDrawer, false)

      await model.beakOpeningChanged(0.6)
      await model.chompHoldChanged(isPressed: true)
      await model.chompHoldChanged(isPressed: false)
      await model.headTiltChanged(-1.0)
      await model.crouchDepthChanged(1.0)
      expectNoDifference(model.hasActiveExpression, true)

      await model.resetExpressionTapped()
      expectNoDifference(model.hasActiveExpression, false)

      await model.thereminToggleTapped()
      expectNoDifference(model.thereminEnabled, true)

      expectNoDifference(
        recordedMouths.value,
        [
          RobotMouthParams(open: 0.6),
          .wideOpen,
          .closed,
          .closed,
        ]
      )
      expectNoDifference(
        recordedHeads.value,
        [
          RobotHeadParams(headRoll: -DuckConstants.maxHeadRollRadians),
          .neutral,
        ]
      )
      expectNoDifference(
        recordedPoses.value,
        [
          RobotPoseParams(z: DuckConstants.minPoseZ, roll: 0, pitch: 0, active: true),
          .nominal,
        ]
      )
      expectNoDifference(thereminToggles.value, [true])
    }
  }

  @Test @MainActor func quickMotionDispatchesClosedLoopGoalAndInlineWingmanOpensPanel() async throws {
    let goals = LockIsolated<[DuckMotionGoal]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.performMotion = { goal in
        goals.withValue { $0.append(goal) }
        return DuckMotionResult(goal: goal, stopReason: .reachedTarget, elapsedSeconds: 0.4, angleTurnedDegrees: 90)
      }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected

      model.quickMotionButtonTapped(label: "↺ 90°", goal: .turnAngle(degrees: 90, speedPercent: 85))
      for _ in 0..<30 where model.activeQuickMotionLabel != nil {
        try await Task.sleep(for: .milliseconds(10))
      }
      expectNoDifference(goals.value, [.turnAngle(degrees: 90, speedPercent: 85)])

      model.showWingmanInspector = false
      model.inlineWingmanPrompt = "Scout ahead"
      model.inlineWingmanSubmitted(isWideLayout: true)
      expectNoDifference(model.showWingmanInspector, true)
      expectNoDifference(model.inlineWingmanPrompt, "")
    }
  }

  @Test @MainActor func xboxAndPlayStationControllerButtonsTriggersAndGazeWorkEndToEnd() async {
    expectNoDifference(
      GamepadFamily.detect(vendorName: "DualSense Wireless Controller", productCategory: "DualSense"),
      .playstation
    )
    expectNoDifference(
      GamepadFamily.detect(vendorName: "Xbox Wireless Controller", productCategory: "Xbox One"),
      .xbox
    )

    let events = LockIsolated<[String]>([])
    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.toggleEnable = { events.withValue { $0.append("toggleEnable") } }
      session.stop = { events.withValue { $0.append("stop") } }
      session.performSkill = { skill in events.withValue { $0.append("skill:\(skill)") } }
      session.playSound = { tag, hold in events.withValue { $0.append("sound:\(tag.rawValue):\(hold.map(String.init) ?? "nil")") } }
      session.sendMouth = { mouth in events.withValue { $0.append("mouth:\(Int((mouth.open * 100).rounded()))") } }
      session.sendPose = { pose in events.withValue { $0.append(pose.active ? "crouch:\(Int((pose.z * -1000).rounded()))" : "crouch:0") } }
      session.sendLook = { _ in
        events.withValue { $0.append("look") }
        return RobotLookResult(accepted: true, clamped: false)
      }
      session.setFlashlight = { on in events.withValue { $0.append("flashlight:\(on)") } }
      $0.duckSession = session
      $0.haptics = .previewValue
    } operation: {
      let model = CockpitModel()
      model.snapshot = .previewConnected

      // Press A (Stand), X (Kick Left), RB (Roulade), D-pad Right (Chirp), RT 80% (Beak), LT 50% (Crouch), Menu (Flashlight)
      await model.handleGamepadState(
        GamepadInputState(
          controllerName: "DualSense Wireless Controller",
          family: .playstation,
          leftTrigger: 0.5,
          rightTrigger: 0.8,
          buttonAPressed: true,
          buttonXPressed: true,
          rightShoulderPressed: true,
          dpadRight: true,
          buttonMenuPressed: true
        )
      )

      // Hold LB + Right Stick -> aims gaze and locks body turning (vyaw == 0)
      await model.handleGamepadState(
        GamepadInputState(
          controllerName: "DualSense Wireless Controller",
          family: .playstation,
          rightX: 0.7,
          rightY: 0.4,
          leftShoulderPressed: true
        )
      )
      expectNoDifference(model.currentTwist.vyaw, 0.0)
      expectNoDifference(model.isLooking, true)

      // Press B -> Emergency stop
      await model.handleGamepadState(
        GamepadInputState(
          controllerName: "DualSense Wireless Controller",
          family: .playstation,
          buttonBPressed: true
        )
      )
      expectNoDifference(model.isLooking, false)
    }

    #expect(events.value.contains("toggleEnable"))
    #expect(events.value.contains("skill:kick_left"))
    #expect(events.value.contains("skill:roulade"))
    #expect(events.value.contains("sound:chirp:nil"))
    #expect(events.value.contains("mouth:80"))
    #expect(events.value.contains("flashlight:true"))
    #expect(events.value.contains("look"))
    #expect(events.value.contains("stop"))
  }
}
