import AppIntents
import DuckProtocol
import Foundation

public enum DuckWalkDirection: String, AppEnum, Sendable {
  case forward
  case backward
  case strafeLeft
  case strafeRight

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Walk Direction")

  public static let caseDisplayRepresentations: [DuckWalkDirection: DisplayRepresentation] = [
    .forward: DisplayRepresentation(
      title: "Forward",
      subtitle: "Walk straight ahead",
      image: .init(systemName: "arrow.up"),
      synonyms: ["Ahead", "Straight"]
    ),
    .backward: DisplayRepresentation(
      title: "Backward",
      subtitle: "Walk backward",
      image: .init(systemName: "arrow.down"),
      synonyms: ["Back", "Reverse"]
    ),
    .strafeLeft: DisplayRepresentation(
      title: "Left",
      subtitle: "Sidestep left",
      image: .init(systemName: "arrow.left"),
      synonyms: ["Sidestep Left", "Strafe Left"]
    ),
    .strafeRight: DisplayRepresentation(
      title: "Right",
      subtitle: "Sidestep right",
      image: .init(systemName: "arrow.right"),
      synonyms: ["Sidestep Right", "Strafe Right"]
    ),
  ]

  public var linearDirection: DuckLinearDirection {
    switch self {
    case .forward: .forward
    case .backward: .backward
    case .strafeLeft: .strafeLeft
    case .strafeRight: .strafeRight
    }
  }
}

public enum DuckTurnDirection: String, AppEnum, Sendable {
  case left
  case right

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Turn Direction")

  public static let caseDisplayRepresentations: [DuckTurnDirection: DisplayRepresentation] = [
    .left: DisplayRepresentation(
      title: "Left",
      subtitle: "Turn counterclockwise",
      image: .init(systemName: "arrow.counterclockwise"),
      synonyms: ["Counterclockwise", "CCW"]
    ),
    .right: DisplayRepresentation(
      title: "Right",
      subtitle: "Turn clockwise",
      image: .init(systemName: "arrow.clockwise"),
      synonyms: ["Clockwise", "CW"]
    ),
  ]
}

public enum DuckClearanceMode: String, AppEnum, Sendable {
  case approach
  case backUpUntilClear

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clearance Mode")

  public static let caseDisplayRepresentations: [DuckClearanceMode: DisplayRepresentation] = [
    .approach: DisplayRepresentation(
      title: "Approach Obstacle",
      subtitle: "Walk forward until reaching the target distance",
      image: .init(systemName: "arrow.up.to.line"),
      synonyms: ["Walk Up To", "Get Closer"]
    ),
    .backUpUntilClear: DisplayRepresentation(
      title: "Back Up Until Clear",
      subtitle: "Walk backward until clear space exceeds the target distance",
      image: .init(systemName: "arrow.down.to.line"),
      synonyms: ["Back Away", "Make Room"]
    ),
  ]
}
