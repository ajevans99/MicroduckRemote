import DuckDependencies
import DuckProtocol
import Foundation
import FoundationModels

public enum WingmanModelBackend: String, CaseIterable, Identifiable, Equatable, Sendable {
  case onDevice
  case privateCloudCompute

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .onDevice: "On-Device"
    case .privateCloudCompute: "Private Cloud"
    }
  }

  public var systemImage: String {
    switch self {
    case .onDevice: "cpu"
    case .privateCloudCompute: "cloud.fill"
    }
  }
}

public enum WingmanMode: String, CaseIterable, Identifiable, Equatable, Sendable {
  case agent
  case missionPlan

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .agent: "Agent"
    case .missionPlan: "Mission Plan"
    }
  }
}

public struct WingmanBackendStatus: Equatable, Sendable {
  public var isAvailable: Bool
  public var supportsVision: Bool
  public var statusText: String

  public init(isAvailable: Bool, supportsVision: Bool, statusText: String) {
    self.isAvailable = isAvailable
    self.supportsVision = supportsVision
    self.statusText = statusText
  }
}

public struct WingmanActivityItem: Identifiable, Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case toolCall
    case missionStep
    case narration
    case error
  }

  public enum Status: String, Equatable, Sendable {
    case running
    case succeeded
    case failed
  }

  public var id: UUID
  public var kind: Kind
  public var title: String
  public var detail: String
  public var status: Status
  public var thumbnailJPEG: Data?
  public var timestamp: Date

  public init(
    id: UUID = UUID(),
    kind: Kind,
    title: String,
    detail: String,
    status: Status,
    thumbnailJPEG: Data? = nil,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.status = status
    self.thumbnailJPEG = thumbnailJPEG
    self.timestamp = timestamp
  }
}

public struct WingmanStarter: Identifiable, Equatable, Sendable {
  public var id: String { title }
  public var title: String
  public var subtitle: String
  public var systemImage: String
  public var prompt: String

  public init(title: String, subtitle: String, systemImage: String, prompt: String) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.prompt = prompt
  }
}

public struct WingmanTurn: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var userPrompt: String
  public var mode: WingmanMode
  public var backend: WingmanModelBackend
  public var attachedFrameJPEG: Data?
  public var toolSteps: [WingmanActivityItem]
  public var planTitle: String?
  public var planSummary: String?
  public var planSteps: [WingmanStepDraft]
  public var finalizedPlan: WingmanMissionPlan?
  public var executingStepIndex: Int?
  public var replyText: String?
  public var errorText: String?
  public var isComplete: Bool
  public var timestamp: Date

  public init(
    id: UUID = UUID(),
    userPrompt: String,
    mode: WingmanMode,
    backend: WingmanModelBackend,
    attachedFrameJPEG: Data? = nil,
    toolSteps: [WingmanActivityItem] = [],
    planTitle: String? = nil,
    planSummary: String? = nil,
    planSteps: [WingmanStepDraft] = [],
    finalizedPlan: WingmanMissionPlan? = nil,
    executingStepIndex: Int? = nil,
    replyText: String? = nil,
    errorText: String? = nil,
    isComplete: Bool = false,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.userPrompt = userPrompt
    self.mode = mode
    self.backend = backend
    self.attachedFrameJPEG = attachedFrameJPEG
    self.toolSteps = toolSteps
    self.planTitle = planTitle
    self.planSummary = planSummary
    self.planSteps = planSteps
    self.finalizedPlan = finalizedPlan
    self.executingStepIndex = executingStepIndex
    self.replyText = replyText
    self.errorText = errorText
    self.isComplete = isComplete
    self.timestamp = timestamp
  }
}

@Generable(description: "Single action kind inside a Microduck Wingman mission step.")
public enum WingmanStepAction: String, Equatable, Sendable {
  case standUp
  case sitDown
  case walkForward
  case walkBackward
  case strafeLeft
  case strafeRight
  case turnLeft
  case turnRight
  case approachObstacle
  case backUpUntilClear
  case look
  case beak
  case chomp
  case headTilt
  case crouch
  case sound
  case trick

