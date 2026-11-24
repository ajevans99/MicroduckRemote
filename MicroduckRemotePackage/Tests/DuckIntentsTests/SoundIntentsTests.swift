import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct SoundIntentsTests {
  private struct RecordedSoundCall: Equatable, Sendable {
    var tag: SoundTag
    var hold: Bool?
  }

  @Test func duckSoundCoversAllProtocolSoundTagsRoundTrip() {
    let roundTripped = SoundTag.allCases.map { DuckSound($0).soundTag }
    expectNoDifference(roundTripped, SoundTag.allCases)
    expectNoDifference(DuckSound.allCases.count, SoundTag.allCases.count)
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
