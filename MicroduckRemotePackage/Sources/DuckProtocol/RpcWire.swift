import CasePaths
import Foundation

public struct RpcRequest<Params: Encodable & Sendable>: Encodable, Sendable {
  public let jsonrpc = "2.0"
  public let id: UInt64
  public let method: String
  public let params: Params

  public init(id: UInt64, method: String, params: Params) {
    self.id = id
    self.method = method
    self.params = params
  }
}

public struct EmptyParams: Codable, Equatable, Sendable {
  public init() {}
}

public struct RpcErrorPayload: Codable, Equatable, Error, LocalizedError, Sendable {
  public var code: Int
  public var message: String

  public init(code: Int, message: String) {
    self.code = code
    self.message = message
  }

  public var errorDescription: String? { message }
}

@CasePathable
@dynamicMemberLookup
public enum IncomingControlMessage: Equatable, Sendable {
  case response(id: UInt64, resultJSON: Data)
  case errorResponse(id: UInt64, error: RpcErrorPayload)
  case robotState(RobotStateFrame)
  case videoInfo(VideoInfoFrame)
  case detections(DetectionFrame)
  case tofFrame(TofFrame)
  case unhandledNotification(method: String)

  public static func decode(from text: String) throws -> IncomingControlMessage {
    let data = Data(text.utf8)
    let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let raw else {
      throw RpcErrorPayload(code: -32700, message: "Invalid JSON object on control channel")
    }

    let decoder = JSONDecoder()

    if let idNumber = raw["id"] as? NSNumber {
      let id = idNumber.uint64Value
      if let errorObj = raw["error"] {
        let errorData = try JSONSerialization.data(withJSONObject: errorObj)
        let rpcError = try decoder.decode(RpcErrorPayload.self, from: errorData)
        return .errorResponse(id: id, error: rpcError)
      }
      let resultObj = raw["result"] ?? [:]
      let resultData = try JSONSerialization.data(withJSONObject: resultObj)
      return .response(id: id, resultJSON: resultData)
    }

    let method = (raw["method"] as? String) ?? "unknown"
    let paramsObj = raw["params"] ?? [:]
    let paramsData = try JSONSerialization.data(withJSONObject: paramsObj)

    switch method {
    case "robot.state":
      return .robotState(try decoder.decode(RobotStateFrame.self, from: paramsData))
    case "media.video":
      return .videoInfo(try decoder.decode(VideoInfoFrame.self, from: paramsData))
    case "media.detections":
      return .detections(try decoder.decode(DetectionFrame.self, from: paramsData))
    case "tof.frame":
      return .tofFrame(try decoder.decode(TofFrame.self, from: paramsData))
    default:
      return .unhandledNotification(method: method)
    }
  }
}

public struct ProducerMeta: Codable, Equatable, Sendable {
  public var name: String?
  public var kind: String?
  public var release: String?
  public var serial: String?
  public var apiVersion: Int?
  public var simulated: Bool?

  enum CodingKeys: String, CodingKey {
    case name
    case kind
    case release
    case serial
    case apiVersion = "api_version"
    case simulated
  }

  public init(
    name: String? = nil,
    kind: String? = nil,
    release: String? = nil,
    serial: String? = nil,
    apiVersion: Int? = nil,
    simulated: Bool? = nil
  ) {
    self.name = name
    self.kind = kind
    self.release = release
    self.serial = serial
    self.apiVersion = apiVersion
    self.simulated = simulated
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    kind = try container.decodeIfPresent(String.self, forKey: .kind)
    release = try container.decodeIfPresent(String.self, forKey: .release)
    serial = try container.decodeIfPresent(String.self, forKey: .serial)

    if let intVal = try? container.decodeIfPresent(Int.self, forKey: .apiVersion) {
      apiVersion = intVal
    } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .apiVersion) {
      apiVersion = Int(strVal)
    } else {
      apiVersion = nil
    }

    if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .simulated) {
      simulated = boolVal
    } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .simulated) {
      simulated = (strVal == "true" || strVal == "1")
    } else {
      simulated = nil
    }
  }
}

