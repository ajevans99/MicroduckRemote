import AppIntents
import DuckIntents
import DuckProtocol
import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

public struct BundledShortcutTemplate: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var subtitle: String
  public var systemImage: String
  public var tintName: String
  public var fileName: String
  public var pipelineSteps: [String]
  public var usesAppleIntelligence: Bool

  public init(
    id: String,
    title: String,
    subtitle: String,
    systemImage: String,
    tintName: String,
    fileName: String,
    pipelineSteps: [String],
    usesAppleIntelligence: Bool
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tintName = tintName
    self.fileName = fileName
    self.pipelineSteps = pipelineSteps
    self.usesAppleIntelligence = usesAppleIntelligence
  }

  public static let gallery: [BundledShortcutTemplate] = [
    BundledShortcutTemplate(
      id: "duck-room-explorer",
      title: "Duck Room Explorer",
      subtitle: "Checks 8×8 ToF proximity clearances, wanders open space safely, and finishes with an animated beak chomp.",
      systemImage: "figure.walk.motion",
      tintName: "teal",
      fileName: "Duck Room Explorer.shortcut",
      pipelineSteps: ["Stand Up", "ToF Proximity", "Explore Room", "Chomp Beak", "Greet"],
      usesAppleIntelligence: false
    ),
    BundledShortcutTemplate(
      id: "duck-morning-briefing",
      title: "Morning Duck Briefing",
      subtitle: "Reads live telemetry, asks Apple Intelligence to pick a mood color & briefing, updates the RGB face light, and greets you.",
      systemImage: "sun.max.fill",
      tintName: "orange",
      fileName: "Morning Duck Briefing.shortcut",
      pipelineSteps: ["Stand Up", "Get Status", "Use Model", "Set Light", "Briefing"],
      usesAppleIntelligence: true
    ),
    BundledShortcutTemplate(
      id: "duck-room-patrol",
      title: "Duck Room Patrol",
      subtitle: "Loops 4× snapping live head-camera photos, lets Apple Intelligence decide Forward / Left / Right / Stop, and steers Microduck.",
      systemImage: "eye.circle.fill",
      tintName: "indigo",
      fileName: "Duck Room Patrol.shortcut",
      pipelineSteps: ["Stand Up", "Repeat 4×", "Snap Photo", "Use Model", "Move / Turn"],
      usesAppleIntelligence: true
    ),
    BundledShortcutTemplate(
      id: "duck-photo-tour",
      title: "Duck Photo Tour",
      subtitle: "Interactive menu to pan left → center → right, look up, or inspect the floor — previewing every upright photo in Quick Look.",
      systemImage: "camera.viewfinder",
      tintName: "blue",
      fileName: "Duck Photo Tour.shortcut",
      pipelineSteps: ["Stand Up", "Choose Tour", "Aim Gaze", "Snap Photo", "Quick Look"],
      usesAppleIntelligence: false
    ),
  ]

  /// Resolves the signed `.shortcut` resource matching the running app's bundle identifier
  /// (`dev.ajevans.microduckremote` or `com.microduck.remote`), falling back cleanly to the default bundle.
  public func resolvedResourceURL(
    bundleIdentifier: String = DuckConstants.appBundleIdentifier
  ) -> URL? {
    let baseName = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension

    let folderSlug = bundleIdentifier.replacingOccurrences(of: ".", with: "-")
    let defaultSlug = DuckConstants.defaultBundleIdentifier.replacingOccurrences(of: ".", with: "-")

    let candidateSubdirs = [
      "ShortcutTemplates/\(folderSlug)",
      "ShortcutTemplates/\(defaultSlug)",
    ]

    for subdir in candidateSubdirs {
      if let url = Bundle.module.url(forResource: baseName, withExtension: ext, subdirectory: subdir) {
        return url
      }
    }
    return nil
  }

  /// Copies the bundled `.shortcut` to a clean temporary URL with the exact user-facing filename
  /// so Apple Shortcuts imports it with the intended title.
  public func prepareImportableFileURL(
    bundleIdentifier: String = DuckConstants.appBundleIdentifier
  ) throws -> URL {
    guard let sourceURL = resolvedResourceURL(bundleIdentifier: bundleIdentifier) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("MicroduckShortcuts", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let destURL = dir.appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: destURL.path) {
      try FileManager.default.removeItem(at: destURL)
    }
    try FileManager.default.copyItem(at: sourceURL, to: destURL)
    return destURL
  }
}

