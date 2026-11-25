import CoreGraphics
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import FoundationModels

public enum WingmanError: Error, LocalizedError, Equatable, Sendable {
  case backendUnavailable(String)
  case emptyPlan

  public var errorDescription: String? {
    switch self {
    case let .backendUnavailable(reason):
      reason
    case .emptyPlan:
      "Wingman did not produce a valid mission plan."
    }
  }
}

public struct WingmanClient: Sendable {
  public var backendStatus: @Sendable (WingmanModelBackend) -> WingmanBackendStatus
  public var runAgentPrompt: @Sendable (
    _ prompt: String,
    _ backend: WingmanModelBackend,
    _ snapshot: DuckSessionSnapshot,
    _ attachCameraFrame: Bool,
    _ onActivity: @escaping WingmanActivityObserver
  ) async throws -> String
  public var streamMissionPlan: @Sendable (
    _ prompt: String,
    _ backend: WingmanModelBackend,
    _ snapshot: DuckSessionSnapshot
  ) -> AsyncThrowingStream<WingmanPlanUpdate, Error>

  public init(
    backendStatus: @escaping @Sendable (WingmanModelBackend) -> WingmanBackendStatus,
    runAgentPrompt: @escaping @Sendable (
      String,
      WingmanModelBackend,
      DuckSessionSnapshot,
      Bool,
      @escaping WingmanActivityObserver
    ) async throws -> String,
    streamMissionPlan: @escaping @Sendable (
      String,
      WingmanModelBackend,
      DuckSessionSnapshot
    ) -> AsyncThrowingStream<WingmanPlanUpdate, Error>
  ) {
    self.backendStatus = backendStatus
    self.runAgentPrompt = runAgentPrompt
    self.streamMissionPlan = streamMissionPlan
  }
}