public struct ProducerInfo: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var meta: ProducerMeta?
  public var busy: Bool?
  public var activeApp: String?

  public init(
    id: String,
    meta: ProducerMeta? = nil,
    busy: Bool? = nil,
    activeApp: String? = nil
  ) {
    self.id = id
    self.meta = meta
    self.busy = busy
    self.activeApp = activeApp
  }

  public var displayName: String {
    if let name = meta?.name, !name.isEmpty {
      return name
    }
    return String(id.prefix(8))
  }

  public var isSimulated: Bool {
    meta?.simulated == true
  }

  enum CodingKeys: String, CodingKey {
    case id
    case peerId
    case meta
    case busy
    case activeApp
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let directID = try container.decodeIfPresent(String.self, forKey: .id) {
      id = directID
    } else if let peerId = try container.decodeIfPresent(String.self, forKey: .peerId) {
      id = peerId
    } else {
      throw DecodingError.keyNotFound(
        CodingKeys.id,
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing producer id")
      )
    }
    meta = try container.decodeIfPresent(ProducerMeta.self, forKey: .meta)
    busy = try container.decodeIfPresent(Bool.self, forKey: .busy)
    activeApp = try container.decodeIfPresent(String.self, forKey: .activeApp)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(meta, forKey: .meta)
    try container.encodeIfPresent(busy, forKey: .busy)
    try container.encodeIfPresent(activeApp, forKey: .activeApp)
  }
}

public struct SdpPayload: Codable, Equatable, Sendable {
  public var type: String
  public var sdp: String

  public init(type: String, sdp: String) {
    self.type = type
    self.sdp = sdp
  }
}

public struct IceCandidatePayload: Codable, Equatable, Sendable {
  public var candidate: String
  public var sdpMLineIndex: Int32

  public var isEndOfCandidates: Bool {
    candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public init(candidate: String, sdpMLineIndex: Int32) {
    self.candidate = candidate
    self.sdpMLineIndex = sdpMLineIndex
  }
}

@CasePathable
public enum SignallingOutbound: Equatable, Sendable {
  case list
  case startSession(peerId: String)
  case endSession(sessionId: String)
  case peerSdp(sessionId: String, sdp: SdpPayload)
  case peerIce(sessionId: String, ice: IceCandidatePayload)

  public func encodedJSON() throws -> Data {
    let dict: [String: Any]
    switch self {
    case .list:
      dict = ["type": "list"]
    case let .startSession(peerId):
      dict = ["type": "startSession", "peerId": peerId]
    case let .endSession(sessionId):
      dict = ["type": "endSession", "sessionId": sessionId]
    case let .peerSdp(sessionId, sdp):
      dict = [
        "type": "peer",
        "sessionId": sessionId,
        "sdp": ["type": sdp.type, "sdp": sdp.sdp],
      ]
    case let .peerIce(sessionId, ice):
      dict = [
        "type": "peer",
        "sessionId": sessionId,
        "ice": ["candidate": ice.candidate, "sdpMLineIndex": ice.sdpMLineIndex],
      ]
    }
    return try JSONSerialization.data(withJSONObject: dict)
  }
}

@CasePathable
public enum SignallingInbound: Equatable, Sendable {
  case welcome(peerId: String?)
  case list([ProducerInfo])
  case sessionStarted(sessionId: String)
  case peerSdp(sessionId: String, sdp: SdpPayload)
  case peerIce(sessionId: String, ice: IceCandidatePayload)
  case endSession(sessionId: String?, reason: String?)
  case sessionRejected(reason: String?, activeApp: String?)
  case peerStatusChanged
  case error(details: String)
  case unknown(type: String)

  public static func decode(from text: String) throws -> SignallingInbound {
    let data = Data(text.utf8)
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw RpcErrorPayload(code: -32700, message: "Invalid signalling frame")
    }
    let type = (raw["type"] as? String) ?? ""
    let decoder = JSONDecoder()

