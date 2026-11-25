import CoreGraphics
import DuckDependencies
import DuckProtocol
import Foundation
import FoundationModels
import ImageIO

public typealias WingmanActivityObserver = @Sendable (WingmanActivityItem) -> Void

/// Serializes concurrent `FoundationModels` tool calls on a single robot so multi-tool turns
/// (e.g., walk + turn + chomp emitted in parallel) execute cleanly in order without fighting over `robot.move`.
public actor WingmanToolSerializer {
  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func perform<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async throws -> T {
    await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try await operation()
  }

  private func acquire() async {
    if !isLocked {
      isLocked = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func release() {
    if waiters.isEmpty {
      isLocked = false
    } else {
      let next = waiters.removeFirst()
      next.resume()
    }
  }
}

enum WingmanImageDecoder {
  static func decodeCGImage(from jpegData: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

/// Aims Microduck's head, captures a live camera frame (attached as a FoundationModels `Attachment(cgImage)`
/// when the active model supports `.vision`), and reports 8×8 ToF zone clearances + odometry.
public struct LookAndSnapDuckTool: Tool {
  public let name = "look_and_snap"
  public let description =
    "Aims Microduck's head gaze, reads 8x8 ToF left/front/right clearances, and snaps a live camera photo to inspect the room."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Horizontal head pan percent from -100 (far left) to 100 (far right); 0 is straight ahead.", .range(-100...100))
    public var horizontalPercent: Double

    @Guide(description: "Vertical head tilt percent from -100 (up) to 100 (down toward floor); 0 is level.", .range(-100...100))
    public var verticalPercent: Double

    @Guide(description: "Whether to capture a camera photo after aiming the head.")
    public var capturePhoto: Bool

    public init(horizontalPercent: Double = 0, verticalPercent: Double = 0, capturePhoto: Bool = true) {
      self.horizontalPercent = horizontalPercent
      self.verticalPercent = verticalPercent
      self.capturePhoto = capturePhoto
    }
  }

  private let duckSession: DuckSessionClient
  private let supportsVision: Bool
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    supportsVision: Bool,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.supportsVision = supportsVision
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> Prompt {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> Prompt {
    let activityID = UUID()
    let hx = min(max(arguments.horizontalPercent, -100), 100)
    let vy = min(max(arguments.verticalPercent, -100), 100)
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Look & Inspect",
        detail: "Pan \(Int(hx.rounded()))%, tilt \(Int(vy.rounded()))%",
        status: .running
      )
    )

    let target = LookGeometry.lookTarget(normalizedX: hx / 100.0, normalizedY: vy / 100.0)
    await duckSession.subscribeTof()
    var wasClamped = false
    // Hold robot.look at 10 Hz for ~500 ms so the head servo physically reaches the target
    // before capturing a frame (robotd expires look intents after 500 ms).
    for _ in 0..<5 {
      try Task.checkCancellation()
      if let lookResult = await duckSession.sendLook(target), lookResult.clamped == true {
        wasClamped = true
      }
      try? await Task.sleep(for: .milliseconds(100))
    }

    let snapshot = await duckSession.currentSnapshot()
    var summaryParts: [String] = [
      "Head aimed to horizontal=\(Int(hx.rounded()))%, vertical=\(Int(vy.rounded()))%."
    ]
    if wasClamped {
      summaryParts.append("Neck hit its ~35° travel limit; turn the body with turn_angle or scan_surroundings to see further.")
    }

    if let zones = snapshot.tofFrame?.analyzeZones() {
      let fmt: (Int?) -> String = { mm in mm.map { "\($0 / 10) cm" } ?? "clear" }
      summaryParts.append(
        "ToF clearances: left=\(fmt(zones.leftMm)), front=\(fmt(zones.frontMm)), right=\(fmt(zones.rightMm))."
      )
      if let lowMm = zones.lowFrontObjectMm {
        summaryParts.append("Low object detected near floor at \(lowMm / 10) cm ahead.")
      }
    } else {
      summaryParts.append("ToF depth sensor has no reading yet.")
    }

    if let odom = snapshot.latestState?.odom {
      summaryParts.append(
        String(format: "Odometry: x=%.2f m, y=%.2f m, heading=%.0f°.", odom.x, odom.y, odom.yawDegrees)
      )
    }

    var capturedJPEG: Data?
    var capturedCGImage: CGImage?
    if arguments.capturePhoto {
      if let frame = try? await duckSession.capturePhoto() {
        capturedJPEG = frame.jpegData
        if supportsVision {
          capturedCGImage = WingmanImageDecoder.decodeCGImage(from: frame.jpegData)
        }
        summaryParts.append("Captured \(frame.width)×\(frame.height) camera frame.")
      } else {
        summaryParts.append("Camera frame unavailable right now.")
      }
    }

    let text = summaryParts.joined(separator: " ")
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Look & Inspect",
        detail: text,
        status: .succeeded,
        thumbnailJPEG: capturedJPEG
      )
    )

    if let cgImage = capturedCGImage {
      return Prompt {
        Attachment(cgImage).label("microduck-camera")
        text
      }
    }
    return Prompt(text)
  }
}

