import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import Observation

@Observable
@MainActor
public final class WingmanModel {
  @ObservationIgnored @Dependency(\.wingman) var wingman
  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.continuousClock) var clock

  public var backend: WingmanModelBackend = .onDevice
  public var mode: WingmanMode = .agent
  public var promptText = ""
  public var attachCameraFrame = true
  public var autoRunPlan = false

  public var backendStatus = WingmanBackendStatus(
    isAvailable: true,
    supportsVision: false,
    statusText: "Checking Apple Intelligence…"
  )
  public var snapshot = DuckSessionSnapshot()

  public var isRunning = false
  public var isExecutingPlan = false
  public var activeStatusSummary: String?
  public var turns: [WingmanTurn] = []
  public var responseText: String?
  public var streamingTitle: String?
  public var streamingSummary: String?
  public var streamingSteps: [WingmanStepDraft] = []
  public var finalizedPlan: WingmanMissionPlan?
  public var executingStepIndex: Int?
  public var activities: [WingmanActivityItem] = []
  public var errorMessage: String?

  @ObservationIgnored private var activeTask: Task<Void, Never>?

  public static let starters: [WingmanStarter] = [
    WingmanStarter(
      title: "Walk & Chomp",
      subtitle: "0.5 m forward · turn left 90° · chomp",
      systemImage: "figure.walk",
      prompt: "Walk forward 0.5m, turn left 90°, and chomp happily"
    ),
    WingmanStarter(
      title: "360° Room Scan",
      subtitle: "Turn body 360° & inspect with camera + ToF",
      systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
      prompt: "Look around 360 degrees and tell me what you see around the room"
    ),
    WingmanStarter(
      title: "Approach 30 cm",
      subtitle: "Walk up to the obstacle ahead",
      systemImage: "arrow.up.to.line",
      prompt: "Walk up to the obstacle ahead and stop 30 cm away"
    ),
    WingmanStarter(
      title: "About-Face",
      subtitle: "Turn 180° · tilt head · chirp",
      systemImage: "arrow.uturn.left",
      prompt: "Turn around 180°, tilt your head curiously, and chirp"
    ),
  ]

  public static var quickPrompts: [String] {
    starters.map(\.prompt)
  }

  public init() {}

  public var canSubmit: Bool {
    !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isRunning
      && !isExecutingPlan
      && backendStatus.isAvailable
      && snapshot.controlOpen
  }

  public func task() async {
    refreshBackendStatus()
    snapshot = await duckSession.currentSnapshot()
    for await updated in duckSession.snapshots() {
      snapshot = updated
    }
  }

  public func refreshBackendStatus() {
    backendStatus = wingman.backendStatus(backend)
  }

  public func backendSelected(_ next: WingmanModelBackend) {
    backend = next
    refreshBackendStatus()
  }

  public func quickPromptTapped(_ prompt: String) {
    promptText = prompt
    runButtonTapped()
  }

  public func runButtonTapped() {
    let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isRunning, !isExecutingPlan else { return }

    promptText = ""
    errorMessage = nil
    responseText = nil
    streamingTitle = nil
    streamingSummary = nil
    streamingSteps = []
    finalizedPlan = nil
    executingStepIndex = nil
    isRunning = true
    activeStatusSummary = mode == .agent ? "Thinking…" : "Planning mission…"

    let turnID = UUID()
    turns.append(
      WingmanTurn(
        id: turnID,
        userPrompt: trimmed,
        mode: mode,
        backend: backend
      )
    )

    activeTask?.cancel()
    activeTask = Task { [weak self] in
      guard let self else { return }
      await self.executePrompt(trimmed, turnID: turnID)
    }
  }

  public func runPlanButtonTapped(turnID: UUID? = nil) {
    let targetID = turnID ?? turns.last(where: { $0.finalizedPlan != nil })?.id
    let plan: WingmanMissionPlan? = if let targetID, let turn = turns.first(where: { $0.id == targetID }) {
      turn.finalizedPlan
    } else {
      finalizedPlan
    }
    guard let plan, !isExecutingPlan else { return }

    errorMessage = nil
    isExecutingPlan = true
    executingStepIndex = nil
    activeStatusSummary = "Running \(plan.title)…"

    activeTask?.cancel()
    activeTask = Task { [weak self] in
      guard let self else { return }
      await self.executePlan(plan, turnID: targetID)
    }
  }

  public func stopButtonTapped() async {
    activeTask?.cancel()
    activeTask = nil
    isRunning = false
    isExecutingPlan = false
    executingStepIndex = nil
    activeStatusSummary = nil
    if let lastIdx = turns.indices.last, !turns[lastIdx].isComplete {
      turns[lastIdx].isComplete = true
      turns[lastIdx].executingStepIndex = nil
    }
    await duckSession.sendMove(.zero)
    try? await duckSession.stop()
  }

  public func clearButtonTapped() {
    guard !isRunning, !isExecutingPlan else { return }
    turns = []
    responseText = nil
    streamingTitle = nil
    streamingSummary = nil
    streamingSteps = []
    finalizedPlan = nil
    activities = []
    errorMessage = nil
    activeStatusSummary = nil
  }

  private func executePrompt(_ prompt: String, turnID: UUID) async {
    let currentSnapshot = await duckSession.currentSnapshot()
    snapshot = currentSnapshot

    do {
      switch mode {
      case .agent:
        let reply = try await wingman.runAgentPrompt(
          prompt,
          backend,
          currentSnapshot,
          attachCameraFrame
        ) { [weak self] item in
          Task { @MainActor [weak self] in
            self?.recordToolActivity(item, turnID: turnID)
          }
        }
        responseText = reply
        updateTurn(id: turnID) { turn in
          turn.replyText = reply
          turn.isComplete = true
        }
        upsertActivity(
          WingmanActivityItem(
            kind: .narration,
            title: "Wingman",
            detail: reply,
            status: .succeeded
          )
        )
        isRunning = false
        activeStatusSummary = nil

      case .missionPlan:
        for try await update in wingman.streamMissionPlan(prompt, backend, currentSnapshot) {
          if let title = update.title {
            streamingTitle = title
            activeStatusSummary = "Planning: \(title)"
          }
          if let summary = update.summary {
            streamingSummary = summary
          }
          if !update.steps.isEmpty {
            streamingSteps = update.steps
          }
          if let plan = update.finalizedPlan {
            finalizedPlan = plan
          }
          updateTurn(id: turnID) { turn in
            if let title = update.title { turn.planTitle = title }
            if let summary = update.summary { turn.planSummary = summary }
            if !update.steps.isEmpty { turn.planSteps = update.steps }
            if let plan = update.finalizedPlan { turn.finalizedPlan = plan }
          }
        }
        isRunning = false
        if autoRunPlan, let plan = finalizedPlan {
          isExecutingPlan = true
          await executePlan(plan, turnID: turnID)
        } else {
          activeStatusSummary = nil
          updateTurn(id: turnID) { turn in
            turn.isComplete = true
          }
        }
      }
    } catch is CancellationError {
      isRunning = false
      activeStatusSummary = nil
      updateTurn(id: turnID) { $0.isComplete = true }
    } catch {
      isRunning = false
      activeStatusSummary = nil
      errorMessage = error.localizedDescription
      updateTurn(id: turnID) { turn in
        turn.errorText = error.localizedDescription
        turn.isComplete = true
      }
      upsertActivity(
        WingmanActivityItem(
          kind: .error,
          title: "Wingman Error",
          detail: error.localizedDescription,
          status: .failed
        )
      )
    }
  }

  private func executePlan(_ plan: WingmanMissionPlan, turnID: UUID?) async {
    do {
      try await WingmanMissionExecutor.execute(
        plan: plan,
        duckSession: duckSession,
        clock: clock,
        onStepStarted: { [weak self] index, step in
          await MainActor.run {
            self?.executingStepIndex = index
            self?.activeStatusSummary = "\(index + 1)/\(plan.steps.count) · \(step.action.displayTitle)"
            if let turnID {
              self?.updateTurn(id: turnID) { $0.executingStepIndex = index }
            }
          }
        },
        onActivity: { [weak self] item in
          Task { @MainActor [weak self] in
            if let turnID {
              self?.recordToolActivity(item, turnID: turnID)
            } else {
              self?.upsertActivity(item)
            }
          }
        }
      )
      isExecutingPlan = false
      executingStepIndex = nil
      activeStatusSummary = nil
      let completionMsg = "Completed mission: \(plan.title)."
      responseText = completionMsg
      if let turnID {
        updateTurn(id: turnID) { turn in
          turn.executingStepIndex = nil
          turn.replyText = completionMsg
          turn.isComplete = true
        }
      }
    } catch is CancellationError {
      isExecutingPlan = false
      executingStepIndex = nil
      activeStatusSummary = nil
      if let turnID {
        updateTurn(id: turnID) { turn in
          turn.executingStepIndex = nil
          turn.isComplete = true
        }
      }
    } catch {
      isExecutingPlan = false
      executingStepIndex = nil
      activeStatusSummary = nil
      errorMessage = error.localizedDescription
      if let turnID {
        updateTurn(id: turnID) { turn in
          turn.executingStepIndex = nil
          turn.errorText = error.localizedDescription
          turn.isComplete = true
        }
      }
    }
  }

  private func recordToolActivity(_ item: WingmanActivityItem, turnID: UUID) {
    upsertActivity(item)
    if item.status == .running {
      activeStatusSummary = "\(item.title) · \(item.detail)"
    }
    updateTurn(id: turnID) { turn in
      if item.title == "Attached Live Camera", let jpeg = item.thumbnailJPEG {
        turn.attachedFrameJPEG = jpeg
        return
      }
      if let idx = turn.toolSteps.firstIndex(where: { $0.id == item.id }) {
        turn.toolSteps[idx] = item
      } else {
        turn.toolSteps.append(item)
      }
    }
  }

  private func updateTurn(id: UUID, _ mutate: (inout WingmanTurn) -> Void) {
    guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
    mutate(&turns[index])
  }

  private func upsertActivity(_ item: WingmanActivityItem) {
    if let existingIndex = activities.firstIndex(where: { $0.id == item.id }) {
      activities[existingIndex] = item
    } else {
      activities.insert(item, at: 0)
    }
  }
}