    switch type {
    case "welcome":
      return .welcome(peerId: raw["peerId"] as? String)
    case "list":
      let arr = raw["producers"] ?? []
      let arrData = try JSONSerialization.data(withJSONObject: arr)
      return .list(try decoder.decode([ProducerInfo].self, from: arrData))
    case "sessionStarted":
      return .sessionStarted(sessionId: (raw["sessionId"] as? String) ?? "")
    case "peer":
      let sessionId = (raw["sessionId"] as? String) ?? ""
      if let sdpObj = raw["sdp"] {
        let sdpData = try JSONSerialization.data(withJSONObject: sdpObj)
        return .peerSdp(sessionId: sessionId, sdp: try decoder.decode(SdpPayload.self, from: sdpData))
      }
      if let iceObj = raw["ice"] {
        let iceData = try JSONSerialization.data(withJSONObject: iceObj)
        return .peerIce(sessionId: sessionId, ice: try decoder.decode(IceCandidatePayload.self, from: iceData))
      }
      return .unknown(type: "peer")
    case "endSession":
      return .endSession(sessionId: raw["sessionId"] as? String, reason: raw["reason"] as? String)
    case "sessionRejected":
      return .sessionRejected(reason: raw["reason"] as? String, activeApp: raw["activeApp"] as? String)
    case "peerStatusChanged":
      return .peerStatusChanged
    case "error":
      return .error(details: (raw["details"] as? String) ?? "Unknown signalling error")
    default:
      return .unknown(type: type)
    }
  }
}

public struct HelloParams: Codable, Equatable, Sendable {
  public var apiVersion: Int

  enum CodingKeys: String, CodingKey {
    case apiVersion = "api_version"
  }

  public init(apiVersion: Int = DuckConstants.apiVersion) {
    self.apiVersion = apiVersion
  }
}

public struct HelloResult: Codable, Equatable, Sendable {
  public var apiVersion: Int
  public var daemonVersion: String?
  public var revision: String?

  enum CodingKeys: String, CodingKey {
    case apiVersion = "api_version"
    case daemonVersion = "daemon_version"
    case revision
  }

  public init(apiVersion: Int, daemonVersion: String? = nil, revision: String? = nil) {
    self.apiVersion = apiVersion
    self.daemonVersion = daemonVersion
    self.revision = revision
  }
}

public struct SystemInfoResult: Codable, Equatable, Sendable {
  public var name: String?
  public var serial: String?
  public var simulated: Bool?
  public var board: String?

  public init(
    name: String? = nil,
    serial: String? = nil,
    simulated: Bool? = nil,
    board: String? = nil
  ) {
    self.name = name
    self.serial = serial
    self.simulated = simulated
    self.board = board
  }
}

public struct RobotMoveParams: Codable, Equatable, Sendable {
  public var vx: Double
  public var vy: Double
  public var vyaw: Double

  public init(vx: Double, vy: Double, vyaw: Double) {
    self.vx = vx
    self.vy = vy
    self.vyaw = vyaw
  }

  public static let zero = RobotMoveParams(vx: 0, vy: 0, vyaw: 0)
}

public struct RobotLookParams: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var z: Double
  public var neckPitch: Double

  enum CodingKeys: String, CodingKey {
    case x
    case y
    case z
    case neckPitch = "neck_pitch"
  }

  public init(x: Double, y: Double, z: Double, neckPitch: Double = 0) {
    self.x = x
    self.y = y
    self.z = z
    self.neckPitch = neckPitch
  }
}

public struct RobotLookResult: Codable, Equatable, Sendable {
  public var head: RobotHeadParams?
  public var accepted: Bool?
  public var clamped: Bool?
  public var reason: String?

  public init(
    head: RobotHeadParams? = nil,
    accepted: Bool? = true,
    clamped: Bool? = false,
    reason: String? = nil
  ) {
    self.head = head
    self.accepted = accepted
    self.clamped = clamped
    self.reason = reason
  }
}

public struct RobotMouthParams: Codable, Equatable, Sendable {
  public var open: Double

  public init(open: Double) {
    self.open = open
  }

  public static let closed = RobotMouthParams(open: 0.0)
  public static let wideOpen = RobotMouthParams(open: 1.0)

  public var clamped: RobotMouthParams {
    RobotMouthParams(open: min(max(open, 0.0), 1.0))
  }

  public static func fromPercent(_ percent: Double) -> RobotMouthParams {
    RobotMouthParams(open: min(max(percent, 0.0), 100.0) / 100.0)
  }
}

