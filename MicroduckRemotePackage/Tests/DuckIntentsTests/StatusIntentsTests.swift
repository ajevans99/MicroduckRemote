import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct StatusIntentsTests {
  @Test func getDuckStatusReturnsStructuredEntityWithTelemetryAndSafety() async throws {
    let entity = try await withDependencies {
      var snap = DuckSessionSnapshot.previewConnected
      snap.health?.motors = MotorsHealth(maxC: 56, hottest: "left_knee")
      snap.latestState?.safety?.fallen = true
      let frozen = snap

      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      $0.duckSession = session
    } operation: {
      let result = try await GetDuckStatusIntent().perform()
      return result.value
    }

    expectNoDifference(entity?.duckName, "duck-eb55")
    expectNoDifference(entity?.isConnected, true)
    expectNoDifference(entity?.isSimulated, true)
    expectNoDifference(entity?.postureSummary, "Fallen")
    expectNoDifference(entity?.isFallen, true)
    expectNoDifference(entity?.batteryPercent, 54)
    expectNoDifference(entity?.maxMotorTempC, 56)
    expectNoDifference(entity?.hottestMotor, "left_knee")
    expectNoDifference(entity?.movementLimitReason, "deadman")
    expectNoDifference(entity?.installedTrickCount, 4)
  }

  @Test func intentTelemetryCapturesToolParametersRoutineStepsErrorsAndQueries() async throws {
    let recorded = LockIsolated<[IntentInvocationRecord]>([])

    try await withDependencies {
      var telemetry = IntentTelemetryClient.testValue
      telemetry.record = { entry in
        recorded.withValue { $0.append(entry) }
      }
      $0.intentTelemetry = telemetry
      $0.duckSession = .previewValue
      $0.continuousClock = ImmediateClock()
      $0.date.now = Date(timeIntervalSince1970: 1_795_150_500)
    } operation: {
      _ = try await InstalledSkillQuery().entities(matching: "bow")

      let routine = DuckRoutine(
        title: "Quick Peek",
        mood: "Curious",
        steps: [
          DuckRoutineStep(caption: "Look left", sound: .inquire, lookHorizontalPercent: -60, durationSeconds: 0.4)
        ]
      )
      _ = try await PerformDuckRoutineIntent(routine: routine).perform()
    }

    await withDependencies {
      var telemetry = IntentTelemetryClient.testValue
      telemetry.record = { entry in
        recorded.withValue { $0.append(entry) }
      }
      var fallen = DuckSessionSnapshot.previewConnected
      fallen.latestState?.safety?.fallen = true
      let frozen = fallen
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      $0.duckSession = session
      $0.intentTelemetry = telemetry
    } operation: {
      await #expect(throws: DuckSessionError.duckFallen) {
        _ = try await PerformTrickIntent(trick: InstalledSkillEntity(id: "roulade")).perform()
      }
    }

    expectNoDifference(recorded.value.count, 3)

    expectNoDifference(recorded.value[0].kind, .entityQuery)
    expectNoDifference(recorded.value[0].intentName, "InstalledSkillQuery.matching")
    expectNoDifference(recorded.value[0].parameters, [.init(key: "query", value: "bow")])
    expectNoDifference(recorded.value[0].outcome.isSuccess, true)

    expectNoDifference(recorded.value[1].kind, .toolIntent)
    expectNoDifference(recorded.value[1].intentName, "PerformDuckRoutineIntent")
    expectNoDifference(recorded.value[1].connectionContext, "Warm (duck-eb55)")
    expectNoDifference(recorded.value[1].parameters.first(where: { $0.key == "title" })?.value, "Quick Peek")
    expectNoDifference(recorded.value[1].parameters.contains(where: { $0.key == "step 1" }), true)
    expectNoDifference(recorded.value[1].outcome.isSuccess, true)

    expectNoDifference(recorded.value[2].kind, .toolIntent)
    expectNoDifference(recorded.value[2].intentName, "PerformTrickIntent")
    expectNoDifference(recorded.value[2].outcome.isSuccess, false)
    expectNoDifference(recorded.value[2].outcome.message, DuckSessionError.duckFallen.localizedDescription)
  }
}
