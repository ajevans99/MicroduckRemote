import DuckProtocol
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct WingmanView: View {
  @Bindable var model: WingmanModel
  private let isEmbedded: Bool
  @Environment(\.dismiss) private var dismiss

  public init(model: WingmanModel, isEmbedded: Bool = false) {
    self.model = model
    self.isEmbedded = isEmbedded
  }

  public var body: some View {
    Group {
      if isEmbedded {
        panelBody
      } else {
        NavigationStack {
          panelBody
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
              }
            }
        }
      }
    }
    .task {
      await model.task()
    }
  }

  private var panelBody: some View {
    VStack(spacing: 0) {
      compactHeader
      Divider().opacity(0.45)

      ScrollViewReader { scrollProxy in
        ScrollView {
          if model.turns.isEmpty {
            emptyStateView
              .padding(.horizontal, 16)
              .padding(.vertical, 20)
          } else {
            LazyVStack(alignment: .leading, spacing: 16) {
              ForEach(model.turns) { turn in
                WingmanTurnRow(
                  turn: turn,
                  isExecutingPlan: model.isExecutingPlan,
                  canExecute: model.snapshot.controlOpen,
                  onRunPlan: { model.runPlanButtonTapped(turnID: turn.id) }
                )
                .id(turn.id)
              }
              Color.clear.frame(height: 6).id("wingman-bottom")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
          }
        }
        .onChange(of: model.turns.count) { _, _ in
          withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo("wingman-bottom", anchor: .bottom)
          }
        }
        .onChange(of: model.turns.last?.toolSteps.count) { _, _ in
          withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo("wingman-bottom", anchor: .bottom)
          }
        }
        .onChange(of: model.turns.last?.replyText) { _, _ in
          withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo("wingman-bottom", anchor: .bottom)
          }
        }
      }

      Divider().opacity(0.45)
      bottomComposer
    }
  }

  private var compactHeader: some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "bird.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.tint)
        Text("Wingman")
          .font(.headline)
      }

      Spacer()

      Menu {
        Section("Foundation Models Backend") {
          ForEach(WingmanModelBackend.allCases) { option in
            Button {
              model.backendSelected(option)
            } label: {
              HStack {
                Label(option.title, systemImage: option.systemImage)
                if model.backend == option {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        }
        Section {
          Text(model.backendStatus.statusText)
        }
      } label: {
        HStack(spacing: 5) {
          Circle()
            .fill(model.backendStatus.isAvailable ? .green : .orange)
            .frame(width: 6, height: 6)
          Text(model.backend.title)
            .font(.caption.weight(.medium))
          if model.backendStatus.supportsVision {
            Image(systemName: "eye")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: Capsule())
      }
      .menuStyle(.borderlessButton)
      .fixedSize()

      if model.isRunning || model.isExecutingPlan {
        Button {
          Task { await model.stopButtonTapped() }
        } label: {
          Image(systemName: "stop.circle.fill")
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .help("Stop Wingman & Microduck")
      } else if !model.turns.isEmpty {
        Button {
          withAnimation(.snappy(duration: 0.2)) {
            model.clearButtonTapped()
          }
        } label: {
          Image(systemName: "trash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear conversation")
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  private var emptyStateView: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Direct Microduck naturally")
          .font(.title3.weight(.semibold))
        Text("Drive by meters, exact angles, or 8×8 ToF clearance — or let Wingman scan 360° with the live camera and plan multi-step moves.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 8)

      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
        spacing: 10
      ) {
        ForEach(WingmanModel.starters) { starter in
          Button {
            model.quickPromptTapped(starter.prompt)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Image(systemName: starter.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
              Text(starter.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
              Text(starter.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(11)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
          .disabled(!model.snapshot.controlOpen || !model.backendStatus.isAvailable)
        }
      }

      if !model.backendStatus.isAvailable {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(model.backendStatus.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
    }
  }

  private var bottomComposer: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        modeSwitchPill

        Spacer()

        if model.mode == .agent {
          Button {
            model.attachCameraFrame.toggle()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: model.attachCameraFrame ? "camera.viewfinder" : "camera")
              Text("Vision")
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              model.attachCameraFrame && model.backendStatus.supportsVision
                ? Color.accentColor.opacity(0.22)
                : Color.primary.opacity(0.08),
              in: Capsule()
            )
            .foregroundStyle(
              model.attachCameraFrame && model.backendStatus.supportsVision
                ? Color.accentColor
                : .secondary
            )
          }
          .buttonStyle(.plain)
          .disabled(!model.backendStatus.supportsVision)
          .help("Include Microduck's live camera frame with your prompt")
        } else {
          Button {
            model.autoRunPlan.toggle()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: model.autoRunPlan ? "play.circle.fill" : "play.circle")
              Text("Auto-Run")
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              model.autoRunPlan ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08),
              in: Capsule()
            )
            .foregroundStyle(model.autoRunPlan ? Color.accentColor : .secondary)
          }
          .buttonStyle(.plain)
        }
      }

      HStack(alignment: .bottom, spacing: 8) {
        TextField(
          model.mode == .agent
            ? "Ask Wingman to move, look, or express…"
            : "Describe a mission plan in meters & degrees…",
          text: $model.promptText,
          axis: .vertical
        )
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        )
        .onSubmit {
          model.runButtonTapped()
        }

        if model.isRunning || model.isExecutingPlan {
          Button {
            Task { await model.stopButtonTapped() }
          } label: {
            Image(systemName: "stop.fill")
              .font(.caption.weight(.bold))
              .foregroundStyle(.white)
              .frame(width: 32, height: 32)
              .background(.red, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Stop Wingman")
        } else {
          Button {
            model.runButtonTapped()
          } label: {
            Image(systemName: "arrow.up")
              .font(.caption.weight(.bold))
              .foregroundStyle(.white)
              .frame(width: 32, height: 32)
              .background(
                model.canSubmit ? Color.accentColor : Color.secondary.opacity(0.35),
                in: Circle()
              )
          }
          .buttonStyle(.plain)
          .disabled(!model.canSubmit)
          .accessibilityLabel("Send to Wingman")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
  }

  private var modeSwitchPill: some View {
    HStack(spacing: 2) {
      ForEach(WingmanMode.allCases) { option in
        let selected = model.mode == option
        Button {
          withAnimation(.snappy(duration: 0.18)) {
            model.mode = option
          }
        } label: {
          Text(option == .agent ? "Agent" : "Plan")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.24) : Color.clear, in: Capsule())
            .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(.primary.opacity(0.07), in: Capsule())
  }
}

private struct WingmanTurnRow: View {
  let turn: WingmanTurn
  let isExecutingPlan: Bool
  let canExecute: Bool
  let onRunPlan: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Spacer(minLength: 28)
        VStack(alignment: .trailing, spacing: 6) {
          Text(turn.userPrompt)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

          if let jpeg = turn.attachedFrameJPEG, let image = platformImage(from: jpeg) {
            HStack(spacing: 5) {
              image
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
              Text("Live camera attached")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if turn.mode == .missionPlan, turn.planTitle != nil || !turn.planSteps.isEmpty {
        missionPlanBubble
      }

      if !turn.toolSteps.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(turn.toolSteps) { step in
            ToolExecutionPillRow(item: step)
          }
        }
      } else if !turn.isComplete && turn.planSteps.isEmpty {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(turn.mode == .agent ? "Wingman is thinking…" : "Streaming mission plan…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: Capsule())
      }

      if let reply = turn.replyText {
        Text(reply)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }

      if let error = turn.errorText {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.caption)
            .padding(.top, 2)
          Text(error)
            .font(.caption)
            .foregroundStyle(.primary)
        }
        .padding(10)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
  }

  private var missionPlanBubble: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(turn.planTitle ?? "Planning Mission…")
            .font(.subheadline.weight(.semibold))
          if let summary = turn.planSummary {
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        if turn.finalizedPlan != nil {
          Button(action: onRunPlan) {
            Label(
              isExecutingPlan ? "Running" : "Run",
              systemImage: "play.fill"
            )
            .font(.caption.weight(.semibold))
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .controlSize(.small)
          .disabled(isExecutingPlan || !canExecute)
        } else {
          ProgressView().controlSize(.small)
        }
      }

      VStack(alignment: .leading, spacing: 5) {
        ForEach(Array(turn.planSteps.enumerated()), id: \.element.id) { index, step in
          let isCurrent = turn.executingStepIndex == index
          HStack(spacing: 8) {
            Image(systemName: step.action?.systemImage ?? "ellipsis.circle")
              .font(.caption.weight(.semibold))
              .foregroundStyle(isCurrent ? .orange : .accentColor)
              .frame(width: 18)
            Text(step.action?.displayTitle ?? "Step \(index + 1)")
              .font(.caption.weight(.semibold))
            if let badge = step.formattedBadge {
              Text(badge)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.16), in: Capsule())
            }
            Spacer()
            if isCurrent {
              ProgressView().controlSize(.mini)
            }
          }
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .background(
            isCurrent ? Color.orange.opacity(0.14) : Color.primary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
        }
      }
    }
    .padding(11)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
    )
  }

  private func platformImage(from data: Data) -> Image? {
    #if canImport(UIKit)
    UIImage(data: data).map(Image.init(uiImage:))
    #elseif canImport(AppKit)
    NSImage(data: data).map(Image.init(nsImage:))
    #else
    nil
    #endif
  }
}

private struct ToolExecutionPillRow: View {
  let item: WingmanActivityItem
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(.snappy(duration: 0.18)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 7) {
          statusBadge
          Text(item.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
          Text(item.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(isExpanded ? 6 : 1)
          Spacer(minLength: 4)
          if item.detail.count > 44 || item.thumbnailJPEG != nil {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)

      if let jpeg = item.thumbnailJPEG, let image = platformImage(from: jpeg) {
        image
          .resizable()
          .scaledToFit()
          .frame(maxHeight: isExpanded ? 190 : 96)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .padding(.leading, 10)
      }
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch item.status {
    case .running:
      ProgressView().controlSize(.mini)
    case .succeeded:
      Image(systemName: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "xmark.octagon.fill")
        .font(.caption)
        .foregroundStyle(.red)
    }
  }

  private func platformImage(from data: Data) -> Image? {
    #if canImport(UIKit)
    UIImage(data: data).map(Image.init(uiImage:))
    #elseif canImport(AppKit)
    NSImage(data: data).map(Image.init(nsImage:))
    #else
    nil
    #endif
  }
}