public struct RobotHeadParams: Codable, Equatable, Sendable {
  public var neckPitch: Double
  public var headPitch: Double
  public var headYaw: Double
  public var headRoll: Double
  public var alpha: Double?

  enum CodingKeys: String, CodingKey {
    case neckPitch = "neck_pitch"
    case headPitch = "head_pitch"
    case headYaw = "head_yaw"
    case headRoll = "head_roll"
    case alpha
  }

  public init(
    neckPitch: Double = 0,
    headPitch: Double = 0,
    headYaw: Double = 0,
    headRoll: Double = 0,
    alpha: Double? = nil
  ) {
    self.neckPitch = neckPitch
    self.headPitch = headPitch
    self.headYaw = headYaw
    self.headRoll = headRoll
    self.alpha = alpha
  }

  public static let neutral = RobotHeadParams()

  public var clamped: RobotHeadParams {
    RobotHeadParams(
      neckPitch: neckPitch,
      headPitch: headPitch,
      headYaw: headYaw,
      headRoll: min(max(headRoll, -DuckConstants.maxHeadRollRadians), DuckConstants.maxHeadRollRadians),
      alpha: alpha.map { min(max($0, 0.0), 1.0) }
    )
  }

  public static func rollRadians(tiltPercent: Double) -> Double {
    let clampedPercent = min(max(tiltPercent, -100.0), 100.0)
    return (clampedPercent / 100.0) * DuckConstants.maxHeadRollRadians
  }

  public static func tilt(percent: Double) -> RobotHeadParams {
    RobotHeadParams(headRoll: rollRadians(tiltPercent: percent)).clamped
  }
}

public struct RobotPoseParams: Codable, Equatable, Sendable {
  public var z: Double
  public var roll: Double
  public var pitch: Double
  public var active: Bool

  public init(z: Double = 0, roll: Double = 0, pitch: Double = 0, active: Bool = true) {
    self.z = z
    self.roll = roll
    self.pitch = pitch
    self.active = active
  }

  public static let nominal = RobotPoseParams(z: 0, roll: 0, pitch: 0, active: false)

  public var clamped: RobotPoseParams {
    RobotPoseParams(
      z: min(max(z, DuckConstants.minPoseZ), DuckConstants.maxPoseZ),
      roll: min(max(roll, -DuckConstants.maxPoseRollRadians), DuckConstants.maxPoseRollRadians),
      pitch: min(max(pitch, -DuckConstants.maxPosePitchRadians), DuckConstants.maxPosePitchRadians),
      active: active
    )
  }

  public static func crouch(percent: Double) -> RobotPoseParams {
    let clampedPercent = min(max(percent, 0.0), 100.0)
    guard clampedPercent > 0.0 else { return .nominal }
    let z = (clampedPercent / 100.0) * DuckConstants.minPoseZ
    return RobotPoseParams(z: z, roll: 0, pitch: 0, active: true).clamped
  }
}

public struct RobotEnableParams: Codable, Equatable, Sendable {
  public var on: Bool
  public var toggle: Bool

  public init(on: Bool = true, toggle: Bool = false) {
    self.on = on
    self.toggle = toggle
  }
}

public struct RobotDoParams: Codable, Equatable, Sendable {
  public var skill: String

  public init(skill: String) {
    self.skill = skill
  }
}

public struct RobotSoundParams: Codable, Equatable, Sendable {
  public var tag: String
  public var hold: Bool?

  public init(tag: String, hold: Bool? = nil) {
    self.tag = tag
    self.hold = hold
  }
}

public struct RobotActiveParams: Codable, Equatable, Sendable {
  public var active: Bool

  public init(active: Bool) {
    self.active = active
  }
}

public struct RobotSoccerParams: Codable, Equatable, Sendable {
  public var active: Bool
  public var autonomous: Bool

  public init(active: Bool, autonomous: Bool = true) {
    self.active = active
    self.autonomous = autonomous
  }
}

public struct RobotFlashlightParams: Codable, Equatable, Sendable {
  public var on: Bool
  public var toggle: Bool
  public var color: String

  public init(on: Bool, toggle: Bool = false, color: String = "white") {
    self.on = on
    self.toggle = toggle
    self.color = color
  }
}