/// Physically rotates Microduck's body in steps (default 4 × 90° = full 360°) and captures a
/// live camera frame + 8×8 ToF clearances at each heading so Wingman can genuinely search a room.
public struct ScanSurroundingsDuckTool: Tool {
  public let name = "scan_surroundings"
  public let description =
    "Physically turns Microduck's body in steps (default 4 views × 90° = full 360°) and snaps a camera photo + 8x8 ToF clearances at each heading. Use this to look around 360° or search for an object not visible straight ahead."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Number of body headings to inspect (2 to 6). Use 4 for a full 360° sweep.", .range(2...6))
    public var views: Int

    @Guide(description: "Turn direction for the body sweep: 'left' or 'right'.")
    public var direction: String

    public init(views: Int = 4, direction: String = "left") {
      self.views = views
      self.direction = direction
    }
  }

  private let duckSession: DuckSessionClient
  private let supportsVision: Bool
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    supportsVision: Bool,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.supportsVision = supportsVision
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> Prompt {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> Prompt {
    let viewCount = min(max(arguments.views, 2), 6)
    let isRight = arguments.direction.lowercased().contains("right")
    let dirLabel = isRight ? "right" : "left"
    let stepDegrees = 360.0 / Double(viewCount)
    let signedStep = isRight ? -stepDegrees : stepDegrees
    let activityID = UUID()

    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "360° Body Scan",
        detail: "Scanning \(viewCount) headings (\(Int(stepDegrees.rounded()))° steps \(dirLabel))…",
        status: .running
      )
    )

    await duckSession.subscribeTof()
    // Center head slightly down so floor props (balls, toys, obstacles) are visible in frame.
    _ = await duckSession.sendLook(LookGeometry.lookTarget(normalizedX: 0, normalizedY: 0.15))

    var capturedFrames: [(label: String, image: CGImage)] = []
    var lines: [String] = []
    var lastJPEG: Data?
    var totalTurned = 0.0

    for index in 0..<viewCount {
      try Task.checkCancellation()
      if index > 0 {
        let turnRes = try await duckSession.performMotion(
          .turnAngle(degrees: signedStep, speedPercent: 85)
        )
        totalTurned += turnRes.angleTurnedDegrees
        try? await Task.sleep(for: .milliseconds(250))
        if case let .interruptedBySafety(reason) = turnRes.stopReason {
          lines.append("Scan interrupted at view \(index + 1): \(reason).")
          break
        }
      }

      let snap = await duckSession.currentSnapshot()
      let headingStr = snap.latestState?.odom.map { "\(Int($0.yawDegrees.rounded()))°" } ?? "unknown"
      let relativeDeg = Int((Double(index) * stepDegrees).rounded())
      let label = "scan-view-\(index + 1)-\(relativeDeg)deg-\(dirLabel)"

      var tofStr = "ToF unavailable"
      if let zones = snap.tofFrame?.analyzeZones() {
        let fmt: (Int?) -> String = { mm in mm.map { "\($0 / 10)cm" } ?? "clear" }
        tofStr = "L=\(fmt(zones.leftMm)), F=\(fmt(zones.frontMm)), R=\(fmt(zones.rightMm))"
      }

      if let frame = try? await duckSession.capturePhoto() {
        lastJPEG = frame.jpegData
        if supportsVision, let cgImage = WingmanImageDecoder.decodeCGImage(from: frame.jpegData) {
          capturedFrames.append((label: label, image: cgImage))
        }
      }

      let backDegrees = Int((Double(viewCount - 1 - index) * stepDegrees).rounded())
      let oppositeDir = isRight ? "left" : "right"
      let turnBackHint = backDegrees == 0
        ? "currently facing this view"
        : "to face this view again, turn \(oppositeDir) \(backDegrees)°"

      lines.append(
        "View \(index + 1) (\(label), odom heading \(headingStr), \(tofStr)): \(turnBackHint)."
      )

      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "360° Body Scan",
          detail: "Captured view \(index + 1)/\(viewCount) (\(tofStr))",
          status: .running,
          thumbnailJPEG: lastJPEG
        )
      )
    }

    let summary = "Completed \(capturedFrames.isEmpty ? viewCount : capturedFrames.count)-view body scan (\(Int(abs(totalTurned).rounded()))° rotated).\n"
      + lines.joined(separator: "\n")

    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "360° Body Scan",
        detail: "Scanned \(viewCount) views (\(Int(abs(totalTurned).rounded()))° body sweep)",
        status: .succeeded,
        thumbnailJPEG: lastJPEG
      )
    )

    return Prompt {
      for item in capturedFrames {
        Attachment(item.image).label(item.label)
      }
      summary
    }
  }
}

