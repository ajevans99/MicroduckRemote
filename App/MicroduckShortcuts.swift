import AppIntents
import DuckIntents

/// Surfaces preconfigured Microduck actions in Spotlight, the Action Button picker,
/// and the Shortcuts app gallery. Must live in the `.app` target so `appintentsmetadataprocessor`
/// resolves `\(.applicationName)` against the app bundle and populates `autoShortcuts`.
struct MicroduckShortcuts: AppShortcutsProvider {
  static let shortcutTileColor: ShortcutTileColor = .yellow

  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: EmergencyStopDuckIntent(),
      phrases: [
        "Stop \(.applicationName)",
        "Emergency stop \(.applicationName)",
        "Halt \(.applicationName)",
      ],
      shortTitle: "Stop Duck",
      systemImageName: "octagon.fill"
    )

    AppShortcut(
      intent: PlayDuckSoundIntent(),
      phrases: [
        "Play \(\.$sound) on \(.applicationName)",
        "Make \(.applicationName) \(\.$sound)",
        "Have \(.applicationName) play \(\.$sound)",
      ],
      shortTitle: "Play Duck Sound",
      systemImageName: "speaker.wave.2.fill"
    )
  }
}
