import Dependencies
import DuckProtocol
import Foundation
import Observation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Observable
@MainActor
public final class HuggingFaceSignInSheetModel: Identifiable {
  @ObservationIgnored @Dependency(\.huggingFaceAuth) var huggingFaceAuth
  @ObservationIgnored @Dependency(\.haptics) var haptics

  public var deviceCode: HuggingFaceDeviceCode?
  public var isRequestingCode = false
  public var isPollingApproval = false
  public var codeCopied = false
  public var urlCopied = false
  public var pastedToken = ""
  public var isVerifyingToken = false
  public var errorMessage: String?
  public var onSignedIn: (HuggingFaceSession) -> Void
  public var onCancel: () -> Void

  public init(
    onSignedIn: @escaping (HuggingFaceSession) -> Void = { _ in },
    onCancel: @escaping () -> Void = {}
  ) {
    self.onSignedIn = onSignedIn
    self.onCancel = onCancel
  }

  public func task() async {
    await startDeviceFlowIfNeeded()
  }

  public func startDeviceFlowIfNeeded() async {
    guard deviceCode == nil, !isRequestingCode else { return }
    isRequestingCode = true
    errorMessage = nil
    do {
      let code = try await huggingFaceAuth.startDeviceLogin()
      deviceCode = code
      isRequestingCode = false
      isPollingApproval = true
      let session = try await huggingFaceAuth.awaitDeviceLogin(code)
      isPollingApproval = false
      huggingFaceAuth.saveSession(session)
      haptics.success()
      onSignedIn(session)
    } catch is CancellationError {
      isRequestingCode = false
      isPollingApproval = false
    } catch {
      isRequestingCode = false
      isPollingApproval = false
      errorMessage = error.localizedDescription
    }
  }

  public func retryDeviceCodeButtonTapped() async {
    deviceCode = nil
    codeCopied = false
    urlCopied = false
    await startDeviceFlowIfNeeded()
  }

  public func copyCodeToClipboard() {
    guard let code = deviceCode?.userCode else { return }
    #if canImport(UIKit)
    UIPasteboard.general.string = code
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
    #endif
    codeCopied = true
    urlCopied = false
    haptics.selectionChanged()
  }

  public func copyURLButtonTapped() {
    guard let uri = deviceCode?.verificationURI else { return }
    #if canImport(UIKit)
    UIPasteboard.general.string = uri
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(uri, forType: .string)
    #endif
    urlCopied = true
    codeCopied = false
    haptics.selectionChanged()
  }

  public func verifyTokenButtonTapped() async {
    let trimmed = pastedToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isVerifyingToken else { return }
    isVerifyingToken = true
    errorMessage = nil
    defer { isVerifyingToken = false }

    do {
      let username = try await huggingFaceAuth.resolveUsername(trimmed)
      let session = HuggingFaceSession(token: trimmed, username: username)
      huggingFaceAuth.saveSession(session)
      pastedToken = ""
      haptics.success()
      onSignedIn(session)
    } catch {
      haptics.warning()
      errorMessage = error.localizedDescription
    }
  }
}

public struct HuggingFaceSignInSheetView: View {
  @Bindable var model: HuggingFaceSignInSheetModel
  @Environment(\.openURL) private var openURL

  public init(model: HuggingFaceSignInSheetModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          if model.isRequestingCode {
            HStack(spacing: 10) {
              ProgressView()
              Text("Requesting verification code…")
                .foregroundStyle(.secondary)
            }
          } else if let code = model.deviceCode {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(code.userCode)
                  .font(.title2.monospaced().weight(.semibold))
                  .tracking(2)
                  .textSelection(.enabled)
                Text(code.verificationURI)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Button(model.codeCopied ? "Copied" : "Copy") {
                model.copyCodeToClipboard()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }

            Button {
              model.copyCodeToClipboard()
              if let url = URL(string: code.verificationURI) {
                openURL(url)
              }
            } label: {
              Label("Copy Code & Open Hugging Face", systemImage: "safari")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button("Generate Code") {
              Task { await model.retryDeviceCodeButtonTapped() }
            }
          }
        } header: {
          HStack {
            Text("Browser Sign-In")
            Spacer()
            if model.isPollingApproval {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.mini)
                Text("Waiting…")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } footer: {
          Text("Sign in to access your private tricks and connect remotely to ducks on your account.")
        }

        Section("Access Token") {
          SecureField("hf_…", text: $model.pastedToken)
            .autocorrectionDisabled()
            #if canImport(UIKit)
            .textInputAutocapitalization(.never)
            #endif

          Button {
            Task { await model.verifyTokenButtonTapped() }
          } label: {
            if model.isVerifyingToken {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Sign In with Token")
            }
          }
          .disabled(model.pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isVerifyingToken)
        }

        if let err = model.errorMessage {
          Section {
            Label(err, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Hugging Face")
      #if canImport(UIKit)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      #if os(macOS)
      .formStyle(.grouped)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            model.onCancel()
          }
        }
      }
      .task {
        await model.task()
      }
    }
    #if os(macOS)
    .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 460)
    #endif
  }
}