/// Walks or sidesteps Microduck a real-world distance in meters via closed-loop contact odometry.
public struct WalkDuckDistanceTool: Tool {
  public let name = "walk_distance"
  public let description =
    "Walks or sidesteps Microduck a real-world distance in meters (0.1 to 2.5 m) using closed-loop odometry and 8x8 ToF obstacle safety."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Direction: forward, backward, strafeLeft, or strafeRight.")
    public var direction: String

    @Guide(description: "Distance to travel in meters (0.1 to 2.5).", .range(0.1...2.5))
    public var meters: Double

    @Guide(description: "Whether to stop early if a forward obstacle is closer than 20 cm.")
    public var stopOnObstacle: Bool

    public init(direction: String, meters: Double, stopOnObstacle: Bool = true) {
      self.direction = direction
      self.meters = meters
      self.stopOnObstacle = stopOnObstacle
    }
  }

  private let duckSession: DuckSessionClient
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> String {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> String {
    let linearDirection = DuckLinearDirection(rawValue: arguments.direction) ?? .forward
    let clampedMeters = min(max(arguments.meters, 0.1), 2.5)
    let activityID = UUID()
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Walk \(linearDirection.spokenLabel.capitalized)",
        detail: String(format: "%.2f m (odometry)", clampedMeters),
        status: .running
      )
    )

    do {
      let result = try await duckSession.performMotion(
        .moveDistance(
          direction: linearDirection,
          meters: clampedMeters,
          speedPercent: 65,
          stopOnObstacle: arguments.stopOnObstacle
        )
      )
      let traveled = String(format: "%.2f m", result.distanceTraveledMeters)
      let message: String = switch result.stopReason {
      case .reachedTarget:
        "Walked \(linearDirection.spokenLabel) \(traveled)."
      case let .stoppedForObstacle(distanceMm):
        "Stopped after \(traveled) — obstacle \(distanceMm / 10) cm ahead."
      case .timedOut:
        "Walked \(traveled) before hitting safety timeout."
      case let .interruptedBySafety(reason):
        "Stopped early after \(traveled): \(reason)."
      }
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Walk \(linearDirection.spokenLabel.capitalized)",
          detail: message,
          status: .succeeded
        )
      )
      return message
    } catch {
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Walk \(linearDirection.spokenLabel.capitalized)",
          detail: error.localizedDescription,
          status: .failed
        )
      )
      return "Failed to walk: \(error.localizedDescription)"
    }
  }
}