public struct RobotRebootMotorsParams: Codable, Equatable, Sendable {
  public var ids: [UInt8]

  public init(ids: [UInt8] = []) {
    self.ids = ids
  }
}

public struct RobotSubscribeParams: Codable, Equatable, Sendable {
  public var hz: Int

  public init(hz: Int) {
    self.hz = hz
  }
}

public struct IntentResult: Codable, Equatable, Sendable {
  public var accepted: Bool
  public var reason: String?

  public init(accepted: Bool, reason: String? = nil) {
    self.accepted = accepted
    self.reason = reason
  }
}

public struct BatteryHealth: Codable, Equatable, Sendable {
  public var volts: Double
  public var percent: Double

  public init(volts: Double, percent: Double) {
    self.volts = volts
    self.percent = percent
  }
}

public struct MotorsHealth: Codable, Equatable, Sendable {
  public var maxC: Double
  public var hottest: String

  enum CodingKeys: String, CodingKey {
    case maxC = "max_c"
    case hottest
  }

  public init(maxC: Double, hottest: String) {
    self.maxC = maxC
    self.hottest = hottest
  }
}

public struct RobotHealthResult: Codable, Equatable, Sendable {
  public var healthy: Bool
  public var degraded: Bool?
  public var reason: String?
  public var battery: BatteryHealth?
  public var motors: MotorsHealth?
  public var cpuTempC: Double?

  enum CodingKeys: String, CodingKey {
    case healthy
    case degraded
    case reason
    case battery
    case motors
    case cpuTempC = "cpu_temp_c"
  }

  public init(
    healthy: Bool,
    degraded: Bool? = nil,
    reason: String? = nil,
    battery: BatteryHealth? = nil,
    motors: MotorsHealth? = nil,
    cpuTempC: Double? = nil
  ) {
    self.healthy = healthy
    self.degraded = degraded
    self.reason = reason
    self.battery = battery
    self.motors = motors
    self.cpuTempC = cpuTempC
  }
}

public struct RobotModeResult: Codable, Equatable, Sendable {
  public var mode: String?
  public var autonomous: Bool?

  public init(mode: String? = nil, autonomous: Bool? = nil) {
    self.mode = mode
    self.autonomous = autonomous
  }
}

public struct RobotPoliciesResult: Codable, Equatable, Sendable {
  public var enabled: Bool?
  public var sitting: Bool?
  public var homed: Bool?
  public var skills: [String]?
  public var changeError: String?

  enum CodingKeys: String, CodingKey {
    case enabled
    case sitting
    case homed
    case skills
    case changeError = "change_error"
  }

  public init(
    enabled: Bool? = nil,
    sitting: Bool? = nil,
    homed: Bool? = nil,
    skills: [String]? = nil,
    changeError: String? = nil
  ) {
    self.enabled = enabled
    self.sitting = sitting
    self.homed = homed
    self.skills = skills
    self.changeError = changeError
  }
}

public struct SkillSummary: Codable, Equatable, Identifiable, Sendable {
  public var name: String
  public var duration: Double?
  public var overridden: Bool?
  public var path: String?

  public var id: String { name }

  public init(name: String, duration: Double? = nil, overridden: Bool? = nil, path: String? = nil) {
    self.name = name
    self.duration = duration
    self.overridden = overridden
    self.path = path
  }
}

public struct RobotSkillsResult: Codable, Equatable, Sendable {
  public var skills: [SkillSummary]

  public init(skills: [SkillSummary] = []) {
    self.skills = skills
  }
}

public struct SetSkillParams: Codable, Equatable, Sendable {
  public var name: String
  public var path: String
  public var duration: Double
  public var chain: Bool
  public var unwind: [Double]?
  public var unwindS: Double?
  public var actionScale: Double?

  enum CodingKeys: String, CodingKey {
    case name
    case path
    case duration
    case chain
    case unwind
    case unwindS = "unwind_s"
    case actionScale = "action_scale"
  }

  public init(
    name: String,
    path: String,
    duration: Double,
    chain: Bool = false,
    unwind: [Double]? = nil,
    unwindS: Double? = nil,
    actionScale: Double? = nil
  ) {
    self.name = name
    self.path = path
    self.duration = duration
    self.chain = chain
    self.unwind = unwind
    self.unwindS = unwindS
    self.actionScale = actionScale
  }
}

