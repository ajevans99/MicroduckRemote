import SwiftUI
import UniformTypeIdentifiers

public struct RoomScanView: View {
  @Bindable var model: RoomScanModel

  public init(model: RoomScanModel) {
    self.model = model
  }

  public var body: some View {
    Group {
      switch model.phase {
      case .idle:
        NavigationStack {
          idleScreen
            .navigationTitle("Room Scan")
        }
      case .scanning:
        scanningOverlayScreen
      case .review:
        NavigationStack {
          reviewAndExportScreen
            .navigationTitle("MJCF Scene")
            .toolbar {
              ToolbarItem(placement: .navigation) {
                Button {
                  Task { await model.newScanButtonTapped() }
                } label: {
                  Label("New Scan", systemImage: "camera.viewfinder")
                }
              }
              ToolbarItem(placement: .primaryAction) {
                Button {
                  model.inspectXMLButtonTapped()
                } label: {
                  Label("XML", systemImage: "chevron.left.forwardslash.chevron.right")
                }
              }
            }
        }
      }
    }
    .fileExporter(
      isPresented: $model.isFileExporterPresented,
      document: model.exportDocument,
      contentType: .xml,
      defaultFilename: model.exportResult?.configuration.fileName ?? "scene_scanned_room.xml"
    ) { result in
      model.fileExporterCompleted(result)
    }
    .sheet(item: $model.xmlInspectorSheet) { inspector in
      XMLInspectorSheet(
        inspector: inspector,
        onCopyXML: { model.copyRawXMLButtonTapped() }
      )
    }
    .onAppear {
      model.onAppear()
    }
  }

  private var idleScreen: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        capabilityBannerCard

        if model.canStartHardwareScan {
          readyToScanCard
        } else if model.needsPermissionRequest {
          permissionRequestCard
        } else if model.isPermissionDeniedOrRestricted {
          permissionDeniedCard
        }

        scanningWorkflowGuideCard

        sampleSceneCard