/// Rotates Microduck in place by an exact angle in degrees via closed-loop heading feedback.
public struct TurnDuckAngleTool: Tool {
  public let name = "turn_angle"
  public let description =
    "Rotates Microduck in place left or right by an exact angle in degrees (15 to 360) using closed-loop heading feedback."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Turn direction: 'left' (counterclockwise) or 'right' (clockwise).")
    public var direction: String

    @Guide(description: "Positive angle in degrees to rotate (15 to 360). Use 90 for a quarter turn and 180 to turn around.", .range(15...360))
    public var degrees: Double

    public init(direction: String, degrees: Double) {
      self.direction = direction
      self.degrees = degrees
    }
  }

  private let duckSession: DuckSessionClient
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> String {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> String {
    let isRight = arguments.direction.lowercased().contains("right")
    let dirLabel = isRight ? "right" : "left"
    let absDegrees = min(max(abs(arguments.degrees), 15), 360)
    let signedDegrees = isRight ? -absDegrees : absDegrees
    let activityID = UUID()
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Turn \(dirLabel.capitalized)",
        detail: "\(Int(absDegrees.rounded()))° (heading feedback)",
        status: .running
      )
    )

    do {
      let result = try await duckSession.performMotion(
        .turnAngle(degrees: signedDegrees, speedPercent: 85)
      )
      let turned = Int(abs(result.angleTurnedDegrees).rounded())
      let message: String = switch result.stopReason {
      case .reachedTarget:
        "Turned \(dirLabel) \(turned)°."
      case .timedOut:
        "Turned \(dirLabel) \(turned)° (safety timeout)."
      case let .stoppedForObstacle(distanceMm):
        "Stopped turning at \(turned)° (obstacle \(distanceMm / 10) cm ahead)."
      case let .interruptedBySafety(reason):
        "Stopped turning early at \(turned)°: \(reason)."
      }
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Turn \(dirLabel.capitalized)",
          detail: message,
          status: .succeeded
        )
      )
      return message
    } catch {
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Turn \(dirLabel.capitalized)",
          detail: error.localizedDescription,
          status: .failed
        )
      )
      return "Failed to turn: \(error.localizedDescription)"
    }
  }
}

/// Approaches an obstacle ahead or backs up until open space ahead reaches a target clearance in cm.
public struct ClearanceMoveDuckTool: Tool {
  public let name = "move_until_clearance"
  public let description =
    "Moves Microduck forward until reaching targetClearanceCm from an obstacle ahead, or backs up until front clearance exceeds targetClearanceCm."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Mode: 'approach' to walk up to an object ahead, or 'backUpUntilClear' to back up until space opens.")
    public var mode: String

    @Guide(description: "Target front clearance in centimeters (15 to 150 cm).", .range(15...150))
    public var targetClearanceCm: Int

    public init(mode: String, targetClearanceCm: Int) {
      self.mode = mode
      self.targetClearanceCm = targetClearanceCm
    }
  }

  private let duckSession: DuckSessionClient
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> String {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> String {
    let isBackUp = arguments.mode.lowercased().contains("back")
    let clampedCm = min(max(arguments.targetClearanceCm, 15), 150)
    let title = isBackUp ? "Back Up Until Clear" : "Approach Obstacle"
    let activityID = UUID()
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: title,
        detail: "Target \(clampedCm) cm via 8×8 ToF",
        status: .running
      )
    )

    let goal: DuckMotionGoal = isBackUp
      ? .backUpUntilClear(targetClearanceMm: clampedCm * 10)
      : .approachObstacle(targetClearanceMm: clampedCm * 10)

    do {
      let result = try await duckSession.performMotion(goal)
      let clearance = result.finalFrontClearanceMm.map { "\($0 / 10) cm" } ?? "unknown"
      let message: String = switch result.stopReason {
      case .reachedTarget:
        isBackUp
          ? "Backed up until front clearance reached \(clearance)."
          : "Approached to \(clearance) from the obstacle ahead."
      case .timedOut:
        "Stopped at \(clearance) ahead (safety timeout)."
      case let .stoppedForObstacle(distanceMm):
        "Stopped at \(distanceMm / 10) cm ahead."
      case let .interruptedBySafety(reason):
        "Stopped early: \(reason)."
      }
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: title,
          detail: message,
          status: .succeeded
        )
      )
      return message
    } catch {
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: title,
          detail: error.localizedDescription,
          status: .failed
        )
      )
      return "Clearance move failed: \(error.localizedDescription)"
    }
  }
}

