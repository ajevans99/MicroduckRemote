import CustomDump
import DuckProtocol
import Foundation
import Testing

@Suite struct DuckProtocolTests {
  @Test func parsesRobotStateNotification() throws {
    let raw = """
    {"jsonrpc":"2.0","method":"robot.state","params":{"t":12.5,"move":{"requested":[0.15,0.0,0.0],"applied":[0.14,0.0,0.0],"limited_by":[]},"head":[0.0,0.1,0.0,0.0],"policy":"walk","safety":{"fallen":false,"picked_up":false,"limp":false},"loop":{"hz":50.0,"missed":0},"joints":[0.1,-0.2],"targets":[0.1,-0.2]}}
    """
    let decoded = try IncomingControlMessage.decode(from: raw)
    expectNoDifference(
      decoded.robotState,
      RobotStateFrame(
        t: 12.5,
        movement: MoveTelemetry(requested: [0.15, 0.0, 0.0], applied: [0.14, 0.0, 0.0], limitedBy: []),
        head: [0.0, 0.1, 0.0, 0.0],
        policy: "walk",
        safety: SafetyTelemetry(fallen: false, pickedUp: false, limp: false),
        controlLoop: LoopTelemetry(hz: 50.0, missed: 0),
        joints: [0.1, -0.2],
        targets: [0.1, -0.2]
      )
    )
  }

  @Test func parsesSignallingPeerSdpAndProducerList() throws {
    let listJSON = """
    {"type":"list","producers":[{"id":"peer-1","meta":{"name":"duck-eb55","kind":"microduck","release":"0.23.0","api_version":68,"simulated":true}}]}
    """
    let listMsg = try SignallingInbound.decode(from: listJSON)
    expectNoDifference(
      listMsg,
      .list([
        ProducerInfo(
          id: "peer-1",
          meta: ProducerMeta(
            name: "duck-eb55",
            kind: "microduck",
            release: "0.23.0",
            apiVersion: 68,
            simulated: true
          )
        )
      ])
    )

    let localGstListJSON = """
    {"type":"list","producers":[{"id":"7c1db1be","meta":{"api_version":"68","name":"duck-eb55","release":"0.23.0","serial":"sim-duck-a","simulated":"true"}}]}
    """
    let localListMsg = try SignallingInbound.decode(from: localGstListJSON)
    expectNoDifference(
      localListMsg,
      .list([
        ProducerInfo(
          id: "7c1db1be",
          meta: ProducerMeta(
            name: "duck-eb55",
            release: "0.23.0",
            serial: "sim-duck-a",
            apiVersion: 68,
            simulated: true
          )
        )
      ])
    )

    let offerJSON = """
    {"type":"peer","sessionId":"sess-9","sdp":{"type":"offer","sdp":"v=0..."}}
    """
    let sdpMsg = try SignallingInbound.decode(from: offerJSON)
    expectNoDifference(
      sdpMsg,
      .peerSdp(sessionId: "sess-9", sdp: SdpPayload(type: "offer", sdp: "v=0..."))
    )

    let endOfCandidatesJSON = """
    {"type":"peer","sessionId":"sess-9","ice":{"candidate":"","sdpMLineIndex":0}}
    """
    let iceMsg = try SignallingInbound.decode(from: endOfCandidatesJSON)
    expectNoDifference(
      iceMsg,
      .peerIce(sessionId: "sess-9", ice: IceCandidatePayload(candidate: "", sdpMLineIndex: 0))
    )
    expectNoDifference(iceMsg[case: \.peerIce]?.ice.isEndOfCandidates, true)
  }

  @Test func sseParserHandlesCRLFFramingAndComments() {
    var parser = SseStreamParser()
    let first = parser.ingest(": keepalive\r\n\r\ndata: {\"type\":\"wel")
    expectNoDifference(first, [])
    let second = parser.ingest("come\",\"peerId\":\"abc\"}\r\n\r\n")
    expectNoDifference(second, ["{\"type\":\"welcome\",\"peerId\":\"abc\"}"])
  }

  @Test func lookGeometryMapsViewportToRobotTrunkFrame() {
    let center = LookGeometry.lookTarget(normalizedX: 0, normalizedY: 0)
    expectNoDifference(center, RobotLookParams(x: 1.0, y: 0.0, z: 0.2, neckPitch: 0))

    let topLeft = LookGeometry.lookTarget(normalizedX: -1.0, normalizedY: -1.0)
    expectNoDifference(topLeft, RobotLookParams(x: 1.0, y: 0.7, z: 0.65, neckPitch: 0))
  }

