import AppIntents
import CoreTransferable
import DuckProtocol
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A first-person JPEG snapshot captured from Microduck's head camera.
/// Conforms to `Transferable` so Siri AI and Shortcuts can hand the photo directly to
/// Messages, Mail, Photos, Notes, or Apple Intelligence vision actions, and to
/// `SnippetRepresentableEntity` so Siri displays the frame inline via `CardSnippet`.
public struct DuckPhotoEntity: TransientAppEntity, Transferable, Equatable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Microduck Photo")

  #if os(iOS)
  @Property(
    title: "Duck Name",
    description: "Name of the Microduck robot or simulator that took this photo."
  )
  public var duckName: String

  @Property(
    title: "Captured At",
    description: "Timestamp when the camera frame was captured."
  )
  public var capturedAt: Date

  @Property(
    title: "Width",
    description: "Upright image width in pixels."
  )
  public var width: Int

  @Property(
    title: "Height",
    description: "Upright image height in pixels."
  )
  public var height: Int

  @Property(
    title: "Caption",
    description: "Short description of this camera snapshot."
  )
  public var caption: String

  @Property(
    title: "Image File",
    description: "JPEG image file captured from Microduck's head camera."
  )
  public var imageFile: IntentFile
  #else
  @Property(title: "Duck Name")
  public var duckName: String

  @Property(title: "Captured At")
  public var capturedAt: Date

  @Property(title: "Width")
  public var width: Int

  @Property(title: "Height")
  public var height: Int

  @Property(title: "Caption")
  public var caption: String

  @Property(title: "Image File")
  public var imageFile: IntentFile
  #endif

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: caption.isEmpty ? "Microduck Snapshot" : caption),
      subtitle: LocalizedStringResource(stringLiteral: "\(duckName) · \(width)×\(height)"),
      image: .init(data: imageFile.data, isTemplate: false)
    )
  }

  public static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .jpeg) { entity in
      entity.imageFile.data
    }
    DataRepresentation(exportedContentType: .plainText) { entity in
      Data(entity.caption.utf8)
    }
  }

  public init() {
    self.duckName = "Microduck"
    self.capturedAt = Date(timeIntervalSince1970: 0)
    self.width = 0
    self.height = 0
    self.caption = "Microduck Head Camera"
    self.imageFile = IntentFile(data: Data(), filename: "microduck.jpg", type: .jpeg)
  }

  public init(duckName: String, frame: DuckCapturedFrame) {
    let timestampSlug = Int(frame.capturedAt.timeIntervalSince1970)
    self.duckName = duckName
    self.capturedAt = frame.capturedAt
    self.width = frame.width
    self.height = frame.height
    self.caption = "Photo from \(duckName)'s head camera"
    self.imageFile = IntentFile(
      data: frame.jpegData,
      filename: "\(duckName)-\(timestampSlug).jpg",
      type: .jpeg
    )
  }

  public static func == (lhs: DuckPhotoEntity, rhs: DuckPhotoEntity) -> Bool {
    lhs.duckName == rhs.duckName
      && lhs.capturedAt == rhs.capturedAt
      && lhs.width == rhs.width
      && lhs.height == rhs.height
      && lhs.caption == rhs.caption
      && lhs.imageFile.data == rhs.imageFile.data
  }
}

@available(iOS 27.3, macOS 27.3, *)
extension DuckPhotoEntity: SnippetRepresentableEntity {
  public static var snippet: some EntitySnippetContent<Self> {
    CardSnippet(supportedFamilies: [.standard, .compact]) { photo, context in
      DuckPhotoCardView(photo: photo, isCompact: context.family == .compact)
    }
  }
}

private struct DuckPhotoCardView: View {
  let photo: DuckPhotoEntity
  let isCompact: Bool

  private var decodedImage: CGImage? {
    guard
      !photo.imageFile.data.isEmpty,
      let source = CGImageSourceCreateWithData(photo.imageFile.data as CFData, nil)
    else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  var body: some View {
    if isCompact {
      HStack(spacing: 10) {
        thumbnailView
          .frame(width: 44, height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(photo.caption)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text("\(photo.duckName) · \(photo.width)×\(photo.height)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(10)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        thumbnailView
          .frame(maxWidth: .infinity)
          .frame(height: 210)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        HStack {
          Label(photo.duckName, systemImage: "camera.fill")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text("\(photo.width)×\(photo.height)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(12)
    }
  }

  @ViewBuilder
  private var thumbnailView: some View {
    if let cgImage = decodedImage {
      Image(decorative: cgImage, scale: 1.0)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color.black.opacity(0.35)
        Image(systemName: "video.fill")
          .font(.title2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
