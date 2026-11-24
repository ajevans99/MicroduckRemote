import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import IdentifiedCollections
import IssueReporting
@preconcurrency import WebRTC

@MainActor
final class LiveDuckSessionEngine: NSObject {
  static let shared = LiveDuckSessionEngine()

  private let factory: RTCPeerConnectionFactory
  private var snapshot = DuckSessionSnapshot()
  private var subscribers: [UUID: AsyncStream<DuckSessionSnapshot>.Continuation] = [:]

  private var webSocketTask: URLSessionWebSocketTask?
  private var sseTask: Task<Void, Never>?
  private var receiveLoopTask: Task<Void, Never>?
  private var healthLoopTask: Task<Void, Never>?
  private var statsLoopTask: Task<Void, Never>?

  private var peerConnection: RTCPeerConnection?
  private var controlChannel: RTCDataChannel?
  private var sessionID: String?
  private var startingSession = false
  private var wantedConnection = false
  private var isSessionBootstrapReady = false
  private var isForegroundActive = false
  private var headlessIdleTask: Task<Void, Never>?
  private var mintedRelayServers: [RTCIceServer] = []

  private var nextRequestID: UInt64 = 1
  private var pendingCalls: [UInt64: CheckedContinuation<Data, any Error>] = [:]
  private var quietIDs: Set<UInt64> = []
  private var loopSampleCounter = 0

  private var previousBytesReceived: UInt64 = 0
  private var previousStatsTimestampUs: Double = 0
  private var previousPacketsReceived: UInt64 = 0
  private var previousPacketsLost: Int64 = 0

  override init() {
    RTCInitializeSSL()
    let encoderFactory = RTCDefaultVideoEncoderFactory()
    let decoderFactory = RTCDefaultVideoDecoderFactory()
    factory = RTCPeerConnectionFactory(
      encoderFactory: encoderFactory,
      decoderFactory: decoderFactory
    )
    super.init()
  }

  func currentSnapshot() -> DuckSessionSnapshot {
    snapshot
  }

  func snapshotsStream() -> AsyncStream<DuckSessionSnapshot> {
    let id = UUID()
    let initial = snapshot
    return AsyncStream { continuation in
      subscribers[id] = continuation
      continuation.yield(initial)
      continuation.onTermination = { _ in
        Task { @MainActor in
          LiveDuckSessionEngine.shared.removeSubscriber(id)
        }
      }
    }
  }

  private func removeSubscriber(_ id: UUID) {
    subscribers.removeValue(forKey: id)
  }

  private func broadcast() {
    let current = snapshot
    for continuation in subscribers.values {
      continuation.yield(current)
    }
    @Dependency(\.duckSharedState) var duckSharedState
    @Dependency(\.date.now) var now
    duckSharedState.publishSummary(DuckSharedSummary(snapshot: current, updatedAt: now))
  }

  func setForegroundActive(_ active: Bool) {
    isForegroundActive = active
    if active {
      headlessIdleTask?.cancel()
      headlessIdleTask = nil
    } else if wantedConnection || snapshot.controlOpen {
      armHeadlessIdleDisconnect()
    }
  }

