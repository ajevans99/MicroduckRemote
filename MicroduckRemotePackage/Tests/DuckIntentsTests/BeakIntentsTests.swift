import CustomDump
import Dependencies
import DependenciesTestSupport
import DuckDependencies
import DuckIntents
import DuckProtocol
import Foundation
import Testing

@Suite struct BeakIntentsTests {
  @Test func controlDuckBeakHandlesOpenCloseAndClampedPercent() async throws {
    let sentMouths = LockIsolated<[RobotMouthParams]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendMouth = { mouth in
        sentMouths.withValue { $0.append(mouth) }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await ControlDuckBeakIntent(action: .open).perform()
      _ = try await ControlDuckBeakIntent(action: .setPercent, openingPercent: 45).perform()
      _ = try await ControlDuckBeakIntent(action: .setPercent, openingPercent: 180).perform()
      _ = try await ControlDuckBeakIntent(action: .setPercent, openingPercent: -25).perform()
      _ = try await ControlDuckBeakIntent(action: .close).perform()
    }

    expectNoDifference(
      sentMouths.value,
      [
        .wideOpen,
        RobotMouthParams(open: 0.45),
        .wideOpen,
        .closed,
        .closed,
      ]
    )
  }

  @Test func controlDuckBeakChompsAt10HzAndGuaranteesTerminalClose() async throws {
    let sentMouths = LockIsolated<[RobotMouthParams]>([])

    try await withDependencies {
      var session = DuckSessionClient.previewValue
      session.sendMouth = { mouth in
        sentMouths.withValue { $0.append(mouth) }
      }
      $0.duckSession = session
      $0.continuousClock = ImmediateClock()
    } operation: {
      _ = try await ControlDuckBeakIntent(
        action: .chomp,
        openingPercent: 80,
        durationSeconds: 0.6
      ).perform()
    }

    expectNoDifference(
      sentMouths.value,
      [
        RobotMouthParams(open: 0.8),
        RobotMouthParams(open: 0.8),
        RobotMouthParams(open: 0.0),
        RobotMouthParams(open: 0.0),
        RobotMouthParams(open: 0.8),
        RobotMouthParams(open: 0.8),
        .closed,
      ]
    )
  }

  @Test func controlDuckBeakClosesGuaranteedOnCancellation() async {
    let sentMouths = LockIsolated<[RobotMouthParams]>([])
    let firstChomp = AsyncStream.makeStream(of: Void.self)

    let task = Task {
      try await withDependencies {
        var session = DuckSessionClient.previewValue
        session.sendMouth = { mouth in
          sentMouths.withValue { $0.append(mouth) }
          if mouth.open > 0 {
            firstChomp.continuation.yield()
          }
        }
        $0.duckSession = session
        $0.continuousClock = ContinuousClock()
      } operation: {
        _ = try await ControlDuckBeakIntent(
          action: .chomp,
          openingPercent: 100,
          durationSeconds: 2.0
        ).perform()
      }
    }

    var iterator = firstChomp.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }

    expectNoDifference(sentMouths.value.first, .wideOpen)
    expectNoDifference(sentMouths.value.last, .closed)
  }
}
