import DuckProtocol
import Foundation

/// Runs sensor-terminated 10 Hz (`100 ms`) motion goals using contact odometry (`odom`),
/// IMU yaw heading, and 8×8 ToF depth feedback, always enforcing upright safety and
/// guaranteeing a terminal `RobotMoveParams.zero` command on completion, error, or cancellation.
public enum DuckClosedLoopMotionExecutor {
  public static func execute(
    goal: DuckMotionGoal,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    subscribeTof: @Sendable () async -> Void,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void
  ) async throws -> DuckMotionResult {
    let initial = await currentSnapshot()
    guard initial.controlOpen else {
      throw RpcErrorPayload(code: -32000, message: "Not connected to duck control channel.")
    }
    if initial.latestState?.safety?.fallen == true {
      throw DuckSessionError.duckFallen
    }
    if initial.latestState?.safety?.pickedUp == true {
      throw DuckSessionError.duckPickedUp
    }
    if initial.policies?.enabled == false || initial.policies?.sitting == true {
      throw DuckSessionError.duckNotStanding
    }

    switch goal {
    case let .moveDistance(direction, meters, speedPercent, stopOnObstacle, minObstacleDistanceMm, timeoutSeconds):
      return try await executeMoveDistance(
        goal: goal,
        direction: direction,
        meters: meters,
        speedPercent: speedPercent,
        stopOnObstacle: stopOnObstacle,
        minObstacleDistanceMm: minObstacleDistanceMm,
        timeoutSeconds: timeoutSeconds,
        initial: initial,
        clock: clock,
        currentSnapshot: currentSnapshot,
        subscribeTof: subscribeTof,
        sendMove: sendMove
      )

    case let .turnAngle(degrees, speedPercent, timeoutSeconds):
      return try await executeTurnAngle(
        goal: goal,
        degrees: degrees,
        speedPercent: speedPercent,
        timeoutSeconds: timeoutSeconds,
        initial: initial,
        clock: clock,
        currentSnapshot: currentSnapshot,
        sendMove: sendMove
      )

    case let .approachObstacle(targetClearanceMm, speedPercent, timeoutSeconds):
      return try await executeApproachObstacle(
        goal: goal,
        targetClearanceMm: targetClearanceMm,
        speedPercent: speedPercent,
        timeoutSeconds: timeoutSeconds,
        initial: initial,
        clock: clock,
        currentSnapshot: currentSnapshot,
        subscribeTof: subscribeTof,
        sendMove: sendMove
      )

    case let .backUpUntilClear(targetClearanceMm, speedPercent, timeoutSeconds):
      return try await executeBackUpUntilClear(
        goal: goal,
        targetClearanceMm: targetClearanceMm,
        speedPercent: speedPercent,
        timeoutSeconds: timeoutSeconds,
        initial: initial,
        clock: clock,
        currentSnapshot: currentSnapshot,
        subscribeTof: subscribeTof,
        sendMove: sendMove
      )
    }
  }

  private static func checkSafety(_ snapshot: DuckSessionSnapshot) throws -> String? {
    if !snapshot.controlOpen {
      throw RpcErrorPayload(code: -32000, message: "Duck disconnected during motion.")
    }
    if snapshot.latestState?.safety?.fallen == true {
      return "Duck fell over"
    }
    if snapshot.latestState?.safety?.pickedUp == true {
      return "Duck was picked up"
    }
    if snapshot.policies?.enabled == false || snapshot.policies?.sitting == true {
      return "Duck is no longer standing"
    }
    return nil
  }

  private static func waitForTofIfNeeded(
    initial: DuckSessionSnapshot,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    subscribeTof: @Sendable () async -> Void
  ) async throws -> DuckSessionSnapshot {
    if initial.tofFrame != nil {
      return initial
    }
    await subscribeTof()
    var latest = initial
    for _ in 0..<4 {
      try Task.checkCancellation()
      try await clock.sleep(for: .milliseconds(100))
      latest = await currentSnapshot()
      if latest.tofFrame != nil {
        break
      }
    }
    return latest
  }

  private static func frontDistanceMm(in snapshot: DuckSessionSnapshot) -> Int? {
    snapshot.tofFrame?.frontObstacleDistanceMm ?? snapshot.tofFrame?.analyzeZones()?.frontMm
  }

