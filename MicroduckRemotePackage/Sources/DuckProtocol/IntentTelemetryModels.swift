import CasePaths
import Foundation

/// Captures a single App Intent tool invocation or entity query lookup made by Siri AI,
/// Shortcuts, Control Center, or Live Activities so developers can inspect exact parameters,
/// generated `GenerableEntity` payloads, cold-start behavior, latency, and outcomes in Telemetry.
public struct IntentInvocationRecord: Codable, Equatable, Identifiable, Sendable {
  @CasePathable
  public enum Kind: String, Codable, Equatable, Sendable {
    case toolIntent = "Tool Intent"
    case entityQuery = "Entity Query"
  }

  public struct ParameterEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(key)=\(value)" }
    public var key: String
    public var value: String

    public init(key: String, value: String) {
      self.key = key
      self.value = value
    }
  }

  @CasePathable
  @dynamicMemberLookup
  public enum Outcome: Codable, Equatable, Sendable {
    case succeeded(summary: String)
    case failed(error: String)

    public var isSuccess: Bool {
      self.is(\.succeeded)
    }

    public var message: String {
      switch self {
      case let .succeeded(summary): summary
      case let .failed(error): error
      }
    }
  }

  public var id: UUID
  public var timestamp: Date
  public var kind: Kind
  public var intentName: String
  public var displayTitle: String
  public var isToolIntent: Bool
  public var parameters: [ParameterEntry]
  public var connectionContext: String
  public var durationMs: Int
  public var outcome: Outcome

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    kind: Kind = .toolIntent,
    intentName: String,
    displayTitle: String,
    isToolIntent: Bool = true,
    parameters: [ParameterEntry] = [],
    connectionContext: String = "",
    durationMs: Int = 0,
    outcome: Outcome
  ) {
    self.id = id
    self.timestamp = timestamp
    self.kind = kind
    self.intentName = intentName
    self.displayTitle = displayTitle
    self.isToolIntent = isToolIntent
    self.parameters = parameters
    self.connectionContext = connectionContext
    self.durationMs = durationMs
    self.outcome = outcome
  }
}
