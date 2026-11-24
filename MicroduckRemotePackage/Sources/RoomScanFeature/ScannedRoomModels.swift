import Foundation
import simd

public enum ScannedConfidence: Int, Codable, Sendable, Equatable, Comparable, CaseIterable, Identifiable {
  case low = 0
  case medium = 1
  case high = 2

  public var id: Int { rawValue }

  public var label: String {
    switch self {
    case .low:
      "All (Low+)"
    case .medium:
      "Medium+"
    case .high:
      "High Only"
    }
  }

  public static func < (lhs: ScannedConfidence, rhs: ScannedConfidence) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum ScannedSurfaceCategory: Codable, Sendable, Equatable, Hashable {
  case wall
  case opening
  case door(isOpen: Bool)
  case window
  case floor
}

public enum ScannedObjectShape: String, Codable, Sendable, Equatable, Hashable {
  case box
  case circularCylinder
}

public enum ScannedObjectCategory: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
  case storage
  case refrigerator
  case stove
  case bed
  case sink
  case washerDryer
  case toilet
  case bathtub
  case oven
  case dishwasher
  case table
  case sofa
  case chair
  case fireplace
  case television
  case stairs
  case other

  public var displayName: String {
    switch self {
    case .storage: "Storage"
    case .refrigerator: "Refrigerator"
    case .stove: "Stove"
    case .bed: "Bed"
    case .sink: "Sink"
    case .washerDryer: "Washer/Dryer"
    case .toilet: "Toilet"
    case .bathtub: "Bathtub"
    case .oven: "Oven"
    case .dishwasher: "Dishwasher"
    case .table: "Table"
    case .sofa: "Sofa"
    case .chair: "Chair"
    case .fireplace: "Fireplace"
    case .television: "Television"
    case .stairs: "Stairs"
    case .other: "Furniture"
    }
  }
}

public struct ScannedArcCurve: Codable, Sendable, Equatable, Hashable {
  public var radius: Float
  public var startAngleRadians: Float
  public var endAngleRadians: Float

  public init(radius: Float, startAngleRadians: Float, endAngleRadians: Float) {
    self.radius = radius
    self.startAngleRadians = startAngleRadians
    self.endAngleRadians = endAngleRadians
  }
}

public struct RoomTransform: Codable, Sendable, Equatable, Hashable {
  public var column0: SIMD4<Float>
  public var column1: SIMD4<Float>
  public var column2: SIMD4<Float>
  public var column3: SIMD4<Float>

  public init(
    column0: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 0),
    column1: SIMD4<Float> = SIMD4<Float>(0, 1, 0, 0),
    column2: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 0),
    column3: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
  ) {
    self.column0 = column0
    self.column1 = column1
    self.column2 = column2
    self.column3 = column3
  }

  public init(_ matrix: simd_float4x4) {
    column0 = matrix.columns.0
    column1 = matrix.columns.1
    column2 = matrix.columns.2
    column3 = matrix.columns.3
  }

  public var matrix: simd_float4x4 {
    simd_float4x4(columns: (column0, column1, column2, column3))
  }

  public static let identity = RoomTransform()

  public static func translationAndYaw(
    x: Float,
    y: Float,
    z: Float,
    yawRadians: Float = 0
  ) -> RoomTransform {
    let c = cos(yawRadians)
    let s = sin(yawRadians)
    return RoomTransform(
      column0: SIMD4<Float>(c, 0, -s, 0),
      column1: SIMD4<Float>(0, 1, 0, 0),
      column2: SIMD4<Float>(s, 0, c, 0),
      column3: SIMD4<Float>(x, y, z, 1)
    )
  }
}

public struct ScannedSurface: Identifiable, Codable, Sendable, Equatable, Hashable {
  public var id: UUID
  public var category: ScannedSurfaceCategory
  public var transform: RoomTransform
  public var dimensions: SIMD3<Float>
  public var polygonCorners: [SIMD3<Float>]
  public var parentIdentifier: UUID?
  public var curve: ScannedArcCurve?
  public var story: Int?
  public var confidence: ScannedConfidence

