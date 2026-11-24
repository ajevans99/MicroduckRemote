import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

@AppIntent(.tool)
public struct ControlDuckBeakIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Control Microduck Beak"
  public static let description = IntentDescription(
    "Opens, closes, sets the opening percentage of, or playfully chomps and chatters Microduck's beak."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Action",
    description: "Whether to open the beak, close it, set a specific opening percentage, or animate a playful chomp.",
    default: .chomp
  )
  public var action: DuckBeakAction

  @Parameter(
    title: "Opening (%)",
    description: "Beak opening percentage from 0 (closed) to 100 (wide open). Used when Action is Set Opening or as peak opening for Chomp.",
    default: 100.0,
    controlStyle: .slider,
    inclusiveRange: (0.0, 100.0)
  )
  public var openingPercent: Double

  @Parameter(
    title: "Duration (Seconds)",
    description: "How long in seconds (0.4 to 5.0) to chomp or chatter the beak. Only applies when Action is Chomp.",
    default: 1.5,
    controlStyle: .field,
    inclusiveRange: (0.4, 5.0)
  )
  public var durationSeconds: Double

  public static var parameterSummary: some ParameterSummary {
    Switch(\.$action) {
      Case(.setPercent) {
        Summary("Set Microduck's beak to \(\.$openingPercent)% open")
      }
      Case(.chomp) {
        Summary("Chomp Microduck's beak for \(\.$durationSeconds) seconds")
      }
      DefaultCase {
        Summary("\(\.$action) Microduck's beak")
      }
    }
  }

  public init() {}

  public init(
    action: DuckBeakAction,
    openingPercent: Double = 100.0,
    durationSeconds: Double = 1.5
  ) {
    self.action = action
    self.openingPercent = openingPercent
    self.durationSeconds = durationSeconds
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    @Dependencies.Dependency(\.continuousClock) var clock

    var params = [IntentInvocationRecord.ParameterEntry(key: "action", value: action.rawValue)]
    switch action {
    case .setPercent:
      let clamped = Int(min(max(openingPercent, 0.0), 100.0).rounded())
      params.append(.init(key: "openingPercent", value: "\(clamped)%"))
    case .chomp:
      let clamped = min(max(durationSeconds, 0.4), 5.0)
      params.append(.init(key: "durationSeconds", value: clamped.formatted(.number.precision(.fractionLength(0...2)))))
    case .open, .close:
      break
    }

    let dialogText = try await DuckIntentRunner.runConnectedTool(
      intentName: "ControlDuckBeakIntent",
      displayTitle: "Control Microduck Beak",
      parameters: params,
      connectionTimeout: .seconds(5)
    ) { connection, duckSession in
      switch action {
      case .open:
        await duckSession.sendMouth(.wideOpen)
        return "Opened \(connection.duckName)'s beak."

      case .close:
        await duckSession.sendMouth(.closed)
        return "Closed \(connection.duckName)'s beak."

      case .setPercent:
        let clampedPercent = min(max(openingPercent, 0.0), 100.0)
        await duckSession.sendMouth(RobotMouthParams.fromPercent(clampedPercent))
        return "Set \(connection.duckName)'s beak to \(Int(clampedPercent.rounded()))% open."

      case .chomp:
        let clampedSeconds = min(max(durationSeconds, 0.4), 5.0)
        let peakOpen = min(max(openingPercent, 20.0), 100.0) / 100.0
        let hz = DuckConstants.intentHz
        let tickInterval = Duration.milliseconds(1000 / hz)
        let totalTicks = max(1, Int((clampedSeconds * Double(hz)).rounded()))

        do {
          for tick in 0..<totalTicks {
            try Task.checkCancellation()
            let openLevel = (tick / 2).isMultiple(of: 2) ? peakOpen : 0.0
            await duckSession.sendMouth(RobotMouthParams(open: openLevel))
            try await clock.sleep(for: tickInterval)
          }
          await duckSession.sendMouth(.closed)
        } catch {
          await duckSession.sendMouth(.closed)
          throw error
        }

        let formattedDuration = clampedSeconds.formatted(.number.precision(.fractionLength(0...1)))
        return "\(connection.duckName) chomped its beak for \(formattedDuration) seconds."
      }
    }

    return .result(value: dialogText)
  }
}