public struct RemoveSkillParams: Codable, Equatable, Sendable {
  public var name: String

  public init(name: String) {
    self.name = name
  }
}

public struct PolicyFetchParams: Codable, Equatable, Sendable {
  public var repo: String
  public var revision: String?
  public var file: String?

  public init(repo: String, revision: String? = nil, file: String? = nil) {
    self.repo = repo
    self.revision = revision
    self.file = file
  }
}

public struct PolicyFetchResult: Codable, Equatable, Sendable {
  public var name: String?
  public var repo: String
  public var revision: String
  public var file: String
  public var path: String
  public var origin: String?
  public var kind: String?
  public var encoding: String?
  public var description: String?
  public var durationS: Double?
  public var unwindS: Double?
  public var idle: [Double]?
  public var chain: Bool?
  public var actionScale: Double?

  enum CodingKeys: String, CodingKey {
    case name
    case repo
    case revision
    case file
    case path
    case origin
    case kind
    case encoding
    case description
    case durationS = "duration_s"
    case unwindS = "unwind_s"
    case idle
    case chain
    case actionScale = "action_scale"
  }

  public init(
    name: String? = nil,
    repo: String,
    revision: String = "main",
    file: String = "policy.onnx",
    path: String,
    origin: String? = nil,
    kind: String? = nil,
    encoding: String? = nil,
    description: String? = nil,
    durationS: Double? = nil,
    unwindS: Double? = nil,
    idle: [Double]? = nil,
    chain: Bool? = nil,
    actionScale: Double? = nil
  ) {
    self.name = name
    self.repo = repo
    self.revision = revision
    self.file = file
    self.path = path
    self.origin = origin
    self.kind = kind
    self.encoding = encoding
    self.description = description
    self.durationS = durationS
    self.unwindS = unwindS
    self.idle = idle
    self.chain = chain
    self.actionScale = actionScale
  }
}

public struct MoveTelemetry: Codable, Equatable, Sendable {
  public var requested: [Double]?
  public var applied: [Double]?
  public var limitedBy: [String]?

  enum CodingKeys: String, CodingKey {
    case requested
    case applied
    case limitedBy = "limited_by"
  }

  public init(requested: [Double]? = nil, applied: [Double]? = nil, limitedBy: [String]? = nil) {
    self.requested = requested
    self.applied = applied
    self.limitedBy = limitedBy
  }
}

public struct SafetyTelemetry: Codable, Equatable, Sendable {
  public var fallen: Bool?
  public var pickedUp: Bool?
  public var limp: Bool?

  enum CodingKeys: String, CodingKey {
    case fallen
    case pickedUp = "picked_up"
    case limp
  }

  public init(fallen: Bool? = nil, pickedUp: Bool? = nil, limp: Bool? = nil) {
    self.fallen = fallen
    self.pickedUp = pickedUp
    self.limp = limp
  }

  public var statusLabel: String {
    let flags = [
      fallen == true ? "Fallen" : nil,
      pickedUp == true ? "Picked Up" : nil,
      limp == true ? "Limp" : nil,
    ].compactMap { $0 }
    return flags.isEmpty ? "Upright" : flags.joined(separator: " · ")
  }

  public var isNominal: Bool {
    fallen != true && pickedUp != true && limp != true
  }
}

public struct LoopTelemetry: Codable, Equatable, Sendable {
  public var hz: Double?
  public var missed: UInt64?

  public init(hz: Double? = nil, missed: UInt64? = nil) {
    self.hz = hz
    self.missed = missed
  }
}

public struct ImuTelemetry: Codable, Equatable, Sendable {
  public var gyro: [Double]?
  /// Orientation trunk → world, scalar-first `[w, x, y, z]`.
  public var quat: [Double]?

  public init(gyro: [Double]? = nil, quat: [Double]? = nil) {
    self.gyro = gyro
    self.quat = quat
  }

