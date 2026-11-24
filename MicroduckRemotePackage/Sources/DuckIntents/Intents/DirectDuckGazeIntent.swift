import AppIntents
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

public struct DirectDuckGazeIntent: AppIntent {
  public static let title: LocalizedStringResource = "Aim Microduck Head"
  public static let description = IntentDescription(
    "Aims Microduck's head and camera toward a horizontal and vertical direction (for example look left, look up at a person, look down at the floor, or center ahead)."
  )

  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let openAppWhenRun: Bool = false

  @Parameter(
    title: "Horizontal (%)",
    description: "Left/right gaze target from -100 (far left) through 0 (center) to 100 (far right).",
    default: 0.0,
    controlStyle: .slider,
    inclusiveRange: (-100.0, 100.0)
  )
  public var horizontalPercent: Double

  @Parameter(
    title: "Vertical (%)",
    description: "Up/down gaze target from -100 (look up) through 0 (level) to 100 (look down at the floor).",
    default: 0.0,
    controlStyle: .slider,
    inclusiveRange: (-100.0, 100.0)
  )
  public var verticalPercent: Double

  public static var parameterSummary: some ParameterSummary {
    Summary("Aim Microduck's head to (\(\.$horizontalPercent)%, \(\.$verticalPercent)%)")
  }

  public init() {}

  public init(horizontalPercent: Double = 0, verticalPercent: Double = 0) {
    self.horizontalPercent = horizontalPercent
    self.verticalPercent = verticalPercent
  }

  public func perform() async throws -> some AppIntents.IntentResult & ProvidesDialog {
    @Dependencies.Dependency(\.duckSession) var duckSession

    let initial = await duckSession.currentSnapshot()
    let duckName: String
    if initial.controlOpen {
      duckName = initial.phase.connected?.name ?? "Microduck"
    } else {
      let identity = try await duckSession.ensureConnected(.seconds(6))
      duckName = identity.name
    }

    let target = LookGeometry.lookTarget(
      normalizedX: min(max(horizontalPercent, -100), 100) / 100.0,
      normalizedY: min(max(verticalPercent, -100), 100) / 100.0
    )
    let result = await duckSession.sendLook(target)
    if result?.clamped == true {
      return .result(dialog: "Aimed \(duckName)'s head toward your target (clamped to joint limits).")
    }
    return .result(dialog: "Aimed \(duckName)'s head.")
  }
}

@available(iOS 27.3, macOS 27.3, *)
extension DirectDuckGazeIntent: ToolIntent, LiveActivityIntent {}
