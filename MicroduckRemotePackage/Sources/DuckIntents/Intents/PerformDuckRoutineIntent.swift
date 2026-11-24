import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import SwiftUI

@AppIntent(.tool)
public struct PerformDuckRoutineIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Perform Duck Routine"
  public static let description = IntentDescription(
    "Performs an improvised multi-step expressive choreography on Microduck combining head gaze, sounds, RGB face light, bounded steps, and built-in tricks. Use this for creative moods, reactions, celebrations, or skits (for example 'act suspicious', 'celebrate', or 'greet my guest')."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Routine",
    description: "The generated choreography containing a title, mood, and 2 to 6 ordered steps for Microduck to perform."
  )
  public var routine: DuckRoutine

  public static var parameterSummary: some ParameterSummary {
    Summary("Perform \(\.$routine) on Microduck")
  }

  public init() {}

  public init(routine: DuckRoutine) {
    self.routine = routine
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<DuckRoutine> & ProvidesDialog & ShowsSnippetView {
    @Dependencies.Dependency(\.duckSession) var duckSession
    @Dependencies.Dependency(\.continuousClock) var clock

    let stepsToRun = Array(routine.steps.prefix(6))
    var params: [IntentInvocationRecord.ParameterEntry] = [
      .init(key: "title", value: routine.title.isEmpty ? "(untitled)" : routine.title),
      .init(key: "mood", value: routine.mood.isEmpty ? "(none)" : routine.mood),
      .init(key: "stepCount", value: "\(routine.steps.count)"),
    ]
    for (idx, step) in stepsToRun.enumerated() {
      let label = step.caption.isEmpty ? step.summarySubtitle : "\(step.caption) — \(step.summarySubtitle)"
      params.append(.init(key: "step \(idx + 1)", value: label))
    }

    let (executedRoutine, dialogText) = try await IntentTelemetryTracer.traceTool(
      intentName: "PerformDuckRoutineIntent",
      displayTitle: "Perform Duck Routine",
      parameters: params
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(
        timeout: .seconds(6),
        refreshIfOpen: true
      )
      setContext(connection.contextLabel)
      let duckName = connection.duckName

      guard !stepsToRun.isEmpty else {
        let message = "No steps were provided for \(duckName)'s routine."
        return ((routine, message), message)
      }

      var completedSteps = 0
      var didTouchLight = false
      var didHoldWheee = false
      var earlyStopNote: String?

      do {
        for step in stepsToRun {
          try Task.checkCancellation()

          let current = await duckSession.currentSnapshot()
          if current.latestState?.safety?.fallen == true {
            earlyStopNote = "stopped early because \(duckName) fell over"
            break
          }
          if current.latestState?.safety?.pickedUp == true {
            earlyStopNote = "stopped early because \(duckName) was picked up"
            break
          }

          if let lightColor = step.lightColor {
            didTouchLight = true
            if lightColor == .off {
              try? await duckSession.setFlashlightColor(false, "white")
            } else {
              try? await duckSession.setFlashlightColor(true, lightColor.rawValue)
            }
          }

          if step.lookHorizontalPercent != 0 || step.lookVerticalPercent != 0 {
            _ = await duckSession.sendLook(step.lookTarget)
          }

          if let sound = step.sound, !sound.soundTag.isHoldable {
            await duckSession.playSound(sound.soundTag, nil)
          }

          let isStanding = current.policies?.enabled != false && current.policies?.sitting != true

          if let trick = step.builtInTrick, isStanding {
            try await duckSession.performSkill(trick.rawValue)
            try await clock.sleep(for: .milliseconds(Int((step.clampedDurationSeconds * 1000).rounded())))
          } else if let direction = step.moveDirection, isStanding {
            let moveRequest = direction.makeRequest(
              durationSeconds: step.clampedDurationSeconds,
              speedPercent: step.clampedSpeedPercent,
              stopOnObstacle: true
            )
            let moveResult = try await duckSession.performMoveStep(moveRequest)
            switch moveResult.stopReason {
            case .completed:
              break
            case let .stoppedForObstacle(distanceMm):
              earlyStopNote = "paused for an obstacle \(distanceMm) mm ahead"
            case let .interruptedBySafety(reason):
              earlyStopNote = reason
            }
            if earlyStopNote != nil {
              completedSteps += 1
              break
            }
          } else if step.sound == .wheee {
            didHoldWheee = true
            let hz = DuckConstants.intentHz
            let tickInterval = Duration.milliseconds(1000 / hz)
            let totalTicks = max(1, Int((step.clampedDurationSeconds * Double(hz)).rounded()))
            for _ in 0..<totalTicks {
              try Task.checkCancellation()
              await duckSession.playSound(.wheee, true)
              try await clock.sleep(for: tickInterval)
            }
            await duckSession.playSound(.wheee, false)
            didHoldWheee = false
          } else {
            try await clock.sleep(for: .milliseconds(Int((step.clampedDurationSeconds * 1000).rounded())))
          }

          completedSteps += 1
        }
      } catch {
        if didHoldWheee {
          await duckSession.playSound(.wheee, false)
        }
        await duckSession.sendMove(.zero)
        if didTouchLight {
          try? await duckSession.setFlashlightColor(false, "white")
        }
        throw error
      }

      await duckSession.sendMove(.zero)
      if didTouchLight {
        try? await duckSession.setFlashlightColor(false, "white")
      }

      let routineTitle = routine.title.isEmpty ? "its routine" : "“\(routine.title)”"
      let message: String
      if let earlyStopNote {
        message = "\(duckName) ran \(completedSteps) of \(stepsToRun.count) steps of \(routineTitle) (\(earlyStopNote))."
      } else {
        message = "\(duckName) performed \(routineTitle) (\(completedSteps) steps)."
      }

      let executed = DuckRoutine(
        title: routine.title,
        mood: routine.mood,
        steps: stepsToRun
      )
      return ((executed, message), message)
    }

    return .result(
      value: executedRoutine,
      dialog: IntentDialog(stringLiteral: dialogText),
      view: DuckRoutineCardView(routine: executedRoutine, isCompact: false)
    )
  }
}
