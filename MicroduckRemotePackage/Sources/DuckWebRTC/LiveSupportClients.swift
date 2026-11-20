import AuthenticationServices
import CryptoKit
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import GameController
import IdentifiedCollections

#if canImport(UIKit)
import UIKit
#endif

extension HubCatalogClient: DependencyKey {
  public static var liveValue: HubCatalogClient {
    HubCatalogClient { session in
      guard let searchURL = URL(string: "\(DuckConstants.hubModelsAPIURL)?search=microduck&limit=50&full=true") else {
        return HubCatalogResult(warningMessage: "Invalid Hub search URL")
      }

      let fetchHits: @Sendable (URL, String?) async throws -> [[String: Any]] = { url, token in
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        if let token, !token.isEmpty {
          req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
          throw RpcErrorPayload(code: -32030, message: "Hugging Face Hub could not be reached right now.")
        }
        guard let hits = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
          throw RpcErrorPayload(code: -32031, message: "Unexpected Hub response.")
        }
        return hits
      }

      do {
        async let publicHitsTask = fetchHits(searchURL, session?.token)
        async let authorHitsTask: [[String: Any]] = {
          guard
            let username = session?.username,
            !username.isEmpty,
            let encodedAuthor = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let authorURL = URL(string: "\(DuckConstants.hubModelsAPIURL)?author=\(encodedAuthor)&limit=100&full=true")
          else {
            return []
          }
          return (try? await fetchHits(authorURL, session?.token)) ?? []
        }()

        let publicHits = try await publicHitsTask
        let authorHits = await authorHitsTask

        var likesByRepo: [String: Int] = [:]
        var previewByRepo: [String: String] = [:]
        var topLevelOnnxByRepo: [String: [String]] = [:]
        var isAuthorRepo: Set<String> = []

        let ingestHit: ([String: Any], Bool) -> Void = { hit, fromAuthor in
          guard let id = (hit["modelId"] as? String) ?? (hit["id"] as? String), !id.isEmpty else {
            return
          }
          if fromAuthor {
            isAuthorRepo.insert(id)
          }
          likesByRepo[id] = max(likesByRepo[id] ?? 0, (hit["likes"] as? Int) ?? 0)
          if let siblings = hit["siblings"] as? [[String: Any]] {
            let files = siblings.compactMap { $0["rfilename"] as? String }
            let onnxFiles = files.filter {
              $0.lowercased().hasSuffix(".onnx") && !$0.contains("/") && !$0.hasPrefix(".")
            }
            if !onnxFiles.isEmpty {
              topLevelOnnxByRepo[id] = onnxFiles
            }
            if let mp4 = files.first(where: { $0.lowercased().hasSuffix(".mp4") }) {
              let encoded = mp4.split(separator: "/").map {
                $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
              }.joined(separator: "/")
              previewByRepo[id] = "https://huggingface.co/\(id)/resolve/main/\(encoded)"
            }
          }
        }

        for hit in publicHits { ingestHit(hit, false) }
        for hit in authorHits { ingestHit(hit, true) }

        let candidateRepos = likesByRepo.keys.filter { $0 != DuckConstants.officialPolicySetRepo }.sorted()
        let allRepos = [DuckConstants.officialPolicySetRepo] + candidateRepos
        let bearerToken = session?.token

        let manifests: [String: Data] = await withTaskGroup(of: (String, Data?).self) { group in
          for repo in allRepos {
            group.addTask {
              guard let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/manifest.json") else {
                return (repo, nil)
              }
              var req = URLRequest(url: url)
              req.timeoutInterval = 8
              if let bearerToken, !bearerToken.isEmpty {
                req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
              }
              guard
                let (mData, mResp) = try? await URLSession.shared.data(for: req),
                let mHttp = mResp as? HTTPURLResponse,
                mHttp.statusCode == 200
              else {
                return (repo, nil)
              }
              return (repo, mData)
            }
          }
          var collected: [String: Data] = [:]
          for await (repo, mData) in group {
            if let mData {
              collected[repo] = mData
            }
          }
          return collected
        }

        var policies: [HubPolicy] = []
        if let officialData = manifests[DuckConstants.officialPolicySetRepo] {
          policies.append(
            contentsOf: HubPolicy.parseManifestEntries(
              manifestJSON: officialData,
              repo: DuckConstants.officialPolicySetRepo,
              likes: 100
            )
          )
        }
        for repo in candidateRepos {
          if let manifestData = manifests[repo] {
            policies.append(
              contentsOf: HubPolicy.parseManifestEntries(
                manifestJSON: manifestData,
                repo: repo,
                likes: likesByRepo[repo] ?? 0,
                videoURL: previewByRepo[repo]
              )
            )
          } else if isAuthorRepo.contains(repo), let onnxFiles = topLevelOnnxByRepo[repo], onnxFiles.count == 1 {
            let file = onnxFiles[0]
            let fallbackName = HubPolicy.stem(repo.split(separator: "/").dropFirst().first.map(String.init))
              .capitalized
            policies.append(
              HubPolicy(
                key: repo,
                repo: repo,
                file: file,
                name: fallbackName.isEmpty ? repo : fallbackName,
                description: "Personal ONNX policy in \(repo) (\(file)).",
                kind: "episodic",
                encoding: "constant",
                durationS: DuckConstants.defaultHoldSeconds,
                official: false,
                videoURL: previewByRepo[repo],
                likes: likesByRepo[repo] ?? 0
              )
            )
          }
        }

        let lowerUsername = session?.username.lowercased()
        policies.sort { lhs, rhs in
          let lhsMine = lowerUsername != nil && lhs.authorName.lowercased() == lowerUsername
          let rhsMine = lowerUsername != nil && rhs.authorName.lowercased() == lowerUsername
          if lhsMine != rhsMine { return lhsMine && !rhsMine }
          if lhs.official != rhs.official { return lhs.official && !rhs.official }
          if lhs.likes != rhs.likes { return lhs.likes > rhs.likes }
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return HubCatalogResult(policies: IdentifiedArray(uniqueElements: policies))
      } catch {
        return HubCatalogResult(warningMessage: "Could not load Hub tricks: \(error.localizedDescription)")
      }
    }
  }
}