  private static func executeMoveDistance(
    goal: DuckMotionGoal,
    direction: DuckLinearDirection,
    meters: Double,
    speedPercent: Double,
    stopOnObstacle: Bool,
    minObstacleDistanceMm: Int,
    timeoutSeconds: Double,
    initial: DuckSessionSnapshot,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    subscribeTof: @Sendable () async -> Void,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void
  ) async throws -> DuckMotionResult {
    let targetMeters = min(max(abs(meters), 0.05), 3.0)
    let baseScale = min(max(speedPercent / 100.0, 0.2), 1.0)
    let clampedTimeout = min(max(timeoutSeconds, 1.0), 20.0)
    let hz = DuckConstants.intentHz
    let dt = 1.0 / Double(hz)
    let tickInterval = Duration.milliseconds(1000 / hz)
    let maxTicks = max(1, Int((clampedTimeout * Double(hz)).rounded()))

    if stopOnObstacle, direction == .forward, initial.tofFrame == nil {
      await subscribeTof()
    }

    var startOdom = initial.latestState?.odom
    var usedClosedLoop = startOdom != nil
    var traveledMeters = 0.0
    var pulsesSent = 0
    var completedTicks = 0
    let fallbackSpeedMps: Double = switch direction {
    case .forward, .strafeLeft, .strafeRight:
      max(0.08, DuckConstants.maxLinearVelocity * baseScale * 0.85)
    case .backward:
      0.16 + 0.10 * baseScale
    }

    do {
      for _ in 0..<maxTicks {
        try Task.checkCancellation()
        let snapshot = await currentSnapshot()
        let elapsed = Double(completedTicks) * dt

        if let safetyReason = try checkSafety(snapshot) {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .interruptedBySafety(safetyReason),
            elapsedSeconds: elapsed,
            distanceTraveledMeters: traveledMeters,
            finalFrontClearanceMm: frontDistanceMm(in: snapshot),
            usedClosedLoopFeedback: usedClosedLoop,
            pulsesSent: pulsesSent
          )
        }

        if let currentOdom = snapshot.latestState?.odom {
          if let origin = startOdom {
            traveledMeters = currentOdom.planarDistance(from: origin)
            usedClosedLoop = true
          } else {
            startOdom = currentOdom
            usedClosedLoop = true
          }
        } else {
          traveledMeters = elapsed * fallbackSpeedMps
        }

        let remainingMeters = targetMeters - traveledMeters
        if remainingMeters <= 0.03 {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .reachedTarget,
            elapsedSeconds: elapsed,
            distanceTraveledMeters: traveledMeters,
            finalFrontClearanceMm: frontDistanceMm(in: snapshot),
            usedClosedLoopFeedback: usedClosedLoop,
            pulsesSent: pulsesSent
          )
        }

        if
          stopOnObstacle,
          direction == .forward,
          let distMm = snapshot.tofFrame?.frontObstacleDistanceMm,
          distMm < minObstacleDistanceMm
        {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .stoppedForObstacle(distanceMm: distMm),
            elapsedSeconds: elapsed,
            distanceTraveledMeters: traveledMeters,
            finalFrontClearanceMm: distMm,
            usedClosedLoopFeedback: usedClosedLoop,
            pulsesSent: pulsesSent
          )
        }

        // Smooth deceleration within the last 18 cm while staying above velstand's walking breakaway floor.
        let decelFactor = remainingMeters < 0.18
          ? max(0.55, remainingMeters / 0.18)
          : 1.0
        let effectiveScale = baseScale * decelFactor
        let requestedLinear = DuckConstants.maxLinearVelocity * baseScale
        let linear = min(requestedLinear, max(0.14, DuckConstants.maxLinearVelocity * effectiveScale))

        let twist: RobotMoveParams = switch direction {
        case .forward:
          RobotMoveParams(vx: linear, vy: 0, vyaw: 0)
        case .backward:
          RobotMoveParams(
            vx: DuckConstants.backwardLinearVelocity(magnitude: effectiveScale),
            vy: 0,
            vyaw: 0
          )
        case .strafeLeft:
          RobotMoveParams(vx: 0, vy: linear, vyaw: 0)
        case .strafeRight:
          RobotMoveParams(vx: 0, vy: -linear, vyaw: 0)
        }