  private func armHeadlessIdleDisconnect() {
    guard !isForegroundActive else { return }
    headlessIdleTask?.cancel()
    headlessIdleTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(DuckConstants.headlessIdleTimeoutSeconds))
      guard let self, !Task.isCancelled, !self.isForegroundActive else { return }
      self.appendLog(.info, "Releasing background WebRTC slot after idle timeout.")
      await self.disconnect()
    }
  }

  private func persistConnectionPreference(for target: ConnectionTarget) {
    @Dependency(\.connectionPreferences) var connectionPreferences
    switch target {
    case let .localSimulator(url):
      connectionPreferences.savePreference(.localSimulator(url: url))
    case let .rendezvous(serverURL, _, _, preferredPeerID):
      connectionPreferences.savePreference(
        .rendezvous(serverURL: serverURL, preferredPeerID: preferredPeerID)
      )
    }
  }

  func ensureConnected(timeout: Duration) async throws -> DuckIdentity {
    armHeadlessIdleDisconnect()

    if snapshot.controlOpen, isSessionBootstrapReady, let identity = snapshot.phase.connected {
      return identity
    }

    if !wantedConnection || snapshot.phase.is(\.disconnected) || snapshot.phase.is(\.failed) {
      @Dependency(\.connectionPreferences) var connectionPreferences
      @Dependency(\.huggingFaceAuth) var huggingFaceAuth
      #if targetEnvironment(simulator)
      let runningInSimulator = true
      #else
      let runningInSimulator = false
      #endif
      let target = try ConnectionPreferencesClient.resolveColdStartTarget(
        preference: connectionPreferences.loadPreference(),
        huggingFaceSession: huggingFaceAuth.loadSession(),
        isSimulator: runningInSimulator
      )
      await connect(target: target)
    }

    return try await withThrowingTaskGroup(of: DuckIdentity.self) { group in
      group.addTask {
        try await self.awaitBootstrapIdentity()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw DuckSessionError.connectionTimedOut
      }
      guard let identity = try await group.next() else {
        throw DuckSessionError.connectionTimedOut
      }
      group.cancelAll()
      self.armHeadlessIdleDisconnect()
      return identity
    }
  }

  private func awaitBootstrapIdentity() async throws -> DuckIdentity {
    let stream = snapshotsStream()
    for await updated in stream {
      if updated.controlOpen, isSessionBootstrapReady, let identity = updated.phase.connected {
        return identity
      }
      if case let .failed(reason) = updated.phase {
        throw DuckSessionError.connectionFailed(reason)
      }
    }
    throw DuckSessionError.connectionTimedOut
  }

  private func appendLog(_ level: RpcLogEntry.Level, _ message: String) {
    snapshot.logs.append(RpcLogEntry(level: level, message: message))
    if snapshot.logs.count > 200 {
      snapshot.logs.removeFirst(snapshot.logs.count - 200)
    }
    broadcast()
  }

  func connect(target: ConnectionTarget) async {
    await teardown(resetTarget: false)
    persistConnectionPreference(for: target)
    snapshot.target = target
    snapshot.phase = .connecting(step: "Opening signalling…")
    snapshot.apiSkewWarning = nil
    wantedConnection = true
    armHeadlessIdleDisconnect()
    broadcast()

    switch target {
    case let .localSimulator(urlString):
      await connectLocalWebSocket(urlString: urlString)
    case let .rendezvous(serverURL, token, _, _):
      await connectRendezvous(serverURL: serverURL, token: token)
    }
  }

  func disconnect() async {
    headlessIdleTask?.cancel()
    headlessIdleTask = nil
    if let sessionID {
      await sendSignalling(.endSession(sessionId: sessionID))
    }
    await teardown(resetTarget: false)
    snapshot.phase = .disconnected
    broadcast()
  }

  func selectDuck(peerID: String) async {
    guard wantedConnection else { return }
    if let currentSession = sessionID {
      await sendSignalling(.endSession(sessionId: currentSession))
      closePeerConnection()
    }
    if case let .rendezvous(serverURL, token, username, _) = snapshot.target {
      let updatedTarget = ConnectionTarget.rendezvous(
        serverURL: serverURL,
        token: token,
        username: username,
        preferredPeerID: peerID
      )
      snapshot.target = updatedTarget
      persistConnectionPreference(for: updatedTarget)
    }
    startingSession = true
    snapshot.phase = .connecting(step: "Requesting duck session…")
    broadcast()
    await sendSignalling(.startSession(peerId: peerID))
  }

  private func teardown(resetTarget: Bool) async {
    wantedConnection = false
    startingSession = false
    isSessionBootstrapReady = false
    sessionID = nil

    receiveLoopTask?.cancel()
    receiveLoopTask = nil
    sseTask?.cancel()
    sseTask = nil
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil

    stopTelemetryLoops()
    closePeerConnection()

    snapshot.controlOpen = false
    snapshot.hasVideoTrack = false
    snapshot.linkStats = LinkStats()
    if resetTarget {
      snapshot.target = .localSimulator(url: DuckConstants.defaultLocalSignallingURL)
    }
  }

  private func closePeerConnection() {
    controlChannel?.delegate = nil
    controlChannel?.close()
    controlChannel = nil
    peerConnection?.delegate = nil
    peerConnection?.close()
    peerConnection = nil
    VideoTrackRegistry.shared.currentTrack = nil
    isSessionBootstrapReady = false
    snapshot.controlOpen = false
    snapshot.hasVideoTrack = false
    failAllPendingCalls(reason: "Control channel closed")
  }

  private func failAllPendingCalls(reason: String) {
    let error = RpcErrorPayload(code: -32000, message: reason)
    for (_, continuation) in pendingCalls {
      continuation.resume(throwing: error)
    }
    pendingCalls.removeAll()
    quietIDs.removeAll()
  }

  private func connectLocalWebSocket(urlString: String) async {
    guard let url = URL(string: urlString) else {
      snapshot.phase = .failed("Invalid signalling URL: \(urlString)")
      broadcast()
      return
    }
    appendLog(.info, "Connecting to local signaller \(urlString)")
    let task = URLSession.shared.webSocketTask(with: url)
    webSocketTask = task
    task.resume()

    receiveLoopTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          let message = try await task.receive()
          switch message {
          case let .string(text):
            await handleSignallingText(text)
          case let .data(data):
            if let text = String(data: data, encoding: .utf8) {
              await handleSignallingText(text)
            }
          @unknown default:
            break
          }
        } catch {
          if !Task.isCancelled, wantedConnection {
            let reason = "Could not reach \(urlString). Ensure DUCK_SIM_CAMERAS=a scripts/duck-sim is running."
            appendLog(.error, reason)
            await teardown(resetTarget: false)
            snapshot.phase = .failed(reason)
            broadcast()
          }
          break
        }
      }
    }
  }

  private func connectRendezvous(serverURL: String, token: String) async {
    let trimmedBase = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    snapshot.phase = .connecting(step: "Minting TURN relays…")
    broadcast()
    mintedRelayServers = await fetchTurnServers(token: token)

    guard let eventsURL = URL(string: "\(trimmedBase)/events") else {
      snapshot.phase = .failed("Invalid rendezvous URL")
      broadcast()
      return
    }

    snapshot.phase = .connecting(step: "Opening Rendezvous stream…")
    broadcast()

    sseTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var request = URLRequest(url: eventsURL)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
      request.timeoutInterval = 3600

      do {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
          let msg = http.statusCode == 401
            ? "Hugging Face rejected this token (HTTP 401)."
            : "Rendezvous returned HTTP \(http.statusCode)."
          await teardown(resetTarget: false)
          snapshot.phase = .failed(msg)
          broadcast()
          return
        }

        var parser = SseStreamParser()
        var chunkBuffer: [UInt8] = []
        for try await byte in bytes {
          if Task.isCancelled { break }
          chunkBuffer.append(byte)
          if byte == 0x0A, chunkBuffer.count >= 2 {
            let text = String(decoding: chunkBuffer, as: UTF8.self)
            chunkBuffer.removeAll(keepingCapacity: true)
            for payload in parser.ingest(text) {
              await handleSignallingText(payload)
            }
          }
        }
      } catch {
        if !Task.isCancelled, wantedConnection {
          let msg = "Rendezvous stream disconnected: \(error.localizedDescription)"
          appendLog(.error, msg)
          await teardown(resetTarget: false)
          snapshot.phase = .failed(msg)
          broadcast()
        }
      }
    }
  }

  private func fetchTurnServers(token: String) async -> [RTCIceServer] {
    guard let url = URL(string: "\(DuckConstants.defaultTurnCredentialsURL)?ttl=600") else {
      return []
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 8
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        return []
      }
      let decoded = try JSONDecoder().decode(TurnCredentialsResponse.self, from: data)
      return decoded.iceServers.compactMap { entry in
        guard let username = entry.username, let credential = entry.credential, !entry.urls.isEmpty else {
          return nil
        }
        return RTCIceServer(urlStrings: entry.urls, username: username, credential: credential)
      }
    } catch {
      return []
    }
  }

  private func sendSignalling(_ outbound: SignallingOutbound) async {
    guard let data = try? outbound.encodedJSON(), let text = String(data: data, encoding: .utf8) else {
      return
    }
    appendLog(.outbound, "sig → \(text.prefix(240))")

    switch snapshot.target {
    case .localSimulator:
      try? await webSocketTask?.send(.string(text))
    case let .rendezvous(serverURL, token, _, _):
      let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      guard let sendURL = URL(string: "\(trimmed)/send") else { return }
      var request = URLRequest(url: sendURL)
      request.httpMethod = "POST"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = data
      do {
        let (replyData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
          return
        }
        if
          let json = (try? JSONSerialization.jsonObject(with: replyData)) as? [String: Any],
          json["type"] is String,
          let replyText = String(data: replyData, encoding: .utf8)
        {
          await handleSignallingText(replyText)
        }
      } catch {
        appendLog(.error, "POST /send failed: \(error.localizedDescription)")
      }
    }
  }

  private func handleSignallingText(_ text: String) async {
    guard let message = try? SignallingInbound.decode(from: text) else {
      return
    }
    if !message.is(\.peerStatusChanged) {
      appendLog(.inbound, "sig ← \(text.prefix(240))")
    }

    switch message {
    case .welcome:
      snapshot.phase = .connecting(step: "Discovering ducks…")
      broadcast()
      await sendSignalling(.list)

    case let .list(producers):
      let filtered: [ProducerInfo]
      if snapshot.target.isRemote {
        filtered = producers.filter { $0.meta?.kind == DuckConstants.robotKind }
      } else {
        filtered = producers
      }
      snapshot.availableDucks = IdentifiedArray(uniqueElements: filtered)

      guard !filtered.isEmpty else {
        let msg = snapshot.target.isRemote
          ? "No duck registered on this Hugging Face account yet."
          : "mediad has no active camera producer yet."
        snapshot.phase = .failed(msg)
        broadcast()
        return
      }

      guard sessionID == nil, !startingSession, wantedConnection else {
        broadcast()
        return
      }

      let preferredID: String?
      if case let .rendezvous(_, _, _, preferred) = snapshot.target {
        preferredID = preferred
      } else {
        preferredID = nil
      }
      let chosen = filtered.first { $0.id == preferredID } ?? filtered[0]
      startingSession = true
      let identity = DuckIdentity(
        peerID: chosen.id,
        name: chosen.displayName,
        release: chosen.meta?.release,
        apiVersion: chosen.meta?.apiVersion,
        isSimulated: chosen.isSimulated
      )
      snapshot.phase = .connecting(step: "Connecting to \(identity.name)…")
      broadcast()
      await sendSignalling(.startSession(peerId: chosen.id))

    case let .sessionStarted(newSessionID):
      startingSession = false
      sessionID = newSessionID
      snapshot.phase = .connecting(step: "Negotiating WebRTC…")
      broadcast()
      createPeerConnection()

    case let .peerSdp(_, sdp):
      guard let pc = peerConnection else { return }
      let rtcType: RTCSdpType = sdp.type == "answer" ? .answer : .offer
      let remoteDesc = RTCSessionDescription(type: rtcType, sdp: sdp.sdp)
      do {
        try await setRemoteDescription(remoteDesc, on: pc)
        if rtcType == .offer {
          let answer = try await createAnswer(on: pc)
          try await setLocalDescription(answer, on: pc)
          if let sessionID {
            await sendSignalling(.peerSdp(sessionId: sessionID, sdp: SdpPayload(type: "answer", sdp: answer.sdp)))
          }
        }
      } catch {
        appendLog(.error, "WebRTC SDP negotiation failed: \(error.localizedDescription)")
      }

    case let .peerIce(_, ice):
      guard let pc = peerConnection else { return }
      let candidate = RTCIceCandidate(
        sdp: ice.candidate,
        sdpMLineIndex: ice.sdpMLineIndex,
        sdpMid: nil
      )
      try? await addIceCandidate(candidate, on: pc)

    case let .endSession(_, reason):
      appendLog(.warning, "Session ended by duck\(reason.map { ": \($0)" } ?? "")")
      sessionID = nil
      startingSession = false
      wantedConnection = false
      stopTelemetryLoops()
      closePeerConnection()
      snapshot.phase = .disconnected
      broadcast()

    case let .sessionRejected(reason, activeApp):
      startingSession = false
      let detail = activeApp.map { " (\($0) is connected)" } ?? ""
      let msg = reason == "robot_busy"
        ? "Duck is busy\(detail). Disconnect the other console first."
        : "Duck refused session (\(reason ?? "rejected"))\(detail)."
      snapshot.phase = .failed(msg)
      broadcast()

    case .peerStatusChanged:
      if snapshot.target.isRemote {
        await sendSignalling(.list)
      }

    case let .error(details):
      snapshot.phase = .failed(details)
      broadcast()

    case .unknown:
      break
    }
  }

  private func createPeerConnection() {
    closePeerConnection()
    let config = RTCConfiguration()
    config.sdpSemantics = .unifiedPlan
    if snapshot.target.isRemote {
      config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])] + mintedRelayServers
    } else {
      config.iceServers = []
    }
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    peerConnection = factory.peerConnection(
      with: config,
      constraints: constraints,
      delegate: self
    )
  }

  private func setRemoteDescription(_ desc: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      pc.setRemoteDescription(desc) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func setLocalDescription(_ desc: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      pc.setLocalDescription(desc) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func createAnswer(on pc: RTCPeerConnection) async throws -> RTCSessionDescription {
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, any Error>) in
      pc.answer(for: constraints) { sdp, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let sdp {
          continuation.resume(returning: sdp)
        } else {
          continuation.resume(throwing: RpcErrorPayload(code: -32001, message: "Empty SDP answer"))
        }
      }
    }
  }

  private func addIceCandidate(_ candidate: RTCIceCandidate, on pc: RTCPeerConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      pc.add(candidate) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func onControlChannelOpened() async {
    snapshot.controlOpen = true
    isSessionBootstrapReady = false
    let chosenProducer = snapshot.availableDucks.first
    snapshot.phase = .connected(
      DuckIdentity(
        peerID: chosenProducer?.id ?? "local",
        name: chosenProducer?.displayName ?? "Microduck",
        release: chosenProducer?.meta?.release,
        apiVersion: chosenProducer?.meta?.apiVersion,
        isSimulated: chosenProducer?.isSimulated ?? false
      )
    )
    broadcast()

    await identifyDuck()
    if let video: VideoInfoFrame = try? await callRPC("media.video", params: EmptyParams(), quiet: true) {
      snapshot.videoInfo = video
    }
    _ = try? await callRPC("robot.subscribe", params: RobotSubscribeParams(hz: 10), quiet: true) as IntentResult
    await refreshSkillsAndPolicies()
    await pollHealthAndMode()
    isSessionBootstrapReady = snapshot.controlOpen
    startTelemetryLoops()
    armHeadlessIdleDisconnect()
    broadcast()
  }

  private func identifyDuck() async {
    var currentIdentity: DuckIdentity
    if case let .connected(existing) = snapshot.phase {
      currentIdentity = existing
    } else {
      currentIdentity = DuckIdentity(peerID: "duck", name: "Microduck")
    }

    if let hello: HelloResult = try? await callRPC("hello", params: HelloParams(), quiet: true) {
      currentIdentity.apiVersion = hello.apiVersion
      if let daemonVersion = hello.daemonVersion {
        if let rev = hello.revision {
          currentIdentity.release = "\(daemonVersion) (\(rev.prefix(7)))"
        } else {
          currentIdentity.release = daemonVersion
        }
      }
      if hello.apiVersion != DuckConstants.apiVersion {
        snapshot.apiSkewWarning = "App speaks API v\(DuckConstants.apiVersion), duck speaks v\(hello.apiVersion)."
      }
    }

    if let info: SystemInfoResult = try? await callRPC("system.info", params: EmptyParams(), quiet: true) {
      if let name = info.name, !name.isEmpty {
        currentIdentity.name = name
      }
      currentIdentity.serial = info.serial
      if let sim = info.simulated {
        currentIdentity.isSimulated = sim
      } else if info.serial?.hasPrefix("sim-") == true {
        currentIdentity.isSimulated = true
      }
    }

    snapshot.phase = .connected(currentIdentity)
    broadcast()
  }

  private func startTelemetryLoops() {
    stopTelemetryLoops()

    healthLoopTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard let self, !Task.isCancelled else { break }
        await pollHealthAndMode()
      }
    }

    statsLoopTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self, !Task.isCancelled else { break }
        await pollWebRTCStats()
      }
    }
  }

  private func stopTelemetryLoops() {
    healthLoopTask?.cancel()
    healthLoopTask = nil
    statsLoopTask?.cancel()
    statsLoopTask = nil
    previousBytesReceived = 0
    previousStatsTimestampUs = 0
  }

  private func pollHealthAndMode() async {
    guard snapshot.controlOpen else { return }
    if let modeRes: RobotModeResult = try? await callRPC("robot.mode", params: EmptyParams(), quiet: true) {
      snapshot.mode = modeRes.mode
    }
    if let healthRes: RobotHealthResult = try? await callRPC("robot.health", params: EmptyParams(), quiet: true) {
      snapshot.health = healthRes
    }
    broadcast()
  }

  private func pollWebRTCStats() async {
    guard let pc = peerConnection else { return }
    let report = await pc.statistics()
    var stats = snapshot.linkStats

    for (_, entry) in report.statistics {
      if entry.type == "inbound-rtp", (entry.values["kind"] as? String) == "video" {
        if let fpsNum = entry.values["framesPerSecond"] as? NSNumber {
          stats.fps = Int(fpsNum.doubleValue.rounded())
        }
        let bytes = (entry.values["bytesReceived"] as? NSNumber)?.uint64Value ?? 0
        let packetsReceived = (entry.values["packetsReceived"] as? NSNumber)?.uint64Value ?? 0
        let packetsLost = (entry.values["packetsLost"] as? NSNumber)?.int64Value ?? 0
        let tsUs = entry.timestamp_us
        if previousStatsTimestampUs > 0, tsUs > previousStatsTimestampUs, bytes >= previousBytesReceived {
          let elapsedSeconds = (tsUs - previousStatsTimestampUs) / 1_000_000.0
          if elapsedSeconds > 0 {
            let bits = Double(bytes - previousBytesReceived) * 8.0
            stats.bitrateKbps = Int((bits / elapsedSeconds / 1000.0).rounded())
          }
          let deltaGot = Int64(packetsReceived - previousPacketsReceived)
          let deltaLost = max(0, packetsLost - previousPacketsLost)
          let total = deltaGot + deltaLost
          if total > 0 {
            stats.packetLossPercent = (Double(deltaLost) * 100.0) / Double(total)
          }
        }
        previousBytesReceived = bytes
        previousStatsTimestampUs = tsUs
        previousPacketsReceived = packetsReceived
        previousPacketsLost = packetsLost
      } else if entry.type == "candidate-pair", (entry.values["nominated"] as? NSNumber)?.boolValue == true {
        if let rttSeconds = (entry.values["currentRoundTripTime"] as? NSNumber)?.doubleValue {
          stats.rttMs = Int((rttSeconds * 1000.0).rounded())
        }
      }
    }

    snapshot.linkStats = stats
    broadcast()
  }

  func refreshSkillsAndPolicies() async {
    guard snapshot.controlOpen else { return }
    if let pol: RobotPoliciesResult = try? await callRPC("robot.policies", params: EmptyParams(), quiet: true) {
      snapshot.policies = pol
    }
    if let skillsResult: RobotSkillsResult = try? await callRPC("robot.skills", params: EmptyParams(), quiet: true) {
      snapshot.installedSkills = IdentifiedArray(uniqueElements: skillsResult.skills)
    } else if let names = snapshot.policies?.skills {
      let summaries = names.map { SkillSummary(name: $0) }
      snapshot.installedSkills = IdentifiedArray(uniqueElements: summaries)
    }
    broadcast()
  }

  func sendFireAndForget<Params: Encodable & Sendable>(_ method: String, params: Params) {
    guard let channel = controlChannel, channel.readyState == .open else { return }
    armHeadlessIdleDisconnect()
    let id = nextRequestID
    nextRequestID += 1
    quietIDs.insert(id)
    let req = RpcRequest(id: id, method: method, params: params)
    guard let data = try? JSONEncoder().encode(req) else { return }
    let buffer = RTCDataBuffer(data: data, isBinary: false)
    channel.sendData(buffer)
  }

  func callRPC<Params: Encodable & Sendable, ResultType: Decodable & Sendable>(
    _ method: String,
    params: Params,
    quiet: Bool = false,
    timeoutSeconds: Double = 12
  ) async throws -> ResultType {
    guard let channel = controlChannel, channel.readyState == .open else {
      throw RpcErrorPayload(code: -32000, message: "Not connected to duck control channel.")
    }
    if !quiet {
      armHeadlessIdleDisconnect()
    }
    let id = nextRequestID
    nextRequestID += 1
    if quiet {
      quietIDs.insert(id)
    }
    let req = RpcRequest(id: id, method: method, params: params)
    let data = try JSONEncoder().encode(req)
    if !quiet, let text = String(data: data, encoding: .utf8) {
      appendLog(.outbound, "rpc → \(text.prefix(220))")
    }

    let rawResultData: Data = try await withCheckedThrowingContinuation { continuation in
      pendingCalls[id] = continuation
      let buffer = RTCDataBuffer(data: data, isBinary: false)
      if !channel.sendData(buffer) {
        pendingCalls.removeValue(forKey: id)
        quietIDs.remove(id)
        continuation.resume(throwing: RpcErrorPayload(code: -32002, message: "Failed to write to control channel"))
        return
      }
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(timeoutSeconds))
        guard let self, let pending = pendingCalls.removeValue(forKey: id) else { return }
        quietIDs.remove(id)
        pending.resume(throwing: RpcErrorPayload(code: -32003, message: "\(method) timed out after \(Int(timeoutSeconds))s"))
      }
    }

    return try JSONDecoder().decode(ResultType.self, from: rawResultData)
  }

  private func handleControlMessage(_ text: String) {
    guard let incoming = try? IncomingControlMessage.decode(from: text) else {
      appendLog(.error, "Unparseable control message: \(text.prefix(120))")
      return
    }

    switch incoming {
    case let .response(id, resultJSON):
      let isQuiet = quietIDs.remove(id) != nil
      if !isQuiet {
        appendLog(.inbound, "rpc ← #\(id) ok")
      }
      if let continuation = pendingCalls.removeValue(forKey: id) {
        continuation.resume(returning: resultJSON)
      }

    case let .errorResponse(id, error):
      quietIDs.remove(id)
      appendLog(.error, "rpc ← #\(id) error: \(error.message)")
      if let continuation = pendingCalls.removeValue(forKey: id) {
        continuation.resume(throwing: error)
      }

    case let .robotState(frame):
      snapshot.latestState = frame
      if let hz = frame.controlLoop?.hz {
        loopSampleCounter += 1
        snapshot.loopHistory.append(LoopSample(id: loopSampleCounter, timestamp: Date(), hz: hz))
        if snapshot.loopHistory.count > 60 {
          snapshot.loopHistory.removeFirst(snapshot.loopHistory.count - 60)
        }
      }
      broadcast()

    case let .videoInfo(info):
      snapshot.videoInfo = info
      broadcast()

    case let .detections(det):
      snapshot.detections = det
      broadcast()

    case let .tofFrame(tof):
      snapshot.tofFrame = tof
      broadcast()

    case .unhandledNotification:
      break
    }
  }

  func ensureIntentAccepted(_ result: IntentResult) throws {
    if !result.accepted {
      throw RpcErrorPayload(code: -32010, message: result.reason ?? "Duck refused command.")
    }
  }

  func waitForHome(timeoutSeconds: Double = 15) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      guard let policies: RobotPoliciesResult = try? await callRPC("robot.policies", params: EmptyParams(), quiet: true) else {
        return
      }
      snapshot.policies = policies
      guard let homed = policies.homed else { return }
      if homed { return }
      try? await Task.sleep(for: .milliseconds(450))
    }
  }

  func installAndRunPolicy(
    _ policy: HubPolicy,
    holdSeconds: Double,
    onStage: @Sendable (TrickInstallStage) -> Void
  ) async throws -> String {
    if let reason = policy.notATrickReason {
      throw RpcErrorPayload(code: -32011, message: reason)
    }

    onStage(.downloading)
    let fetched: PolicyFetchResult = try await callRPC(
      "policy.fetch",
      params: PolicyFetchParams(repo: policy.repo, file: policy.file),
      timeoutSeconds: 180
    )

    onStage(.installing)
    let skillParams = SetSkillParams.from(fetched: fetched, holdSeconds: holdSeconds)
    let setResult: IntentResult = try await callRPC("robot.setSkill", params: skillParams)
    try ensureIntentAccepted(setResult)

    let afterPolicies: RobotPoliciesResult = try await callRPC("robot.policies", params: EmptyParams(), quiet: true)
    snapshot.policies = afterPolicies
    if let changeError = afterPolicies.changeError, !changeError.isEmpty {
      throw RpcErrorPayload(code: -32012, message: changeError)
    }

    onStage(.waitingForStand)
    await waitForHome()
    await refreshSkillsAndPolicies()

    onStage(.performing)
    let doResult: IntentResult = try await callRPC("robot.do", params: RobotDoParams(skill: skillParams.name))
    try ensureIntentAccepted(doResult)
    return skillParams.name
  }

  func refreshMapData(resM: Double) async {
    if let status: MapStatusResult = try? await callRPC("map.status", params: EmptyParams(), quiet: true) {
      snapshot.mapStatus = status
    }
    if let grid: MapGridResult = try? await callRPC("map.grid", params: MapGridParams(resM: resM), quiet: true) {
      snapshot.mapGrid = grid
      broadcast()
    }
  }

  func wipeMapData() async throws {
    _ = try await callRPC("map.wipe", params: EmptyParams()) as EmptyParams
    snapshot.mapGrid = nil
    broadcast()
  }
}

