import AppIntents
import DuckProtocol

/// Bridges `DuckProtocol.SoundTag` into a static `AppEnum` vocabulary so Siri AI, Shortcuts,
/// and `appintentsmetadataprocessor` can index every case, icon, and natural-language synonym
/// at compile time.
public enum DuckSound: String, AppEnum, Sendable {
  case chirp
  case greet
  case inquire
  case alarm
  case peck
  case coo
  case wheee

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Sound")

  public static let caseDisplayRepresentations: [DuckSound: DisplayRepresentation] = [
    .chirp: DisplayRepresentation(
      title: "Chirp",
      subtitle: "Short cheerful chirp",
      image: .init(systemName: "waveform"),
      synonyms: ["Quack", "Peep", "Tweet"]
    ),
    .greet: DisplayRepresentation(
      title: "Greet",
      subtitle: "Friendly hello sound",
      image: .init(systemName: "hand.wave.fill"),
      synonyms: ["Hello", "Hi", "Say Hello", "Wave"]
    ),
    .inquire: DisplayRepresentation(
      title: "Inquire",
      subtitle: "Curious questioning chirp",
      image: .init(systemName: "questionmark.bubble.fill"),
      synonyms: ["Question", "Huh", "Curious", "Ask"]
    ),
    .alarm: DisplayRepresentation(
      title: "Alarm",
      subtitle: "Startled warning sound",
      image: .init(systemName: "exclamationmark.triangle.fill"),
      synonyms: ["Alert", "Siren", "Warning", "Startled"]
    ),
    .peck: DisplayRepresentation(
      title: "Peck",
      subtitle: "Quick beak peck sound",
      image: .init(systemName: "chevron.down.circle.fill"),
      synonyms: ["Tap", "Boop"]
    ),
    .coo: DisplayRepresentation(
      title: "Coo",
      subtitle: "Soft affectionate purr",
      image: .init(systemName: "heart.fill"),
      synonyms: ["Purr", "Happy", "Affectionate", "Love"]
    ),
    .wheee: DisplayRepresentation(
      title: "Wheee",
      subtitle: "Excited held sound",
      image: .init(systemName: "wind"),
      synonyms: ["Whee", "Celebrate", "Cheer", "Yay"]
    ),
  ]

  public init(_ soundTag: SoundTag) {
    switch soundTag {
    case .chirp: self = .chirp
    case .greet: self = .greet
    case .inquire: self = .inquire
    case .alarm: self = .alarm
    case .peck: self = .peck
    case .coo: self = .coo
    case .wheee: self = .wheee
    }
  }

  public var soundTag: SoundTag {
    switch self {
    case .chirp: .chirp
    case .greet: .greet
    case .inquire: .inquire
    case .alarm: .alarm
    case .peck: .peck
    case .coo: .coo
    case .wheee: .wheee
    }
  }
}
