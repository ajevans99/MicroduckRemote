import AppIntents
import Foundation
import SwiftUI

/// An ordered, improvised multi-step robot choreography generated directly by Siri AI
/// (`@AppEntity(.generable)`) and rendered as a timeline `CardSnippet` after execution.
@AppEntity(.generable)
public struct DuckRoutine: TransientAppEntity, SnippetRepresentableEntity, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duck Routine")

  @Property(
    title: "Routine Title",
    description: "Short playful title for this performance (for example 'Suspicious Peek' or 'Victory Dance')."
  )
  public var title: String

  @Property(
    title: "Mood",
    description: "One- or two-word emotional vibe of the routine (for example 'Curious', 'Excited', 'Suspicious', 'Shy')."
  )
  public var mood: String

  @Property(
    title: "Steps",
    description: "Between 2 and 6 ordered expressive steps combining head gaze, vocal sounds, bounded movement, RGB face light, or built-in tricks."
  )
  public var steps: [DuckRoutineStep]

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: title.isEmpty ? "Duck Routine" : title),
      subtitle: LocalizedStringResource(stringLiteral: "\(mood) · \(steps.count) steps"),
      image: .init(systemName: "theatermasks.fill")
    )
  }

  public init() {
    self.title = "Duck Routine"
    self.mood = "Playful"
    self.steps = []
  }

  public init(title: String, mood: String = "Playful", steps: [DuckRoutineStep]) {
    self.title = title
    self.mood = mood
    self.steps = steps
  }

  public static func == (lhs: DuckRoutine, rhs: DuckRoutine) -> Bool {
    lhs.title == rhs.title
      && lhs.mood == rhs.mood
      && lhs.steps == rhs.steps
  }

  public static var snippet: some EntitySnippetContent<Self> {
    CardSnippet(supportedFamilies: [.standard, .compact]) { routine, context in
      DuckRoutineCardView(routine: routine, isCompact: context.family == .compact)
    }
  }
}

struct DuckRoutineCardView: View {
  let routine: DuckRoutine
  let isCompact: Bool

  var body: some View {
    if isCompact {
      HStack(spacing: 10) {
        Image(systemName: "theatermasks.fill")
          .foregroundStyle(.yellow)
        VStack(alignment: .leading, spacing: 2) {
          Text(routine.title.isEmpty ? "Duck Routine" : routine.title)
            .font(.subheadline.weight(.semibold))
          Text("\(routine.mood) · \(routine.steps.count) beats")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(12)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label(routine.title.isEmpty ? "Duck Routine" : routine.title, systemImage: "theatermasks.fill")
            .font(.headline)
          Spacer()
          if !routine.mood.isEmpty {
            Text(routine.mood)
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(.yellow.opacity(0.22), in: Capsule())
              .foregroundStyle(.orange)
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(routine.steps.prefix(6).enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 8) {
              Text("\(index + 1)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
              VStack(alignment: .leading, spacing: 1) {
                Text(step.caption.isEmpty ? "Step \(index + 1)" : step.caption)
                  .font(.caption.weight(.semibold))
                Text(step.summarySubtitle)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer(minLength: 0)
            }
          }
        }
      }
      .padding(14)
    }
  }
}