  /// Heading (yaw) extracted from the trunk → world quaternion, in radians.
  public var yawRadians: Double? {
    guard let quat, quat.count >= 4 else { return nil }
    let w = quat[0]
    let x = quat[1]
    let y = quat[2]
    let z = quat[3]
    let normSq = w * w + x * x + y * y + z * z
    guard normSq > 1e-9 else { return nil }
    let sinyCosp = 2.0 * (w * z + x * y)
    let cosyCosp = 1.0 - 2.0 * (y * y + z * z)
    return atan2(sinyCosp, cosyCosp)
  }
}

public struct OdomTelemetry: Codable, Equatable, Sendable {
  /// Trunk position `[x, y, z]` in metres in the IMU's gravity-aligned world frame.
  public var position: [Double]
  /// Heading in radians.
  public var yaw: Double

  public init(position: [Double] = [0, 0, 0], yaw: Double = 0) {
    self.position = position
    self.yaw = yaw
  }

  public var x: Double { position.count > 0 ? position[0] : 0 }
  public var y: Double { position.count > 1 ? position[1] : 0 }
  public var z: Double { position.count > 2 ? position[2] : 0 }

  public var yawDegrees: Double {
    yaw * 180.0 / .pi
  }

  public func planarDistance(from other: OdomTelemetry) -> Double {
    hypot(x - other.x, y - other.y)
  }
}

public enum DuckGeometry {
  /// Normalizes an angle in radians into `(-π, π]`.
  public static func normalizedAngleRadians(_ radians: Double) -> Double {
    var angle = radians.truncatingRemainder(dividingBy: 2.0 * .pi)
    if angle > .pi {
      angle -= 2.0 * .pi
    } else if angle <= -.pi {
      angle += 2.0 * .pi
    }
    return angle
  }

  /// Shortest signed angular delta `to - from` in radians within `(-π, π]`.
  public static func angularDeltaRadians(from start: Double, to end: Double) -> Double {
    normalizedAngleRadians(end - start)
  }
}

public struct RobotStateFrame: Codable, Equatable, Sendable {
  public var t: Double?
  public var movement: MoveTelemetry?
  public var head: [Double]?
  public var policy: String?
  public var safety: SafetyTelemetry?
  public var controlLoop: LoopTelemetry?
  public var joints: [Double]?
  public var targets: [Double]?
  public var imu: ImuTelemetry?
  public var odom: OdomTelemetry?

  enum CodingKeys: String, CodingKey {
    case t
    case movement = "move"
    case head
    case policy
    case safety
    case controlLoop = "loop"
    case joints
    case targets
    case imu
    case odom
  }

  public init(
    t: Double? = nil,
    movement: MoveTelemetry? = nil,
    head: [Double]? = nil,
    policy: String? = nil,
    safety: SafetyTelemetry? = nil,
    controlLoop: LoopTelemetry? = nil,
    joints: [Double]? = nil,
    targets: [Double]? = nil,
    imu: ImuTelemetry? = nil,
    odom: OdomTelemetry? = nil
  ) {
    self.t = t
    self.movement = movement
    self.head = head
    self.policy = policy
    self.safety = safety
    self.controlLoop = controlLoop
    self.joints = joints
    self.targets = targets
    self.imu = imu
    self.odom = odom
  }

  /// Best available yaw heading in radians, preferring contact odometry and falling back to IMU quaternion.
  public var headingRadians: Double? {
    if let odom, odom.yaw.isFinite {
      return odom.yaw
    }
    return imu?.yawRadians
  }
}

public struct VideoInfoFrame: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var rotate: Int

  public init(width: Int = 640, height: Int = 360, rotate: Int = 0) {
    self.width = width
    self.height = height
    self.rotate = rotate
  }

  public var normalizedRotation: Int {
    ((rotate % 360) + 360) % 360
  }

  public var uprightAspectRatio: Double {
    let quarter = normalizedRotation == 90 || normalizedRotation == 270
    let uw = Double(quarter ? height : width)
    let uh = Double(quarter ? width : height)
    guard uw > 0, uh > 0 else { return 16.0 / 9.0 }
    return uw / uh
  }
}

public struct DetectionBox: Codable, Equatable, Identifiable, Sendable {
  public var x0: Double
  public var y0: Double
  public var x1: Double
  public var y1: Double

  public var id: String { "\(x0)-\(y0)-\(x1)-\(y1)" }

