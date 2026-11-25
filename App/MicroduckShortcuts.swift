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

    AppShortcut(
      intent: SnapDuckPhotoIntent(),
      phrases: [
        "Take a photo with \(.applicationName)",
        "Snap a photo from \(.applicationName)",
        "Show me what \(.applicationName) sees",
      ],
      shortTitle: "Snap Duck Photo",
      systemImageName: "camera.fill"
    )

    AppShortcut(
      intent: SetDuckModeIntent(),
      phrases: [
        "Start \(\.$mode) on \(.applicationName)",
        "Turn on \(\.$mode) on \(.applicationName)",
        "Enable \(\.$mode) on \(.applicationName)",
      ],
      shortTitle: "Duck Mode",
      systemImageName: "wand.and.stars"
    )

    AppShortcut(
      intent: SetDuckLightIntent(),
      phrases: [
        "Set \(.applicationName) light to \(\.$color)",
        "Turn \(.applicationName) light \(\.$color)",
      ],
      shortTitle: "Duck Light",
      systemImageName: "lightbulb.fill"
    )

    AppShortcut(
      intent: ExploreApartmentIntent(),
      phrases: [
        "Explore the room with \(.applicationName)",
        "Have \(.applicationName) explore",
      ],
      shortTitle: "Explore Room",
      systemImageName: "figure.walk.motion"
    )
  }
}