extension LiveDuckSessionEngine: RTCPeerConnectionDelegate {
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    if let videoTrack = stream.videoTracks.first {
      Task { @MainActor in
        VideoTrackRegistry.shared.currentTrack = videoTrack
        LiveDuckSessionEngine.shared.snapshot.hasVideoTrack = true
        LiveDuckSessionEngine.shared.broadcast()
      }
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    let sdp = candidate.sdp
    let mLine = candidate.sdpMLineIndex
    Task { @MainActor in
      guard let sessionID = LiveDuckSessionEngine.shared.sessionID else { return }
      await LiveDuckSessionEngine.shared.sendSignalling(
        .peerIce(
          sessionId: sessionID,
          ice: IceCandidatePayload(candidate: sdp, sdpMLineIndex: mLine)
        )
      )
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    Task { @MainActor in
      let engine = LiveDuckSessionEngine.shared
      engine.controlChannel = dataChannel
      dataChannel.delegate = engine
      if dataChannel.readyState == .open {
        await engine.onControlChannelOpened()
      }
    }
  }

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didAdd rtpReceiver: RTCRtpReceiver,
    streams mediaStreams: [RTCMediaStream]
  ) {
    if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
      Task { @MainActor in
        VideoTrackRegistry.shared.currentTrack = videoTrack
        LiveDuckSessionEngine.shared.snapshot.hasVideoTrack = true
        LiveDuckSessionEngine.shared.broadcast()
      }
    }
  }
}

