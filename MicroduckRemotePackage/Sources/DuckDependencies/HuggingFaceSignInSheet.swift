import Dependencies
import DuckProtocol
import Foundation
import Observation
import SwiftUI

#if canImport(UIKit)
import UIKit
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
    #endif
    codeCopied = true
    urlCopied = false
    haptics.selectionChanged()
  }

  public func copyURLButtonTapped() {
    guard let uri = deviceCode?.verificationURI else { return }
    #if canImport(UIKit)
    UIPasteboard.general.string = uri
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
      ScrollView {
        VStack(spacing: 22) {
          VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.sparkles")
              .font(.system(size: 44))
              .foregroundStyle(Color.accentColor)
            Text("Sign in with Hugging Face")
              .font(.title2.weight(.bold))
            Text("Unlock your published & private Microduck tricks—and reach remote ducks signed into your account.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 12)
          }
          .padding(.top, 8)

          deviceFlowCard
          pasteTokenCard

          if let err = model.errorMessage {
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
              Text(err)
                .font(.footnote)
                .foregroundStyle(.secondary)
              Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
        }
        .padding(20)
      }
      #if canImport(UIKit)
      .navigationBarTitleDisplayMode(.inline)
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
  }

  private var deviceFlowCard: some View {
    VStack(spacing: 14) {
      HStack {
        Label("Quick Browser Sign-In", systemImage: "safari.fill")
          .font(.headline)
        Spacer()
        if model.isPollingApproval {
          HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Waiting…")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
        }
      }

      if model.isRequestingCode {
        ProgressView("Getting your 8-character code…")
          .padding(.vertical, 16)
      } else if let code = model.deviceCode {
        Text("Open this URL on this phone or any computer and enter the code below:")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 10) {
          Image(systemName: "link")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(code.verificationURI)
            .font(.footnote.monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .textSelection(.enabled)
          Spacer(minLength: 4)
          Button {
            model.copyURLButtonTapped()
          } label: {
            Label(
              model.urlCopied ? "Copied" : "Copy URL",
              systemImage: model.urlCopied ? "checkmark" : "doc.on.doc"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        HStack {
          Text(code.userCode)
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .tracking(3)
            .textSelection(.enabled)
          Spacer()
          Button {
            model.copyCodeToClipboard()
          } label: {
            Label(
              model.codeCopied ? "Copied" : "Copy Code",
              systemImage: model.codeCopied ? "checkmark" : "doc.on.doc"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        Button {
          model.copyCodeToClipboard()
          if let url = URL(string: code.verificationURI) {
            openURL(url)
          }
        } label: {
          Label("Copy Code & Open Hugging Face", systemImage: "arrow.up.right.square.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
      } else {
        Button {
          Task { await model.retryDeviceCodeButtonTapped() }
        } label: {
          Label("Generate New Code", systemImage: "arrow.clockwise")
            .font(.subheadline.weight(.semibold))
        }
      }
    }
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var pasteTokenCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Or Paste an Access Token", systemImage: "key.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        SecureField("hf_…", text: $model.pastedToken)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          #if canImport(UIKit)
          .textInputAutocapitalization(.never)
          #endif

        Button {
          Task { await model.verifyTokenButtonTapped() }
        } label: {
          if model.isVerifyingToken {
            ProgressView().controlSize(.small)
              .padding(.horizontal, 8)
          } else {
            Text("Sign In")
              .font(.subheadline.weight(.semibold))
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isVerifyingToken)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}