extension HuggingFaceAuthClient: DependencyKey {
  private static let defaultsKey = "microduck.hf.session.v1"

  private static func lookupUsername(token: String) async throws -> String {
    if let oauthURL = URL(string: "\(DuckConstants.huggingFaceBaseURL)/oauth/userinfo") {
      var req = URLRequest(url: oauthURL)
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      req.timeoutInterval = 10
      if
        let (data, resp) = try? await URLSession.shared.data(for: req),
        let http = resp as? HTTPURLResponse,
        http.statusCode == 200,
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let handle = (json["preferred_username"] as? String) ?? (json["name"] as? String),
        !handle.isEmpty
      {
        return handle
      }
    }

    guard let whoamiURL = URL(string: "\(DuckConstants.huggingFaceBaseURL)/api/whoami-v2") else {
      throw RpcErrorPayload(code: -32020, message: "Invalid Hugging Face URL")
    }
    var req = URLRequest(url: whoamiURL)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.timeoutInterval = 10
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw RpcErrorPayload(code: -32021, message: "Hugging Face did not accept that token.")
    }
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    return (json?["name"] as? String) ?? "user"
  }

  public static var liveValue: HuggingFaceAuthClient {
    HuggingFaceAuthClient(
      loadSession: {
        let data = UserDefaults.microduckShared.data(forKey: defaultsKey)
          ?? UserDefaults.standard.data(forKey: defaultsKey)
        guard
          let data,
          let session = try? JSONDecoder().decode(HuggingFaceSession.self, from: data),
          session.isValid(at: Date())
        else {
          return nil
        }
        return session
      },
      saveSession: { session in
        if let data = try? JSONEncoder().encode(session) {
          UserDefaults.microduckShared.set(data, forKey: defaultsKey)
          UserDefaults.standard.set(data, forKey: defaultsKey)
          NotificationCenter.default.post(name: .microduckHuggingFaceSessionChanged, object: nil)
        }
      },
      clearSession: {
        UserDefaults.microduckShared.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        NotificationCenter.default.post(name: .microduckHuggingFaceSessionChanged, object: nil)
      },
      resolveUsername: { token in
        try await lookupUsername(token: token)
      },
      startDeviceLogin: {
        guard let url = URL(string: "\(DuckConstants.huggingFaceBaseURL)/oauth/device") else {
          throw RpcErrorPayload(code: -32026, message: "Invalid Hugging Face device URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
          URLQueryItem(name: "client_id", value: DuckConstants.huggingFaceDeviceClientID)
        ]
        req.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        req.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: req)
        guard
          let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let deviceCode = json["device_code"] as? String,
          let userCode = json["user_code"] as? String
        else {
          throw RpcErrorPayload(code: -32027, message: "Could not start Hugging Face device login.")
        }
        let verificationURI = (json["verification_uri"] as? String) ?? "https://hf.co/oauth/device"
        let expiresIn = (json["expires_in"] as? Int) ?? 300
        let interval = max(2, (json["interval"] as? Int) ?? 5)
        return HuggingFaceDeviceCode(
          deviceCode: deviceCode,
          userCode: userCode,
          verificationURI: verificationURI,
          expiresIn: expiresIn,
          interval: interval
        )
      },
      awaitDeviceLogin: { code in
        guard let tokenURL = URL(string: "\(DuckConstants.huggingFaceBaseURL)/oauth/token") else {
          throw RpcErrorPayload(code: -32028, message: "Invalid Hugging Face token URL")
        }
        var pollSeconds = Double(max(2, code.interval))
        let deadline = Date().addingTimeInterval(Double(code.expiresIn))

        while Date() < deadline {
          try Task.checkCancellation()
          try await Task.sleep(for: .seconds(pollSeconds))
          try Task.checkCancellation()

          var req = URLRequest(url: tokenURL)
          req.httpMethod = "POST"
          req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
          var body = URLComponents()
          body.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
            URLQueryItem(name: "client_id", value: DuckConstants.huggingFaceDeviceClientID),
            URLQueryItem(name: "device_code", value: code.deviceCode),
          ]
          req.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
          req.timeoutInterval = 12

          guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            continue
          }
          if let http = resp as? HTTPURLResponse, http.statusCode >= 500 {
            continue
          }
          guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            continue
          }

          if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
            let expiresIn = (json["expires_in"] as? Double) ?? 86400
            let username = (try? await lookupUsername(token: accessToken)) ?? "user"
            return HuggingFaceSession(
              token: accessToken,
              username: username,
              expiresAt: Date().addingTimeInterval(expiresIn)
            )
          }

          if let err = json["error"] as? String {
            switch err {
            case "authorization_pending":
              continue
            case "slow_down":
              pollSeconds += 5
            case "expired_token":
              throw RpcErrorPayload(code: -32029, message: "Code expired before approval. Tap Sign In to try again.")
            case "access_denied":
              throw RpcErrorPayload(code: -32029, message: "Sign-in was declined on Hugging Face.")
            default:
              let desc = (json["error_description"] as? String) ?? err
              throw RpcErrorPayload(code: -32029, message: desc)
            }
          }
        }
        throw RpcErrorPayload(code: -32029, message: "Sign-in code expired. Please try again.")
      },
      signInWithPKCE: { clientID in
        try await HuggingFacePKCECoordinator.shared.signIn(clientID: clientID)
      }
    )
  }
}

