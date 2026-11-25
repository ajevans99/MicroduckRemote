import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckProtocol
import Foundation
import Testing
import TricksFeature

@Suite struct TricksFeatureTests {
  @Test @MainActor func installAndPerformAdvancesThroughStagesAndShowsBanner() async {
    let observedStages = LockIsolated<[TrickInstallStage]>([])

    await withDependencies {
      var session = DuckSessionClient.previewValue
      session.installPolicy = { _, _, onStage in
        onStage(.downloading)
        observedStages.withValue { $0.append(.downloading) }
        onStage(.installing)
        observedStages.withValue { $0.append(.installing) }
        onStage(.waitingForStand)
        observedStages.withValue { $0.append(.waitingForStand) }
        onStage(.performing)
        observedStages.withValue { $0.append(.performing) }
        return "polite-bow"
      }
      $0.duckSession = session
      $0.hubCatalog = .previewValue
      $0.haptics = .previewValue
    } operation: {
      let model = TricksModel()
      model.snapshot = .previewConnected

      let bow = HubPolicy(
        key: "neil-jo/microduck-polite-bow",
        repo: "neil-jo/microduck-polite-bow",
        name: "Polite Bow",
        durationS: 4.0
      )

      await model.installAndPerformButtonTapped(bow)

      expectNoDifference(
        observedStages.value,
        [.downloading, .installing, .waitingForStand, .performing]
      )
      expectNoDifference(model.statusBannerMessage, "Installed and triggered “polite-bow”!")
      expectNoDifference(model.statusBannerIsError, false)
      expectNoDifference(model.busyPolicyKey, nil)
    }
  }

  @Test @MainActor func signedInSessionLoadsAndFiltersPersonalTricks() async {
    await withDependencies {
      var auth = HuggingFaceAuthClient.previewValue
      auth.loadSession = {
        HuggingFaceSession(token: "hf_oauth_test", username: "demo-user")
      }
      $0.huggingFaceAuth = auth
      $0.hubCatalog = .previewValue
      $0.duckSession = .previewValue
      $0.haptics = .previewValue
    } operation: {
      let model = TricksModel()
      model.huggingFaceSession = HuggingFaceSession(token: "hf_oauth_test", username: "demo-user")
      await model.refreshCatalogButtonTapped()

      expectNoDifference(model.myTricks.map(\.name), ["Custom Wave"])
      model.filterScope = .mine
      expectNoDifference(model.filteredTricks.map(\.repo), ["demo-user/microduck-custom-wave"])
    }
  }

  @Test func bundledSignedShortcutsResolveForBothBundleIdentifiers() throws {
    for bundleID in ["dev.ajevans.microduckremote", "com.microduck.remote", "com.unknown.custom"] {
      for template in BundledShortcutTemplate.gallery {
        let url = try #require(
          template.resolvedResourceURL(bundleIdentifier: bundleID),
          "Missing bundled shortcut \(template.fileName) for \(bundleID)"
        )
        let data = try Data(contentsOf: url)
        #expect(data.count > 1000, "Signed shortcut \(template.fileName) should be non-empty")

        let importURL = try template.prepareImportableFileURL(bundleIdentifier: bundleID)
        expectNoDifference(importURL.lastPathComponent, template.fileName)
      }
    }
  }
}