  public init(
    id: UUID = UUID(),
    category: ScannedSurfaceCategory,
    transform: RoomTransform,
    dimensions: SIMD3<Float>,
    polygonCorners: [SIMD3<Float>] = [],
    parentIdentifier: UUID? = nil,
    curve: ScannedArcCurve? = nil,
    story: Int? = nil,
    confidence: ScannedConfidence = .high
  ) {
    self.id = id
    self.category = category
    self.transform = transform
    self.dimensions = dimensions
    self.polygonCorners = polygonCorners
    self.parentIdentifier = parentIdentifier
    self.curve = curve
    self.story = story
    self.confidence = confidence
  }
}

public struct ScannedObject: Identifiable, Codable, Sendable, Equatable, Hashable {
  public var id: UUID
  public var category: ScannedObjectCategory
  public var shapeHint: ScannedObjectShape
  public var transform: RoomTransform
  public var dimensions: SIMD3<Float>
  public var story: Int?
  public var confidence: ScannedConfidence

  public init(
    id: UUID = UUID(),
    category: ScannedObjectCategory,
    shapeHint: ScannedObjectShape = .box,
    transform: RoomTransform,
    dimensions: SIMD3<Float>,
    story: Int? = nil,
    confidence: ScannedConfidence = .high
  ) {
    self.id = id
    self.category = category
    self.shapeHint = shapeHint
    self.transform = transform
    self.dimensions = dimensions
    self.story = story
    self.confidence = confidence
  }
}

public struct ScannedRoom: Identifiable, Codable, Sendable, Equatable, Hashable {
  public var id: UUID
  public var name: String
  public var story: Int?
  public var surfaces: [ScannedSurface]
  public var objects: [ScannedObject]

  public init(
    id: UUID = UUID(),
    name: String,
    story: Int? = 0,
    surfaces: [ScannedSurface],
    objects: [ScannedObject] = []
  ) {
    self.id = id
    self.name = name
    self.story = story
    self.surfaces = surfaces
    self.objects = objects
  }
}

public enum ScannedStructureSource: String, Codable, Sendable, Equatable, Hashable {
  case singleRoom
  case mergedStructure
  case fallbackMultiRoomUnion
  case samplePreset

  public var summaryLabel: String {
    switch self {
    case .singleRoom:
      "Single Room (RoomBuilder)"
    case .mergedStructure:
      "Merged Multi-Room (StructureBuilder)"
    case .fallbackMultiRoomUnion:
      "Multi-Room Shared-AR Alignment"
    case .samplePreset:
      "Sample Apartment Preset"
    }
  }
}

public struct ScannedSceneCapture: Identifiable, Codable, Sendable, Equatable {
  public var id: UUID
  public var capturedAt: Date
  public var rooms: [ScannedRoom]
  public var mergedSurfaces: [ScannedSurface]?
  public var mergedObjects: [ScannedObject]?
  public var source: ScannedStructureSource
  public var notes: [String]

  public init(
    id: UUID = UUID(),
    capturedAt: Date = Date(timeIntervalSince1970: 1_740_000_000),
    rooms: [ScannedRoom],
    mergedSurfaces: [ScannedSurface]? = nil,
    mergedObjects: [ScannedObject]? = nil,
    source: ScannedStructureSource,
    notes: [String] = []
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.rooms = rooms
    self.mergedSurfaces = mergedSurfaces
    self.mergedObjects = mergedObjects
    self.source = source
    self.notes = notes
  }
}

