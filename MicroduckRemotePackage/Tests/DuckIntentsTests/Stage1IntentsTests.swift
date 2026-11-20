import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct Stage1IntentsTests {
  private struct RecordedSoundCall: Equatable, Sendable {
    var tag: SoundTag
    var hold: Bool?
  }

  @Test func duckSoundCoversAllProtocolSoundTagsRoundTrip() {
    let roundTripped = SoundTag.allCases.map { DuckSound($0).soundTag }
    expectNoDifference(roundTripped, SoundTag.allCases)
    expectNoDifference(DuckSound.allCases.count, SoundTag.allCases.count)
  }

  @Test func emergencyStopImmediatelyZeroesVelocityAndHaltsWhenConnected() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.ensureConnected = { _ in
        events.withValue { $0.append("ensureConnected") }
        return DuckIdentity(peerID: "sim-duck-a", name: "duck-eb55", isSimulated: true)
      }
      session.sendMove = { move in
        events.withValue { $0.append("move:\(move.vx),\(move.vy),\(move.vyaw)") }
      }
      session.stop = {
        events.withValue { $0.append("stop") }
      }
      $0.duckSession = session
    } operation: {
      let intent = EmergencyStopDuckIntent()
      _ = try await intent.perform()
    }

    expectNoDifference(
      events.value,
      [
        "move:0.0,0.0,0.0",
        "stop",
      ]
    )
  }

  @Test func emergencyStopColdStartsConnectionWhenControlChannelIsClosed() async throws {
    let events = LockIsolated<[String]>([])

    try await withDependencies {
      var disconnected = DuckSessionSnapshot.previewConnected
      disconnected.controlOpen = false
      disconnected.phase = .disconnected
      let snapshot = disconnected

      var session = DuckSessionClient.previewValue
      session.currentSnapshot = { snapshot }
      session.ensureConnected = { _ in
        events.withValue { $0.append("ensureConnected") }
        return DuckIdentity(peerID: "hw-duck-1", name: "duck-01", isSimulated: false)
      }
      session.sendMove = { move in
        events.withValue { $0.append("move:\(move.vx),\(move.vy),\(move.vyaw)") }
      }
      session.stop = {
        events.withValue { $0.append("stop") }
      }
      $0.duckSession = session
    } operation: {
      let intent = EmergencyStopDuckIntent()
      _ = try await intent.perform()
    }

    expectNoDifference(
      events.value,
      [
        "ensureConnected",
        "move:0.0,0.0,0.0",
        "stop",
      ]
    )
  }

  @Test func playDuckSoundSendsSingleOneShotForNonHoldableTag() async throws {
    let calls = LockIsolated<[RecordedSoundCall]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.playSound = { tag, hold in
        calls.withValue { $0.append(RecordedSoundCall(tag: tag, hold: hold)) }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      let intent = PlayDuckSoundIntent(sound: .greet, holdSeconds: 3.0)
      _ = try await intent.perform()
    }

    expectNoDifference(
      calls.value,
      [RecordedSoundCall(tag: .greet, hold: nil)]
    )
  }

  @Test func playDuckSoundPulsesHoldableWheeeAt10HzAndReleases() async throws {
    let calls = LockIsolated<[RecordedSoundCall]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.playSound = { tag, hold in
        calls.withValue { $0.append(RecordedSoundCall(tag: tag, hold: hold)) }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      // 0.1s clamps up to minimum 0.3s -> 3 pulses at 10 Hz + 1 release
      let intent = PlayDuckSoundIntent(sound: .wheee, holdSeconds: 0.1)
      _ = try await intent.perform()
    }

    expectNoDifference(
      calls.value,
      [
        RecordedSoundCall(tag: .wheee, hold: true),
        RecordedSoundCall(tag: .wheee, hold: true),
        RecordedSoundCall(tag: .wheee, hold: true),
        RecordedSoundCall(tag: .wheee, hold: false),
      ]
    )
  }

  @Test func playDuckSoundSendsReleaseFrameWhenCancelledMidHold() async {
    let calls = LockIsolated<[RecordedSoundCall]>([])
    let firstHoldSent = AsyncStream.makeStream(of: Void.self)

    let task = Task {
      try await withDependencies {
        var session = DuckSessionClient.previewValue
        session.playSound = { tag, hold in
          calls.withValue { $0.append(RecordedSoundCall(tag: tag, hold: hold)) }
          if hold == true {
            firstHoldSent.continuation.yield()
          }
        }
        $0.duckSession = session
        $0.continuousClock = ContinuousClock()
      } operation: {
        let intent = PlayDuckSoundIntent(sound: .wheee, holdSeconds: 3.0)
        _ = try await intent.perform()
      }
    }

    var iterator = firstHoldSent.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }

    expectNoDifference(
      calls.value,
      [
        RecordedSoundCall(tag: .wheee, hold: true),
        RecordedSoundCall(tag: .wheee, hold: false),
      ]
    )
  }
}
