import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Testing

@Suite struct ModesAndLightIntentsTests {
  @Test func setDuckModeRoutesEachAutonomousModeAndRefreshesPolicies() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.refreshSkills = { events.withValue { $0.append("refresh") } }
      session.setAutonomous = { on in events.withValue { $0.append("autonomous:\(on)") } }
      session.setSoccer = { on in events.withValue { $0.append("soccer:\(on)") } }
      session.setLaserTrack = { on in events.withValue { $0.append("laser:\(on)") } }
      $0.duckSession = session
    } operation: {
      _ = try await SetDuckModeIntent(mode: .autonomous, enabled: true).perform()
      _ = try await SetDuckModeIntent(mode: .soccer, enabled: true).perform()
      _ = try await SetDuckModeIntent(mode: .laserTrack, enabled: false).perform()
    }

    expectNoDifference(
      events.value,
      [
        "refresh",
        "autonomous:true",
        "refresh",
        "soccer:true",
        "refresh",
        "laser:false",
      ]
    )
  }

  @Test func setDuckModeRefusesToEnableWhileSittingButAllowsDisabling() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var sitting = DuckSessionSnapshot.previewConnected
      sitting.policies?.sitting = true
      let frozen = sitting

      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      session.setSoccer = { on in events.withValue { $0.append("soccer:\(on)") } }
      $0.duckSession = session
    } operation: {
      await #expect(throws: DuckSessionError.duckNotStanding) {
        _ = try await SetDuckModeIntent(mode: .soccer, enabled: true).perform()
      }
      _ = try await SetDuckModeIntent(mode: .soccer, enabled: false).perform()
    }

    expectNoDifference(events.value, ["soccer:false"])
  }

  @Test func setDuckLightSendsColorOrTurnsOff() async throws {
    let calls = LockIsolated<[String]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.setFlashlightColor = { on, color in
        calls.withValue { $0.append("\(on):\(color)") }
      }
      $0.duckSession = session
    } operation: {
      _ = try await SetDuckLightIntent(color: .cyan).perform()
      _ = try await SetDuckLightIntent(color: .off).perform()
    }

    expectNoDifference(calls.value, ["true:cyan", "false:white"])
  }
}
