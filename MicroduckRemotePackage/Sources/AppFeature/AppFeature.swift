import CasePaths
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import Observation
import SwiftUI
import SwiftUINavigation
import CockpitFeature
import RoomScanFeature
import SimulatorFeature
import TelemetryFeature
import TricksFeature

@Observable
@MainActor
public final class ConnectionSheetModel: Identifiable {
  public enum ModeSelection: String, CaseIterable, Identifiable {
    case local = "Local Simulator"
    case remote = "Hugging Face"

    public var id: String { rawValue }
  }

  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.huggingFaceAuth) var huggingFaceAuth
  @ObservationIgnored @Dependency(\.haptics) var haptics

  public var snapshot = DuckSessionSnapshot()
  public var modeSelection: ModeSelection = .local
  public var localSignallingURL = DuckConstants.defaultLocalSignallingURL
  public var rendezvousServerURL = DuckConstants.defaultRendezvousURL
  public var pastedToken = ""
  public var oauthClientID = ""
  public var savedSession: HuggingFaceSession?
  public var signInSheet: HuggingFaceSignInSheetModel?
  public var isAuthenticating = false
  public var errorMessage: String?
  public var onDismiss: () -> Void

  public init(onDismiss: @escaping () -> Void = {}) {
    self.onDismiss = onDismiss
  }

  public func task() async {
    savedSession = huggingFaceAuth.loadSession()
    snapshot = await duckSession.currentSnapshot()
    switch snapshot.target {
    case let .localSimulator(url):
      modeSelection = .local
      localSignallingURL = url
    case let .rendezvous(serverURL, _, _, _):
      modeSelection = .remote
      rendezvousServerURL = serverURL
    }
    for await updated in duckSession.snapshots() {
      snapshot = updated
    }
  }

  public func connectLocalButtonTapped() async {
    haptics.impactMedium()
    errorMessage = nil
    let trimmed = localSignallingURL.trimmingCharacters(in: .whitespacesAndNewlines)
    await duckSession.connect(.localSimulator(url: trimmed))
    onDismiss()
  }

  public func saveTokenAndConnectButtonTapped() async {
    let trimmed = pastedToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isAuthenticating = true
    errorMessage = nil
    defer { isAuthenticating = false }

    do {
      let username = try await huggingFaceAuth.resolveUsername(trimmed)
      let session = HuggingFaceSession(token: trimmed, username: username)
      huggingFaceAuth.saveSession(session)
      savedSession = session
      pastedToken = ""
      haptics.success()
      await duckSession.connect(
        .rendezvous(
          serverURL: rendezvousServerURL,
          token: session.token,
          username: session.username,
          preferredPeerID: nil
        )
      )
      onDismiss()
    } catch {
      errorMessage = error.localizedDescription
      haptics.warning()
    }
  }

  public func oauthSignInButtonTapped() async {
    let trimmed = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter a Hugging Face OAuth Client ID or paste an access token above."
      return
    }
    isAuthenticating = true
    errorMessage = nil
    defer { isAuthenticating = false }

    do {
      let session = try await huggingFaceAuth.signInWithPKCE(trimmed)
      huggingFaceAuth.saveSession(session)
      savedSession = session
      haptics.success()
      await duckSession.connect(
        .rendezvous(
          serverURL: rendezvousServerURL,
          token: session.token,
          username: session.username,
          preferredPeerID: nil
        )
      )
      onDismiss()
    } catch {
      errorMessage = error.localizedDescription
      haptics.warning()
    }
  }

  public func connectSavedAccountButtonTapped() async {
    guard let session = savedSession else { return }
    haptics.impactMedium()
    await duckSession.connect(
      .rendezvous(
        serverURL: rendezvousServerURL,
        token: session.token,
        username: session.username,
        preferredPeerID: nil
      )
    )
    onDismiss()
  }

  public func duckRowTapped(_ peerID: String) async {
    haptics.selectionChanged()
    await duckSession.selectDuck(peerID)
    onDismiss()
  }

  public func deviceSignInButtonTapped() {
    haptics.selectionChanged()
    signInSheet = HuggingFaceSignInSheetModel(
      onSignedIn: { [weak self] session in
        guard let self else { return }
        savedSession = session
        signInSheet = nil
        Task {
          await self.duckSession.connect(
            .rendezvous(
              serverURL: self.rendezvousServerURL,
              token: session.token,
              username: session.username,
              preferredPeerID: nil
            )
          )
          self.onDismiss()
        }
      },
      onCancel: { [weak self] in
        self?.signInSheet = nil
      }
    )
  }

  public func signOutButtonTapped() {
    huggingFaceAuth.clearSession()
    savedSession = nil
  }

  public func disconnectButtonTapped() async {
    haptics.selectionChanged()
    await duckSession.disconnect()
  }
}

