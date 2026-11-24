import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol

@AppIntent(.tool)
public struct SetDuckLightIntent: LiveActivityIntent {
  public static let title: LocalizedStringResource = "Set Microduck Light"
  public static let description = IntentDescription(
    "Sets Microduck's RGB face light to a specific color (white, red, green, blue, yellow, cyan, or magenta) or turns it off."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Color",
    description: "Target face light color, or Off to turn the light off.",
    default: .white
  )
  public var color: DuckLightColor

  public static var parameterSummary: some ParameterSummary {
    Switch(\.$color) {
      Case(.off) {
        Summary("Turn off Microduck's light")
      }
      DefaultCase {
        Summary("Set Microduck's light to \(\.$color)")
      }
    }
  }

  public init() {}

  public init(color: DuckLightColor) {
    self.color = color
  }

  public func perform() async throws -> some AppIntents.IntentResult & ReturnsValue<String> {
    let dialogText = try await DuckIntentRunner.runConnectedTool(
      intentName: "SetDuckLightIntent",
      displayTitle: "Set Microduck Light",
      parameters: [.init(key: "color", value: color.rawValue)]
    ) { connection, duckSession in
      if color == .off {
        try await duckSession.setFlashlightColor(false, "white")
        return "Turned off \(connection.duckName)'s light."
      } else {
        try await duckSession.setFlashlightColor(true, color.rawValue)
        return "Set \(connection.duckName)'s light to \(color.rawValue)."
      }
    }

    return .result(value: dialogText)
  }
}