/// Controls Microduck's posture (`standUp`, `sitDown`, `recover`, `stop`).
public struct PostureDuckTool: Tool {
  public let name = "set_posture"
  public let description =
    "Changes Microduck's posture: 'standUp', 'sitDown', 'recover' (from a fall), or 'stop' (emergency halt)."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Posture action: standUp, sitDown, recover, or stop.")
    public var action: String

    public init(action: String) {
      self.action = action
    }
  }

  private let duckSession: DuckSessionClient
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> String {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> String {
    let normalized = arguments.action.lowercased()
    let activityID = UUID()
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Posture: \(arguments.action)",
        detail: "Sending posture command…",
        status: .running
      )
    )

    do {
      let message: String
      if normalized.contains("stop") || normalized.contains("halt") {
        await duckSession.sendMove(.zero)
        try await duckSession.stop()
        message = "Stopped Microduck immediately."
      } else if normalized.contains("recover") {
        try await duckSession.standBackUp()
        message = "Triggered fall recovery and stood Microduck back up."
      } else if normalized.contains("sit") {
        try await duckSession.setEnabled(false)
        message = "Sat Microduck down."
      } else {
        try await duckSession.setEnabled(true)
        message = "Microduck is standing and balancing."
      }
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Posture: \(arguments.action)",
          detail: message,
          status: .succeeded
        )
      )
      return message
    } catch {
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Posture: \(arguments.action)",
          detail: error.localizedDescription,
          status: .failed
        )
      )
      return "Posture change failed: \(error.localizedDescription)"
    }
  }
}

/// Performs expressive actions: beak open/chomp, head tilt, crouch, sound, and face light color.
public struct ExpressDuckTool: Tool {
  public let name = "express"
  public let description =
    "Controls Microduck's expressive actuators: beak opening (or animated chomp), head tilt, crouch, sound effects, and RGB face light."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Optional beak open percent (0 closed to 100 wide open).", .range(0...100))
    public var beakOpenPercent: Double?

    @Guide(description: "If true, animates a playful beak chomp for ~1.4 seconds.")
    public var chomp: Bool

    @Guide(description: "Optional head tilt percent (-100 left to 100 right).", .range(-100...100))
    public var headTiltPercent: Double?

    @Guide(description: "Optional crouch depth percent (0 standing to 100 full crouch).", .range(0...100))
    public var crouchPercent: Double?

    @Guide(description: "Optional sound tag: chirp, greet, inquire, alarm, peck, or coo.")
    public var sound: String?

    @Guide(description: "Optional face light color: off, white, red, green, blue, yellow, cyan, or magenta.")
    public var lightColor: String?