  public var displayTitle: String {
    switch self {
    case .standUp: "Stand Up"
    case .sitDown: "Sit Down"
    case .walkForward: "Walk Forward"
    case .walkBackward: "Walk Backward"
    case .strafeLeft: "Sidestep Left"
    case .strafeRight: "Sidestep Right"
    case .turnLeft: "Turn Left"
    case .turnRight: "Turn Right"
    case .approachObstacle: "Approach Obstacle"
    case .backUpUntilClear: "Back Up Until Clear"
    case .look: "Look"
    case .beak: "Beak"
    case .chomp: "Chomp"
    case .headTilt: "Head Tilt"
    case .crouch: "Crouch"
    case .sound: "Sound"
    case .trick: "Trick"
    }
  }

  public var systemImage: String {
    switch self {
    case .standUp: "figure.stand"
    case .sitDown: "figure.seated.side"
    case .walkForward: "arrow.up"
    case .walkBackward: "arrow.down"
    case .strafeLeft: "arrow.left"
    case .strafeRight: "arrow.right"
    case .turnLeft: "arrow.counterclockwise"
    case .turnRight: "arrow.clockwise"
    case .approachObstacle: "arrow.up.to.line"
    case .backUpUntilClear: "arrow.down.to.line"
    case .look: "eye"
    case .beak, .chomp: "mouth"
    case .headTilt: "rotate.left"
    case .crouch: "arrow.down.to.line.compact"
    case .sound: "speaker.wave.2"
    case .trick: "sparkles"
    }
  }
}

@Generable(description: "One bounded step in a Microduck mission plan using real-world distances, angles, clearances, or expressive controls.")
public struct WingmanMissionStep: Equatable, Sendable {
  @Guide(description: "The action to perform in this step.")
  public var action: WingmanStepAction

  @Guide(description: "Primary numeric parameter: meters (0.1 to 2.5) for walk/strafe, degrees (15 to 360) for turn, centimeters (20 to 150) for approach/backUp, horizontal gaze (-100 to 100) for look, or percent for beak (0 to 100), headTilt (-100 to 100), or crouch (0 to 100).")
  public var amount: Double?

  @Guide(description: "Optional secondary numeric parameter: vertical gaze (-100 to 100) for look, or duration seconds (0.5 to 3.0) for chomp.")
  public var secondaryAmount: Double?

  @Guide(description: "Optional label: sound tag (chirp, greet, inquire, alarm, peck, coo) for sound, or installed trick name for trick.")
  public var label: String?

  @Guide(description: "Concise 3 to 10 word description of this step.")
  public var note: String

  public init(
    action: WingmanStepAction,
    amount: Double? = nil,
    secondaryAmount: Double? = nil,
    label: String? = nil,
    note: String
  ) {
    self.action = action
    self.amount = amount
    self.secondaryAmount = secondaryAmount
    self.label = label
    self.note = note
  }
}

@Generable(description: "A structured, safe Microduck mission plan using real-world units (meters, degrees, centimeters) and expressive actions.")
public struct WingmanMissionPlan: Equatable, Sendable {
  @Guide(description: "Short 2 to 5 word title for this mission.")
  public var title: String

  @Guide(description: "One-sentence summary of what Microduck will do.")
  public var summary: String

  @Guide(description: "Ordered list of 1 to 6 bounded steps to execute.", .count(1...6))
  public var steps: [WingmanMissionStep]

  public init(title: String, summary: String, steps: [WingmanMissionStep]) {
    self.title = title
    self.summary = summary
    self.steps = steps
  }
}

/// UI-friendly snapshot of a streaming or finalized mission step.
public struct WingmanStepDraft: Identifiable, Equatable, Sendable {
  public var id: String
  public var action: WingmanStepAction?
  public var amount: Double?
  public var secondaryAmount: Double?
  public var label: String?
  public var note: String

