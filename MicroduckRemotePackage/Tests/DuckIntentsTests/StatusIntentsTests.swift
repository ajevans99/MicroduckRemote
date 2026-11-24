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
}