@Observable
@MainActor
public final class AppModel {
  public enum Tab: Hashable {
    case cockpit
    case tricks
    case roomScan
    case telemetry
    #if os(macOS)
    case simulator
    #endif
  }

  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.connectionPreferences) var connectionPreferences
  @ObservationIgnored @Dependency(\.huggingFaceAuth) var huggingFaceAuth

  public var selectedTab: Tab = .cockpit
  public var cockpitModel = CockpitModel()
  public var tricksModel = TricksModel()
  public var roomScanModel = RoomScanModel()
  public var telemetryModel = TelemetryModel()
  #if os(macOS)
  public var simulatorModel = SimulatorModel()
  #endif
  public var connectionSheet: ConnectionSheetModel?
  private var didAutoConnect = false

  public init() {
    cockpitModel.onConnectionPillTapped = { [weak self] in
      self?.presentConnectionSheet()
    }
    #if os(macOS)
    simulatorModel.onOpenDriveTab = { [weak self] in
      self?.selectedTab = .cockpit
    }
    #endif
  }

  public func task() async {
    guard !didAutoConnect else { return }
    didAutoConnect = true
    let current = await duckSession.currentSnapshot()
    if !current.phase.isConnected, !current.phase.is(\.connecting) {
      #if targetEnvironment(simulator) || os(macOS)
      let runningInSimulator = true
      #else
      let runningInSimulator = false
      #endif
      if let target = try? ConnectionPreferencesClient.resolveColdStartTarget(
        preference: connectionPreferences.loadPreference(),
        huggingFaceSession: huggingFaceAuth.loadSession(),
        isSimulator: runningInSimulator
      ) {
        await duckSession.connect(target)
      }
    }
  }

  public func scenePhaseChanged(isActive: Bool) async {
    await duckSession.setForegroundActive(isActive)
  }

  public func presentConnectionSheet() {
    connectionSheet = ConnectionSheetModel(onDismiss: { [weak self] in
      self?.connectionSheet = nil
    })
  }
}

public struct RootAppView: View {
  @Bindable var model: AppModel
  @Environment(\.scenePhase) private var scenePhase

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    TabView(selection: $model.selectedTab) {
      Tab("Drive", systemImage: "gamecontroller.fill", value: AppModel.Tab.cockpit) {
        CockpitView(model: model.cockpitModel)
      }
      Tab("Tricks", systemImage: "sparkles", value: AppModel.Tab.tricks) {
        TricksGalleryView(model: model.tricksModel)
      }
      Tab("Room Scan", systemImage: "arkit", value: AppModel.Tab.roomScan) {
        RoomScanView(model: model.roomScanModel)
      }
      Tab("Telemetry", systemImage: "waveform.path.ecg", value: AppModel.Tab.telemetry) {
        TelemetryInspectorView(model: model.telemetryModel)
      }
      #if os(macOS)
      Tab("Simulator", systemImage: "desktopcomputer", value: AppModel.Tab.simulator) {
        SimulatorView(model: model.simulatorModel)
      }
      #endif
    }
    .sheet(item: $model.connectionSheet) { sheetModel in
      ConnectionSheetView(model: sheetModel)
    }
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      Task {
        await model.scenePhaseChanged(isActive: newPhase == .active)
      }
    }
    .task {
      await model.task()
    }
    #if os(macOS)
    .frame(minWidth: 820, minHeight: 600)
    #endif
  }
}

public struct ConnectionSheetView: View {
  @Bindable var model: ConnectionSheetModel
  @Environment(\.dismiss) private var dismiss

  public init(model: ConnectionSheetModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Transport", selection: $model.modeSelection) {
            ForEach(ConnectionSheetModel.ModeSelection.allCases) { option in
              Text(option.rawValue).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }

        if model.modeSelection == .local {
          Section {
            TextField("ws://127.0.0.1:8443", text: $model.localSignallingURL)
              .autocorrectionDisabled()
              #if canImport(UIKit)
              .textInputAutocapitalization(.never)
              .keyboardType(.URL)
              #endif
            Button("Connect to Local Simulator") {
              Task { await model.connectLocalButtonTapped() }
            }
            .fontWeight(.semibold)
          } header: {
            Text("Local Signalling")
          } footer: {
            Text("Connects to mediad from local duck-sim. Only one client can connect at a time.")
          }
        } else {
          Section("Hugging Face") {
            if let session = model.savedSession {
              LabeledContent("Account", value: "@\(session.username)")
              Button("Connect via Rendezvous") {
                Task { await model.connectSavedAccountButtonTapped() }
              }
              .fontWeight(.semibold)
              Button("Sign Out", role: .destructive) {
                model.signOutButtonTapped()
              }
            } else {
              Button {
                model.deviceSignInButtonTapped()
              } label: {
                Label("Sign In with Browser Code", systemImage: "safari")
                  .fontWeight(.semibold)
              }

              SecureField("Access Token (hf_…)", text: $model.pastedToken)
                .autocorrectionDisabled()
              Button("Verify Token & Connect") {
                Task { await model.saveTokenAndConnectButtonTapped() }
              }
              .disabled(model.pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAuthenticating)
            }
          }
        }

        if !model.snapshot.availableDucks.isEmpty {
          Section("Available Ducks") {
            ForEach(model.snapshot.availableDucks) { duck in
              Button {
                Task { await model.duckRowTapped(duck.id) }
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(duck.displayName)
                      .foregroundStyle(.primary)
                    Text(duck.isSimulated ? "MuJoCo Simulator" : "Hardware")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  if duck.busy == true {
                    Text("Busy")
                      .font(.caption.weight(.medium))
                      .foregroundStyle(.orange)
                  }
                }
              }
            }
          }
        }

        if model.snapshot.phase.isConnected || model.snapshot.controlOpen {
          Section {
            Button("Disconnect", role: .destructive) {
              Task { await model.disconnectButtonTapped() }
            }
          }
        }

        if let err = model.errorMessage {
          Section {
            Label(err, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
              .font(.footnote)
          }
        }
      }
      .navigationTitle("Connect")
      #if canImport(UIKit)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      #if os(macOS)
      .formStyle(.grouped)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .sheet(item: $model.signInSheet) { sheetModel in
        HuggingFaceSignInSheetView(model: sheetModel)
      }
      .task {
        await model.task()
      }
    }
    #if os(macOS)
    .frame(minWidth: 460, idealWidth: 520, minHeight: 460, idealHeight: 540)
    #endif
  }
}

#Preview(
  traits: .dependencies {
    $0.duckSession = .previewValue
    $0.hubCatalog = .previewValue
    $0.roomScan = .previewValue
    $0.iCloudSceneSync = .previewValue
  }
) {
  RootAppView(model: AppModel())
}