  public init(
    id: String,
    action: WingmanStepAction? = nil,
    amount: Double? = nil,
    secondaryAmount: Double? = nil,
    label: String? = nil,
    note: String = ""
  ) {
    self.id = id
    self.action = action
    self.amount = amount
    self.secondaryAmount = secondaryAmount
    self.label = label
    self.note = note
  }

  public init(step: WingmanMissionStep, index: Int) {
    self.id = "step-\(index)"
    self.action = step.action
    self.amount = step.amount
    self.secondaryAmount = step.secondaryAmount
    self.label = step.label
    self.note = step.note
  }

  public var formattedBadge: String? {
    guard let action else { return nil }
    switch action {
    case .walkForward, .walkBackward, .strafeLeft, .strafeRight:
      let meters = amount ?? 0.4
      return String(format: "%.2f m", meters)
    case .turnLeft, .turnRight:
      let deg = Int((amount ?? 90).rounded())
      return "\(deg)°"
    case .approachObstacle, .backUpUntilClear:
      let cm = Int((amount ?? 30).rounded())
      return "\(cm) cm"
    case .beak, .headTilt, .crouch:
      if let amount { return "\(Int(amount.rounded()))%" }
      return nil
    case .chomp:
      let sec = secondaryAmount ?? 1.5
      return String(format: "%.1fs", sec)
    case .sound, .trick:
      return label
    case .look:
      if let x = amount {
        let y = secondaryAmount ?? 0
        return "\(Int(x.rounded()))%, \(Int(y.rounded()))%"
      }
      return nil
    case .standUp, .sitDown:
      return nil
    }
  }
}

public struct WingmanPlanUpdate: Equatable, Sendable {
  public var title: String?
  public var summary: String?
  public var steps: [WingmanStepDraft]
  public var finalizedPlan: WingmanMissionPlan?

  public init(
    title: String? = nil,
    summary: String? = nil,
    steps: [WingmanStepDraft] = [],
    finalizedPlan: WingmanMissionPlan? = nil
  ) {
    self.title = title
    self.summary = summary
    self.steps = steps
    self.finalizedPlan = finalizedPlan
  }
}

/// Builds state-aware system instructions and locomotion tool gates from live `DuckSessionSnapshot`.
public enum WingmanContextBuilder {
  public static func canDriveNow(_ snapshot: DuckSessionSnapshot) -> Bool {
    guard snapshot.controlOpen else { return false }
    if snapshot.latestState?.safety?.fallen == true { return false }
    if snapshot.latestState?.safety?.pickedUp == true { return false }
    if snapshot.policies?.enabled == false || snapshot.policies?.sitting == true { return false }
    return true
  }