@MainActor
private final class HuggingFacePKCECoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let shared = HuggingFacePKCECoordinator()

  func signIn(clientID: String) async throws -> HuggingFaceSession {
    let verifierData = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    let verifier = verifierData.base64URLEncoded()
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    let state = UUID().uuidString
    let redirectURI = "microduckremote://oauth/callback"

    var components = URLComponents(string: "https://huggingface.co/oauth/authorize")!
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "scope", value: "openid profile"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    guard let authURL = components.url else {
      throw RpcErrorPayload(code: -32022, message: "Could not build OAuth URL")
    }

    let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: authURL,
        callbackURLScheme: "microduckremote"
      ) { url, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let url {
          continuation.resume(returning: url)
        } else {
          continuation.resume(throwing: RpcErrorPayload(code: -32023, message: "Sign-in cancelled"))
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      session.start()
    }

    let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let code = query.first(where: { $0.name == "code" })?.value else {
      throw RpcErrorPayload(code: -32024, message: "Missing authorization code from Hugging Face")
    }

    var tokenRequest = URLRequest(url: URL(string: "https://huggingface.co/oauth/token")!)
    tokenRequest.httpMethod = "POST"
    tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var bodyComponents = URLComponents()
    bodyComponents.queryItems = [
      URLQueryItem(name: "grant_type", value: "authorization_code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "code", value: code),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "code_verifier", value: verifier),
    ]
    tokenRequest.httpBody = Data((bodyComponents.percentEncodedQuery ?? "").utf8)

    let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenRequest)
    guard let http = tokenResp as? HTTPURLResponse, http.statusCode == 200,
      let tokenJSON = (try? JSONSerialization.jsonObject(with: tokenData)) as? [String: Any],
      let accessToken = tokenJSON["access_token"] as? String
    else {
      throw RpcErrorPayload(code: -32025, message: "OAuth token exchange failed")
    }

    let expiresIn = (tokenJSON["expires_in"] as? Double) ?? 86400
    let username = (try? await HuggingFaceAuthClient.liveValue.resolveUsername(accessToken)) ?? "user"
    return HuggingFaceSession(
      token: accessToken,
      username: username,
      expiresAt: Date().addingTimeInterval(expiresIn)
    )
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    #if canImport(UIKit)
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
      return window
    }
    return ASPresentationAnchor()
    #else
    return ASPresentationAnchor()
    #endif
  }
}

