import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation

enum IntentTelemetryTracer {
  static func traceTool<Output>(
    intentName: String,
    displayTitle: String,
    parameters: [IntentInvocationRecord.ParameterEntry] = [],
    operation: (_ setConnectionContext: @Sendable (String) -> Void) async throws -> (output: Output, summary: String)
  ) async throws -> Output {
    @Dependency(\.intentTelemetry) var telemetry

    let startedAt = ContinuousClock.now
    let connectionContext = LockIsolated("Not connected")

    do {
      let result = try await operation { label in
        connectionContext.setValue(label)
      }
      let elapsedMs = durationMilliseconds(since: startedAt)
      telemetry.record(
        IntentInvocationRecord(
          kind: .toolIntent,
          intentName: intentName,
          displayTitle: displayTitle,
          isToolIntent: true,
          parameters: parameters,
          connectionContext: connectionContext.value,
          durationMs: elapsedMs,
          outcome: .succeeded(summary: result.summary)
        )
      )
      return result.output
    } catch {
      let elapsedMs = durationMilliseconds(since: startedAt)
      let message = (error as? CancellationError) != nil
        ? "Cancelled"
        : error.localizedDescription
      telemetry.record(
        IntentInvocationRecord(
          kind: .toolIntent,
          intentName: intentName,
          displayTitle: displayTitle,
          isToolIntent: true,
          parameters: parameters,
          connectionContext: connectionContext.value,
          durationMs: elapsedMs,
          outcome: .failed(error: message)
        )
      )
      throw error
    }
  }

  static func traceQuery<Output>(
    queryName: String,
    displayTitle: String,
    parameters: [IntentInvocationRecord.ParameterEntry] = [],
    operation: () async throws -> (output: Output, connectionContext: String, summary: String)
  ) async throws -> Output {
    @Dependency(\.intentTelemetry) var telemetry

    let startedAt = ContinuousClock.now
    do {
      let result = try await operation()
      let elapsedMs = durationMilliseconds(since: startedAt)
      telemetry.record(
        IntentInvocationRecord(
          kind: .entityQuery,
          intentName: queryName,
          displayTitle: displayTitle,
          isToolIntent: false,
          parameters: parameters,
          connectionContext: result.connectionContext,
          durationMs: elapsedMs,
          outcome: .succeeded(summary: result.summary)
        )
      )
      return result.output
    } catch {
      let elapsedMs = durationMilliseconds(since: startedAt)
      telemetry.record(
        IntentInvocationRecord(
          kind: .entityQuery,
          intentName: queryName,
          displayTitle: displayTitle,
          isToolIntent: false,
          parameters: parameters,
          connectionContext: "Query error",
          durationMs: elapsedMs,
          outcome: .failed(error: error.localizedDescription)
        )
      )
      throw error
    }
  }

  private static func durationMilliseconds(since start: ContinuousClock.Instant) -> Int {
    let duration = start.duration(to: .now)
    let seconds = Double(duration.components.seconds)
    let attoseconds = Double(duration.components.attoseconds) / 1e18
    return max(0, Int(((seconds + attoseconds) * 1000.0).rounded()))
  }
}
