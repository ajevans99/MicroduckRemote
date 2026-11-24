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
      List {
        if let banner = model.statusBannerMessage {
          Section {
            HStack(spacing: 10) {
              Image(systemName: model.statusBannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.statusBannerIsError ? .orange : .green)
              Text(banner)
                .font(.footnote)
              Spacer()
              Button {
                model.statusBannerMessage = nil
              } label: {
                Image(systemName: "xmark")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }
        }

        installedSkillsSection

        if model.huggingFaceSession == nil {
          Section {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Personal & Private Tricks")
                  .font(.subheadline.weight(.medium))
                Text("Sign in with Hugging Face to access your own policies.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Sign In") {
                model.signInButtonTapped()
              }
              .buttonStyle(.borderedProminent)
              .buttonBorderShape(.capsule)
              .controlSize(.small)
            }
          }
        } else if model.filterScope == .all, !model.myTricks.isEmpty {
          Section("My Tricks (@\(model.huggingFaceSession?.username ?? ""))") {
            ForEach(model.myTricks) { policy in
              trickRow(policy)
            }
          }
        }

        Section {
          Picker("Scope", selection: $model.filterScope) {
            ForEach(model.availableScopes) { scope in
              Text(scope.rawValue).tag(scope)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

          if model.isLoadingCatalog, model.catalogPolicies.isEmpty {
            HStack {
              Spacer()
              ProgressView("Loading tricks…")
                .padding(.vertical, 24)
              Spacer()
            }
          } else if let warning = model.catalogWarning, model.catalogPolicies.isEmpty {
            ContentUnavailableView(
              "Couldn’t Load Hub",
              systemImage: "wifi.exclamationmark",
              description: Text(warning)
            )
          } else if model.filterScope == .mine, model.filteredTricks.isEmpty {
            ContentUnavailableView(
              "No Personal Tricks",
              systemImage: "sparkles",
              description: Text("Publish an ONNX policy under @\(model.huggingFaceSession?.username ?? "you") on Hugging Face.")
            )
          } else if model.filteredTricks.isEmpty {
            ContentUnavailableView.search(text: model.searchQuery)
          } else {
            ForEach(model.filteredTricks) { policy in
              trickRow(policy)
            }
          }
        } header: {
          Text("Discover")
        }
      }
      #if canImport(UIKit)
      .listStyle(.insetGrouped)
      #else
      .listStyle(.inset)
      #endif
      .navigationTitle("Tricks")
      .searchable(text: $model.searchQuery, prompt: "Search tricks")
      .refreshable {
        await model.refreshCatalogButtonTapped()
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if let session = model.huggingFaceSession {
            Menu {
              Button {
                model.filterScope = .mine
              } label: {
                Label("My Tricks", systemImage: "sparkles")
              }
              Button {
                Task { await model.refreshCatalogButtonTapped() }
              } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
              }
              Divider()
              Button(role: .destructive) {
                Task { await model.signOutButtonTapped() }
              } label: {
                Label("Sign Out (@\(session.username))", systemImage: "rectangle.portrait.and.arrow.right")
              }
            } label: {
              Label("@\(session.username)", systemImage: "person.crop.circle.fill")
                .font(.footnote.weight(.medium))
            }
          } else {
            Button("Sign In") {
              model.signInButtonTapped()
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

  private var installedSkillsSection: some View {
    Section {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.snapshot.skillNames, id: \.self) { name in
            let summary = model.snapshot.installedSkills[id: name]
            HStack(spacing: 4) {
              Button {
                Task { await model.runInstalledSkillButtonTapped(name) }
              } label: {
                Label(
                  name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized,
                  systemImage: "play.fill"
                )
                .font(.footnote.weight(.medium))
              }
              .buttonStyle(.bordered)
              .buttonBorderShape(.capsule)
              .controlSize(.small)
              .disabled(!model.snapshot.controlOpen || model.busyPolicyKey != nil)

              if summary?.overridden == true {
                Button(role: .destructive) {
                  Task { await model.removeInstalledSkillButtonTapped(name) }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!model.snapshot.controlOpen || model.busyPolicyKey != nil)
              }
            }
          }
        }
        .padding(.vertical, 2)
      }
    } header: {
      HStack {
        Text("On Your Duck")
        Spacer()
        Text(model.snapshot.controlOpen ? "Ready" : "Offline")
          .font(.caption)
          .foregroundStyle(model.snapshot.controlOpen ? .green : .secondary)
          .textCase(nil)
      }
    }
  }

  private func trickRow(_ policy: HubPolicy) -> some View {
    let isThisBusy = model.busyPolicyKey == policy.key
    return HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(policy.name)
            .font(.body.weight(.medium))

          if model.isOwnedBySignedInUser(policy) {
            Text("Yours")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.green)
          } else if policy.official {
            Image(systemName: "checkmark.seal.fill")
              .font(.caption)
              .foregroundStyle(Color.accentColor)
          }

          if let variant = policy.forRobot {
            Text(variant)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.orange)
          }
        }

        if let desc = policy.description, !desc.isEmpty {
          Text(desc)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        HStack(spacing: 6) {
          Text(policy.authorName)
          Text("·")
          Text(policy.durationLabel)
          if policy.likes > 0 {
            Text("·")
            Label("\(policy.likes)", systemImage: "heart")
              .labelStyle(.titleAndIcon)
          }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 8)

      if isThisBusy, let stage = model.activeStage {
        VStack(alignment: .trailing, spacing: 4) {
          ProgressView()
            .controlSize(.small)
          Text(stage.rawValue)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      } else {
        Button("Install") {
          Task { await model.installAndPerformButtonTapped(policy) }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(model.busyPolicyKey != nil)
      }
    }
    .padding(.vertical, 4)
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