        await sendMove(twist)
        pulsesSent += 1
        try await clock.sleep(for: tickInterval)
        completedTicks += 1
      }

      let finalSnap = await currentSnapshot()
      if let origin = startOdom, let currentOdom = finalSnap.latestState?.odom {
        traveledMeters = currentOdom.planarDistance(from: origin)
      }
      await sendMove(.zero)
      return DuckMotionResult(
        goal: goal,
        stopReason: traveledMeters >= targetMeters - 0.03 ? .reachedTarget : .timedOut,
        elapsedSeconds: Double(completedTicks) * dt,
        distanceTraveledMeters: traveledMeters,
        finalFrontClearanceMm: frontDistanceMm(in: finalSnap),
        usedClosedLoopFeedback: usedClosedLoop,
        pulsesSent: pulsesSent
      )
    } catch {
      await sendMove(.zero)
      throw error
    }
  }

  private static func executeTurnAngle(
    goal: DuckMotionGoal,
    degrees: Double,
    speedPercent: Double,
    timeoutSeconds: Double,
    initial: DuckSessionSnapshot,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void
  ) async throws -> DuckMotionResult {
    let clampedDegrees = min(max(degrees, -360.0), 360.0)
    guard abs(clampedDegrees) >= 2.0 else {
      return DuckMotionResult(
        goal: goal,
        stopReason: .reachedTarget,
        elapsedSeconds: 0,
        angleTurnedDegrees: 0,
        finalFrontClearanceMm: frontDistanceMm(in: initial),
        usedClosedLoopFeedback: initial.latestState?.headingRadians != nil,
        pulsesSent: 0
      )
    }

    let turnSign: Double = clampedDegrees >= 0 ? 1.0 : -1.0
    let targetAbsRad = abs(clampedDegrees) * .pi / 180.0
    let baseScale = min(max(speedPercent / 100.0, 0.25), 1.0)
    let clampedTimeout = min(max(timeoutSeconds, 1.0), 15.0)
    let hz = DuckConstants.intentHz
    let dt = 1.0 / Double(hz)
    let tickInterval = Duration.milliseconds(1000 / hz)
    let maxTicks = max(1, Int((clampedTimeout * Double(hz)).rounded()))

    var lastHeading = initial.latestState?.headingRadians
    var usedClosedLoop = lastHeading != nil
    var accumulatedSignedRad = 0.0
    var pulsesSent = 0
    var completedTicks = 0
    // Calibrated fallback: ~90 deg/s at 100% turn speed (~2.1 s for 180 deg).
    let fallbackRateRadPerSec = (Double.pi / 2.1) * baseScale

    do {
      for _ in 0..<maxTicks {
        try Task.checkCancellation()
        let snapshot = await currentSnapshot()
        let elapsed = Double(completedTicks) * dt

        if let safetyReason = try checkSafety(snapshot) {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .interruptedBySafety(safetyReason),
            elapsedSeconds: elapsed,
            angleTurnedDegrees: accumulatedSignedRad * 180.0 / .pi,
            finalFrontClearanceMm: frontDistanceMm(in: snapshot),
            usedClosedLoopFeedback: usedClosedLoop,
            pulsesSent: pulsesSent
          )
        }

        if let heading = snapshot.latestState?.headingRadians {
          if let previous = lastHeading {
            accumulatedSignedRad += DuckGeometry.angularDeltaRadians(from: previous, to: heading)
          }
          lastHeading = heading
          usedClosedLoop = true
        } else {
          accumulatedSignedRad = turnSign * elapsed * fallbackRateRadPerSec
        }

        let progressRad = accumulatedSignedRad * turnSign
        let remainingRad = targetAbsRad - progressRad
        let toleranceRad = 7.0 * .pi / 180.0
        if remainingRad <= toleranceRad {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .reachedTarget,
            elapsedSeconds: elapsed,
            angleTurnedDegrees: accumulatedSignedRad * 180.0 / .pi,
            finalFrontClearanceMm: frontDistanceMm(in: snapshot),
            usedClosedLoopFeedback: usedClosedLoop,
            pulsesSent: pulsesSent
          )
        }

        // Taper angular speed in the last 30 degrees while staying above velstand's turn breakaway floor.
        let slowZoneRad = 30.0 * .pi / 180.0
        let decelFactor = remainingRad < slowZoneRad
          ? max(0.60, remainingRad / slowZoneRad)
          : 1.0
        let maxAbsVyaw = DuckConstants.maxAngularVelocity * baseScale
        let absVyaw = min(maxAbsVyaw, max(0.85, maxAbsVyaw * decelFactor))
        let vyaw = turnSign * absVyaw

        await sendMove(RobotMoveParams(vx: 0, vy: 0, vyaw: vyaw))
        pulsesSent += 1
        try await clock.sleep(for: tickInterval)
        completedTicks += 1
      }

      let finalSnap = await currentSnapshot()
      if let previous = lastHeading, let heading = finalSnap.latestState?.headingRadians {
        accumulatedSignedRad += DuckGeometry.angularDeltaRadians(from: previous, to: heading)
      }
      await sendMove(.zero)
      let progressRad = accumulatedSignedRad * turnSign
      let reached = (targetAbsRad - progressRad) <= (7.0 * .pi / 180.0)
      return DuckMotionResult(
        goal: goal,
        stopReason: reached ? .reachedTarget : .timedOut,
        elapsedSeconds: Double(completedTicks) * dt,
        angleTurnedDegrees: accumulatedSignedRad * 180.0 / .pi,
        finalFrontClearanceMm: frontDistanceMm(in: finalSnap),
        usedClosedLoopFeedback: usedClosedLoop,
        pulsesSent: pulsesSent
      )
    } catch {
      await sendMove(.zero)
      throw error
    }
  }

  private static func executeApproachObstacle(
    goal: DuckMotionGoal,
    targetClearanceMm: Int,
    speedPercent: Double,
    timeoutSeconds: Double,
    initial: DuckSessionSnapshot,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    subscribeTof: @Sendable () async -> Void,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void
  ) async throws -> DuckMotionResult {
    let targetMm = min(max(targetClearanceMm, 150), 1500)
    let baseScale = min(max(speedPercent / 100.0, 0.2), 0.85)
    let clampedTimeout = min(max(timeoutSeconds, 1.0), 15.0)
    let hz = DuckConstants.intentHz
    let dt = 1.0 / Double(hz)
    let tickInterval = Duration.milliseconds(1000 / hz)
    let maxTicks = max(1, Int((clampedTimeout * Double(hz)).rounded()))

    let primed = try await waitForTofIfNeeded(
      initial: initial,
      clock: clock,
      currentSnapshot: currentSnapshot,
      subscribeTof: subscribeTof
    )
    let startOdom = primed.latestState?.odom
    var traveledMeters = 0.0
    var pulsesSent = 0
    var completedTicks = 0
    var lastFrontMm = frontDistanceMm(in: primed)

    do {
      for _ in 0..<maxTicks {
        try Task.checkCancellation()
        let snapshot = await currentSnapshot()
        let elapsed = Double(completedTicks) * dt

        if let safetyReason = try checkSafety(snapshot) {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .interruptedBySafety(safetyReason),
            elapsedSeconds: elapsed,
            distanceTraveledMeters: traveledMeters,
            finalFrontClearanceMm: lastFrontMm,
            usedClosedLoopFeedback: true,
            pulsesSent: pulsesSent
          )
        }

        if let origin = startOdom, let currentOdom = snapshot.latestState?.odom {
          traveledMeters = currentOdom.planarDistance(from: origin)
        }

        if let frontMm = frontDistanceMm(in: snapshot) {
          lastFrontMm = frontMm
          if frontMm <= targetMm {
            await sendMove(.zero)
            return DuckMotionResult(
              goal: goal,
              stopReason: .reachedTarget,
              elapsedSeconds: elapsed,
              distanceTraveledMeters: traveledMeters,
              finalFrontClearanceMm: frontMm,
              usedClosedLoopFeedback: true,
              pulsesSent: pulsesSent
            )
          }
        }

        let marginMm = (lastFrontMm ?? (targetMm + 500)) - targetMm
        let decelFactor = marginMm < 220
          ? max(0.55, Double(marginMm) / 220.0)
          : 1.0
        let maxVx = DuckConstants.maxLinearVelocity * baseScale
        let vx = min(maxVx, max(0.14, maxVx * decelFactor))

        await sendMove(RobotMoveParams(vx: vx, vy: 0, vyaw: 0))
        pulsesSent += 1
        try await clock.sleep(for: tickInterval)
        completedTicks += 1
      }

      await sendMove(.zero)
      return DuckMotionResult(
        goal: goal,
        stopReason: .timedOut,
        elapsedSeconds: Double(completedTicks) * dt,
        distanceTraveledMeters: traveledMeters,
        finalFrontClearanceMm: lastFrontMm,
        usedClosedLoopFeedback: lastFrontMm != nil,
        pulsesSent: pulsesSent
      )
    } catch {
      await sendMove(.zero)
      throw error
    }
  }

  private static func executeBackUpUntilClear(
    goal: DuckMotionGoal,
    targetClearanceMm: Int,
    speedPercent: Double,
    timeoutSeconds: Double,
    initial: DuckSessionSnapshot,
    clock: any Clock<Duration>,
    currentSnapshot: @Sendable () async -> DuckSessionSnapshot,
    subscribeTof: @Sendable () async -> Void,
    sendMove: @escaping @Sendable (RobotMoveParams) async -> Void
  ) async throws -> DuckMotionResult {
    let targetMm = min(max(targetClearanceMm, 250), 1800)
    let baseScale = min(max(speedPercent / 100.0, 0.2), 1.0)
    let clampedTimeout = min(max(timeoutSeconds, 1.0), 12.0)
    let hz = DuckConstants.intentHz
    let dt = 1.0 / Double(hz)
    let tickInterval = Duration.milliseconds(1000 / hz)
    let maxTicks = max(1, Int((clampedTimeout * Double(hz)).rounded()))

    let primed = try await waitForTofIfNeeded(
      initial: initial,
      clock: clock,
      currentSnapshot: currentSnapshot,
      subscribeTof: subscribeTof
    )
    let startOdom = primed.latestState?.odom
    var traveledMeters = 0.0
    var pulsesSent = 0
    var completedTicks = 0
    var lastFrontMm = frontDistanceMm(in: primed)

    do {
      for _ in 0..<maxTicks {
        try Task.checkCancellation()
        let snapshot = await currentSnapshot()
        let elapsed = Double(completedTicks) * dt

        if let safetyReason = try checkSafety(snapshot) {
          await sendMove(.zero)
          return DuckMotionResult(
            goal: goal,
            stopReason: .interruptedBySafety(safetyReason),
            elapsedSeconds: elapsed,
            distanceTraveledMeters: traveledMeters,
            finalFrontClearanceMm: lastFrontMm,
            usedClosedLoopFeedback: true,
            pulsesSent: pulsesSent
          )
        }

        if let origin = startOdom, let currentOdom = snapshot.latestState?.odom {
          traveledMeters = currentOdom.planarDistance(from: origin)
        }

        if let frontMm = frontDistanceMm(in: snapshot) {
          lastFrontMm = frontMm
          if frontMm >= targetMm {
            await sendMove(.zero)
            return DuckMotionResult(
              goal: goal,
              stopReason: .reachedTarget,
              elapsedSeconds: elapsed,
              distanceTraveledMeters: traveledMeters,
              finalFrontClearanceMm: frontMm,
              usedClosedLoopFeedback: true,
              pulsesSent: pulsesSent
            )
          }
        }

        let vx = DuckConstants.backwardLinearVelocity(magnitude: baseScale)
        await sendMove(RobotMoveParams(vx: vx, vy: 0, vyaw: 0))
        pulsesSent += 1
        try await clock.sleep(for: tickInterval)
        completedTicks += 1
      }

      await sendMove(.zero)
      return DuckMotionResult(
        goal: goal,
        stopReason: .timedOut,
        elapsedSeconds: Double(completedTicks) * dt,
        distanceTraveledMeters: traveledMeters,
        finalFrontClearanceMm: lastFrontMm,
        usedClosedLoopFeedback: lastFrontMm != nil,
        pulsesSent: pulsesSent
      )
    } catch {
      await sendMove(.zero)
      throw error
    }
  }
}
