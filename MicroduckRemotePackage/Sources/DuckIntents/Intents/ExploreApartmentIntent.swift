import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct ExploreApartmentIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Explore Apartment with Microduck"
  public static let description = IntentDescription(
    "Runs a bounded, obstacle-aware closed-loop exploration routine where Microduck steers toward open space using its 8x8 ToF sensor, pauses to pan its head, reacts playfully to close floor objects, and always stops cleanly on obstacles, falls, or cancellation."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Duration (Seconds)",
    description: "Maximum time in seconds (3 to 30) to spend exploring before stopping automatically.",
    default: 12.0,
    controlStyle: .field,
    inclusiveRange: (3.0, 30.0)
  )
  public var durationSeconds: Double

  @Parameter(
    title: "Max Steps",
    description: "Maximum number of exploration legs (1 to 12) to perform.",
    default: 6,
    controlStyle: .field,
    inclusiveRange: (1, 12)
  )
  public var maxSteps: Int

  @Parameter(
    title: "Playful Reactions",
    description: "When enabled, Microduck pauses to pan its head, chirp or inquire, tint its face light, and playfully nudge or inspect close low objects.",
    default: true
  )
  public var playfulReactions: Bool

  public static var parameterSummary: some ParameterSummary {
    Summary("Explore with Microduck for \(\.$durationSeconds) seconds") {
      \.$maxSteps
      \.$playfulReactions
    }
  }

  public init() {}

  public init(
    durationSeconds: Double = 12.0,
    maxSteps: Int = 6,
    playfulReactions: Bool = true
  ) {
    self.durationSeconds = durationSeconds
    self.maxSteps = maxSteps
    self.playfulReactions = playfulReactions
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    @Dependencies.Dependency(\.continuousClock) var clock

    let clampedDuration = min(max(durationSeconds, 3.0), 30.0)
    let clampedSteps = min(max(maxSteps, 1), 12)

    let summary = try await DuckIntentRunner.runConnectedTool(
      intentName: "ExploreApartmentIntent",
      displayTitle: "Explore Apartment with Microduck",
      parameters: [
        .init(key: "duration", value: "\(clampedDuration.formatted(.number.precision(.fractionLength(0...1))))s"),
        .init(key: "maxSteps", value: "\(clampedSteps)"),
        .init(key: "playfulReactions", value: playfulReactions ? "true" : "false"),
      ],
      refreshIfOpen: true
    ) { connection, duckSession in
      let duckName = connection.duckName
      var snapshot = await duckSession.currentSnapshot()
      if snapshot.latestState?.safety?.fallen == true {
        throw DuckSessionError.duckFallen
      }
      if snapshot.latestState?.safety?.pickedUp == true {
        throw DuckSessionError.duckPickedUp
      }
      if snapshot.policies?.enabled == false || snapshot.policies?.sitting == true {
        throw DuckSessionError.duckNotStanding
      }

      await duckSession.subscribeTof()
      if snapshot.tofFrame == nil {
        for _ in 0..<4 {
          try Task.checkCancellation()
          try await clock.sleep(for: .milliseconds(100))
          snapshot = await duckSession.currentSnapshot()
          if snapshot.tofFrame != nil { break }
        }
      }

      let elapsedWallSeconds = Self.makeElapsedTimer(clock)
      var accountedSeconds = 0.0
      var stepsCompleted = 0
      var forwardLegs = 0
      var turnsMade = 0
      var obstaclesAvoided = 0
      var reactionsPerformed = 0
      var didTouchLight = false
      var didPanHead = false
      var earlyStopReason: String?

      func remainingBudgetSeconds() -> Double {
        let wallElapsed = elapsedWallSeconds()
        return clampedDuration - max(wallElapsed, accountedSeconds)
      }

      do {
        for legIndex in 0..<clampedSteps {
          try Task.checkCancellation()
          let remaining = remainingBudgetSeconds()
          if remaining < 0.4 {
            break
          }

          snapshot = await duckSession.currentSnapshot()
          if !snapshot.controlOpen {
            earlyStopReason = "disconnected from \(duckName)"
            break
          }
          if snapshot.latestState?.safety?.fallen == true {
            earlyStopReason = "\(duckName) fell over"
            break
          }
          if snapshot.latestState?.safety?.pickedUp == true {
            earlyStopReason = "\(duckName) was picked up"
            break
          }
          if snapshot.policies?.enabled == false || snapshot.policies?.sitting == true {
            earlyStopReason = "\(duckName) is no longer standing"
            break
          }

          let analysis = snapshot.tofFrame?.analyzeZones(
            warningThresholdMm: DuckConstants.defaultProximityWarningMm
          )

          if playfulReactions,
             let lowObjMm = analysis?.lowFrontObjectMm,
             lowObjMm < 340
          {
            didPanHead = true
            _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: 0.0, normalizedY: 0.45))
            didTouchLight = true
            try? await duckSession.setFlashlightColor(true, DuckLightColor.yellow.rawValue)
            await duckSession.playSound(.inquire, nil)
            try await clock.sleep(for: .milliseconds(250))
            accountedSeconds += 0.25

            let availableSkills = Set(snapshot.skillNames)
            if availableSkills.contains("kick_right") {
              try? await duckSession.performSkill("kick_right")
              try await clock.sleep(for: .milliseconds(900))
              accountedSeconds += 0.9
            } else if availableSkills.contains("ground_pick") {
              try? await duckSession.performSkill("ground_pick")
              try await clock.sleep(for: .milliseconds(900))
              accountedSeconds += 0.9
            }
            reactionsPerformed += 1

            let clearDirection: DuckMoveDirection =
              (analysis?.leftMm ?? 0) >= (analysis?.rightMm ?? 0) ? .turnLeft : .turnRight
            let pivotDuration = min(0.8, max(0.3, remainingBudgetSeconds()))
            if pivotDuration >= 0.3 {
              let pivotResult = try await duckSession.performMoveStep(
                clearDirection.makeRequest(
                  durationSeconds: pivotDuration,
                  speedPercent: 80,
                  stopOnObstacle: false
                )
              )
              accountedSeconds += pivotResult.elapsedSeconds
              turnsMade += 1
              if case let .interruptedBySafety(reason) = pivotResult.stopReason {
                earlyStopReason = reason
                stepsCompleted += 1
                break
              }
            }

            stepsCompleted += 1
            continue
          }

          if let analysis,
             analysis.recommendedDirection == .turnLeft || analysis.recommendedDirection == .turnRight
          {
            obstaclesAvoided += 1
            let turnDirection: DuckMoveDirection =
              analysis.recommendedDirection == .turnLeft ? .turnLeft : .turnRight

            if playfulReactions {
              didPanHead = true
              let lookX = turnDirection == .turnLeft ? -0.6 : 0.6
              _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: lookX, normalizedY: 0.0))
              didTouchLight = true
              try? await duckSession.setFlashlightColor(true, DuckLightColor.cyan.rawValue)
              await duckSession.playSound(.inquire, nil)
              reactionsPerformed += 1
            }

            let turnDuration = min(0.9, max(0.3, remaining))
            let turnResult = try await duckSession.performMoveStep(
              turnDirection.makeRequest(
                durationSeconds: turnDuration,
                speedPercent: 80,
                stopOnObstacle: false
              )
            )
            accountedSeconds += turnResult.elapsedSeconds
            turnsMade += 1
            stepsCompleted += 1

            if case let .interruptedBySafety(reason) = turnResult.stopReason {
              earlyStopReason = reason
              break
            }
            continue
          }

          let walkDuration = min(1.8, max(0.4, remaining))
          let walkRequest = DuckMoveDirection.forward.makeRequest(
            durationSeconds: walkDuration,
            speedPercent: 60,
            stopOnObstacle: true
          )
          let walkResult = try await duckSession.performMoveStep(walkRequest)
          accountedSeconds += walkResult.elapsedSeconds
          forwardLegs += 1

          switch walkResult.stopReason {
          case .completed:
            if playfulReactions && legIndex.isMultiple(of: 2) && remainingBudgetSeconds() >= 0.9 {
              didPanHead = true
              didTouchLight = true
              try? await duckSession.setFlashlightColor(true, DuckLightColor.green.rawValue)
              _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: -0.65, normalizedY: -0.1))
              await duckSession.playSound(legIndex == 0 ? .greet : .chirp, nil)
              try await clock.sleep(for: .milliseconds(300))
              accountedSeconds += 0.3
              _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: 0.65, normalizedY: -0.1))
              try await clock.sleep(for: .milliseconds(300))
              accountedSeconds += 0.3
              _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: 0.0, normalizedY: 0.0))
              reactionsPerformed += 1
            }

          case .stoppedForObstacle:
            obstaclesAvoided += 1
            let updatedSnapshot = await duckSession.currentSnapshot()
            let updatedZones = updatedSnapshot.tofFrame?.analyzeZones()
            let avoidDirection: DuckMoveDirection =
              (updatedZones?.leftMm ?? 0) >= (updatedZones?.rightMm ?? 0) ? .turnLeft : .turnRight

            if playfulReactions {
              didTouchLight = true
              try? await duckSession.setFlashlightColor(true, DuckLightColor.cyan.rawValue)
              await duckSession.playSound(.inquire, nil)
              reactionsPerformed += 1
            }

            let pivotDuration = min(0.9, max(0.3, remainingBudgetSeconds()))
            if pivotDuration >= 0.3 {
              let pivotResult = try await duckSession.performMoveStep(
                avoidDirection.makeRequest(
                  durationSeconds: pivotDuration,
                  speedPercent: 80,
                  stopOnObstacle: false
                )
              )
              accountedSeconds += pivotResult.elapsedSeconds
              turnsMade += 1
              if case let .interruptedBySafety(reason) = pivotResult.stopReason {
                earlyStopReason = reason
                stepsCompleted += 1
                break
              }
            }

          case let .interruptedBySafety(reason):
            earlyStopReason = reason
            stepsCompleted += 1
            break
          }

          stepsCompleted += 1
          if earlyStopReason != nil {
            break
          }
        }
      } catch {
        await duckSession.sendMove(.zero)
        if didPanHead {
          _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: 0.0, normalizedY: 0.0))
        }
        if didTouchLight {
          try? await duckSession.setFlashlightColor(false, DuckLightColor.white.rawValue)
        }
        throw error
      }

      await duckSession.sendMove(.zero)
      if didPanHead {
        _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: 0.0, normalizedY: 0.0))
      }
      if didTouchLight {
        try? await duckSession.setFlashlightColor(false, DuckLightColor.white.rawValue)
      }

      var stats: [String] = [
        "\(stepsCompleted) leg\(stepsCompleted == 1 ? "" : "s")",
        "\(forwardLegs) forward",
        "\(turnsMade) turn\(turnsMade == 1 ? "" : "s")",
      ]
      if obstaclesAvoided > 0 {
        stats.append("\(obstaclesAvoided) obstacle\(obstaclesAvoided == 1 ? "" : "s") avoided")
      }
      if reactionsPerformed > 0 {
        stats.append("\(reactionsPerformed) playful reaction\(reactionsPerformed == 1 ? "" : "s")")
      }

      if let earlyStopReason {
        return "\(duckName) stopped exploring early (\(earlyStopReason)) after \(stats.joined(separator: ", "))."
      }
      return "\(duckName) finished exploring the room (\(stats.joined(separator: ", ")))."
    }

    return .result(value: summary)
  }

  private static func makeElapsedTimer<C: Clock>(
    _ clock: C
  ) -> @Sendable () -> Double where C.Duration == Duration {
    let start = clock.now
    return {
      let components = start.duration(to: clock.now).components
      return Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
  }
}
