import AppIntents

/// Matches Microduck's 3-channel RGB face flashlight (`duck_ipc_proto::FlashlightColor`)
/// plus `.off` so Siri AI and Shortcuts can set or turn off the headlight cleanly.
public enum DuckLightColor: String, AppEnum, Sendable {
  case off
  case white
  case red
  case green
  case blue
  case yellow
  case cyan
  case magenta

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Light Color")

  public static let caseDisplayRepresentations: [DuckLightColor: DisplayRepresentation] = [
    .off: DisplayRepresentation(
      title: "Off",
      subtitle: "Turn face light off",
      image: .init(systemName: "lightbulb.slash"),
      synonyms: ["Dark", "None"]
    ),
    .white: DisplayRepresentation(
      title: "White",
      subtitle: "Full white headlight",
      image: .init(systemName: "lightbulb.max.fill"),
      synonyms: ["Bright", "Headlight"]
    ),
    .red: DisplayRepresentation(
      title: "Red",
      subtitle: "Alert red glow",
      image: .init(systemName: "circle.fill"),
      synonyms: ["Alert", "Warning"]
    ),
    .green: DisplayRepresentation(
      title: "Green",
      subtitle: "Happy green glow",
      image: .init(systemName: "circle.fill"),
      synonyms: ["Go", "Success"]
    ),
    .blue: DisplayRepresentation(
      title: "Blue",
      subtitle: "Calm blue glow",
      image: .init(systemName: "circle.fill"),
      synonyms: ["Cool", "Calm"]
    ),
    .yellow: DisplayRepresentation(
      title: "Yellow",
      subtitle: "Warm yellow glow",
      image: .init(systemName: "circle.fill"),
      synonyms: ["Amber", "Gold", "Warm"]
    ),
    .cyan: DisplayRepresentation(
      title: "Cyan",
      subtitle: "Curious cyan glow",
      image: .init(systemName: "circle.fill"),
      synonyms: ["Aqua", "Teal"]
    ),
    .magenta: DisplayRepresentation(
      title: "Magenta",
      subtitle: "Playful magenta glow",
      image: .init(systemName: "circle.fill"),
      synonyms: ["Pink", "Purple"]
    ),
  ]
}
