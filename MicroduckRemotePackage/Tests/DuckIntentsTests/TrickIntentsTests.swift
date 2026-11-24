import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct TrickIntentsTests {
  @Test func installedSkillQueryReadsLiveSkillsExcludesSitToggleAndMatchesFuzzyStrings() async throws {
    try await withDependencies {
      $0.duckSession = .previewValue
      $0.duckSharedState = .previewValue
    } operation: {
      let query = InstalledSkillQuery()
      let all = try await query.allEntities()
      expectNoDifference(all.map(\.id), ["roulade", "kick_left", "kick_right", "polite-bow"])
      expectNoDifference(all.first(where: { $0.id == "polite-bow" })?.isCustom, true)

      let matches = try await query.entities(matching: "left kick")
      expectNoDifference(matches.map(\.id), ["kick_left"])

      let bowMatches = try await query.entities(matching: "bow")
      expectNoDifference(bowMatches.map(\.id), ["polite-bow"])
    }
  }

  @Test func installedSkillQueryFallsBackToSharedSummaryOfflineWithoutConnecting() async throws {
    let connectCalls = LockIsolated(0)

    try await withDependencies {
      var disconnected = DuckSessionSnapshot.previewConnected
      disconnected.controlOpen = false
      disconnected.phase = .disconnected
      let frozen = disconnected

      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      session.ensureConnected = { _ in
        connectCalls.withValue { $0 += 1 }
        return DuckIdentity(peerID: "x", name: "x")
      }
      $0.duckSession = session

      var shared = DuckSharedStateClient.previewValue
      shared.loadSummary = {
        DuckSharedSummary(installedSkillNames: ["roulade", "sit_toggle", "happy-hop"])
      }
      $0.duckSharedState = shared
    } operation: {
      let all = try await InstalledSkillQuery().allEntities()
      expectNoDifference(all.map(\.id), ["roulade", "happy-hop"])
      expectNoDifference(connectCalls.value, 0)
    }
  }

  @Test func performTrickRunsWhenStandingAndBlocksWhenFallenOrSitting() async throws {
    let performed = LockIsolated<[String]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.performSkill = { skill in
        performed.withValue { $0.append(skill) }
      }
      $0.duckSession = session
    } operation: {
      let intent = PerformTrickIntent(trick: InstalledSkillEntity(id: "roulade"))
      _ = try await intent.perform()
    }
    expectNoDifference(performed.value, ["roulade"])

    await withDependencies {
      var fallen = DuckSessionSnapshot.previewConnected
      fallen.latestState?.safety?.fallen = true
      let frozen = fallen
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      $0.duckSession = session
    } operation: {
      await #expect(throws: DuckSessionError.duckFallen) {
        _ = try await PerformTrickIntent(trick: InstalledSkillEntity(id: "roulade")).perform()
      }
    }

    await withDependencies {
      var sitting = DuckSessionSnapshot.previewConnected
      sitting.policies?.sitting = true
      let frozen = sitting
      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { frozen }
      $0.duckSession = session
    } operation: {
      await #expect(throws: DuckSessionError.duckNotStanding) {
        _ = try await PerformTrickIntent(trick: InstalledSkillEntity(id: "kick_left")).perform()
      }
    }
  }
}