extension ScannedSceneCapture {
  public static let sampleTwoRoomApartment: ScannedSceneCapture = {
    let sharedWallID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let frontWallID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let livingRoom = ScannedRoom(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
      name: "Living Room",
      story: 0,
      surfaces: [
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
          category: .floor,
          transform: .translationAndYaw(x: -1.6, y: 0.0, z: 0.0),
          dimensions: SIMD3<Float>(3.6, 0.0, 4.2)
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
          category: .wall,
          transform: .translationAndYaw(x: -1.6, y: 1.25, z: -2.1),
          dimensions: SIMD3<Float>(3.6, 2.5, 0.12)
        ),
        ScannedSurface(
          id: frontWallID,
          category: .wall,
          transform: .translationAndYaw(x: -1.6, y: 1.25, z: 2.1),
          dimensions: SIMD3<Float>(3.6, 2.5, 0.12)
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
          category: .door(isOpen: false),
          transform: .translationAndYaw(x: -2.5, y: 1.025, z: 2.1),
          dimensions: SIMD3<Float>(0.88, 2.05, 0.06),
          parentIdentifier: frontWallID
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
          category: .wall,
          transform: .translationAndYaw(x: -3.4, y: 1.25, z: 0.0, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(4.2, 2.5, 0.12)
        ),
        ScannedSurface(
          id: sharedWallID,
          category: .wall,
          transform: .translationAndYaw(x: 0.2, y: 1.25, z: 0.0, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(4.2, 2.5, 0.12)
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000005")!,
          category: .door(isOpen: true),
          transform: .translationAndYaw(x: 0.2, y: 1.025, z: -0.4, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(0.92, 2.05, 0.12),
          parentIdentifier: sharedWallID
        ),
      ],
      objects: [
        ScannedObject(
          id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
          category: .sofa,
          transform: .translationAndYaw(x: -2.65, y: 0.42, z: -0.9, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(1.9, 0.84, 0.86)
        ),
        ScannedObject(
          id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
          category: .table,
          shapeHint: .circularCylinder,
          transform: .translationAndYaw(x: -1.55, y: 0.23, z: -0.85),
          dimensions: SIMD3<Float>(0.72, 0.46, 0.72)
        ),
      ]
    )

    let studyRoom = ScannedRoom(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
      name: "Study",
      story: 0,
      surfaces: [
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000006")!,
          category: .floor,
          transform: .translationAndYaw(x: 1.7, y: 0.0, z: 0.0),
          dimensions: SIMD3<Float>(3.0, 0.0, 4.2)
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000007")!,
          category: .wall,
          transform: .translationAndYaw(x: 1.7, y: 1.25, z: -2.1),
          dimensions: SIMD3<Float>(3.0, 2.5, 0.12)
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000008")!,
          category: .wall,
          transform: .translationAndYaw(x: 1.7, y: 1.25, z: 2.1),
          dimensions: SIMD3<Float>(3.0, 2.5, 0.12)
        ),
        ScannedSurface(
          id: UUID(uuidString: "30000000-0000-0000-0000-000000000009")!,
          category: .wall,
          transform: .translationAndYaw(x: 3.2, y: 1.25, z: 0.0, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(4.2, 2.5, 0.12)
        ),
      ],
      objects: [
        ScannedObject(
          id: UUID(uuidString: "40000000-0000-0000-0000-000000000003")!,
          category: .table,
          transform: .translationAndYaw(x: 2.35, y: 0.37, z: -1.25),
          dimensions: SIMD3<Float>(1.3, 0.74, 0.65)
        ),
        ScannedObject(
          id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
          category: .chair,
          transform: .translationAndYaw(x: 2.25, y: 0.42, z: -0.45),
          dimensions: SIMD3<Float>(0.55, 0.84, 0.55)
        ),
        ScannedObject(
          id: UUID(uuidString: "40000000-0000-0000-0000-000000000005")!,
          category: .storage,
          transform: .translationAndYaw(x: 2.75, y: 0.90, z: 1.55, yawRadians: .pi / 2),
          dimensions: SIMD3<Float>(0.95, 1.80, 0.42)
        ),
      ]
    )

    return ScannedSceneCapture(
      id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
      rooms: [livingRoom, studyRoom],
      mergedSurfaces: livingRoom.surfaces + studyRoom.surfaces,
      mergedObjects: livingRoom.objects + studyRoom.objects,
      source: .samplePreset,
      notes: ["Sample 2-room floor plan with an open interior doorway and closed entry door."]
    )
  }()
}
