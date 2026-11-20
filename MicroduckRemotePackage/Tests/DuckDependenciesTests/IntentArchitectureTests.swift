import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckProtocol
import Foundation
import Testing

@Suite struct IntentArchitectureTests {
  @Test func coldStartTargetResolvesSavedPreferencesAndSimulatorFallback() throws {
    let hfSession = HuggingFaceSession(token: "hf_secret", username: "ajevans99")

    let remoteTarget = try ConnectionPreferencesClient.resolveColdStartTarget(
      preference: .rendezvous(
        serverURL: DuckConstants.defaultRendezvousURL,
        preferredPeerID: "duck-hw-01"
      ),
      huggingFaceSession: hfSession,
      isSimulator: false
    )
    expectNoDifference(
      remoteTarget,
      .rendezvous(
        serverURL: DuckConstants.defaultRendezvousURL,
        token: "hf_secret",
        username: "ajevans99",
        preferredPeerID: "duck-hw-01"
      )
    )

    #expect(throws: DuckSessionError.missingHuggingFaceAccount) {
      try ConnectionPreferencesClient.resolveColdStartTarget(
        preference: .rendezvous(
          serverURL: DuckConstants.defaultRendezvousURL,
          preferredPeerID: "duck-hw-01"
        ),
        huggingFaceSession: nil,
        isSimulator: true
      )
    }

    let simDefault = try ConnectionPreferencesClient.resolveColdStartTarget(
      preference: nil,
      huggingFaceSession: nil,
      isSimulator: true
    )
    expectNoDifference(
      simDefault,
      .localSimulator(url: DuckConstants.defaultLocalSignallingURL)
    )
  }

  @Test func moveStepExecutorPulsesAt10HzAndGuaranteesTerminalZeroTwist() async throws {
    let sentMoves = LockIsolated<[RobotMoveParams]>([])
    let tofSubscriptions = LockIsolated(0)
    var snapshot = DuckSessionSnapshot.previewConnected
    snapshot.tofFrame = nil
    let frozenSnapshot = snapshot

    let result = try await DuckMoveStepExecutor.execute(
      request: DuckMoveStepRequest(vx: 0.2, vy: 0, vyaw: 0, durationSeconds: 0.3),
      clock: ImmediateClock(),
      currentSnapshot: { frozenSnapshot },
      subscribeTof: { tofSubscriptions.withValue { $0 += 1 } },
      sendMove: { move in sentMoves.withValue { $0.append(move) } }
    )

    expectNoDifference(tofSubscriptions.value, 1)
    expectNoDifference(
      result,
      DuckMoveStepResult(
        appliedTwist: RobotMoveParams(vx: 0.2, vy: 0, vyaw: 0),
        elapsedSeconds: 0.3,
        pulsesSent: 3,
        stopReason: .completed
      )
    )
    expectNoDifference(
      sentMoves.value,
      [
        RobotMoveParams(vx: 0.2, vy: 0, vyaw: 0),
        RobotMoveParams(vx: 0.2, vy: 0, vyaw: 0),
        RobotMoveParams(vx: 0.2, vy: 0, vyaw: 0),
        .zero,
      ]
    )
  }

  @Test func moveStepExecutorStopsImmediatelyOnFrontTofObstacle() async throws {
    let sentMoves = LockIsolated<[RobotMoveParams]>([])
    let tickCount = LockIsolated(0)

    let result = try await DuckMoveStepExecutor.execute(
      request: DuckMoveStepRequest(
        vx: 0.25,
        vy: 0,
        vyaw: 0,
        durationSeconds: 1.0,
        stopOnObstacle: true,
        minObstacleDistanceMm: 200
      ),
      clock: ImmediateClock(),
      currentSnapshot: {
        let step = tickCount.withValue { current -> Int in
          defer { current += 1 }
          return current
        }
        var snap = DuckSessionSnapshot.previewConnected
        // Initial pre-check (step 0), tick 0 (step 1), tick 1 (step 2) are clear (500 mm);
        // tick 2 (step 3) sees an obstacle at 140 mm:
        let centerMm = step >= 3 ? 140 : 500
        snap.tofFrame = TofFrame(
          seq: UInt64(step),
          rows: 8,
          cols: 8,
          distanceMm: Array(repeating: centerMm, count: 64)
        )
        return snap
      },
      subscribeTof: {},
      sendMove: { move in sentMoves.withValue { $0.append(move) } }
    )

    expectNoDifference(
      result,
      DuckMoveStepResult(
        appliedTwist: RobotMoveParams(vx: 0.25, vy: 0, vyaw: 0),
        elapsedSeconds: 0.2,
        pulsesSent: 2,
        stopReason: .stoppedForObstacle(distanceMm: 140)
      )
    )
    expectNoDifference(
      sentMoves.value,
      [
        RobotMoveParams(vx: 0.25, vy: 0, vyaw: 0),
        RobotMoveParams(vx: 0.25, vy: 0, vyaw: 0),
        .zero,
      ]
    )
  }

  @Test func moveStepExecutorHaltsWhenDuckFallsAndRefusesIfAlreadyFallen() async throws {
    var fallenSnapshot = DuckSessionSnapshot.previewConnected
    fallenSnapshot.latestState?.safety?.fallen = true

    let snapshotCopy = fallenSnapshot
    await #expect(throws: DuckSessionError.duckFallen) {
      try await DuckMoveStepExecutor.execute(
        request: DuckMoveStepRequest(vx: 0.2, durationSeconds: 0.5),
        clock: ImmediateClock(),
        currentSnapshot: { snapshotCopy },
        subscribeTof: {},
        sendMove: { _ in }
      )
    }

    let sentMoves = LockIsolated<[RobotMoveParams]>([])
    let reads = LockIsolated(0)
    let midWalkFallResult = try await DuckMoveStepExecutor.execute(
      request: DuckMoveStepRequest(vx: 0.15, durationSeconds: 0.5),
      clock: ImmediateClock(),
      currentSnapshot: {
        let count = reads.withValue { value -> Int in
          defer { value += 1 }
          return value
        }
        var snap = DuckSessionSnapshot.previewConnected
        if count >= 2 {
          snap.latestState?.safety?.fallen = true
        }
        return snap
      },
      subscribeTof: {},
      sendMove: { move in sentMoves.withValue { $0.append(move) } }
    )

    expectNoDifference(
      midWalkFallResult.stopReason,
      .interruptedBySafety("Duck fell over")
    )
    expectNoDifference(sentMoves.value.last, .zero)
  }

  @Test func moveStepExecutorSendsZeroTwistWhenCancelledMidStep() async {
    let sentMoves = LockIsolated<[RobotMoveParams]>([])
    let firstPulseSent = AsyncStream.makeStream(of: Void.self)

    let moveTask = Task {
      try await DuckMoveStepExecutor.execute(
        request: DuckMoveStepRequest(vx: 0.2, durationSeconds: 2.0),
        clock: ContinuousClock(),
        currentSnapshot: { .previewConnected },
        subscribeTof: {},
        sendMove: { move in
          sentMoves.withValue { $0.append(move) }
          if move != .zero {
            firstPulseSent.continuation.yield()
          }
        }
      )
    }

    var iterator = firstPulseSent.stream.makeAsyncIterator()
    _ = await iterator.next()
    moveTask.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await moveTask.value
    }

    expectNoDifference(
      sentMoves.value,
      [
        RobotMoveParams(vx: 0.2, vy: 0, vyaw: 0),
        .zero,
      ]
    )
  }
}