public struct ShortcutGalleryContent: View {
  let templates: [BundledShortcutTemplate]
  let onStatusMessage: (String, Bool) -> Void
  @State private var showSiriTip = true

  public init(
    templates: [BundledShortcutTemplate] = BundledShortcutTemplate.gallery,
    onStatusMessage: @escaping (String, Bool) -> Void = { _, _ in }
  ) {
    self.templates = templates
    self.onStatusMessage = onStatusMessage
  }

  public var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Automate Microduck with Apple Shortcuts")
              .font(.subheadline.weight(.semibold))
            Text("Install pre-built, editable multi-action workflows combining Microduck App Intents, Apple Intelligence, loops, and Quick Look.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          #if os(iOS)
          ShortcutsLink()
            .shortcutsLinkStyle(.automatic)
          #elseif os(macOS)
          Button {
            openShortcutsApp()
          } label: {
            Label("Open Shortcuts", systemImage: "square.stack.3d.up.fill")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .controlSize(.small)
          #endif
        }

        #if os(iOS)
        if showSiriTip {
          SiriTipView(intent: GetDuckStatusIntent(), isVisible: $showSiriTip)
            .siriTipViewStyle(.automatic)
        }
        #else
        HStack(spacing: 8) {
          Image(systemName: "waveform.circle.fill")
            .foregroundStyle(.tint)
          Text("Try Siri: “Check Microduck status” or “Explore the room with Microduck”")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        #endif
      }
      .padding(.vertical, 4)
    }

    Section {
      ForEach(templates) { template in
        shortcutRow(template)
      }
    } header: {
      Text("Signed Multi-Action Workflows")
    } footer: {
      Text("Each workflow is compiled from Swift and signed as a portable .shortcut file. Tapping Add opens Apple Shortcuts so you can review and customize every step.")
    }
  }

  private func shortcutRow(_ template: BundledShortcutTemplate) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: template.systemImage)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(tintColor(for: template.tintName).gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(template.title)
              .font(.subheadline.weight(.semibold))
            if template.usesAppleIntelligence {
              Text("Apple Intelligence")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.14), in: Capsule())
            }
          }
          Text(template.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        addShortcutButton(for: template)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(Array(template.pipelineSteps.enumerated()), id: \.offset) { index, step in
            if index > 0 {
              Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
            }
            Text(step)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(.quaternary.opacity(0.6), in: Capsule())
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func addShortcutButton(for template: BundledShortcutTemplate) -> some View {
    #if os(macOS)
    Button {
      openInMacShortcuts(template)
    } label: {
      Label("Add", systemImage: "plus")
        .font(.caption.weight(.semibold))
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .controlSize(.small)
    #else
    if let importURL = try? template.prepareImportableFileURL() {
      ShareLink(item: importURL, preview: SharePreview(template.title)) {
        Label("Add", systemImage: "plus")
          .font(.caption.weight(.semibold))
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
    } else {
      Button("Unavailable") {}
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
    }
    #endif
  }

  #if os(macOS)
  private func openShortcutsApp() {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
      NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
  }

  private func openInMacShortcuts(_ template: BundledShortcutTemplate) {
    do {
      let url = try template.prepareImportableFileURL()
      let shortcutsBundleURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.shortcuts"
      )
      if let shortcutsBundleURL {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: shortcutsBundleURL, configuration: config) { _, error in
          Task { @MainActor in
            if let error {
              onStatusMessage("Could not open Shortcuts: \(error.localizedDescription)", true)
            } else {
              onStatusMessage("Opened “\(template.title)” in Apple Shortcuts — click Add Shortcut to install.", false)
            }
          }
        }
      } else {
        NSWorkspace.shared.open(url)
        onStatusMessage("Opened “\(template.title)” in Apple Shortcuts.", false)
      }
    } catch {
      onStatusMessage("Could not load “\(template.title)”: \(error.localizedDescription)", true)
    }
  }
  #endif

  private func tintColor(for name: String) -> Color {
    switch name {
    case "teal": .teal
    case "orange": .orange
    case "indigo": .indigo
    case "blue": .blue
    default: .accentColor
    }
  }
}
