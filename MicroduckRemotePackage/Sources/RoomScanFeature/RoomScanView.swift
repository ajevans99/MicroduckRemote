import SwiftUI
import UniformTypeIdentifiers

public struct RoomScanView: View {
  @Bindable var model: RoomScanModel
  @State private var showTips = false
  @State private var showCLIHelp = false

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
            .navigationTitle("Scene")
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
                  Label("Inspect XML", systemImage: "chevron.left.forwardslash.chevron.right")
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
    .fileImporter(
      isPresented: $model.isFolderImporterPresented,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      Task { await model.folderImporterCompleted(result) }
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
    .task {
      await model.refreshSyncedScenes()
    }
  }

  private var idleScreen: some View {
    List {
      if let errorMessage = model.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }

      Section {
        if model.canStartHardwareScan {
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text("LiDAR Room Capture")
                .font(.headline)
              Text("Scan one or more connected rooms with RoomPlan to generate a MuJoCo scene for Microduck.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Button {
              Task { await model.startScanButtonTapped() }
            } label: {
              Label("Start LiDAR Scan", systemImage: "arkit")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
          }
          .padding(.vertical, 4)
        } else if model.needsPermissionRequest {
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Camera Permission Required")
                .font(.headline)
              Text("RoomPlan uses your camera and LiDAR on-device. Nothing is uploaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Button {
              Task { await model.requestCameraPermissionButtonTapped() }
            } label: {
              Label("Allow Camera & Start Scan", systemImage: "camera")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isRequestingPermission)
          }
          .padding(.vertical, 4)
        } else if model.isPermissionDeniedOrRestricted {
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Camera Access Disabled")
                .font(.headline)
              Text("Enable Camera access in Settings to scan rooms with LiDAR.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
              Button("Open Settings") {
                Task { await model.openSettingsButtonTapped() }
              }
              .buttonStyle(.borderedProminent)

              Button("Recheck") {
                model.refreshCapabilities()
              }
              .buttonStyle(.bordered)
            }
          }
          .padding(.vertical, 4)
        } else {
          VStack(alignment: .leading, spacing: 10) {
            Label(model.deviceSupport.title, systemImage: "arkit")
              .font(.headline)
            Text(model.deviceSupport.message)
              .font(.footnote)
              .foregroundStyle(.secondary)
            Button("Preview Sample Apartment") {
              model.loadSampleApartmentButtonTapped()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
          }
          .padding(.vertical, 4)
        }
      }

      syncedScenesSection

