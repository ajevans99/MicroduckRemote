import AppIntents
import DuckProtocol
import Foundation

/// A single expressive beat in an Apple Intelligence–synthesized `DuckRoutine`.
/// Every stored property is a plain value type or `AppEnum` so `@AppEntity(.generable)`
/// lets Siri AI instantiate an array of steps directly from natural language.
@AppEntity(.generable)
public struct DuckRoutineStep: TransientAppEntity, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Routine Step")

  @Property(
    title: "Beat Description",
    description: "Short playful 2-to-5 word description of this beat (for example 'Peek left nervously' or 'Victory chirp')."
  )
  public var caption: String

  @Property(
    title: "Sound",
    description: "Optional vocal sound for this beat (chirp, greet, inquire, alarm, peck, coo, or wheee)."
  )
  public var sound: DuckSound?

  @Property(
    title: "Look Horizontal (%)",
    description: "Head yaw aim from -100 (far left) through 0 (straight ahead) to 100 (far right)."
  )
  public var lookHorizontalPercent: Int

  @Property(
    title: "Look Vertical (%)",
    description: "Head pitch aim from -100 (look high up at a person) through 0 (level) to 100 (look down at the floor)."
  )
  public var lookVerticalPercent: Int

  @Property(
    title: "Move Direction",
    description: "Optional walking or turning direction for this beat. Omit to stay in place while looking or making a sound."
  )
  public var moveDirection: DuckMoveDirection?

  @Property(
    title: "Duration (Seconds)",
    description: "Duration of this beat in seconds between 0.3 and 3.0."
  )
  public var durationSeconds: Double

  @Property(
    title: "Speed (%)",
    description: "Movement speed percentage from 20 (slow/cautious) to 100 (fast/excited). Used when Move Direction is set."
  )
  public var speedPercent: Int

  @Property(
    title: "Built-in Trick",
    description: "Optional acrobatic built-in trick (roulade, kickLeft, kickRight, or groundPick) to perform during this beat."
  )
  public var builtInTrick: DuckBuiltInTrick?

  @Property(
    title: "Light Color",
    description: "Optional RGB face light color for this beat (white, red, green, blue, yellow, cyan, magenta, or off)."
  )
  public var lightColor: DuckLightColor?

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: caption.isEmpty ? "Duck Beat" : caption),
      subtitle: LocalizedStringResource(stringLiteral: summarySubtitle),
      image: .init(systemName: "sparkles")
    )
  }

  public var summarySubtitle: String {
    var parts: [String] = []
    if let sound {
      parts.append(sound.soundTag.displayName)
    }
    if let builtInTrick {
      parts.append(InstalledSkillEntity.prettyName(for: builtInTrick.rawValue))
    } else if let moveDirection {
      parts.append(moveDirection.spokenLabel.capitalized)
    }
    if lookHorizontalPercent != 0 || lookVerticalPercent != 0 {
      parts.append("Look (\(clampedHorizontalPercent)%, \(clampedVerticalPercent)%)")
    }
    if let lightColor, lightColor != .off {
      parts.append("\(lightColor.rawValue.capitalized) light")
    }
    let secs = clampedDurationSeconds.formatted(.number.precision(.fractionLength(0...1)))
    parts.append("\(secs)s")
    return parts.joined(separator: " · ")
  }

  public var clampedHorizontalPercent: Int {
    min(max(lookHorizontalPercent, -100), 100)
  }

  public var clampedVerticalPercent: Int {
    min(max(lookVerticalPercent, -100), 100)
  }

  public var clampedDurationSeconds: Double {
    min(max(durationSeconds, 0.3), 3.0)
  }

  public var clampedSpeedPercent: Double {
    Double(min(max(speedPercent, 20), 100))
  }

  public var lookTarget: RobotLookParams {
    LookGeometry.lookTarget(
      normalizedX: Double(clampedHorizontalPercent) / 100.0,
      normalizedY: Double(clampedVerticalPercent) / 100.0
    )
  }

  public init() {
    self.caption = "Greet"
    self.sound = nil
    self.lookHorizontalPercent = 0
    self.lookVerticalPercent = 0
    self.moveDirection = nil
    self.durationSeconds = 0.8
    self.speedPercent = 60
    self.builtInTrick = nil
    self.lightColor = nil
  }

  public init(
    caption: String,
    sound: DuckSound? = nil,
    lookHorizontalPercent: Int = 0,
    lookVerticalPercent: Int = 0,
    moveDirection: DuckMoveDirection? = nil,
    durationSeconds: Double = 0.8,
    speedPercent: Int = 60,
    builtInTrick: DuckBuiltInTrick? = nil,
    lightColor: DuckLightColor? = nil
  ) {
    self.caption = caption
    self.sound = sound
    self.lookHorizontalPercent = lookHorizontalPercent
    self.lookVerticalPercent = lookVerticalPercent
    self.moveDirection = moveDirection
    self.durationSeconds = durationSeconds
    self.speedPercent = speedPercent
    self.builtInTrick = builtInTrick
    self.lightColor = lightColor
  }

  public static func == (lhs: DuckRoutineStep, rhs: DuckRoutineStep) -> Bool {
    lhs.caption == rhs.caption
      && lhs.sound == rhs.sound
      && lhs.lookHorizontalPercent == rhs.lookHorizontalPercent
      && lhs.lookVerticalPercent == rhs.lookVerticalPercent
      && lhs.moveDirection == rhs.moveDirection
      && lhs.durationSeconds == rhs.durationSeconds
      && lhs.speedPercent == rhs.speedPercent
      && lhs.builtInTrick == rhs.builtInTrick
      && lhs.lightColor == rhs.lightColor
  }
}
