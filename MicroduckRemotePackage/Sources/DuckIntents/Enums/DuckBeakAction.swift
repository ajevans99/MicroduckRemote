import AppIntents

public enum DuckBeakAction: String, AppEnum, CaseIterable, Sendable {
  case open
  case close
  case setPercent
  case chomp

  public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Beak Action"

  public static let caseDisplayRepresentations: [DuckBeakAction: DisplayRepresentation] = [
    .open: DisplayRepresentation(
      title: "Open",
      subtitle: "Open Microduck's beak wide",
      image: .init(systemName: "mouth.fill")
    ),
    .close: DisplayRepresentation(
      title: "Close",
      subtitle: "Close Microduck's beak",
      image: .init(systemName: "mouth")
    ),
    .setPercent: DisplayRepresentation(
      title: "Set Opening",
      subtitle: "Open Microduck's beak to a specific percentage",
      image: .init(systemName: "slider.horizontal.3")
    ),
    .chomp: DisplayRepresentation(
      title: "Chomp",
      subtitle: "Playfully chatter or chomp Microduck's beak",
      image: .init(systemName: "waveform.path")
    ),
  ]
}