        if let errorMessage = model.errorMessage {
          errorCard(errorMessage)
        }
      }
      .padding()
    }
  }

  private var capabilityBannerCard: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: model.deviceSupport.isSupported ? "cube.transparent.fill" : "exclamationmark.triangle.fill")
        .font(.title2)
        .foregroundStyle(model.deviceSupport.isSupported ? .cyan : .orange)
        .frame(width: 34)

      VStack(alignment: .leading, spacing: 6) {
        Text(model.deviceSupport.title)
          .font(.headline)
        Text(model.deviceSupport.message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var readyToScanCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Scan Room or Floor Plan")
        .font(.headline)
      Text("Captures walls, open doorways, floor elevation, and furniture on-device with Apple RoomPlan, then exports a ready-to-run MuJoCo MJCF XML scene for Microduck.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button {
        Task { await model.startScanButtonTapped() }
      } label: {
        Label("Start Camera + LiDAR Scan", systemImage: "camera.metering.matrix")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var permissionRequestCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Camera & LiDAR Permission Needed", systemImage: "camera.badge.ellipsis")
        .font(.headline)
      Text("RoomPlan uses your iPhone camera together with the LiDAR scanner locally on-device to detect walls, doorways, and furniture. No images or room meshes are uploaded.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button {
        Task { await model.requestCameraPermissionButtonTapped() }
      } label: {
        Label("Allow Camera Access & Start Scan", systemImage: "checkmark.shield.fill")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.isRequestingPermission)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var permissionDeniedCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Camera Access Disabled", systemImage: "lock.shield")
        .font(.headline)
        .foregroundStyle(.orange)
      Text("Enable Camera access for Microduck in iOS Settings to scan rooms with LiDAR and RoomPlan.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Button {
          Task { await model.openSettingsButtonTapped() }
        } label: {
          Label("Open Settings", systemImage: "gear")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)

        Button {
          model.refreshCapabilities()
        } label: {
          Label("Recheck", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var scanningWorkflowGuideCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Single-Room & Multi-Room Tips", systemImage: "map")
        .font(.headline)
      guideBullet(icon: "door.left.hand.open", text: "Open interior doors before scanning so doorways are carved open for Microduck.")
      guideBullet(icon: "point.topleft.down.to.point.bottomright.curvepath", text: "For multiple rooms on the same floor, scan Room 1, tap Add Connected Room, and walk continuously through the open doorway so the shared ARSession keeps rooms aligned.")
      guideBullet(icon: "stairs", text: "Multi-story scans keep the primary floor at z = 0; scan one floor per simulator scene.")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var sampleSceneCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Preview Exporter Without LiDAR", systemImage: "doc.badge.gearshape")
        .font(.headline)
      Text("Load a sample 2-room apartment to inspect doorway carving, collision boxes, duck spawn placement, and XML export.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button {
        model.loadSampleApartmentButtonTapped()
      } label: {
        Label("Load Sample 2-Room Apartment", systemImage: "building.2.crop.circle")
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var scanningOverlayScreen: some View {
    ZStack {
      model.makeActiveCaptureView()
        .ignoresSafeArea()

      VStack {
        VStack(spacing: 8) {
          HStack(spacing: 12) {
            Label("Room \(model.liveProgress.currentRoomNumber)", systemImage: "cube.transparent.fill")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(.cyan)

            if model.liveProgress.completedRoomCount > 0 {
              Text("\(model.liveProgress.completedRoomCount) saved")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.green.opacity(0.25), in: Capsule())
                .foregroundStyle(.green)
            }

            Spacer()

            Text("\(model.liveProgress.liveWallCount)W · \(model.liveProgress.liveDoorwayCount)D · \(model.liveProgress.liveObjectCount)F")
              .font(.caption.monospacedDigit().weight(.semibold))
              .foregroundStyle(.white.opacity(0.9))
          }

          if let coaching = model.liveProgress.coachingInstruction {
            Text(coaching)
              .font(.footnote.weight(.medium))
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let statusBanner = model.liveProgress.statusBanner {
            Text(statusBanner)
              .font(.caption)
              .foregroundStyle(.yellow)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(14)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)

        Spacer()

        if model.liveProgress.isProcessingRoom {
          HStack(spacing: 10) {
            ProgressView()
              .tint(.white)
            Text("Processing RoomPlan geometry on-device…")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.white)
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(.black.opacity(0.78), in: Capsule())
          .padding(.bottom, 8)
        }

        VStack(spacing: 10) {
          HStack(spacing: 10) {
            Button {
              model.addNextRoomButtonTapped()
            } label: {
              Label("Add Connected Room", systemImage: "plus.square.on.square")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(model.liveProgress.isProcessingRoom)

            Button {
              model.finishScanButtonTapped()
            } label: {
              Label("Finish & Build XML", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(model.liveProgress.isProcessingRoom)
          }

          Button(role: .cancel) {
            model.cancelScanButtonTapped()
          } label: {
            Text("Cancel Scan")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.white.opacity(0.85))
          }
          .disabled(model.liveProgress.isProcessingRoom)
        }
        .padding(14)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.bottom, 12)
      }
    }
  }

  private var reviewAndExportScreen: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let toast = model.statusToast {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text(toast)
              .font(.footnote.weight(.semibold))
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.green.opacity(0.14), in: Capsule())
        }

        if let errorMessage = model.errorMessage {
          errorCard(errorMessage)
        }

        if let result = model.exportResult {
          FloorPlanPreviewCanvas(preview: result.preview)
            .frame(height: 270)

          metricsSummaryGrid(result.summary, source: model.currentCapture?.source)

          if !result.summary.warnings.isEmpty {
            warningsCard(result.summary.warnings)
          }

          exportActionsCard(result)

          configurationCard(result)

          simulatorInstructionsCard(result.configuration)
        }
      }
      .padding()
    }
  }

  private func metricsSummaryGrid(
    _ summary: MJCFExportSummary,
    source: ScannedStructureSource?
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if let source {
        Text(source.summaryLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        metricTile(title: "Rooms", value: "\(summary.roomCount)")
        metricTile(title: "Wall Boxes", value: "\(summary.wallSegmentCount)")
        metricTile(title: "Open Doors", value: "\(summary.openDoorwayCount)")
        metricTile(title: "Furniture", value: "\(summary.furnitureCount)")
        metricTile(
          title: "Footprint",
          value: String(format: "%.1f×%.1fm", summary.footprintWidthMeters, summary.footprintDepthMeters)
        )
        metricTile(
          title: "Spawn Clear",
          value: String(format: "%.2fm", summary.spawnClearanceMeters)
        )
      }
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func metricTile(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(.headline.monospacedDigit())
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private func warningsCard(_ warnings: [String]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Scan Notes", systemImage: "info.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
      ForEach(Array(warnings.enumerated()), id: \.offset) { _, note in
        Text("• \(note)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func exportActionsCard(_ result: MJCFExportResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(result.configuration.fileName)
            .font(.headline.monospaced())
          Text("Includes robot_groundcontact_backlash.xml + 35-DOF keyframes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      HStack(spacing: 10) {
        Button {
          model.exportToFilesButtonTapped()
        } label: {
          Label("Save XML to Files", systemImage: "folder.badge.plus")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)

        if let shareFileURL = model.shareFileURL {
          ShareLink(item: shareFileURL) {
            Label("AirDrop / Share", systemImage: "square.and.arrow.up")
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 6)
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func configurationCard(_ result: MJCFExportResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("MJCF Export Options")
        .font(.headline)

      VStack(alignment: .leading, spacing: 4) {
        Text("Scene Name")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextField("my_apartment", text: $model.exportConfiguration.sceneName)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          #if canImport(UIKit)
          .textInputAutocapitalization(.never)
          #endif
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Doorway Collision Policy")
          .font(.caption)
          .foregroundStyle(.secondary)
        Picker("Doorways", selection: $model.exportConfiguration.doorPolicy) {
          ForEach(DoorExportPolicy.allCases) { policy in
            Text(policy.label).tag(policy)
          }
        }
        .pickerStyle(.segmented)
        Text(model.exportConfiguration.doorPolicy.summaryDescription)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Toggle("Include Furniture Collision Shapes", isOn: $model.exportConfiguration.includeFurniture)
        .font(.subheadline)

      Toggle("Include Visual Room Floor Textures", isOn: $model.exportConfiguration.includeFloorOverlays)
        .font(.subheadline)

      Toggle("Align Dominant Walls to X / Y Axes", isOn: $model.exportConfiguration.alignDominantWallAxis)
        .font(.subheadline)

      Toggle("Place Duck Spawn (0, 0) in Clear Floor Space", isOn: $model.exportConfiguration.autoClearSpawnOrigin)
        .font(.subheadline)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func simulatorInstructionsCard(_ config: MJCFExportConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Run in Microduck Simulator", systemImage: "terminal")
        .font(.headline)

      Text("1. AirDrop or copy **\(config.fileName)** into your `microduck_rl` checkout so `<include file=\"robot_groundcontact_backlash.xml\" />` and `assets/` resolve without copying robot meshes:")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("\(config.targetDirectoryRelativePath)\(config.fileName)")
        .font(.caption.monospaced())
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

      Text("2. Restart `duck-sim` from `pollen-robotics/microduck`:")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack {
        Text(config.duckSimCommand)
          .font(.caption.monospaced())
          .lineLimit(2)
        Spacer()
        Button {
          model.copyLaunchCommandButtonTapped()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.bordered)
      }
      .padding(8)
      .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func guideBullet(icon: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(.cyan)
        .frame(width: 20)
      Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func errorCard(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.octagon.fill")
        .foregroundStyle(.red)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.red)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
  }
}

private struct XMLInspectorSheet: View {
  let inspector: XMLInspectorSheetModel
  let onCopyXML: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView([.vertical, .horizontal]) {
        Text(inspector.xml)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .padding()
      }
      .navigationTitle(inspector.fileName)
      #if canImport(UIKit)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .safeAreaInset(edge: .bottom) {
        HStack {
          Text("\(inspector.lineCount) lines · \(ByteCountFormatter.string(fromByteCount: Int64(inspector.byteCount), countStyle: .file))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            onCopyXML()
          } label: {
            Label("Copy XML", systemImage: "doc.on.doc")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview(
  traits: .dependencies {
    $0.roomScan = .previewValue
    $0.haptics = .previewValue
  }
) {
  let model = RoomScanModel()
  model.loadSampleApartmentButtonTapped()
  return RoomScanView(model: model)
}