    public init(
      beakOpenPercent: Double? = nil,
      chomp: Bool = false,
      headTiltPercent: Double? = nil,
      crouchPercent: Double? = nil,
      sound: String? = nil,
      lightColor: String? = nil
    ) {
      self.beakOpenPercent = beakOpenPercent
      self.chomp = chomp
      self.headTiltPercent = headTiltPercent
      self.crouchPercent = crouchPercent
      self.sound = sound
      self.lightColor = lightColor
    }
  }

  private let duckSession: DuckSessionClient
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> String {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> String {
    let activityID = UUID()
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Express",
        detail: "Performing expressive gesture…",
        status: .running
      )
    )

    var performed: [String] = []

    if let soundRaw = arguments.sound?.lowercased(), let tag = SoundTag(rawValue: soundRaw) {
      await duckSession.playSound(tag, nil)
      performed.append("sound=\(tag.rawValue)")
    }

    if let color = arguments.lightColor?.lowercased(), !color.isEmpty {
      if color == "off" {
        try? await duckSession.setFlashlightColor(false, "white")
        performed.append("light=off")
      } else {
        try? await duckSession.setFlashlightColor(true, color)
        performed.append("light=\(color)")
      }
    }

    if let tilt = arguments.headTiltPercent {
      await duckSession.sendHead(RobotHeadParams.tilt(percent: tilt))
      performed.append("tilt=\(Int(tilt.rounded()))%")
    }

    if let crouch = arguments.crouchPercent {
      await duckSession.sendPose(RobotPoseParams.crouch(percent: crouch))
      performed.append("crouch=\(Int(crouch.rounded()))%")
    }

    if arguments.chomp {
      for tick in 0..<12 {
        try Task.checkCancellation()
        let open = (tick / 2).isMultiple(of: 2) ? 1.0 : 0.0
        await duckSession.sendMouth(RobotMouthParams(open: open))
        try? await Task.sleep(for: .milliseconds(100))
      }
      await duckSession.sendMouth(.closed)
      performed.append("chomp")
    } else if let beak = arguments.beakOpenPercent {
      await duckSession.sendMouth(RobotMouthParams.fromPercent(beak))
      performed.append("beak=\(Int(beak.rounded()))%")
      try? await Task.sleep(for: .milliseconds(700))
      await duckSession.sendMouth(.closed)
    } else if arguments.headTiltPercent != nil || arguments.crouchPercent != nil {
      try? await Task.sleep(for: .milliseconds(700))
    }

    if arguments.headTiltPercent != nil {
      await duckSession.sendHead(.neutral)
    }
    if arguments.crouchPercent != nil {
      await duckSession.sendPose(.nominal)
    }

    let message = performed.isEmpty
      ? "Completed neutral expression."
      : "Expressed: \(performed.joined(separator: ", "))."
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Express",
        detail: message,
        status: .succeeded
      )
    )
    return message
  }
}

/// Triggers an installed built-in or Hugging Face trick by name.
public struct PerformDuckTrickTool: Tool {
  public let name = "perform_trick"
  public let description = "Runs an installed Microduck trick by name (for example roulade, kick_left, kick_right, or an installed Hub skill)."

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Exact name of an installed trick from Microduck's skill list.")
    public var trickName: String

    public init(trickName: String) {
      self.trickName = trickName
    }
  }

  private let duckSession: DuckSessionClient
  private let serializer: WingmanToolSerializer
  private let onActivity: WingmanActivityObserver

  public init(
    duckSession: DuckSessionClient,
    serializer: WingmanToolSerializer = WingmanToolSerializer(),
    onActivity: @escaping WingmanActivityObserver
  ) {
    self.duckSession = duckSession
    self.serializer = serializer
    self.onActivity = onActivity
  }

  public func call(arguments: Arguments) async throws -> String {
    try await serializer.perform {
      try await performCall(arguments: arguments)
    }
  }

  private func performCall(arguments: Arguments) async throws -> String {
    let activityID = UUID()
    onActivity(
      WingmanActivityItem(
        id: activityID,
        kind: .toolCall,
        title: "Trick: \(arguments.trickName)",
        detail: "Performing trick…",
        status: .running
      )
    )

    do {
      try await duckSession.performSkill(arguments.trickName)
      let message = "Performed trick '\(arguments.trickName)'."
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Trick: \(arguments.trickName)",
          detail: message,
          status: .succeeded
        )
      )
      return message
    } catch {
      onActivity(
        WingmanActivityItem(
          id: activityID,
          kind: .toolCall,
          title: "Trick: \(arguments.trickName)",
          detail: error.localizedDescription,
          status: .failed
        )
      )
      return "Trick '\(arguments.trickName)' failed: \(error.localizedDescription)"
    }
  }
}