  public init(x0: Double, y0: Double, x1: Double, y1: Double) {
    self.x0 = x0
    self.y0 = y0
    self.x1 = x1
    self.y1 = y1
  }
}

public struct DetectionFrame: Codable, Equatable, Sendable {
  public var width: Double
  public var height: Double
  public var boxes: [DetectionBox]
  public var tookMs: Double?

  enum CodingKeys: String, CodingKey {
    case width
    case height
    case boxes
    case tookMs = "took_ms"
  }

  public init(width: Double, height: Double, boxes: [DetectionBox] = [], tookMs: Double? = nil) {
    self.width = width
    self.height = height
    self.boxes = boxes
    self.tookMs = tookMs
  }
}

public struct TofFrame: Codable, Equatable, Sendable {
  public var seq: UInt64
  public var rows: Int
  public var cols: Int
  public var distanceMm: [Int]
  public var status: [Int]?

  enum CodingKeys: String, CodingKey {
    case seq
    case rows
    case cols
    case distanceMm = "distance_mm"
    case status
  }

  public init(seq: UInt64 = 0, rows: Int = 8, cols: Int = 8, distanceMm: [Int] = [], status: [Int]? = nil) {
    self.seq = seq
    self.rows = rows
    self.cols = cols
    self.distanceMm = distanceMm
    self.status = status
  }
}

public struct MapPose: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var yaw: Double

  public init(x: Double, y: Double, yaw: Double) {
    self.x = x
    self.y = y
    self.yaw = yaw
  }
}

public struct MapGridParams: Codable, Equatable, Sendable {
  public var resM: Double?

  enum CodingKeys: String, CodingKey {
    case resM = "res_m"
  }

  public init(resM: Double? = 0.1) {
    self.resM = resM
  }
}

public struct MapStatusResult: Codable, Equatable, Sendable {
  public var unavailable: String?
  public var loops: Int
  public var relocalizations: Int
  public var islandKeyframes: Int
  public var path: String

  enum CodingKeys: String, CodingKey {
    case unavailable
    case loops
    case relocalizations
    case islandKeyframes = "island_keyframes"
    case path
  }

  public init(
    unavailable: String? = nil,
    loops: Int = 0,
    relocalizations: Int = 0,
    islandKeyframes: Int = 0,
    path: String = ""
  ) {
    self.unavailable = unavailable
    self.loops = loops
    self.relocalizations = relocalizations
    self.islandKeyframes = islandKeyframes
    self.path = path
  }
}

public struct MapGridResult: Codable, Equatable, Sendable {
  public var resM: Double
  public var origin: [Double]
  public var width: Int
  public var height: Int
  public var cells: String
  public var keyframes: [MapPose]
  public var pose: MapPose?

  enum CodingKeys: String, CodingKey {
    case resM = "res_m"
    case origin
    case width
    case height
    case cells
    case keyframes
    case pose
  }

  public init(
    resM: Double = 0.1,
    origin: [Double] = [0, 0],
    width: Int = 0,
    height: Int = 0,
    cells: String = "",
    keyframes: [MapPose] = [],
    pose: MapPose? = nil
  ) {
    self.resM = resM
    self.origin = origin
    self.width = width
    self.height = height
    self.cells = cells
    self.keyframes = keyframes
    self.pose = pose
  }
}

public struct TurnIceServer: Codable, Equatable, Sendable {
  public var urls: [String]
  public var username: String?
  public var credential: String?

  enum CodingKeys: String, CodingKey {
    case urls
    case username
    case credential
  }

  public init(urls: [String], username: String? = nil, credential: String? = nil) {
    self.urls = urls
    self.username = username
    self.credential = credential
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let array = try? container.decode([String].self, forKey: .urls) {
      urls = array
    } else if let single = try? container.decode(String.self, forKey: .urls) {
      urls = [single]
    } else {
      urls = []
    }
    username = try container.decodeIfPresent(String.self, forKey: .username)
    credential = try container.decodeIfPresent(String.self, forKey: .credential)
  }
}

public struct TurnCredentialsResponse: Codable, Equatable, Sendable {
  public var iceServers: [TurnIceServer]

  public init(iceServers: [TurnIceServer] = []) {
    self.iceServers = iceServers
  }
}
