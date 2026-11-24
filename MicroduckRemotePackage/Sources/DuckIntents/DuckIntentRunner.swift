import Dependencies
import DuckDependencies
import DuckProtocol

/// Composes `DuckSessionClient.connectForIntent` with `IntentTelemetryTracer.traceTool`
/// so individual tool intents stay focused on robot behavior rather than connection/tracing plumbing.
enum DuckIntentRunner {
  static func runConnectedTool<Output>(
    intentName: String,
    displayTitle: String,
    parameters: [IntentInvocationRecord.ParameterEntry] = [],
    connectionTimeout: Duration = .seconds(6),
    refreshIfOpen: Bool = false,
    operation: (_ connection: IntentConnection, _ duckSession: DuckSessionClient) async throws -> (output: Output, summary: String)
  ) async throws -> Output {
    @Dependency(\.duckSession) var duckSession

    return try await IntentTelemetryTracer.traceTool(
      intentName: intentName,
      displayTitle: displayTitle,
      parameters: parameters
    ) { setConnectionContext in
      let connection = try await duckSession.connectForIntent(
        timeout: connectionTimeout,
        refreshIfOpen: refreshIfOpen
      )
      setConnectionContext(connection.telemetryLabel)
      return try await operation(connection, duckSession)
    }
  }

  static func runConnectedTool(
    intentName: String,
    displayTitle: String,
    parameters: [IntentInvocationRecord.ParameterEntry] = [],
    connectionTimeout: Duration = .seconds(6),
    refreshIfOpen: Bool = false,
    operation: (_ connection: IntentConnection, _ duckSession: DuckSessionClient) async throws -> String
  ) async throws -> String {
    try await runConnectedTool(
      intentName: intentName,
      displayTitle: displayTitle,
      parameters: parameters,
      connectionTimeout: connectionTimeout,
      refreshIfOpen: refreshIfOpen
    ) { connection, duckSession in
      let message = try await operation(connection, duckSession)
      return (output: message, summary: message)
    }
  }
}
