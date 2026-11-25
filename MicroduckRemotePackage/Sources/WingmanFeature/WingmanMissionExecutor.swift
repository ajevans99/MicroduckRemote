import DuckDependencies
import DuckProtocol
import Foundation

/// Executes a finalized `WingmanMissionPlan` step-by-step against `DuckSessionClient`,
/// reporting per-step activity updates and guaranteeing neutral cleanup on exit or cancellation.
public enum WingmanMissionExecutor {
  public static func execute(
    plan: WingmanMissionPlan,
    duckSession: DuckSessionClient,
    clock: any Clock<Duration>,
    onStepStarted: @Sendable (Int, WingmanMissionStep) async -> Void,
    onActivity: @escaping WingmanActivityObserver
  ) async throws {
    var didTouchBeak = false
    var didTouchHead = false
    var didTouchPose = false

    func cleanup() async {
      await duckSession.sendMove(.zero)
      if didTouchBeak {
        await duckSession.sendMouth(.closed)
      }
      if didTouchHead {
        await duckSession.sendHead(.neutral)
      }
      if didTouchPose {
        await duckSession.sendPose(.nominal)
      }
    }

    do {
      for (index, step) in plan.steps.enumerated() {
        try Task.checkCancellation()
        await onStepStarted(index, step)

        let itemID = UUID()
        onActivity(
          WingmanActivityItem(
            id: itemID,
            kind: .missionStep,
            title: "\(index + 1). \(step.action.displayTitle)",
            detail: step.note,
            status: .running
          )
        )

        let detail = try await runSingleStep(
          step,
          duckSession: duckSession,
          clock: clock,
          didTouchBeak: &didTouchBeak,
          didTouchHead: &didTouchHead,
          didTouchPose: &didTouchPose
        )

        onActivity(
          WingmanActivityItem(
            id: itemID,
            kind: .missionStep,
            title: "\(index + 1). \(step.action.displayTitle)",
            detail: detail,
            status: .succeeded
          )
        )
      }
      await cleanup()
    } catch {
      await cleanup()
      throw error
    }
  }

  private static func runSingleStep(
    _ step: WingmanMissionStep,
    duckSession: DuckSessionClient,
    clock: any Clock<Duration>,
    didTouchBeak: inout Bool,
    didTouchHead: inout Bool,
    didTouchPose: inout Bool
  ) async throws -> String {
    switch step.action {
    case .standUp:
      try await duckSession.setEnabled(true)
      return "Standing and balancing."

    case .sitDown:
      try await duckSession.setEnabled(false)
      return "Sat down."

    case .walkForward:
      let meters = min(max(step.amount ?? 0.5, 0.1), 2.5)
      let res = try await duckSession.performMotion(
        .moveDistance(direction: .forward, meters: meters)
      )
      return describeMotion(res, verb: "Walked forward")

    case .walkBackward:
      let meters = min(max(step.amount ?? 0.4, 0.1), 2.5)
      let res = try await duckSession.performMotion(
        .moveDistance(direction: .backward, meters: meters, stopOnObstacle: false)
      )
      return describeMotion(res, verb: "Walked backward")

    case .strafeLeft:
      let meters = min(max(step.amount ?? 0.35, 0.1), 2.0)
      let res = try await duckSession.performMotion(
        .moveDistance(direction: .strafeLeft, meters: meters, stopOnObstacle: false)
      )
      return describeMotion(res, verb: "Sidestepped left")

    case .strafeRight:
      let meters = min(max(step.amount ?? 0.35, 0.1), 2.0)
      let res = try await duckSession.performMotion(
        .moveDistance(direction: .strafeRight, meters: meters, stopOnObstacle: false)
      )
      return describeMotion(res, verb: "Sidestepped right")

    case .turnLeft:
      let deg = min(max(abs(step.amount ?? 90), 15), 360)
      let res = try await duckSession.performMotion(.turnAngle(degrees: deg))
      return "Turned left \(Int(abs(res.angleTurnedDegrees).rounded()))°."

    case .turnRight:
      let deg = min(max(abs(step.amount ?? 90), 15), 360)
      let res = try await duckSession.performMotion(.turnAngle(degrees: -deg))
      return "Turned right \(Int(abs(res.angleTurnedDegrees).rounded()))°."

    case .approachObstacle:
      let cm = Int(min(max(step.amount ?? 30, 15), 150).rounded())
      let res = try await duckSession.performMotion(.approachObstacle(targetClearanceMm: cm * 10))
      let finalCm = res.finalFrontClearanceMm.map { "\($0 / 10) cm" } ?? "\(cm) cm"
      return "Approached to \(finalCm) ahead."

    case .backUpUntilClear:
      let cm = Int(min(max(step.amount ?? 60, 25), 150).rounded())
      let res = try await duckSession.performMotion(.backUpUntilClear(targetClearanceMm: cm * 10))
      let finalCm = res.finalFrontClearanceMm.map { "\($0 / 10) cm" } ?? "\(cm) cm"
      return "Backed up to \(finalCm) clearance."

    case .look:
      let hx = min(max(step.amount ?? 0, -100), 100)
      let vy = min(max(step.secondaryAmount ?? 0, -100), 100)
      didTouchHead = true
      _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: hx / 100.0, normalizedY: vy / 100.0))
      try await clock.sleep(for: .milliseconds(450))
      return "Aimed gaze (\(Int(hx.rounded()))%, \(Int(vy.rounded()))%)."