      Section {
        if model.deviceSupport.isSupported {
          Button {
            model.loadSampleApartmentButtonTapped()
          } label: {
            Label("Preview Sample Apartment", systemImage: "building.2")
          }
        }

        DisclosureGroup("Scanning Tips", isExpanded: $showTips) {
          Label("Open interior doors first so Microduck can walk between rooms.", systemImage: "door.left.hand.open")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Label("For multi-room scans, tap Add Room while keeping the doorway in view.", systemImage: "plus.square.on.square")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Label("Scan one floor per simulator scene.", systemImage: "square.stack.3d.up")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    #if canImport(UIKit)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.inset)
    #endif
  }

  private var scanningOverlayScreen: some View {
    ZStack {
      model.makeActiveCaptureView()
        .ignoresSafeArea()

      VStack {
        VStack(spacing: 6) {
          HStack(spacing: 10) {
            Label("Room \(model.liveProgress.currentRoomNumber)", systemImage: "arkit")
              .font(.subheadline.weight(.semibold))

            if model.liveProgress.completedRoomCount > 0 {
              Text("\(model.liveProgress.completedRoomCount) saved")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
            }

            Spacer()

            Text("\(model.liveProgress.liveWallCount)W · \(model.liveProgress.liveDoorwayCount)D · \(model.liveProgress.liveObjectCount)F")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }

          if let coaching = model.liveProgress.coachingInstruction {
            Text(coaching)
              .font(.footnote)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let statusBanner = model.liveProgress.statusBanner {
            Text(statusBanner)
              .font(.caption)
              .foregroundStyle(.orange)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)

        Spacer()

        if model.liveProgress.isProcessingRoom {
          HStack(spacing: 8) {
            ProgressView()
            Text("Processing geometry…")
              .font(.subheadline.weight(.medium))
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(.bottom, 8)
        }

        VStack(spacing: 10) {
          HStack(spacing: 10) {
            Button {
              model.addNextRoomButtonTapped()
            } label: {
              Label("Add Room", systemImage: "plus")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.liveProgress.isProcessingRoom)

            Button {
              model.finishScanButtonTapped()
            } label: {
              Label("Finish", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.liveProgress.isProcessingRoom)
          }

          Button("Cancel", role: .cancel) {
            model.cancelScanButtonTapped()
          }
          .font(.footnote.weight(.medium))
          .disabled(model.liveProgress.isProcessingRoom)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 12)
      }
    }
  }

  private var reviewAndExportScreen: some View {
    List {
      if let toast = model.statusToast {
        Section {
          Label(toast, systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.green)
        }
      }

      if let errorMessage = model.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }

      if let result = model.exportResult {
        Section {
          FloorPlanPreviewCanvas(preview: result.preview)
            .frame(height: 250)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

          HStack {
            compactStat(title: "Rooms", value: "\(result.summary.roomCount)")
            Divider()
            compactStat(title: "Doors", value: "\(result.summary.openDoorwayCount)")
            Divider()
            compactStat(title: "Objects", value: "\(result.summary.furnitureCount)")
            Divider()
            compactStat(
              title: "Size",
              value: String(format: "%.1f×%.1fm", result.summary.footprintWidthMeters, result.summary.footprintDepthMeters)
            )
          }
          .padding(.vertical, 4)
        } footer: {
          if let source = model.currentCapture?.source {
            Text(source.summaryLabel)
          }
        }

        if !result.summary.warnings.isEmpty {
          Section("Notes") {
            ForEach(Array(result.summary.warnings.enumerated()), id: \.offset) { _, note in
              Label(note, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }

        Section {
          Button {
            Task { await model.saveToICloudButtonTapped() }
          } label: {
            HStack {
              if model.isSyncingToICloud {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: model.iCloudAvailability.isConnected ? "icloud.and.arrow.up" : "folder.badge.gearshape")
              }
              Text(
                model.iCloudAvailability.connectedFolderName.map { "Save to iCloud Drive (\($0))" }
                  ?? "Choose iCloud Folder & Save"
              )
              .fontWeight(.semibold)
            }
          }
          .disabled(model.isSyncingToICloud)

          Button {
            model.exportToFilesButtonTapped()
          } label: {
            Label("Save XML to Files…", systemImage: "folder.badge.plus")
          }

          if let shareFileURL = model.shareFileURL {
            ShareLink(item: shareFileURL) {
              Label("Share / AirDrop XML", systemImage: "square.and.arrow.up")
            }
          }
        } header: {
          Text("Export")
        } footer: {
          Text(result.configuration.fileName)
            .font(.caption2.monospaced())
        }

        Section("Options") {
          LabeledContent("Name") {
            TextField("my_apartment", text: $model.exportConfiguration.sceneName)
              .multilineTextAlignment(.trailing)
              .autocorrectionDisabled()
              #if canImport(UIKit)
              .textInputAutocapitalization(.never)
              #endif
          }

          Picker("Doorways", selection: $model.exportConfiguration.doorPolicy) {
            ForEach(DoorExportPolicy.allCases) { policy in
              Text(policy.label).tag(policy)
            }
          }

          Toggle("Furniture Collisions", isOn: $model.exportConfiguration.includeFurniture)
          Toggle("Floor Textures", isOn: $model.exportConfiguration.includeFloorOverlays)
          Toggle("Align Walls to Axes", isOn: $model.exportConfiguration.alignDominantWallAxis)
          Toggle("Auto-Clear Spawn Point", isOn: $model.exportConfiguration.autoClearSpawnOrigin)
        }

        syncedScenesSection

        Section {
          DisclosureGroup("Manual Simulator Command", isExpanded: $showCLIHelp) {
            HStack {
              Text(result.configuration.duckSimCommand)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
              Spacer()
              Button {
                model.copyLaunchCommandButtonTapped()
              } label: {
                Image(systemName: "doc.on.doc")
              }
              .buttonStyle(.borderless)
            }
          }
        }
      }
    }
    #if canImport(UIKit)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.inset)
    #endif
  }

  private func compactStat(title: String, value: String) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.subheadline.monospacedDigit().weight(.semibold))
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var syncedScenesSection: some View {
    Section {
      HStack {
        if let folderName = model.iCloudAvailability.connectedFolderName {
          Label(folderName, systemImage: "icloud")
            .font(.subheadline)
          Spacer()
          Button("Change") {
            model.chooseSyncedFolderButtonTapped()
          }
          .font(.footnote)
        } else {
          Text("Choose iCloud Drive folder")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Choose…") {
            model.chooseSyncedFolderButtonTapped()
          }
          .font(.footnote.weight(.medium))
        }
      }

      if model.syncedScenes.isEmpty {
        Text("No synced scenes yet.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.syncedScenes) { record in
          Button {
            Task { await model.inspectSyncedSceneButtonTapped(record) }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(record.metadata.displayName)
                  .foregroundStyle(.primary)
                Text("\(record.fileName) · \(record.metadata.roomCount)R · \(record.metadata.obstacleCount) objects")
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Text(record.metadata.exportedAt, format: .dateTime.month().day())
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
          }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              Task { await model.deleteSyncedSceneButtonTapped(record) }
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    } header: {
      HStack {
        Text("Synced Scenes")
        Spacer()
        if model.isLoadingSyncedScenes {
          ProgressView()
            .controlSize(.mini)
        } else {
          Button {
            Task { await model.refreshSyncedScenes() }
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.caption)
          }
          .buttonStyle(.borderless)
        }
      }
    }
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
    $0.iCloudSceneSync = .previewValue
    $0.haptics = .previewValue
  }
) {
  let model = RoomScanModel()
  model.loadSampleApartmentButtonTapped()
  return RoomScanView(model: model)
}
