import CasePaths
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import IdentifiedCollections
import Observation
import SwiftUI

@Observable
@MainActor
public final class TricksModel {
  public enum FilterScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case mine = "Mine"
    case official = "Official"
    case community = "Community"

    public var id: String { rawValue }
  }

  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.hubCatalog) var hubCatalog
  @ObservationIgnored @Dependency(\.huggingFaceAuth) var huggingFaceAuth
  @ObservationIgnored @Dependency(\.haptics) var haptics

  public var snapshot = DuckSessionSnapshot()
  public var huggingFaceSession: HuggingFaceSession?
  public var signInSheet: HuggingFaceSignInSheetModel?
  public var catalogPolicies: IdentifiedArrayOf<HubPolicy> = []
  public var searchQuery = ""
  public var filterScope: FilterScope = .all
  public var isLoadingCatalog = false
  public var catalogWarning: String?

  public var busyPolicyKey: String?
  public var activeStage: TrickInstallStage?
  public var statusBannerMessage: String?
  public var statusBannerIsError = false
  public var holdDurationSeconds = DuckConstants.defaultHoldSeconds

  public init() {}

  public var availableScopes: [FilterScope] {
    if huggingFaceSession != nil {
      return [.all, .mine, .official, .community]
    }
    return [.all, .official, .community]
  }

  public func isOwnedBySignedInUser(_ policy: HubPolicy) -> Bool {
    guard let username = huggingFaceSession?.username, !username.isEmpty else { return false }
    return policy.authorName.caseInsensitiveCompare(username) == .orderedSame
  }

  public var myTricks: [HubPolicy] {
    guard huggingFaceSession != nil else { return [] }
    return catalogPolicies.filter { policy in
      isOwnedBySignedInUser(policy) && matchesSearch(policy)
    }
  }

  public var filteredTricks: [HubPolicy] {
    catalogPolicies.filter { policy in
      if filterScope != .mine {
        guard policy.isTrick else { return false }
      }
      switch filterScope {
      case .all:
        break
      case .mine:
        if !isOwnedBySignedInUser(policy) { return false }
      case .official:
        if !policy.official { return false }
      case .community:
        if policy.official { return false }
      }
      return matchesSearch(policy)
    }
  }

  private func matchesSearch(_ policy: HubPolicy) -> Bool {
    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    return policy.name.localizedCaseInsensitiveContains(trimmed)
      || policy.repo.localizedCaseInsensitiveContains(trimmed)
      || (policy.description?.localizedCaseInsensitiveContains(trimmed) == true)
  }

  public var locomotionPolicies: [HubPolicy] {
    catalogPolicies.filter { !$0.isTrick }
  }

  public func task() async {
    huggingFaceSession = huggingFaceAuth.loadSession()
    snapshot = await duckSession.currentSnapshot()
    async let catalogLoad: Void = loadInitialCatalogIfNeeded()
    async let snapshotUpdates: Void = observeSnapshots()
    async let authUpdates: Void = observeAuthChanges()
    _ = await (catalogLoad, snapshotUpdates, authUpdates)
  }

  private func loadInitialCatalogIfNeeded() async {
    if catalogPolicies.isEmpty {
      await refreshCatalogButtonTapped()
    }
  }

  private func observeSnapshots() async {
    for await updated in duckSession.snapshots() {
      snapshot = updated
    }
  }

  private func observeAuthChanges() async {
    for await _ in NotificationCenter.default.notifications(named: .microduckHuggingFaceSessionChanged) {
      let updated = huggingFaceAuth.loadSession()
      if updated != huggingFaceSession {
        huggingFaceSession = updated
        if updated == nil, filterScope == .mine {
          filterScope = .all
        }
        await refreshCatalogButtonTapped()
      }
    }
  }

  public func refreshCatalogButtonTapped() async {
    isLoadingCatalog = true
    defer { isLoadingCatalog = false }
    let result = await hubCatalog.fetchCatalog(huggingFaceSession)
    catalogPolicies = result.policies
    catalogWarning = result.warningMessage
  }

  public func signInButtonTapped() {
    haptics.selectionChanged()
    signInSheet = HuggingFaceSignInSheetModel(
      onSignedIn: { [weak self] session in
        guard let self else { return }
        huggingFaceSession = session
        signInSheet = nil
        statusBannerMessage = "Signed in to Hugging Face as @\(session.username)."
        statusBannerIsError = false
        Task { await self.refreshCatalogButtonTapped() }
      },
      onCancel: { [weak self] in
        self?.signInSheet = nil
      }
    )
  }

  public func signOutButtonTapped() async {
    haptics.selectionChanged()
    huggingFaceAuth.clearSession()
    huggingFaceSession = nil
    if filterScope == .mine {
      filterScope = .all
    }
    await refreshCatalogButtonTapped()
  }

  public func installAndPerformButtonTapped(_ policy: HubPolicy) async {
    guard snapshot.controlOpen else {
      statusBannerMessage = "Connect to your duck first before installing a trick."
      statusBannerIsError = true
      haptics.warning()
      return
    }
    guard busyPolicyKey == nil else { return }

    haptics.impactMedium()
    busyPolicyKey = policy.key
    activeStage = .downloading
    statusBannerMessage = nil
    statusBannerIsError = false

    do {
      let installedName = try await duckSession.installPolicy(policy, holdDurationSeconds) { stage in
        Task { @MainActor [weak self] in
          self?.activeStage = stage
        }
      }
      haptics.success()
      statusBannerMessage = "Installed and triggered “\(installedName)”!"
      statusBannerIsError = false
    } catch {
      haptics.warning()
      statusBannerMessage = humanizePolicyError(error.localizedDescription, policy: policy)
      statusBannerIsError = true
    }

    busyPolicyKey = nil
    activeStage = nil
  }

  public func runInstalledSkillButtonTapped(_ skillName: String) async {
    guard snapshot.controlOpen, busyPolicyKey == nil else { return }
    haptics.impactMedium()
    busyPolicyKey = "run:\(skillName)"
    defer { busyPolicyKey = nil }
    do {
      try await duckSession.performSkill(skillName)
      haptics.success()
      statusBannerMessage = "Performing \(skillName)!"
      statusBannerIsError = false
    } catch {
      haptics.warning()
      statusBannerMessage = error.localizedDescription
      statusBannerIsError = true
    }
  }

  public func removeInstalledSkillButtonTapped(_ skillName: String) async {
    guard snapshot.controlOpen, busyPolicyKey == nil else { return }
    haptics.selectionChanged()
    busyPolicyKey = "remove:\(skillName)"
    defer { busyPolicyKey = nil }
    do {
      try await duckSession.removeSkill(skillName)
      statusBannerMessage = "Removed \(skillName) from duck."
      statusBannerIsError = false
    } catch {
      statusBannerMessage = error.localizedDescription
      statusBannerIsError = true
    }
  }

  private func humanizePolicyError(_ raw: String, policy: HubPolicy) -> String {
    raw
      .replacingOccurrences(of: "network error: ", with: "")
      .replacingOccurrences(of: "\(policy.repo) ", with: "")
  }
}

