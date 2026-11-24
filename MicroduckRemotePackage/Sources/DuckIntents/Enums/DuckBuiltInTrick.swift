import AppIntents

/// Static `AppEnum` of built-in Microduck tricks so `@AppEntity(.generable)` routines can
/// include acrobatic beats directly without running an entity query.
public enum DuckBuiltInTrick: String, AppEnum, Sendable {
  case roulade
  case kickLeft = "kick_left"
  case kickRight = "kick_right"
  case groundPick = "ground_pick"

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Built-in Trick")

  public static let caseDisplayRepresentations: [DuckBuiltInTrick: DisplayRepresentation] = [
    .roulade: DisplayRepresentation(
      title: "Roulade",
      subtitle: "Forward somersault roll",
      image: .init(systemName: "arrow.trianglehead.2.clockwise.rotate.90"),
      synonyms: ["Roll", "Somersault", "Tumble"]
    ),
    .kickLeft: DisplayRepresentation(
      title: "Kick Left",
      subtitle: "Kick forward with the left foot",
      image: .init(systemName: "figure.soccer"),
      synonyms: ["Left Kick"]
    ),
    .kickRight: DisplayRepresentation(
      title: "Kick Right",
      subtitle: "Kick forward with the right foot",
      image: .init(systemName: "figure.soccer"),
      synonyms: ["Right Kick"]
    ),
    .groundPick: DisplayRepresentation(
      title: "Ground Pick",
      subtitle: "Lean down to peck or pick from the floor",
      image: .init(systemName: "hand.point.down.fill"),
      synonyms: ["Pick Up", "Bow Down", "Inspect Floor"]
    ),
  ]
}