  @Test func encodesEnableAndModeToggleParamsMatchingDaemonSchema() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let enableJSON = String(decoding: try encoder.encode(RobotEnableParams(on: true, toggle: true)), as: UTF8.self)
    expectNoDifference(enableJSON, #"{"on":true,"toggle":true}"#)

    let autoJSON = String(decoding: try encoder.encode(RobotActiveParams(active: true)), as: UTF8.self)
    expectNoDifference(autoJSON, #"{"active":true}"#)

    let flashJSON = String(decoding: try encoder.encode(RobotFlashlightParams(on: true)), as: UTF8.self)
    expectNoDifference(flashJSON, #"{"color":"white","on":true,"toggle":false}"#)

    let rebootJSON = String(decoding: try encoder.encode(RobotRebootMotorsParams()), as: UTF8.self)
    expectNoDifference(rebootJSON, #"{"ids":[]}"#)

    let mouthJSON = String(decoding: try encoder.encode(RobotMouthParams(open: 0.75)), as: UTF8.self)
    expectNoDifference(mouthJSON, #"{"open":0.75}"#)

    let headJSON = String(
      decoding: try encoder.encode(RobotHeadParams(neckPitch: 0.1, headPitch: -0.2, headYaw: 0.3, headRoll: -0.25)),
      as: UTF8.self
    )
    expectNoDifference(
      headJSON,
      #"{"head_pitch":-0.2,"head_roll":-0.25,"head_yaw":0.3,"neck_pitch":0.1}"#
    )

    let poseJSON = String(
      decoding: try encoder.encode(RobotPoseParams(z: -0.02, roll: 0.1, pitch: -0.1, active: true)),
      as: UTF8.self
    )
    expectNoDifference(poseJSON, #"{"active":true,"pitch":-0.1,"roll":0.1,"z":-0.02}"#)
  }

  @Test func clampsMouthHeadAndPoseToTrainedHardwareLimits() throws {
    expectNoDifference(RobotMouthParams(open: 1.8).clamped, .wideOpen)
    expectNoDifference(RobotMouthParams(open: -0.4).clamped, .closed)
    expectNoDifference(RobotMouthParams.fromPercent(150), .wideOpen)
    expectNoDifference(RobotMouthParams.fromPercent(-20), .closed)

    expectNoDifference(
      RobotHeadParams(neckPitch: 0.1, headPitch: 0.2, headYaw: -0.3, headRoll: 1.2, alpha: 2.0).clamped,
      RobotHeadParams(
        neckPitch: 0.1,
        headPitch: 0.2,
        headYaw: -0.3,
        headRoll: DuckConstants.maxHeadRollRadians,
        alpha: 1.0
      )
    )
    expectNoDifference(
      RobotHeadParams.rollRadians(tiltPercent: -150),
      -DuckConstants.maxHeadRollRadians
    )

    expectNoDifference(
      RobotPoseParams(z: -0.10, roll: 0.9, pitch: -0.9, active: true).clamped,
      RobotPoseParams(
        z: DuckConstants.minPoseZ,
        roll: DuckConstants.maxPoseRollRadians,
        pitch: -DuckConstants.maxPosePitchRadians,
        active: true
      )
    )
    expectNoDifference(
      RobotPoseParams(z: 0.5, roll: 0, pitch: 0, active: true).clamped.z,
      DuckConstants.maxPoseZ
    )
    expectNoDifference(RobotPoseParams.crouch(percent: 0), .nominal)
    expectNoDifference(
      RobotPoseParams.crouch(percent: 100),
      RobotPoseParams(z: DuckConstants.minPoseZ, roll: 0, pitch: 0, active: true)
    )

    let lookJSON = Data(
      #"{"head":{"neck_pitch":0.05,"head_pitch":-0.1,"head_yaw":0.4,"head_roll":0.0},"clamped":false}"#.utf8
    )
    let lookResult = try JSONDecoder().decode(RobotLookResult.self, from: lookJSON)
    expectNoDifference(
      lookResult.head,
      RobotHeadParams(neckPitch: 0.05, headPitch: -0.1, headYaw: 0.4, headRoll: 0.0)
    )
    expectNoDifference(lookResult.clamped, false)
  }

  @Test func hubManifestAndSkillConversionMatchDaemonContract() throws {
    let manifest = Data(
      """
      {"schema_version":2,"name":"polite-bow","description":"Bows politely.","kind":"episodic","duration_s":4.0,"command":{"encoding":"constant","idle":[0,0,0]}}
      """.utf8
    )
    let parsed = HubPolicy.parseManifestEntries(
      manifestJSON: manifest,
      repo: "neil-jo/microduck-polite-bow",
      likes: 7
    )
    expectNoDifference(parsed.count, 1)
    expectNoDifference(parsed[0].isTrick, true)
    expectNoDifference(parsed[0].name, "Polite Bow")

    let fetched = PolicyFetchResult(
      name: "polite bow",
      repo: "neil-jo/microduck-polite-bow",
      path: "/tmp/policies/polite-bow/policy.onnx",
      durationS: 4.0,
      idle: [0, 0, 0],
      chain: false
    )
    let skill = SetSkillParams.from(fetched: fetched)
    expectNoDifference(
      skill,
      SetSkillParams(
        name: "polite-bow",
        path: "/tmp/policies/polite-bow/policy.onnx",
        duration: 4.0,
        chain: false,
        unwind: [0, 0, 0]
      )
    )
  }

  @Test func tofFrontObstacleConeIgnoresOuterFloorCellsAndInvalidStatuses() {
    var distances = Array(repeating: 600, count: 64)
    var statuses = Array(repeating: 0, count: 64)
    // Bottom-row floor reflection should be ignored by the central 4x4 cone:
    distances[7 * 8 + 3] = 85
    // Invalid sensor status (255) inside the central cone should be ignored:
    distances[3 * 8 + 3] = 50
    statuses[3 * 8 + 3] = 255
    // Valid obstacle inside central 4x4 cone (rows 2..<6, cols 2..<6):
    distances[4 * 8 + 4] = 165

    let frame = TofFrame(seq: 1, rows: 8, cols: 8, distanceMm: distances, status: statuses)
    expectNoDifference(frame.frontObstacleDistanceMm, 165)
  }

  @Test func tofZoneAnalysisComputesLeftFrontRightClearancesAndOpenDirection() {
    // 1. Blocked straight ahead & on right -> recommends turning left:
    var distances = Array(repeating: 900, count: 64)
    let statuses = Array(repeating: 5, count: 64)
    // Front obstacle in center columns (2..<6), middle rows (2..<6):
    distances[3 * 8 + 3] = 240
    // Closer obstacle on right side (cols 6..<8):
    distances[3 * 8 + 6] = 310
    // Left side (cols 0..<2) remains 900 mm:
    let blockedRightFrame = TofFrame(seq: 10, rows: 8, cols: 8, distanceMm: distances, status: statuses)
    let rightBlocked = blockedRightFrame.analyzeZones()
    expectNoDifference(rightBlocked?.frontMm, 240)
    expectNoDifference(rightBlocked?.leftMm, 900)
    expectNoDifference(rightBlocked?.rightMm, 310)
    expectNoDifference(rightBlocked?.closestMm, 240)
    expectNoDifference(rightBlocked?.obstacleWarning, true)
    expectNoDifference(rightBlocked?.recommendedDirection, .turnLeft)

    // 2. Blocked straight ahead & on left -> recommends turning right:
    var leftBlockedDist = Array(repeating: 900, count: 64)
    leftBlockedDist[3 * 8 + 4] = 210
    leftBlockedDist[4 * 8 + 1] = 260
    let leftBlocked = TofFrame(seq: 11, rows: 8, cols: 8, distanceMm: leftBlockedDist, status: statuses).analyzeZones()
    expectNoDifference(leftBlocked?.recommendedDirection, .turnRight)
    expectNoDifference(leftBlocked?.obstacleWarning, true)

    // 3. All status == 255 (no target within 4 m) -> clear open space:
    let openSpace = TofFrame(
      seq: 12,
      rows: 8,
      cols: 8,
      distanceMm: Array(repeating: 0, count: 64),
      status: Array(repeating: 255, count: 64)
    ).analyzeZones()
    expectNoDifference(openSpace?.frontMm, DuckConstants.tofMaxRangeMm)
    expectNoDifference(openSpace?.leftMm, DuckConstants.tofMaxRangeMm)
    expectNoDifference(openSpace?.rightMm, DuckConstants.tofMaxRangeMm)
    expectNoDifference(openSpace?.obstacleWarning, false)
    expectNoDifference(openSpace?.recommendedDirection, .clear)

    // 4. Front passable (450 mm) with tight side wall -> forward:
    var hallwayDist = Array(repeating: 450, count: 64)
    hallwayDist[3 * 8 + 0] = 180
    let hallway = TofFrame(seq: 13, rows: 8, cols: 8, distanceMm: hallwayDist, status: statuses).analyzeZones()
    expectNoDifference(hallway?.obstacleWarning, true)
    expectNoDifference(hallway?.recommendedDirection, .forward)

    // 5. Low floor object (soccer ball at 250 mm in lower front rows, open above):
    var ballDist = Array(repeating: 1400, count: 64)
    ballDist[5 * 8 + 3] = 250
    let ballAnalysis = TofFrame(seq: 14, rows: 8, cols: 8, distanceMm: ballDist, status: statuses).analyzeZones()
    expectNoDifference(ballAnalysis?.lowFrontObjectMm, 250)
  }

  @Test func moveStepRequestClampsOutOfRangeVelocitiesAndDurations() {
    let request = DuckMoveStepRequest(
      vx: 1.8,
      vy: -0.9,
      vyaw: -4.2,
      durationSeconds: 45.0
    )
    expectNoDifference(
      request.clampedTwist,
      RobotMoveParams(
        vx: DuckConstants.maxLinearVelocity,
        vy: -DuckConstants.maxLinearVelocity,
        vyaw: -DuckConstants.maxAngularVelocity
      )
    )
    expectNoDifference(request.clampedDurationSeconds, DuckConstants.maxStepDurationSeconds)

    let backwardRequest = DuckMoveStepRequest(vx: -0.9)
    expectNoDifference(backwardRequest.clampedTwist.vx, -DuckConstants.maxBackwardLinearVelocity)
    expectNoDifference(DuckConstants.backwardLinearVelocity(magnitude: 0.0), 0.0)
    expectNoDifference(DuckConstants.backwardLinearVelocity(magnitude: 1.0), -DuckConstants.maxBackwardLinearVelocity)
    expectNoDifference(
      abs(DuckConstants.backwardLinearVelocity(magnitude: 0.5) - (-0.46)) < 0.0001,
      true
    )
  }

  @Test func sharedSummaryCoalescesTelemetryJitterUntilDiscreteStateChanges() {
    let t0 = Date(timeIntervalSince1970: 1_795_150_000)
    let base = DuckSharedSummary(
      isConnected: true,
      duckName: "duck-eb55",
      peerID: "sim-a",
      isSimulated: true,
      isEnabled: true,
      isSitting: false,
      isFallen: false,
      activePolicy: "walk",
      batteryVolts: 7.42,
      batteryPercent: 54,
      maxMotorTempC: 32,
      hottestMotor: "left_hip_yaw",
      updatedAt: t0
    )

    var jittered = base
    jittered.batteryVolts = 7.39
    jittered.batteryPercent = 52
    jittered.maxMotorTempC = 34
    jittered.updatedAt = t0.addingTimeInterval(0.02)
    expectNoDifference(base.hasSameControlSurfaceState(as: jittered), true)

    var satDown = jittered
    satDown.isSitting = true
    expectNoDifference(base.hasSameControlSurfaceState(as: satDown), false)
  }

  @Test func robotStateFrameDecodesOdomAndImuHeadingWithAngleWrapping() throws {
    let json = """
    {
      "t": 12.5,
      "policy": "walk",
      "odom": { "position": [0.42, -0.18, 0.116], "yaw": 1.5707963267948966 },
      "imu": { "gyro": [0.0, 0.0, 0.2], "quat": [0.70710678, 0.0, 0.0, 0.70710678] }
    }
    """
    let frame = try JSONDecoder().decode(RobotStateFrame.self, from: Data(json.utf8))
    let odom = try #require(frame.odom)
    expectNoDifference(odom.x, 0.42)
    expectNoDifference(odom.y, -0.18)
    expectNoDifference(abs(odom.yawDegrees - 90.0) < 0.001, true)
    expectNoDifference(abs((frame.headingRadians ?? 0) - .pi / 2.0) < 0.001, true)

    let origin = OdomTelemetry(position: [0.0, 0.0, 0.116], yaw: 0)
    expectNoDifference(abs(odom.planarDistance(from: origin) - hypot(0.42, -0.18)) < 1e-9, true)

    // IMU quaternion fallback when odom is absent
    let imuOnly = RobotStateFrame(imu: ImuTelemetry(quat: [0.70710678, 0, 0, -0.70710678]))
    expectNoDifference(abs((imuOnly.headingRadians ?? 0) - (-.pi / 2.0)) < 0.001, true)

    // Wrapped angular delta across +/- pi seam (+170 deg -> -170 deg = +20 deg)
    let start = 170.0 * .pi / 180.0
    let end = -170.0 * .pi / 180.0
    let deltaDeg = DuckGeometry.angularDeltaRadians(from: start, to: end) * 180.0 / .pi
    expectNoDifference(abs(deltaDeg - 20.0) < 0.001, true)
  }
}