  public static func stateSummary(for snapshot: DuckSessionSnapshot) -> String {
    let name = snapshot.phase.connected?.name ?? "Microduck"
    var lines: [String] = ["Robot: \(name) (connected: \(snapshot.controlOpen ? "yes" : "no"))"]

    if snapshot.latestState?.safety?.fallen == true {
      lines.append("Posture: FALLEN — must recover/stand up before walking.")
    } else if snapshot.latestState?.safety?.pickedUp == true {
      lines.append("Posture: PICKED UP — feet off the ground, do not walk.")
    } else if snapshot.policies?.sitting == true {
      lines.append("Posture: SITTING — stand up before walking.")
    } else if snapshot.policies?.enabled == false {
      lines.append("Posture: DISABLED — enable/stand up before walking.")
    } else {
      lines.append("Posture: STANDING and ready to walk.")
    }

    if let battery = snapshot.health?.battery {
      let pct = Int(battery.percent.rounded())
      var line = "Battery: \(pct)% (\(String(format: "%.2f", battery.volts)) V)"
      if pct < 20 {
        line += " — LOW BATTERY, keep movements short."
      }
      lines.append(line)
    }

    if let motors = snapshot.health?.motors {
      let temp = Int(motors.maxC.rounded())
      var line = "Motors: max \(temp)°C (\(motors.hottest))"
      if temp >= 55 {
        line += " — WARM, avoid intense tricks."
      }
      lines.append(line)
    }

    if let odom = snapshot.latestState?.odom {
      lines.append(
        String(
          format: "Odometry: x=%.2fm, y=%.2fm, heading=%.0f°",
          odom.x, odom.y, odom.yawDegrees
        )
      )
    }

    if let zones = snapshot.tofFrame?.analyzeZones() {
      let fmt: (Int?) -> String = { mm in mm.map { "\($0 / 10)cm" } ?? "clear" }
      lines.append(
        "8x8 ToF Clearances: left=\(fmt(zones.leftMm)), front=\(fmt(zones.frontMm)), right=\(fmt(zones.rightMm))"
      )
    }

    let skills = snapshot.skillNames
    if !skills.isEmpty {
      lines.append("Installed tricks: \(skills.joined(separator: ", "))")
    }

    return lines.joined(separator: "\n")
  }

  public static func agentInstructions(
    for snapshot: DuckSessionSnapshot,
    supportsVision: Bool
  ) -> String {
    var parts: [String] = [
      """
      You are Wingman, the in-app robotics controller for Microduck (a small bipedal duck robot).
      Always drive Microduck using real-world units: meters for walking/sidestepping, explicit left/right direction + positive degrees for turns, and centimeters for ToF obstacle approach or backing up.
      """,
      """
      Body vs. head & honesty rules (CRITICAL):
      - Microduck's neck can ONLY pan about ±35°. It CANNOT look 360° or look behind itself with look_and_snap!
      - Whenever the user asks to "look around 360°", search the room, or find/go to an object (like a pink ball, doorway, or chair) that is NOT clearly visible in the current camera image, you MUST call scan_surroundings(views: 4, direction: "left") to physically rotate Microduck's body and inspect all directions.
      - Once you locate a target in a scan view, use turn_angle to rotate Microduck's body to face that view, then call walk_distance or move_until_clearance to actually walk to it BEFORE answering.
      - NEVER promise a future action in text (never say "I'll now move forward" or "next I will walk") — execute the movement tool right now before replying.
      - NEVER claim you see an object unless it is genuinely visible in an attached camera image. If you didn't find it after scanning, honestly say you didn't see it and describe what you did see.
      - Never walk while Microduck is fallen, picked up, sitting, or disabled. Call set_posture(standUp or recover) first if needed.
      """,
    ]

    if supportsVision {
      parts.append(
        "Vision is enabled: call look_and_snap to inspect Microduck's live head camera and 8x8 ToF clearances when finding objects, doorways, or checking what is ahead."
      )
    } else {
      parts.append(
        "Vision images are unavailable on this model; rely on look_and_snap's 8x8 ToF zone clearances and odometry."
      )
    }

    parts.append("Live telemetry:\n\(stateSummary(for: snapshot))")
    return parts.joined(separator: "\n\n")
  }

  public static func missionPlanInstructions(for snapshot: DuckSessionSnapshot) -> String {
    """
    You are Wingman, Microduck's mission planner. Convert the user's request into a concise, safe WingmanMissionPlan (1 to 6 steps).
    - Prefer real-world units: meters (0.1 to 2.5 m), degrees (15 to 360°), and centimeters (20 to 150 cm for approachObstacle or backUpUntilClear).
    - If Microduck is sitting, disabled, or fallen, start the plan with a standUp step before any walking or turning.
    - Use expressive steps (look, beak, chomp, headTilt, crouch, sound, trick) when the user asks for personality or reactions.
    - Only use trick names from the installed tricks list.

    Live telemetry:
    \(stateSummary(for: snapshot))
    """
  }
}