extension Data {
  fileprivate func base64URLEncoded() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

extension HapticsClient: DependencyKey {
  public static var liveValue: HapticsClient {
    #if canImport(UIKit)
    HapticsClient(
      impactLight: {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      },
      impactMedium: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      },
      selectionChanged: {
        UISelectionFeedbackGenerator().selectionChanged()
      },
      success: {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      },
      warning: {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
      }
    )
    #else
    previewValue
    #endif
  }
}

extension GamepadClient: DependencyKey {
  public static var liveValue: GamepadClient {
    GamepadClient {
      AsyncStream { continuation in
        let emitCurrent: @Sendable () -> Void = {
          guard let controller = GCController.controllers().first,
            let pad = controller.extendedGamepad
          else {
            continuation.yield(GamepadInputState())
            return
          }
          continuation.yield(
            GamepadInputState(
              controllerName: controller.vendorName ?? "Controller",
              leftX: Double(pad.leftThumbstick.xAxis.value),
              leftY: Double(pad.leftThumbstick.yAxis.value),
              rightX: Double(pad.rightThumbstick.xAxis.value),
              buttonAPressed: pad.buttonA.isPressed,
              buttonBPressed: pad.buttonB.isPressed
            )
          )
        }

        let wireController: @Sendable (GCController) -> Void = { controller in
          controller.extendedGamepad?.valueChangedHandler = { _, _ in
            emitCurrent()
          }
          emitCurrent()
        }

        for controller in GCController.controllers() {
          wireController(controller)
        }
        emitCurrent()

        let watchTask = Task {
          await withTaskGroup(of: Void.self) { group in
            group.addTask {
              for await note in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                if let controller = note.object as? GCController {
                  wireController(controller)
                }
              }
            }
            group.addTask {
              for await _ in NotificationCenter.default.notifications(named: .GCControllerDidDisconnect) {
                emitCurrent()
              }
            }
          }
        }

        continuation.onTermination = { _ in
          watchTask.cancel()
        }
      }
    }
  }
}