extension WingmanClient: DependencyKey {
  public static var liveValue: WingmanClient {
    WingmanClient(
      backendStatus: { backend in
        resolveBackendStatus(backend)
      },
      runAgentPrompt: { promptText, backend, snapshot, attachCameraFrame, onActivity in
        @Dependency(\.duckSession) var duckSession
        let status = resolveBackendStatus(backend)
        guard status.isAvailable else {
          throw WingmanError.backendUnavailable(status.statusText)
        }

        let tools = buildAgentTools(
          snapshot: snapshot,
          duckSession: duckSession,
          supportsVision: status.supportsVision,
          onActivity: onActivity
        )
        let instructionsText = WingmanContextBuilder.agentInstructions(
          for: snapshot,
          supportsVision: status.supportsVision
        )

        var attachedCGImage: CGImage?
        if attachCameraFrame, status.supportsVision, snapshot.hasVideoTrack {
          if let frame = try? await duckSession.capturePhoto() {
            attachedCGImage = WingmanImageDecoder.decodeCGImage(from: frame.jpegData)
            onActivity(
              WingmanActivityItem(
                kind: .toolCall,
                title: "Attached Live Camera",
                detail: "\(frame.width)×\(frame.height) frame sent with prompt",
                status: .succeeded,
                thumbnailJPEG: frame.jpegData
              )
            )
          }
        }

        let userPrompt: Prompt = if let cgImage = attachedCGImage {
          Prompt {
            Attachment(cgImage).label("live-cockpit-frame")
            promptText
          }
        } else {
          Prompt(promptText)
        }

        let session = makeSession(
          backend: backend,
          tools: tools,
          instructions: Instructions(instructionsText)
        )
        let response = try await session.respond(to: userPrompt)
        return response.content
      },
      streamMissionPlan: { promptText, backend, snapshot in
        AsyncThrowingStream { continuation in
          let task = Task {
            do {
              let status = resolveBackendStatus(backend)
              guard status.isAvailable else {
                throw WingmanError.backendUnavailable(status.statusText)
              }

              let instructionsText = WingmanContextBuilder.missionPlanInstructions(for: snapshot)
              let session = makeSession(
                backend: backend,
                tools: [],
                instructions: Instructions(instructionsText)
              )

              let stream = session.streamResponse(
                to: Prompt(promptText),
                generating: WingmanMissionPlan.self
              )

              var latestPlan: WingmanMissionPlan?
              for try await partial in stream {
                try Task.checkCancellation()
                let content = partial.content
                let drafts: [WingmanStepDraft] = (content.steps ?? []).enumerated().map { idx, step in
                  WingmanStepDraft(
                    id: "step-\(idx)",
                    action: step.action,
                    amount: step.amount,
                    secondaryAmount: step.secondaryAmount,
                    label: step.label,
                    note: step.note ?? ""
                  )
                }

                if
                  let title = content.title,
                  let summary = content.summary,
                  let rawSteps = content.steps,
                  !rawSteps.isEmpty
                {
                  let concreteSteps: [WingmanMissionStep] = rawSteps.compactMap { step in
                    guard let action = step.action else { return nil }
                    return WingmanMissionStep(
                      action: action,
                      amount: step.amount,
                      secondaryAmount: step.secondaryAmount,
                      label: step.label,
                      note: step.note ?? action.displayTitle
                    )
                  }
                  if concreteSteps.count == rawSteps.count {
                    latestPlan = WingmanMissionPlan(
                      title: title,
                      summary: summary,
                      steps: concreteSteps
                    )
                  }
                }

                continuation.yield(
                  WingmanPlanUpdate(
                    title: content.title,
                    summary: content.summary,
                    steps: drafts,
                    finalizedPlan: nil
                  )
                )
              }

              let finalized = try await stream.collect().content
              let finalDrafts = finalized.steps.enumerated().map { idx, step in
                WingmanStepDraft(step: step, index: idx)
              }
              continuation.yield(
                WingmanPlanUpdate(
                  title: finalized.title,
                  summary: finalized.summary,
                  steps: finalDrafts,
                  finalizedPlan: finalized
                )
              )
              _ = latestPlan
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in
            task.cancel()
          }
        }
      }
    )
  }

  public static var previewValue: WingmanClient {
    WingmanClient(
      backendStatus: { backend in
        WingmanBackendStatus(
          isAvailable: true,
          supportsVision: true,
          statusText: backend == .onDevice ? "Apple Intelligence Ready" : "Private Cloud Ready"
        )
      },
      runAgentPrompt: { prompt, _, _, _, onActivity in
        onActivity(
          WingmanActivityItem(
            kind: .toolCall,
            title: "Walk Forward",
            detail: "Walked forward 0.50 m.",
            status: .succeeded
          )
        )
        return "Completed '\(prompt)' using closed-loop odometry."
      },
      streamMissionPlan: { prompt, _, _ in
        let plan = WingmanMissionPlan(
          title: "Scout & Greet",
          summary: "Walk forward half a meter, turn left 90°, and chomp happily.",
          steps: [
            WingmanMissionStep(action: .walkForward, amount: 0.5, note: "Walk forward 0.50 m"),
            WingmanMissionStep(action: .turnLeft, amount: 90, note: "Turn left 90°"),
            WingmanMissionStep(action: .chomp, secondaryAmount: 1.4, note: "Chomp beak playfully"),
          ]
        )
        return AsyncThrowingStream { continuation in
          continuation.yield(
            WingmanPlanUpdate(
              title: plan.title,
              summary: "Planning '\(prompt)'…",
              steps: [WingmanStepDraft(step: plan.steps[0], index: 0)]
            )
          )
          continuation.yield(
            WingmanPlanUpdate(
              title: plan.title,
              summary: plan.summary,
              steps: plan.steps.enumerated().map { WingmanStepDraft(step: $0.element, index: $0.offset) },
              finalizedPlan: plan
            )
          )
          continuation.finish()
        }
      }
    )
  }

  public static var testValue: WingmanClient {
    previewValue
  }

  private static func resolveBackendStatus(_ backend: WingmanModelBackend) -> WingmanBackendStatus {
    switch backend {
    case .onDevice:
      let model = SystemLanguageModel.default
      let supportsVision = model.capabilities.contains(.vision)
      switch model.availability {
      case .available:
        return WingmanBackendStatus(
          isAvailable: true,
          supportsVision: supportsVision,
          statusText: supportsVision ? "On-Device · Vision Ready" : "On-Device Ready"
        )
      case let .unavailable(reason):
        return WingmanBackendStatus(
          isAvailable: false,
          supportsVision: false,
          statusText: describeOnDeviceUnavailable(reason)
        )
      }

    case .privateCloudCompute:
      let model = PrivateCloudComputeLanguageModel()
      let supportsVision = model.capabilities.contains(.vision)
      switch model.availability {
      case .available:
        return WingmanBackendStatus(
          isAvailable: true,
          supportsVision: supportsVision,
          statusText: supportsVision ? "Private Cloud · Vision Ready" : "Private Cloud Ready"
        )
      case let .unavailable(reason):
        let reasonText = switch reason {
        case .deviceNotEligible: "Device not eligible for Private Cloud Compute"
        case .systemNotReady: "Private Cloud Compute is not ready"
        @unknown default: "Private Cloud Compute unavailable"
        }
        return WingmanBackendStatus(
          isAvailable: false,
          supportsVision: false,
          statusText: reasonText
        )
      }
    }
  }

  private static func describeOnDeviceUnavailable(
    _ reason: SystemLanguageModel.Availability.UnavailableReason
  ) -> String {
    switch reason {
    case .deviceNotEligible:
      "Device does not support Apple Intelligence"
    case .appleIntelligenceNotEnabled:
      "Enable Apple Intelligence in Settings"
    case .modelNotReady:
      "On-device model is still downloading"
    @unknown default:
      "On-device model unavailable"
    }
  }

  private static func makeSession(
    backend: WingmanModelBackend,
    tools: [any Tool],
    instructions: Instructions
  ) -> LanguageModelSession {
    switch backend {
    case .onDevice:
      LanguageModelSession(
        model: SystemLanguageModel.default,
        tools: tools,
        instructions: instructions
      )
    case .privateCloudCompute:
      LanguageModelSession(
        model: PrivateCloudComputeLanguageModel(),
        tools: tools,
        instructions: instructions
      )
    }
  }

  private static func buildAgentTools(
    snapshot: DuckSessionSnapshot,
    duckSession: DuckSessionClient,
    supportsVision: Bool,
    onActivity: @escaping WingmanActivityObserver
  ) -> [any Tool] {
    let serializer = WingmanToolSerializer()
    var tools: [any Tool] = [
      PostureDuckTool(duckSession: duckSession, serializer: serializer, onActivity: onActivity),
      LookAndSnapDuckTool(
        duckSession: duckSession,
        supportsVision: supportsVision,
        serializer: serializer,
        onActivity: onActivity
      ),
      ExpressDuckTool(duckSession: duckSession, serializer: serializer, onActivity: onActivity),
    ]

    // Expose locomotion & trick tools when Microduck isn't picked up or fallen; if sitting,
    // keep them available so Wingman can chain set_posture(standUp) -> walk_distance cleanly.
    if snapshot.latestState?.safety?.pickedUp != true {
      tools.append(
        ScanSurroundingsDuckTool(
          duckSession: duckSession,
          supportsVision: supportsVision,
          serializer: serializer,
          onActivity: onActivity
        )
      )
      tools.append(WalkDuckDistanceTool(duckSession: duckSession, serializer: serializer, onActivity: onActivity))
      tools.append(TurnDuckAngleTool(duckSession: duckSession, serializer: serializer, onActivity: onActivity))
      tools.append(ClearanceMoveDuckTool(duckSession: duckSession, serializer: serializer, onActivity: onActivity))
      tools.append(PerformDuckTrickTool(duckSession: duckSession, serializer: serializer, onActivity: onActivity))
    }

    return tools
  }
}

extension DependencyValues {
  public var wingman: WingmanClient {
    get { self[WingmanClient.self] }
    set { self[WingmanClient.self] = newValue }
  }
}