public struct TricksGalleryView: View {
  @Bindable var model: TricksModel

  public init(model: TricksModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let banner = model.statusBannerMessage {
            HStack(spacing: 10) {
              Image(systemName: model.statusBannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.statusBannerIsError ? .orange : .green)
              Text(banner)
                .font(.footnote.weight(.medium))
              Spacer()
              Button {
                model.statusBannerMessage = nil
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
            .padding(12)
            .background(
              (model.statusBannerIsError ? Color.orange : Color.green).opacity(0.15),
              in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
          }

          installedSkillsSection

          huggingFaceAccountSection

          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Discover on Hugging Face")
                .font(.headline)
              Spacer()
            }

            Picker("Scope", selection: $model.filterScope) {
              ForEach(model.availableScopes) { scope in
                Text(scope.rawValue).tag(scope)
              }
            }
            .pickerStyle(.segmented)

            if model.isLoadingCatalog, model.catalogPolicies.isEmpty {
              HStack {
                Spacer()
                ProgressView("Loading Microduck tricks from Hugging Face…")
                  .padding(.vertical, 32)
                Spacer()
              }
            } else if let warning = model.catalogWarning, model.catalogPolicies.isEmpty {
              ContentUnavailableView(
                "Could Not Load Hub",
                systemImage: "wifi.exclamationmark",
                description: Text(warning)
              )
            } else if model.filterScope == .mine, model.filteredTricks.isEmpty {
              emptyPersonalTricksCard(username: model.huggingFaceSession?.username ?? "you")
            } else {
              LazyVStack(spacing: 12) {
                ForEach(model.filteredTricks) { policy in
                  trickCard(policy)
                }
              }
            }
          }
        }
        .padding(16)
      }
      .navigationTitle("Duck Tricks")
      .searchable(text: $model.searchQuery, prompt: "Search hops, bows, kicks…")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if let session = model.huggingFaceSession {
            Menu {
              Button {
                model.filterScope = .mine
              } label: {
                Label("Show My Tricks", systemImage: "sparkles.rectangle.stack")
              }
              Button {
                Task { await model.refreshCatalogButtonTapped() }
              } label: {
                Label("Refresh Tricks", systemImage: "arrow.clockwise")
              }
              Divider()
              Button(role: .destructive) {
                Task { await model.signOutButtonTapped() }
              } label: {
                Label("Sign Out (@\(session.username))", systemImage: "rectangle.portrait.and.arrow.right")
              }
            } label: {
              Label("@\(session.username)", systemImage: "person.crop.circle.fill.badge.checkmark")
                .font(.footnote.weight(.semibold))
            }
          } else {
            Button {
              model.signInButtonTapped()
            } label: {
              Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                .font(.footnote.weight(.semibold))
            }
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await model.refreshCatalogButtonTapped() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(model.isLoadingCatalog)
        }
      }
      .sheet(item: $model.signInSheet) { sheetModel in
        HuggingFaceSignInSheetView(model: sheetModel)
      }
      .task {
        await model.task()
      }
    }
  }

  @ViewBuilder
  private var huggingFaceAccountSection: some View {
    if let session = model.huggingFaceSession {
      if model.filterScope == .all {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Label("My Tricks (@\(session.username))", systemImage: "person.crop.circle.fill")
              .font(.headline)
            Spacer()
            if !model.myTricks.isEmpty {
              Text("\(model.myTricks.count)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
          }
          if model.myTricks.isEmpty {
            emptyPersonalTricksCard(username: session.username)
          } else {
            LazyVStack(spacing: 12) {
              ForEach(model.myTricks) { policy in
                trickCard(policy)
              }
            }
          }
        }
      }
    } else {
      HStack(spacing: 12) {
        Image(systemName: "person.crop.circle.badge.sparkles")
          .font(.title2)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
          Text("Have Your Own Tricks?")
            .font(.subheadline.weight(.semibold))
          Text("Sign in with Hugging Face to view your personal & private policies.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          model.signInButtonTapped()
        } label: {
          Text("Sign In")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
      }
      .padding(14)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
  }

  private func emptyPersonalTricksCard(username: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("No Microduck policies published under @\(username) yet.")
        .font(.subheadline.weight(.medium))
      Text("Publish any trained .onnx policy from microduck_rl with:")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("uv run publish --onnx output.onnx --repo \(username)/microduck-my-trick")
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var installedSkillsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("On Your Duck")
          .font(.headline)
        Spacer()
        Text(model.snapshot.controlOpen ? "Ready" : "Offline")
          .font(.caption.weight(.semibold))
          .foregroundStyle(model.snapshot.controlOpen ? .green : .secondary)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(model.snapshot.skillNames, id: \.self) { name in
            let summary = model.snapshot.installedSkills[id: name]
            HStack(spacing: 8) {
              Button {
                Task { await model.runInstalledSkillButtonTapped(name) }
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
                  Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                }
              }
              .buttonStyle(.plain)
              .disabled(!model.snapshot.controlOpen || model.busyPolicyKey != nil)

              if summary?.overridden == true {
                Button {
                  Task { await model.removeInstalledSkillButtonTapped(name) }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!model.snapshot.controlOpen || model.busyPolicyKey != nil)
              }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
          }
        }
      }
    }
  }

  private func trickCard(_ policy: HubPolicy) -> some View {
    let isThisBusy = model.busyPolicyKey == policy.key
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(policy.name)
              .font(.headline)
            if model.isOwnedBySignedInUser(policy) {
              Text("Yours")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.22), in: Capsule())
                .foregroundStyle(.green)
            }
            if policy.official {
              Text("Official")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
            if let variant = policy.forRobot {
              Text(variant)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
            }
          }
          Text("by \(policy.authorName) · \(policy.durationLabel)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if policy.likes > 0 {
          Label("\(policy.likes)", systemImage: "heart.fill")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.pink)
        }
      }

      if let desc = policy.description, !desc.isEmpty {
        Text(desc)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      HStack {
        if isThisBusy, let stage = model.activeStage {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text(stage.rawValue)
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Color.accentColor)
          }
        } else {
          Button {
            Task { await model.installAndPerformButtonTapped(policy) }
          } label: {
            Label("Put on Duck & Do It", systemImage: "arrow.down.circle.fill")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(Color.accentColor, in: Capsule())
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .disabled(model.busyPolicyKey != nil)
        }
        Spacer()
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

#Preview(
  traits: .dependencies {
    $0.duckSession = .previewValue
    $0.hubCatalog = .previewValue
  }
) {
  TricksGalleryView(model: TricksModel())
}
