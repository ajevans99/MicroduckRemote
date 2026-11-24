import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct PlayDuckSoundIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Play Duck Sound"
  public static let description = IntentDescription(
    "Plays an expressive sound on Microduck, such as chirp, greet, inquire, alarm, peck, coo, or a held wheee."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Sound",
    description: "Which sound expression Microduck should play.",
    default: .greet
  )
  public var sound: DuckSound

  @Parameter(
    title: "Hold Duration (Seconds)",
    description: "How long in seconds (0.3 to 5.0) to hold the sound. Only applies when Sound is Wheee.",
    default: 1.5,
    controlStyle: .field,
    inclusiveRange: (0.3, 5.0)
  )
  public var holdSeconds: Double

  public static var parameterSummary: some ParameterSummary {
    Switch(\.$sound) {
      Case(.wheee) {
        Summary("Play \(\.$sound) on Microduck for \(\.$holdSeconds) seconds")
      }
      DefaultCase {
        Summary("Play \(\.$sound) on Microduck")
      }
    }
  }

  public init() {}

  public init(sound: DuckSound, holdSeconds: Double = 1.5) {
    self.sound = sound
    self.holdSeconds = holdSeconds
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    @Dependencies.Dependency(\.duckSession) var duckSession
    @Dependencies.Dependency(\.continuousClock) var clock

    let tag = sound.soundTag
    var params = [IntentInvocationRecord.ParameterEntry(key: "sound", value: tag.rawValue)]
    if tag.isHoldable {
      params.append(.init(key: "holdSeconds", value: holdSeconds.formatted(.number.precision(.fractionLength(0...2)))))
    }

    let dialogText = try await IntentTelemetryTracer.traceTool(
      intentName: "PlayDuckSoundIntent",
      displayTitle: "Play Duck Sound",
      parameters: params
    ) { setContext in
      let connection = try await IntentTelemetryTracer.ensureConnected(timeout: .seconds(5))
      setContext(connection.contextLabel)

      guard tag.isHoldable else {
        await duckSession.playSound(tag, nil)
        let message = "\(connection.duckName) played \(tag.displayName)."
        return (message, message)
      }

      let clampedSeconds = min(max(holdSeconds, 0.3), 5.0)
      let hz = DuckConstants.intentHz
      let tickInterval = Duration.milliseconds(1000 / hz)
      let totalTicks = max(1, Int((clampedSeconds * Double(hz)).rounded()))

      do {
        for _ in 0..<totalTicks {
          try Task.checkCancellation()
          await duckSession.playSound(.wheee, true)
          try await clock.sleep(for: tickInterval)
        }
        await duckSession.playSound(.wheee, false)
      } catch {
        await duckSession.playSound(.wheee, false)
        throw error
      }

      let formattedDuration = clampedSeconds.formatted(.number.precision(.fractionLength(0...1)))
      let message = "\(connection.duckName) held Wheee for \(formattedDuration) seconds."
      return (message, message)
    }

    return .result(value: dialogText)
  }
}