extension LiveDuckSessionEngine: RTCDataChannelDelegate {
  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    let state = dataChannel.readyState
    Task { @MainActor in
      let engine = LiveDuckSessionEngine.shared
      if state == .open {
        await engine.onControlChannelOpened()
      } else if state == .closed {
        engine.snapshot.controlOpen = false
        engine.stopTelemetryLoops()
        engine.broadcast()
      }
    }
  }

  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
    guard let text = String(data: buffer.data, encoding: .utf8) else { return }
    Task { @MainActor in
      LiveDuckSessionEngine.shared.handleControlMessage(text)
    }
  }
}

extension DuckSessionClient: DependencyKey {
  public static var liveValue: DuckSessionClient {
    DuckSessionClient(
      currentSnapshot: {
        await LiveDuckSessionEngine.shared.currentSnapshot()
      },
      snapshots: {
        MainActor.assumeIsolated {
          LiveDuckSessionEngine.shared.snapshotsStream()
        }
      },
      connect: { target in
        await LiveDuckSessionEngine.shared.connect(target: target)
      },
      disconnect: {
        await LiveDuckSessionEngine.shared.disconnect()
      },
      selectDuck: { peerID in
        await LiveDuckSessionEngine.shared.selectDuck(peerID: peerID)
      },
      sendMove: { move in
        await MainActor.run {
          LiveDuckSessionEngine.shared.sendFireAndForget("robot.move", params: move)
        }
      },
      sendLook: { look in
        try? await LiveDuckSessionEngine.shared.callRPC("robot.look", params: look, quiet: true)
      },
      setEnabled: { @MainActor on in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.enable",
          params: RobotEnableParams(on: on, toggle: false)
        )
        try engine.ensureIntentAccepted(res)
        await engine.refreshSkillsAndPolicies()
      },
      toggleEnable: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.enable",
          params: RobotEnableParams(on: true, toggle: true)
        )
        try engine.ensureIntentAccepted(res)
        await engine.refreshSkillsAndPolicies()
      },
      standBackUp: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        await engine.refreshSkillsAndPolicies()
        if engine.currentSnapshot().policies?.enabled == true {
          let offRes: IntentResult = try await engine.callRPC(
            "robot.enable",
            params: RobotEnableParams(on: false, toggle: false)
          )
          try engine.ensureIntentAccepted(offRes)
          try? await Task.sleep(for: .seconds(2))
        }
        let onRes: IntentResult = try await engine.callRPC(
          "robot.enable",
          params: RobotEnableParams(on: true, toggle: false)
        )
        try engine.ensureIntentAccepted(onRes)
        await engine.refreshSkillsAndPolicies()
      },
      stop: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC("robot.stop", params: EmptyParams())
        try engine.ensureIntentAccepted(res)
      },
      initPose: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC("robot.init", params: EmptyParams())
        try engine.ensureIntentAccepted(res)
      },
      relax: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC("robot.relax", params: EmptyParams())
        try engine.ensureIntentAccepted(res)
      },
      rebootMotors: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.rebootMotors",
          params: RobotRebootMotorsParams()
        )
        try engine.ensureIntentAccepted(res)
      },
      performSkill: { @MainActor skill in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC("robot.do", params: RobotDoParams(skill: skill))
        try engine.ensureIntentAccepted(res)
      },
      playSound: { @MainActor tag, hold in
        let engine = LiveDuckSessionEngine.shared
        _ = try? await engine.callRPC(
          "robot.sound",
          params: RobotSoundParams(tag: tag.rawValue, hold: hold),
          quiet: hold != nil
        ) as IntentResult
      },
      setAutonomous: { @MainActor on in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.autonomous",
          params: RobotActiveParams(active: on)
        )
        try engine.ensureIntentAccepted(res)
      },
      setFlashlight: { @MainActor on in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.flashlight",
          params: RobotFlashlightParams(on: on)
        )
        try engine.ensureIntentAccepted(res)
      },
      setFlashlightColor: { @MainActor on, color in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.flashlight",
          params: RobotFlashlightParams(on: on, color: color)
        )
        try engine.ensureIntentAccepted(res)
      },
      setLaserTrack: { @MainActor on in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.laserTrack",
          params: RobotActiveParams(active: on)
        )
        try engine.ensureIntentAccepted(res)
      },
      setSoccer: { @MainActor on in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC(
          "robot.soccer",
          params: RobotSoccerParams(active: on, autonomous: on)
        )
        try engine.ensureIntentAccepted(res)
      },
      subscribeTof: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        _ = try? await engine.callRPC("tof.stream", params: EmptyParams(), quiet: true) as IntentResult
      },
      refreshMap: { @MainActor resM in
        await LiveDuckSessionEngine.shared.refreshMapData(resM: resM)
      },
      wipeMap: { @MainActor in
        try await LiveDuckSessionEngine.shared.wipeMapData()
      },
      refreshSkills: { @MainActor in
        await LiveDuckSessionEngine.shared.refreshSkillsAndPolicies()
      },
      installPolicy: { @MainActor policy, holdSeconds, onStage in
        try await LiveDuckSessionEngine.shared.installAndRunPolicy(
          policy,
          holdSeconds: holdSeconds,
          onStage: onStage
        )
      },
      removeSkill: { @MainActor name in
        let engine = LiveDuckSessionEngine.shared
        let res: IntentResult = try await engine.callRPC("robot.removeSkill", params: RemoveSkillParams(name: name))
        try engine.ensureIntentAccepted(res)
        await engine.refreshSkillsAndPolicies()
      },
      ensureConnected: { timeout in
        try await LiveDuckSessionEngine.shared.ensureConnected(timeout: timeout)
      },
      setForegroundActive: { active in
        await MainActor.run {
          LiveDuckSessionEngine.shared.setForegroundActive(active)
        }
      },
      performMoveStep: { request in
        @Dependency(\.continuousClock) var clock
        return try await DuckMoveStepExecutor.execute(
          request: request,
          clock: clock,
          currentSnapshot: {
            await LiveDuckSessionEngine.shared.currentSnapshot()
          },
          subscribeTof: { @MainActor in
            let engine = LiveDuckSessionEngine.shared
            _ = try? await engine.callRPC("tof.stream", params: EmptyParams(), quiet: true) as IntentResult
          },
          sendMove: { move in
            await MainActor.run {
              LiveDuckSessionEngine.shared.sendFireAndForget("robot.move", params: move)
            }
          }
        )
      },
      capturePhoto: { @MainActor in
        let engine = LiveDuckSessionEngine.shared
        let videoInfo = engine.currentSnapshot().videoInfo
        return try await VideoTrackRegistry.shared.captureNextFrame(videoInfo: videoInfo)
      }
    )
  }
}
