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

    AppShortcut(
      intent: PerformTrickIntent(),
      phrases: [
        "Do \(\.$trick) on \(.applicationName)",
        "Make \(.applicationName) perform \(\.$trick)",
        "Have \(.applicationName) do \(\.$trick)",
      ],
      shortTitle: "Do Duck Trick",
      systemImageName: "sparkles"
    )

    AppShortcut(
      intent: GetDuckStatusIntent(),
      phrases: [
        "Check \(.applicationName) status",
        "How is \(.applicationName) doing",
        "Check \(.applicationName) battery",
      ],
      shortTitle: "Duck Status",
      systemImageName: "waveform.path.ecg"
    )

    AppShortcut(
      intent: SetDuckPostureIntent(),
      phrases: [
        "Have \(.applicationName) \(\.$posture)",
        "Make \(.applicationName) \(\.$posture)",
      ],
      shortTitle: "Duck Posture",
      systemImageName: "figure.stand"
    )

    AppShortcut(
      intent: MoveDuckStepIntent(),
      phrases: [
        "Move \(.applicationName) \(\.$direction)",
        "Walk \(.applicationName) \(\.$direction)",
      ],
      shortTitle: "Move Duck",
      systemImageName: "arrow.up.and.down.and.arrow.left.and.right"
    )
  }
}