    case .beak:
      let pct = min(max(step.amount ?? 100, 0), 100)
      didTouchBeak = true
      await duckSession.sendMouth(RobotMouthParams.fromPercent(pct))
      try await clock.sleep(for: .milliseconds(550))
      return "Set beak to \(Int(pct.rounded()))%."

    case .chomp:
      let duration = min(max(step.secondaryAmount ?? 1.4, 0.5), 3.0)
      let ticks = max(4, Int((duration * 10.0).rounded()))
      didTouchBeak = true
      for tick in 0..<ticks {
        try Task.checkCancellation()
        let open = (tick / 2).isMultiple(of: 2) ? 1.0 : 0.0
        await duckSession.sendMouth(RobotMouthParams(open: open))
        try await clock.sleep(for: .milliseconds(100))
      }
      await duckSession.sendMouth(.closed)
      return String(format: "Chomped for %.1fs.", duration)

    case .headTilt:
      let pct = min(max(step.amount ?? 75, -100), 100)
      didTouchHead = true
      await duckSession.sendHead(RobotHeadParams.tilt(percent: pct))
      try await clock.sleep(for: .milliseconds(650))
      return "Tilted head \(Int(pct.rounded()))%."

    case .crouch:
      let pct = min(max(step.amount ?? 75, 0), 100)
      didTouchPose = true
      await duckSession.sendPose(RobotPoseParams.crouch(percent: pct))
      try await clock.sleep(for: .milliseconds(700))
      return "Crouched \(Int(pct.rounded()))%."

    case .sound:
      let tag = SoundTag(rawValue: (step.label ?? "chirp").lowercased()) ?? .chirp
      await duckSession.playSound(tag, nil)
      try await clock.sleep(for: .milliseconds(300))
      return "Played '\(tag.displayName)' sound."

    case .trick:
      let skill = step.label ?? "roulade"
      try await duckSession.performSkill(skill)
      return "Performed trick '\(skill)'."
    }
  }

  private static func describeMotion(_ result: DuckMotionResult, verb: String) -> String {
    let dist = String(format: "%.2f m", result.distanceTraveledMeters)
    switch result.stopReason {
    case .reachedTarget:
      return "\(verb) \(dist)."
    case let .stoppedForObstacle(distanceMm):
      return "Stopped after \(dist) (obstacle \(distanceMm / 10) cm ahead)."
    case .timedOut:
      return "\(verb) \(dist) (timeout)."
    case let .interruptedBySafety(reason):
      return "Stopped early after \(dist): \(reason)."
    }
  }
}
