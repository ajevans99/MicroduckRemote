import AppIntents

public enum DuckAutonomousMode: String, AppEnum, CaseIterable, Sendable {
  case autonomous
  case soccer
  case laserTrack

  public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Duck Mode"

  public static let caseDisplayRepresentations: [DuckAutonomousMode: DisplayRepresentation] = [
    .autonomous: DisplayRepresentation(
      title: "Autonomous Roaming",
      subtitle: "Let Microduck explore on its own",
      image: .init(systemName: "wand.and.stars")
    ),
    .soccer: DisplayRepresentation(
      title: "Soccer",
      subtitle: "Chase and kick a soccer ball",
      image: .init(systemName: "soccerball")
    ),
    .laserTrack: DisplayRepresentation(
      title: "Laser Tracking",
      subtitle: "Follow a laser pointer dot",
      image: .init(systemName: "scope")
    ),
  ]

  public var spokenLabel: String {
    switch self {
    case .autonomous: "autonomous roaming"
    case .soccer: "soccer mode"
    case .laserTrack: "laser tracking"
    }
  }
}
