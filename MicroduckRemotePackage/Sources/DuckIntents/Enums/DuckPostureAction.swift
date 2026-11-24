import AppIntents

public enum DuckPostureAction: String, AppEnum, Sendable {
  case standUp
  case sitDown
  case recoverFromFall
  case initPose

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Posture")

  public static let caseDisplayRepresentations: [DuckPostureAction: DisplayRepresentation] = [
    .standUp: DisplayRepresentation(
      title: "Stand Up",
      subtitle: "Enable balance and stand upright",
      image: .init(systemName: "figure.stand"),
      synonyms: ["Stand", "Get Up", "Wake Up"]
    ),
    .sitDown: DisplayRepresentation(
      title: "Sit Down",
      subtitle: "Park safely in the seated pose",
      image: .init(systemName: "figure.seated.side"),
      synonyms: ["Sit", "Rest", "Park"]
    ),
    .recoverFromFall: DisplayRepresentation(
      title: "Stand Back Up",
      subtitle: "Reset balance after a fall and stand upright",
      image: .init(systemName: "arrow.uturn.up.circle.fill"),
      synonyms: ["Recover", "Get Back Up", "Recover From Fall"]
    ),
    .initPose: DisplayRepresentation(
      title: "Home Pose",
      subtitle: "Ramp all servos to the neutral home pose",
      image: .init(systemName: "house.fill"),
      synonyms: ["Reset Pose", "Home"]
    ),
  ]
}
