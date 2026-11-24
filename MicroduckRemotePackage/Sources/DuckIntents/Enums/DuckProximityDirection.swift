import AppIntents
import DuckProtocol

public enum DuckProximityDirection: String, AppEnum, Sendable {
  case forward
  case turnLeft
  case turnRight
  case clear

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Open Direction")

  public static let caseDisplayRepresentations: [DuckProximityDirection: DisplayRepresentation] = [
    .forward: DisplayRepresentation(
      title: "Forward",
      subtitle: "Path ahead is passable",
      image: .init(systemName: "arrow.up")
    ),
    .turnLeft: DisplayRepresentation(
      title: "Turn Left",
      subtitle: "More open space to the left",
      image: .init(systemName: "arrow.turn.up.left")
    ),
    .turnRight: DisplayRepresentation(
      title: "Turn Right",
      subtitle: "More open space to the right",
      image: .init(systemName: "arrow.turn.up.right")
    ),
    .clear: DisplayRepresentation(
      title: "Clear",
      subtitle: "Wide open space ahead and to both sides",
      image: .init(systemName: "checkmark.circle.fill")
    ),
  ]

  public init(_ direction: TofRecommendedDirection) {
    switch direction {
    case .forward: self = .forward
    case .turnLeft: self = .turnLeft
    case .turnRight: self = .turnRight
    case .clear: self = .clear
    }
  }

  public var label: String {
    switch self {
    case .forward: "Forward"
    case .turnLeft: "Turn Left"
    case .turnRight: "Turn Right"
    case .clear: "Clear"
    }
  }

  public var systemImage: String {
    switch self {
    case .forward: "arrow.up"
    case .turnLeft: "arrow.turn.up.left"
    case .turnRight: "arrow.turn.up.right"
    case .clear: "checkmark.circle.fill"
    }
  }
}
