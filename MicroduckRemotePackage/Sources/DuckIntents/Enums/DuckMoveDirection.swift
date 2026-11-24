import AppIntents
import DuckProtocol
import Foundation

public enum DuckMoveDirection: String, AppEnum, Sendable {
  case forward
  case backward
  case strafeLeft
  case strafeRight
  case turnLeft
  case turnRight

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Move Direction")

  public static let caseDisplayRepresentations: [DuckMoveDirection: DisplayRepresentation] = [
    .forward: DisplayRepresentation(
      title: "Forward",
      subtitle: "Walk straight ahead",
      image: .init(systemName: "arrow.up"),
      synonyms: ["Ahead", "Straight", "Walk Forward"]
    ),
    .backward: DisplayRepresentation(
      title: "Backward",
      subtitle: "Walk backward",
      image: .init(systemName: "arrow.down"),
      synonyms: ["Back", "Reverse", "Back Up"]
    ),
    .strafeLeft: DisplayRepresentation(
      title: "Left",
      subtitle: "Sidestep to the left",
      image: .init(systemName: "arrow.left"),
      synonyms: ["Sidestep Left", "Strafe Left"]
    ),
    .strafeRight: DisplayRepresentation(
      title: "Right",
      subtitle: "Sidestep to the right",
      image: .init(systemName: "arrow.right"),
      synonyms: ["Sidestep Right", "Strafe Right"]
    ),
    .turnLeft: DisplayRepresentation(
      title: "Turn Left",
      subtitle: "Rotate counterclockwise in place",
      image: .init(systemName: "arrow.counterclockwise"),
      synonyms: ["Spin Left", "Rotate Left"]
    ),
    .turnRight: DisplayRepresentation(
      title: "Turn Right",
      subtitle: "Rotate clockwise in place",
      image: .init(systemName: "arrow.clockwise"),
      synonyms: ["Spin Right", "Rotate Right", "Turn Around"]
    ),
  ]

  public var spokenLabel: String {
    switch self {
    case .forward: "forward"
    case .backward: "backward"
    case .strafeLeft: "left"
    case .strafeRight: "right"
    case .turnLeft: "left in place"
    case .turnRight: "right in place"
    }
  }

  public func makeRequest(
    durationSeconds: Double,
    speedPercent: Double,
    stopOnObstacle: Bool
  ) -> DuckMoveStepRequest {
    let scale = min(max(speedPercent / 100.0, 0.2), 1.0)
    let linear = DuckConstants.maxLinearVelocity * scale
    let angular = DuckConstants.maxAngularVelocity * scale

    let (vx, vy, vyaw): (Double, Double, Double) = switch self {
    case .forward: (linear, 0, 0)
    case .backward: (DuckConstants.backwardLinearVelocity(magnitude: scale), 0, 0)
    case .strafeLeft: (0, linear, 0)
    case .strafeRight: (0, -linear, 0)
    case .turnLeft: (0, 0, angular)
    case .turnRight: (0, 0, -angular)
    }

    return DuckMoveStepRequest(
      vx: vx,
      vy: vy,
      vyaw: vyaw,
      durationSeconds: min(max(durationSeconds, 0.2), 5.0),
      stopOnObstacle: stopOnObstacle
    )
  }
}
