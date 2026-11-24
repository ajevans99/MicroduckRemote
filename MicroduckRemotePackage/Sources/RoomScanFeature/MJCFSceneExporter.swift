import Foundation
import simd

public enum DoorExportPolicy: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
  case openDoorwaysOnly
  case allDoorsOpen
  case allDoorsSolid

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .openDoorwaysOnly:
      "Open Doorways"
    case .allDoorsOpen:
      "Open All Doors"
    case .allDoorsSolid:
      "Solid Doors"
    }
  }

  public var summaryDescription: String {
    switch self {
    case .openDoorwaysOnly:
      "Openings and open doors stay passable; closed doors export as separate door boxes."
    case .allDoorsOpen:
      "All detected doors and archways are carved open so Microduck can walk between every room."
    case .allDoorsSolid:
      "Only archways without door leaves stay open; all doors export as solid barriers."
    }
  }

  public func isPassable(for category: ScannedSurfaceCategory) -> Bool {
    switch category {
    case .opening:
      true
    case let .door(isOpen):
      switch self {
      case .openDoorwaysOnly:
        isOpen
      case .allDoorsOpen:
        true
      case .allDoorsSolid:
        false
      }
    case .wall, .window, .floor:
      false
    }
  }
}

public struct MJCFExportConfiguration: Codable, Sendable, Equatable {
  public var sceneName: String
  public var doorPolicy: DoorExportPolicy
  public var includeFurniture: Bool
  public var includeFloorOverlays: Bool
  public var includePlaygroundProps: Bool
  public var alignDominantWallAxis: Bool
  public var autoClearSpawnOrigin: Bool
  public var minimumWallThickness: Double
  public var minimumConfidence: ScannedConfidence

  public init(
    sceneName: String = "scanned_room",
    doorPolicy: DoorExportPolicy = .openDoorwaysOnly,
    includeFurniture: Bool = true,
    includeFloorOverlays: Bool = true,
    includePlaygroundProps: Bool = false,
    alignDominantWallAxis: Bool = true,
    autoClearSpawnOrigin: Bool = true,
    minimumWallThickness: Double = 0.10,
    minimumConfidence: ScannedConfidence = .low
  ) {
    self.sceneName = sceneName
    self.doorPolicy = doorPolicy
    self.includeFurniture = includeFurniture
    self.includeFloorOverlays = includeFloorOverlays
    self.includePlaygroundProps = includePlaygroundProps
    self.alignDominantWallAxis = alignDominantWallAxis
    self.autoClearSpawnOrigin = autoClearSpawnOrigin
    self.minimumWallThickness = minimumWallThickness
    self.minimumConfidence = minimumConfidence
  }

  public var sceneSlug: String {
    var raw = sceneName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if raw.hasSuffix(".xml") {
      raw.removeLast(4)
    }
    if raw.hasPrefix("scene_") {
      raw.removeFirst(6)
    }
    let mapped = raw.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) {
        return Character(scalar)
      }
      return "_"
    }
    let collapsed = String(mapped)
      .split(separator: "_", omittingEmptySubsequences: true)
      .joined(separator: "_")
    return collapsed.isEmpty ? "scanned_room" : collapsed
  }

  public var fileName: String {
    "scene_\(sceneSlug).xml"
  }

  public var targetDirectoryRelativePath: String {
    "src/mjlab_microduck/robot/microduck/"
  }

  public var duckSimCommand: String {
    "DUCK_SIM_SCENE=\(sceneSlug) DUCK_SIM_CAMERAS=a scripts/duck-sim"
  }
}

public enum MJCFGeomKind: Sendable, Equatable, Hashable {
  case wall
  case lintel
  case closedDoor
  case floorOverlay
  case furniture(ScannedObjectCategory)
}

public enum MJCFPrimitiveShape: Sendable, Equatable, Hashable {
  case box(halfExtents: SIMD3<Double>)
  case cylinder(radius: Double, halfHeight: Double)
}

public struct MJCFGeneratedGeom: Identifiable, Sendable, Equatable, Hashable {
  public var id: String { name }
  public var name: String
  public var kind: MJCFGeomKind
  public var shape: MJCFPrimitiveShape
  public var position: SIMD3<Double>
  public var quaternion: SIMD4<Double>
  public var yawRadians: Double
  public var hasCollision: Bool
  public var materialName: String

  public init(
    name: String,
    kind: MJCFGeomKind,
    shape: MJCFPrimitiveShape,
    position: SIMD3<Double>,
    quaternion: SIMD4<Double>,
    yawRadians: Double,
    hasCollision: Bool,
    materialName: String
  ) {
    self.name = name
    self.kind = kind
    self.shape = shape
    self.position = position
    self.quaternion = quaternion
    self.yawRadians = yawRadians
    self.hasCollision = hasCollision
    self.materialName = materialName
  }

  public var bottomZ: Double {
    switch shape {
    case let .box(halfExtents):
      position.z - halfExtents.z
    case let .cylinder(_, halfHeight):
      position.z - halfHeight
    }
  }

  public var topZ: Double {
    switch shape {
    case let .box(halfExtents):
      position.z + halfExtents.z
    case let .cylinder(_, halfHeight):
      position.z + halfHeight
    }
  }
}

public enum MJCFPropKind: String, Codable, Sendable, Equatable, Hashable {
  case soccerBall
  case targetCone
  case toyBlock
}

public enum MJCFPropShape: Sendable, Equatable, Hashable {
  case sphere(radius: Double)
  case cylinder(radius: Double, halfHeight: Double)
  case box(halfExtents: SIMD3<Double>)

  public var footprintRadius: Double {
    switch self {
    case let .sphere(radius):
      radius
    case let .cylinder(radius, _):
      radius
    case let .box(halfExtents):
      hypot(halfExtents.x, halfExtents.y)
    }
  }
}

public struct MJCFInteractiveProp: Identifiable, Sendable, Equatable, Hashable {
  public var id: String { name }
  public var name: String
  public var kind: MJCFPropKind
  public var shape: MJCFPropShape
  public var position: SIMD3<Double>
  public var mass: Double
  public var diagInertia: SIMD3<Double>
  public var materialName: String
  public var friction: String

  public init(
    name: String,
    kind: MJCFPropKind,
    shape: MJCFPropShape,
    position: SIMD3<Double>,
    mass: Double,
    diagInertia: SIMD3<Double>,
    materialName: String,
    friction: String = "0.5 0.005 0.0001"
  ) {
    self.name = name
    self.kind = kind
    self.shape = shape
    self.position = position
    self.mass = mass
    self.diagInertia = diagInertia
    self.materialName = materialName
    self.friction = friction
  }

  public var footprintRadius: Double {
    shape.footprintRadius
  }
}

public struct FloorPlanDoorwayGap: Identifiable, Sendable, Equatable, Hashable {
  public var id: String
  public var center: SIMD2<Double>
  public var tangent: SIMD2<Double>
  public var width: Double
  public var thickness: Double

  public init(
    id: String,
    center: SIMD2<Double>,
    tangent: SIMD2<Double>,
    width: Double,
    thickness: Double
  ) {
    self.id = id
    self.center = center
    self.tangent = tangent
    self.width = width
    self.thickness = thickness
  }
}

public struct FloorPlanPreview: Sendable, Equatable {
  public var boundsMin: SIMD2<Double>
  public var boundsMax: SIMD2<Double>
  public var floorPolygons: [[SIMD2<Double>]]
  public var geoms: [MJCFGeneratedGeom]
  public var openDoorways: [FloorPlanDoorwayGap]
  public var interactiveProps: [MJCFInteractiveProp]
  public var spawnPoint: SIMD2<Double>
  public var spawnClearanceMeters: Double

  public init(
    boundsMin: SIMD2<Double>,
    boundsMax: SIMD2<Double>,
    floorPolygons: [[SIMD2<Double>]],
    geoms: [MJCFGeneratedGeom],
    openDoorways: [FloorPlanDoorwayGap],
    interactiveProps: [MJCFInteractiveProp] = [],
    spawnPoint: SIMD2<Double>,
    spawnClearanceMeters: Double
  ) {
    self.boundsMin = boundsMin
    self.boundsMax = boundsMax
    self.floorPolygons = floorPolygons
    self.geoms = geoms
    self.openDoorways = openDoorways
    self.interactiveProps = interactiveProps
    self.spawnPoint = spawnPoint
    self.spawnClearanceMeters = spawnClearanceMeters
  }
}

public struct MJCFExportSummary: Sendable, Equatable {
  public var roomCount: Int
  public var wallSegmentCount: Int
  public var openDoorwayCount: Int
  public var closedDoorCount: Int
  public var furnitureCount: Int
  public var interactivePropCount: Int
  public var footprintWidthMeters: Double
  public var footprintDepthMeters: Double
  public var floorElevationOffsetMeters: Double
  public var spawnClearanceMeters: Double
  public var warnings: [String]

  public init(
    roomCount: Int,
    wallSegmentCount: Int,
    openDoorwayCount: Int,
    closedDoorCount: Int,
    furnitureCount: Int,
    interactivePropCount: Int = 0,
    footprintWidthMeters: Double,
    footprintDepthMeters: Double,
    floorElevationOffsetMeters: Double,
    spawnClearanceMeters: Double,
    warnings: [String]
  ) {
    self.roomCount = roomCount
    self.wallSegmentCount = wallSegmentCount
    self.openDoorwayCount = openDoorwayCount
    self.closedDoorCount = closedDoorCount
    self.furnitureCount = furnitureCount
    self.interactivePropCount = interactivePropCount
    self.footprintWidthMeters = footprintWidthMeters
    self.footprintDepthMeters = footprintDepthMeters
    self.floorElevationOffsetMeters = floorElevationOffsetMeters
    self.spawnClearanceMeters = spawnClearanceMeters
    self.warnings = warnings
  }
}

public struct MJCFExportResult: Sendable, Equatable {
  public var configuration: MJCFExportConfiguration
  public var geoms: [MJCFGeneratedGeom]
  public var interactiveProps: [MJCFInteractiveProp]
  public var preview: FloorPlanPreview
  public var summary: MJCFExportSummary
  public var xml: String

  public init(
    configuration: MJCFExportConfiguration,
    geoms: [MJCFGeneratedGeom],
    interactiveProps: [MJCFInteractiveProp] = [],
    preview: FloorPlanPreview,
    summary: MJCFExportSummary,
    xml: String
  ) {
    self.configuration = configuration
    self.geoms = geoms
    self.interactiveProps = interactiveProps
    self.preview = preview
    self.summary = summary
    self.xml = xml
  }
}

public enum MJCFSceneExporter {
  public static func export(
    capture: ScannedSceneCapture,
    configuration: MJCFExportConfiguration = MJCFExportConfiguration()
  ) -> MJCFExportResult {
    var warnings = capture.notes

    let rawSurfaces = capture.mergedSurfaces ?? capture.rooms.flatMap(\.surfaces)
    let rawObjects = capture.mergedObjects ?? capture.rooms.flatMap(\.objects)

    let primaryStory = selectPrimaryStory(surfaces: rawSurfaces, rooms: capture.rooms)
    let storyFilteredSurfaces: [ScannedSurface]
    let storyFilteredObjects: [ScannedObject]

    if let primaryStory {
      var excludedCount = 0
      storyFilteredSurfaces = rawSurfaces.filter { surface in
        guard let story = surface.story else { return true }
        if story == primaryStory { return true }
        excludedCount += 1
        return false
      }
      storyFilteredObjects = rawObjects.filter { object in
        guard let story = object.story else { return true }
        if story == primaryStory { return true }
        excludedCount += 1
        return false
      }
      if excludedCount > 0 {
        warnings.append(
          "Excluded \(excludedCount) element(s) from another story; exported scene models floor story \(primaryStory) at z = 0."
        )
      }
    } else {
      storyFilteredSurfaces = rawSurfaces
      storyFilteredObjects = rawObjects
    }

    let confidentSurfaces = storyFilteredSurfaces.filter {
      $0.confidence >= configuration.minimumConfidence
    }
    let confidentObjects = storyFilteredObjects.filter {
      $0.confidence >= configuration.minimumConfidence
    }

    let floorZ = estimateFloorElevation(
      surfaces: confidentSurfaces,
      objects: confidentObjects
    )

    let preliminaryWalls = confidentSurfaces.compactMap { surface -> OrientedVerticalSlab? in
      guard surface.category == .wall else { return nil }
      return extractVerticalSlab(
        surface: surface,
        floorZ: floorZ,
        sceneYawDelta: 0,
        minimumThickness: max(configuration.minimumWallThickness, 0.02)
      )
    }

    let sceneYawDelta: Double
    if configuration.alignDominantWallAxis, !preliminaryWalls.isEmpty {
      sceneYawDelta = -dominantOrthogonalAngle(slabs: preliminaryWalls)
    } else {
      sceneYawDelta = 0
    }

    var walls = confidentSurfaces.compactMap { surface -> OrientedVerticalSlab? in
      guard surface.category == .wall else { return nil }
      return extractVerticalSlab(
        surface: surface,
        floorZ: floorZ,
        sceneYawDelta: sceneYawDelta,
        minimumThickness: max(configuration.minimumWallThickness, 0.02)
      )
    }

    if capture.mergedSurfaces == nil && capture.rooms.count > 1 {
      walls = deduplicateCoplanarWalls(walls)
    }

    let apertures = confidentSurfaces.compactMap { surface -> ApertureCut? in
      switch surface.category {
      case .opening, .door:
        guard let slab = extractVerticalSlab(
          surface: surface,
          floorZ: floorZ,
          sceneYawDelta: sceneYawDelta,
          minimumThickness: 0.04
        ) else {
          return nil
        }
        return ApertureCut(
          id: surface.id,
          parentID: surface.parentIdentifier,
          category: surface.category,
          isPassable: configuration.doorPolicy.isPassable(for: surface.category),
          slab: slab
        )
      case .wall, .window, .floor:
        return nil
      }
    }

    let floorExtractions = confidentSurfaces.compactMap { surface -> ExtractedFloorRegion? in
      guard surface.category == .floor else { return nil }
      return extractFloorRegion(surface: surface, floorZ: floorZ, sceneYawDelta: sceneYawDelta)
    }

    var generatedGeoms: [MJCFGeneratedGeom] = []
    var openDoorwayGaps: [FloorPlanDoorwayGap] = []

    if configuration.includeFloorOverlays {
      for (index, region) in floorExtractions.enumerated() {
        guard region.halfExtents.x >= 0.05, region.halfExtents.y >= 0.05 else { continue }
        let canonical = canonicalizeHorizontalBox(
          halfX: region.halfExtents.x,
          halfY: region.halfExtents.y,
          yaw: region.yaw
        )
        generatedGeoms.append(
          MJCFGeneratedGeom(
            name: String(format: "scan_floor_%02d", index + 1),
            kind: .floorOverlay,
            shape: .box(halfExtents: SIMD3<Double>(canonical.halfX, canonical.halfY, 0.001)),
            position: SIMD3<Double>(region.center.x, region.center.y, 0.002),
            quaternion: yawQuaternion(canonical.yaw),
            yawRadians: canonical.yaw,
            hasCollision: false,
            materialName: index.isMultiple(of: 2) ? "scan_mat_floor_a" : "scan_mat_floor_b"
          )
        )
      }
    }

    var wallCounter = 0
    var lintelCounter = 0
    var closedDoorCounter = 0
    var openGapDedup: [SIMD2<Double>] = []

    for wall in walls {
      let matchingCuts = matchApertures(apertures, to: wall)
      if let curve = wall.curve, matchingCuts.isEmpty, abs(Double(curve.endAngleRadians - curve.startAngleRadians)) > 0.15 {
        let chordSlabs = discretizeCurvedWall(wall: wall, curve: curve)
        for chord in chordSlabs {
          wallCounter += 1
          generatedGeoms.append(
            makeHorizontalBoxGeom(
              name: String(format: "scan_wall_%02d", wallCounter),
              kind: .wall,
              center2D: chord.center,
              yaw: chord.yaw,
              halfLength: chord.length * 0.5,
              halfThickness: chord.thickness * 0.5,
              bottomZ: chord.bottomZ,
              topZ: chord.topZ,
              hasCollision: true,
              materialName: "scan_mat_wall"
            )
          )
        }
        continue
      }

      let halfWallLen = wall.length * 0.5
      let solidIntervals = subtractIntervals(
        baseStart: -halfWallLen,
        baseEnd: halfWallLen,
        cuts: matchingCuts.map { ($0.uStart, $0.uEnd) },
        minimumSpan: 0.03
      )

      for (segStart, segEnd) in solidIntervals {
        let segLen = segEnd - segStart
        let uMid = (segStart + segEnd) * 0.5
        let segCenter = wall.center + wall.tangent * uMid
        wallCounter += 1
        generatedGeoms.append(
          makeHorizontalBoxGeom(
            name: String(format: "scan_wall_%02d", wallCounter),
            kind: .wall,
            center2D: segCenter,
            yaw: wall.yaw,
            halfLength: segLen * 0.5,
            halfThickness: wall.thickness * 0.5,
            bottomZ: wall.bottomZ,
            topZ: wall.topZ,
            hasCollision: true,
            materialName: "scan_mat_wall"
          )
        )
      }

      let mergedCutWindows = mergeCutWindows(matchingCuts, wallHalfLength: halfWallLen)
      for window in mergedCutWindows {
        let cutLen = window.uEnd - window.uStart
        guard cutLen >= 0.08 else { continue }
        let uMid = (window.uStart + window.uEnd) * 0.5
        let cutCenter = wall.center + wall.tangent * uMid

        if wall.topZ - window.topZ >= 0.08 {
          lintelCounter += 1
          generatedGeoms.append(
            makeHorizontalBoxGeom(
              name: String(format: "scan_lintel_%02d", lintelCounter),
              kind: .lintel,
              center2D: cutCenter,
              yaw: wall.yaw,
              halfLength: cutLen * 0.5,
              halfThickness: wall.thickness * 0.5,
              bottomZ: window.topZ,
              topZ: wall.topZ,
              hasCollision: true,
              materialName: "scan_mat_wall"
            )
          )
        }

        if window.isPassable {
          let alreadyRecorded = openGapDedup.contains { simd_distance($0, cutCenter) < 0.25 }
          if !alreadyRecorded {
            openGapDedup.append(cutCenter)
            openDoorwayGaps.append(
              FloorPlanDoorwayGap(
                id: String(format: "doorway_%02d", openDoorwayGaps.count + 1),
                center: cutCenter,
                tangent: wall.tangent,
                width: cutLen,
                thickness: wall.thickness
              )
            )
          }
        } else {
          closedDoorCounter += 1
          let doorThickness = min(wall.thickness, 0.06)
          generatedGeoms.append(
            makeHorizontalBoxGeom(
              name: String(format: "scan_door_closed_%02d", closedDoorCounter),
              kind: .closedDoor,
              center2D: cutCenter,
              yaw: wall.yaw,
              halfLength: cutLen * 0.5,
              halfThickness: max(doorThickness * 0.5, 0.02),
              bottomZ: 0.0,
              topZ: max(window.topZ, 0.50),
              hasCollision: true,
              materialName: "scan_mat_door"
            )
          )
        }
      }
    }

    var furnitureCounter = 0
    if configuration.includeFurniture {
      for object in confidentObjects {
        guard let geom = extractFurnitureGeom(
          object: object,
          index: furnitureCounter + 1,
          floorZ: floorZ,
          sceneYawDelta: sceneYawDelta
        ) else {
          continue
        }
        furnitureCounter += 1
        generatedGeoms.append(geom)
      }
    }

    let primaryRoomCenter = computePrimaryRoomCenter(
      capture: capture,
      floorZ: floorZ,
      sceneYawDelta: sceneYawDelta,
      fallbackFloors: floorExtractions,
      fallbackWalls: walls
    )

    let floorPolygons = floorExtractions.map(\.polygon)
    let spawnSolution: (point: SIMD2<Double>, clearance: Double)
    if configuration.autoClearSpawnOrigin {
      spawnSolution = findSafeSpawnPoint(
        preferredCenter: primaryRoomCenter,
        floorPolygons: floorPolygons,
        geoms: generatedGeoms
      )
      if spawnSolution.clearance < 0.22, !generatedGeoms.isEmpty {
        warnings.append(
          String(
            format: "Tight floor clearance (%.2f m) around duck spawn at (0, 0); verify obstacle spacing before walking.",
            spawnSolution.clearance
          )
        )
      }
    } else {
      let clearance = obstacleClearance(at: primaryRoomCenter, geoms: generatedGeoms)
      spawnSolution = (primaryRoomCenter, clearance)
    }

    let shift = -spawnSolution.point
    for index in generatedGeoms.indices {
      generatedGeoms[index].position = cleanVec3(
        SIMD3<Double>(
          generatedGeoms[index].position.x + shift.x,
          generatedGeoms[index].position.y + shift.y,
          generatedGeoms[index].position.z
        )
      )
    }
    for index in openDoorwayGaps.indices {
      openDoorwayGaps[index].center += shift
    }
    let shiftedPolygons = floorPolygons.map { polygon in
      polygon.map { $0 + shift }
    }

    let bounds = computeSceneBounds(geoms: generatedGeoms, floorPolygons: shiftedPolygons)

    var interactiveProps: [MJCFInteractiveProp] = []
    if configuration.includePlaygroundProps {
      interactiveProps = placeInteractiveProps(
        bounds: bounds,
        floorPolygons: shiftedPolygons,
        geoms: generatedGeoms,
        openDoorways: openDoorwayGaps
      )
      if interactiveProps.isEmpty {
        warnings.append(
          "No open floor space met clearance margins for playground props; exported scene without props."
        )
      }
    }

    let preview = FloorPlanPreview(
      boundsMin: bounds.min,
      boundsMax: bounds.max,
      floorPolygons: shiftedPolygons,
      geoms: generatedGeoms,
      openDoorways: openDoorwayGaps,
      interactiveProps: interactiveProps,
      spawnPoint: .zero,
      spawnClearanceMeters: max(spawnSolution.clearance, 0)
    )

    let summary = MJCFExportSummary(
      roomCount: max(capture.rooms.count, rawSurfaces.isEmpty && rawObjects.isEmpty ? 0 : 1),
      wallSegmentCount: wallCounter,
      openDoorwayCount: openDoorwayGaps.count,
      closedDoorCount: closedDoorCounter,
      furnitureCount: furnitureCounter,
      interactivePropCount: interactiveProps.count,
      footprintWidthMeters: max(bounds.max.x - bounds.min.x, 0),
      footprintDepthMeters: max(bounds.max.y - bounds.min.y, 0),
      floorElevationOffsetMeters: floorZ,
      spawnClearanceMeters: max(spawnSolution.clearance, 0),
      warnings: warnings
    )

    let xml = renderMJCFXML(
      configuration: configuration,
      geoms: generatedGeoms,
      interactiveProps: interactiveProps,
      summary: summary
    )

    return MJCFExportResult(
      configuration: configuration,
      geoms: generatedGeoms,
      interactiveProps: interactiveProps,
      preview: preview,
      summary: summary,
      xml: xml
    )
  }
}

private struct OrientedVerticalSlab {
  var id: UUID
  var center: SIMD2<Double>
  var tangent: SIMD2<Double>
  var normal: SIMD2<Double>
  var yaw: Double
  var length: Double
  var thickness: Double
  var bottomZ: Double
  var topZ: Double
  var curve: ScannedArcCurve?
}

private struct ApertureCut {
  var id: UUID
  var parentID: UUID?
  var category: ScannedSurfaceCategory
  var isPassable: Bool
  var slab: OrientedVerticalSlab
}

private struct WallCutProjection {
  var uStart: Double
  var uEnd: Double
  var topZ: Double
  var isPassable: Bool
}

private struct ExtractedFloorRegion {
  var center: SIMD2<Double>
  var halfExtents: SIMD2<Double>
  var yaw: Double
  var polygon: [SIMD2<Double>]
}

extension MJCFSceneExporter {
  fileprivate static func arToMuJoCo(_ v: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3<Double>(v.x, -v.z, v.y)
  }

  fileprivate static func rotate2D(_ p: SIMD2<Double>, by angle: Double) -> SIMD2<Double> {
    let c = cos(angle)
    let s = sin(angle)
    return SIMD2<Double>(c * p.x - s * p.y, s * p.x + c * p.y)
  }

  fileprivate static func selectPrimaryStory(
    surfaces: [ScannedSurface],
    rooms: [ScannedRoom]
  ) -> Int? {
    var weights: [Int: Double] = [:]
    for surface in surfaces {
      guard let story = surface.story else { continue }
      let d = SIMD3<Double>(surface.dimensions)
      let area = max(d.x * max(d.y, d.z), 0.1)
      weights[story, default: 0] += area
    }
    if weights.isEmpty {
      for room in rooms {
        if let story = room.story {
          weights[story, default: 0] += 1.0
        }
      }
    }
    return weights.max { lhs, rhs in
      if abs(lhs.value - rhs.value) > 1e-6 {
        return lhs.value < rhs.value
      }
      return lhs.key > rhs.key
    }?.key
  }

  fileprivate static func estimateFloorElevation(
    surfaces: [ScannedSurface],
    objects: [ScannedObject]
  ) -> Double {
    var floorSamples: [(z: Double, weight: Double)] = []
    var wallBottoms: [Double] = []

    for surface in surfaces {
      let decomposed = decomposeTransform(surface.transform, dimensions: surface.dimensions)
      switch surface.category {
      case .floor:
        let horizontalArea = max(decomposed.sortedHorizontalLengths.0 * decomposed.sortedHorizontalLengths.1, 0.25)
        floorSamples.append((decomposed.centerMJ.z, horizontalArea))
      case .wall, .door, .opening:
        wallBottoms.append(decomposed.centerMJ.z - decomposed.verticalExtent * 0.5)
      case .window:
        break
      }
    }

    if !floorSamples.isEmpty {
      let sorted = floorSamples.sorted { $0.z < $1.z }
      let totalWeight = sorted.reduce(0.0) { $0 + $1.weight }
      var cumulative = 0.0
      for sample in sorted {
        cumulative += sample.weight
        if cumulative >= totalWeight * 0.5 {
          return sample.z
        }
      }
      return sorted[sorted.count / 2].z
    }

    if !wallBottoms.isEmpty {
      let sorted = wallBottoms.sorted()
      return sorted[sorted.count / 2]
    }

    var objectBottoms: [Double] = []
    for object in objects {
      let decomposed = decomposeTransform(object.transform, dimensions: object.dimensions)
      objectBottoms.append(decomposed.centerMJ.z - decomposed.verticalExtent * 0.5)
    }
    if let minBottom = objectBottoms.min() {
      return minBottom
    }

    return 0.0
  }

  private struct DecomposedTransform {
    var centerMJ: SIMD3<Double>
    var unitAxesMJ: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)
    var fullLengths: SIMD3<Double>
    var verticalAxisIndex: Int
    var verticalExtent: Double
    var sortedHorizontalLengths: (Double, Double)
  }

  private static func decomposeTransform(
    _ transform: RoomTransform,
    dimensions: SIMD3<Float>
  ) -> DecomposedTransform {
    let m = transform.matrix
    let rawAxes = [
      SIMD3<Double>(Double(m.columns.0.x), Double(m.columns.0.y), Double(m.columns.0.z)),
      SIMD3<Double>(Double(m.columns.1.x), Double(m.columns.1.y), Double(m.columns.1.z)),
      SIMD3<Double>(Double(m.columns.2.x), Double(m.columns.2.y), Double(m.columns.2.z)),
    ]
    let scales = rawAxes.map { max(simd_length($0), 1e-6) }
    let unitAR = zip(rawAxes, scales).map { $0 / $1 }
    let unitMJ = unitAR.map(arToMuJoCo)
    let centerAR = SIMD3<Double>(
      Double(m.columns.3.x),
      Double(m.columns.3.y),
      Double(m.columns.3.z)
    )
    let centerMJ = arToMuJoCo(centerAR)
    let fullLengths = SIMD3<Double>(
      max(Double(dimensions.x) * scales[0], 0),
      max(Double(dimensions.y) * scales[1], 0),
      max(Double(dimensions.z) * scales[2], 0)
    )

    let absZ = unitMJ.map { abs($0.z) }
    var verticalIndex = 1
    if absZ[0] > absZ[verticalIndex] { verticalIndex = 0 }
    if absZ[2] > absZ[verticalIndex] { verticalIndex = 2 }

    let lengthsArray = [fullLengths.x, fullLengths.y, fullLengths.z]
    var horiz: [Double] = []
    for idx in 0..<3 where idx != verticalIndex {
      horiz.append(lengthsArray[idx])
    }
    horiz.sort(by: >)

    return DecomposedTransform(
      centerMJ: centerMJ,
      unitAxesMJ: (unitMJ[0], unitMJ[1], unitMJ[2]),
      fullLengths: fullLengths,
      verticalAxisIndex: verticalIndex,
      verticalExtent: lengthsArray[verticalIndex],
      sortedHorizontalLengths: (horiz.first ?? 0, horiz.last ?? 0)
    )
  }

  fileprivate static func extractVerticalSlab(
    surface: ScannedSurface,
    floorZ: Double,
    sceneYawDelta: Double,
    minimumThickness: Double
  ) -> OrientedVerticalSlab? {
    let d = decomposeTransform(surface.transform, dimensions: surface.dimensions)
    let axes = [d.unitAxesMJ.0, d.unitAxesMJ.1, d.unitAxesMJ.2]
    let lengths = [d.fullLengths.x, d.fullLengths.y, d.fullLengths.z]

    let horizIndices = (0..<3).filter { $0 != d.verticalAxisIndex }
    guard horizIndices.count == 2 else { return nil }

    let spanIndex: Int
    let normalIndex: Int
    if d.verticalAxisIndex == 1 {
      spanIndex = 0
      normalIndex = 2
    } else if lengths[horizIndices[0]] >= lengths[horizIndices[1]] {
      spanIndex = horizIndices[0]
      normalIndex = horizIndices[1]
    } else {
      spanIndex = horizIndices[1]
      normalIndex = horizIndices[0]
    }

    let spanLength = lengths[spanIndex]
    let height = d.verticalExtent
    guard spanLength >= 0.04, height >= 0.08 else { return nil }

    var tangent2D = SIMD2<Double>(axes[spanIndex].x, axes[spanIndex].y)
    let tangentNorm = simd_length(tangent2D)
    if tangentNorm < 1e-5 {
      tangent2D = SIMD2<Double>(1, 0)
    } else {
      tangent2D /= tangentNorm
    }
    tangent2D = rotate2D(tangent2D, by: sceneYawDelta)
    if tangent2D.x < -1e-6 || (abs(tangent2D.x) <= 1e-6 && tangent2D.y < 0) {
      tangent2D = -tangent2D
    }

    let normal2D = SIMD2<Double>(-tangent2D.y, tangent2D.x)
    let center2D = rotate2D(SIMD2<Double>(d.centerMJ.x, d.centerMJ.y), by: sceneYawDelta)
    let yaw = atan2(tangent2D.y, tangent2D.x)

    let rawBottom = (d.centerMJ.z - floorZ) - height * 0.5
    let rawTop = (d.centerMJ.z - floorZ) + height * 0.5
    guard rawTop > 0.05 else { return nil }

    let clampedBottom: Double
    switch surface.category {
    case .wall:
      clampedBottom = abs(rawBottom) <= 0.30 ? 0.0 : max(rawBottom, 0.0)
    case .door, .opening:
      clampedBottom = max(rawBottom, 0.0)
    case .window, .floor:
      clampedBottom = max(rawBottom, 0.0)
    }

    guard rawTop - clampedBottom >= 0.06 else { return nil }

    return OrientedVerticalSlab(
      id: surface.id,
      center: center2D,
      tangent: tangent2D,
      normal: normal2D,
      yaw: yaw,
      length: spanLength,
      thickness: max(lengths[normalIndex], minimumThickness),
      bottomZ: clampedBottom,
      topZ: rawTop,
      curve: surface.curve
    )
  }

  fileprivate static func extractFloorRegion(
    surface: ScannedSurface,
    floorZ: Double,
    sceneYawDelta: Double
  ) -> ExtractedFloorRegion? {
    let matrix = surface.transform.matrix
    if surface.polygonCorners.count >= 3 {
      let world2D: [SIMD2<Double>] = surface.polygonCorners.map { local in
        let world4 = matrix * SIMD4<Float>(local.x, local.y, local.z, 1.0)
        let mj = arToMuJoCo(SIMD3<Double>(Double(world4.x), Double(world4.y), Double(world4.z)))
        return rotate2D(SIMD2<Double>(mj.x, mj.y), by: sceneYawDelta)
      }
      var minPt = world2D[0]
      var maxPt = world2D[0]
      for pt in world2D {
        minPt = simd_min(minPt, pt)
        maxPt = simd_max(maxPt, pt)
      }
      let center = (minPt + maxPt) * 0.5
      let half = (maxPt - minPt) * 0.5
      guard half.x >= 0.05 || half.y >= 0.05 else { return nil }
      return ExtractedFloorRegion(
        center: center,
        halfExtents: SIMD2<Double>(max(half.x, 0.05), max(half.y, 0.05)),
        yaw: 0,
        polygon: world2D
      )
    }

    let d = decomposeTransform(surface.transform, dimensions: surface.dimensions)
    let axes = [d.unitAxesMJ.0, d.unitAxesMJ.1, d.unitAxesMJ.2]
    let lengths = [d.fullLengths.x, d.fullLengths.y, d.fullLengths.z]
    let horizIndices = (0..<3).filter { $0 != d.verticalAxisIndex }
    guard horizIndices.count == 2 else { return nil }

    let i0 = horizIndices[0]
    let i1 = horizIndices[1]
    let len0 = lengths[i0]
    let len1 = lengths[i1]
    guard len0 >= 0.10, len1 >= 0.10 else { return nil }

    var axis0 = SIMD2<Double>(axes[i0].x, axes[i0].y)
    let norm0 = simd_length(axis0)
    axis0 = norm0 > 1e-5 ? (axis0 / norm0) : SIMD2<Double>(1, 0)
    axis0 = rotate2D(axis0, by: sceneYawDelta)
    let axis1 = SIMD2<Double>(-axis0.y, axis0.x)

    let center = rotate2D(SIMD2<Double>(d.centerMJ.x, d.centerMJ.y), by: sceneYawDelta)
    let hx = len0 * 0.5
    let hy = len1 * 0.5
    let corners = [
      center - axis0 * hx - axis1 * hy,
      center + axis0 * hx - axis1 * hy,
      center + axis0 * hx + axis1 * hy,
      center - axis0 * hx + axis1 * hy,
    ]
    return ExtractedFloorRegion(
      center: center,
      halfExtents: SIMD2<Double>(hx, hy),
      yaw: atan2(axis0.y, axis0.x),
      polygon: corners
    )
  }

  private static func dominantOrthogonalAngle(slabs: [OrientedVerticalSlab]) -> Double {
    var sumCos = 0.0
    var sumSin = 0.0
    for slab in slabs {
      let fourTheta = 4.0 * slab.yaw
      sumCos += slab.length * cos(fourTheta)
      sumSin += slab.length * sin(fourTheta)
    }
    guard hypot(sumCos, sumSin) > 1e-6 else { return 0 }
    return 0.25 * atan2(sumSin, sumCos)
  }

  private static func deduplicateCoplanarWalls(_ walls: [OrientedVerticalSlab]) -> [OrientedVerticalSlab] {
    var result: [OrientedVerticalSlab] = []
    for candidate in walls {
      var mergedIntoExisting = false
      for index in result.indices {
        let existing = result[index]
        guard existing.curve == nil, candidate.curve == nil else { continue }
        let parallel = abs(simd_dot(existing.tangent, candidate.tangent))
        guard parallel >= 0.97 else { continue }

        let delta = candidate.center - existing.center
        let normalDist = abs(simd_dot(delta, existing.normal))
        guard normalDist <= max(0.18, max(existing.thickness, candidate.thickness)) else { continue }

        let uOffset = simd_dot(delta, existing.tangent)
        let eStart = -existing.length * 0.5
        let eEnd = existing.length * 0.5
        let cStart = uOffset - candidate.length * 0.5
        let cEnd = uOffset + candidate.length * 0.5

        if min(eEnd, cEnd) - max(eStart, cStart) >= -0.05 {
          let unionStart = min(eStart, cStart)
          let unionEnd = max(eEnd, cEnd)
          let uMid = (unionStart + unionEnd) * 0.5
          result[index].center = existing.center + existing.tangent * uMid + existing.normal * (simd_dot(delta, existing.normal) * 0.5)
          result[index].length = unionEnd - unionStart
          result[index].thickness = max(existing.thickness, candidate.thickness)
          result[index].bottomZ = min(existing.bottomZ, candidate.bottomZ)
          result[index].topZ = max(existing.topZ, candidate.topZ)
          mergedIntoExisting = true
          break
        }
      }
      if !mergedIntoExisting {
        result.append(candidate)
      }
    }
    return result
  }

  private static func matchApertures(
    _ apertures: [ApertureCut],
    to wall: OrientedVerticalSlab
  ) -> [WallCutProjection] {
    let halfWall = wall.length * 0.5
    var projections: [WallCutProjection] = []

    for aperture in apertures {
      guard aperture.slab.bottomZ <= 0.40 else { continue }

      let delta = aperture.slab.center - wall.center
      let isDirectChild = aperture.parentID == wall.id
      let parallel = abs(simd_dot(aperture.slab.tangent, wall.tangent))
      let normalOffset = abs(simd_dot(delta, wall.normal))

      if !isDirectChild {
        guard parallel >= 0.90, normalOffset <= max(0.28, wall.thickness * 1.5) else {
          continue
        }
      }

      let centerU = simd_dot(delta, wall.tangent)
      let halfCut = aperture.slab.length * 0.5
      let clampedStart = max(-halfWall, centerU - halfCut)
      let clampedEnd = min(halfWall, centerU + halfCut)
      guard clampedEnd - clampedStart >= 0.08 else { continue }

      projections.append(
        WallCutProjection(
          uStart: clampedStart,
          uEnd: clampedEnd,
          topZ: min(aperture.slab.topZ, wall.topZ),
          isPassable: aperture.isPassable
        )
      )
    }

    return projections
  }

  private static func subtractIntervals(
    baseStart: Double,
    baseEnd: Double,
    cuts: [(Double, Double)],
    minimumSpan: Double
  ) -> [(Double, Double)] {
    guard !cuts.isEmpty else {
      return baseEnd - baseStart >= minimumSpan ? [(baseStart, baseEnd)] : []
    }
    let sorted = cuts
      .map { (max(baseStart, min($0.0, $0.1)), min(baseEnd, max($0.0, $0.1))) }
      .filter { $0.1 > $0.0 }
      .sorted { $0.0 < $1.0 }

    var merged: [(Double, Double)] = []
    for cut in sorted {
      if let last = merged.last, cut.0 <= last.1 + 0.02 {
        merged[merged.count - 1].1 = max(last.1, cut.1)
      } else {
        merged.append(cut)
      }
    }

    var remaining: [(Double, Double)] = []
    var cursor = baseStart
    for cut in merged {
      if cut.0 - cursor >= minimumSpan {
        remaining.append((cursor, cut.0))
      }
      cursor = max(cursor, cut.1)
    }
    if baseEnd - cursor >= minimumSpan {
      remaining.append((cursor, baseEnd))
    }
    return remaining
  }

  private static func mergeCutWindows(
    _ cuts: [WallCutProjection],
    wallHalfLength: Double
  ) -> [WallCutProjection] {
    guard !cuts.isEmpty else { return [] }
    let sorted = cuts.sorted { $0.uStart < $1.uStart }
    var merged: [WallCutProjection] = []

    for cut in sorted {
      let cStart = max(-wallHalfLength, cut.uStart)
      let cEnd = min(wallHalfLength, cut.uEnd)
      guard cEnd > cStart else { continue }

      if let last = merged.last, cStart <= last.uEnd + 0.02, last.isPassable == cut.isPassable {
        merged[merged.count - 1].uEnd = max(last.uEnd, cEnd)
        merged[merged.count - 1].topZ = max(last.topZ, cut.topZ)
      } else {
        merged.append(
          WallCutProjection(
            uStart: cStart,
            uEnd: cEnd,
            topZ: cut.topZ,
            isPassable: cut.isPassable
          )
        )
      }
    }
    return merged
  }

  private static func discretizeCurvedWall(
    wall: OrientedVerticalSlab,
    curve: ScannedArcCurve
  ) -> [OrientedVerticalSlab] {
    let start = Double(curve.startAngleRadians)
    let end = Double(curve.endAngleRadians)
    let radius = max(Double(curve.radius), 0.25)
    let span = end - start
    let stepCount = max(2, min(16, Int(ceil(abs(span) / (.pi / 10)))))
    let chordCenter = wall.center - wall.normal * radius * cos(span * 0.5)

    var segments: [OrientedVerticalSlab] = []
    for idx in 0..<stepCount {
      let a0 = start + span * (Double(idx) / Double(stepCount))
      let a1 = start + span * (Double(idx + 1) / Double(stepCount))
      let p0 = chordCenter + rotate2D(SIMD2<Double>(cos(a0), sin(a0)) * radius, by: wall.yaw)
      let p1 = chordCenter + rotate2D(SIMD2<Double>(cos(a1), sin(a1)) * radius, by: wall.yaw)
      let delta = p1 - p0
      let len = simd_length(delta)
      guard len >= 0.04 else { continue }
      let t = delta / len
      segments.append(
        OrientedVerticalSlab(
          id: wall.id,
          center: (p0 + p1) * 0.5,
          tangent: t,
          normal: SIMD2<Double>(-t.y, t.x),
          yaw: atan2(t.y, t.x),
          length: len,
          thickness: wall.thickness,
          bottomZ: wall.bottomZ,
          topZ: wall.topZ,
          curve: nil
        )
      )
    }
    return segments.isEmpty ? [wall] : segments
  }

  private static func extractFurnitureGeom(
    object: ScannedObject,
    index: Int,
    floorZ: Double,
    sceneYawDelta: Double
  ) -> MJCFGeneratedGeom? {
    let m = object.transform.matrix
    let rawAxes = [
      SIMD3<Double>(Double(m.columns.0.x), Double(m.columns.0.y), Double(m.columns.0.z)),
      SIMD3<Double>(Double(m.columns.1.x), Double(m.columns.1.y), Double(m.columns.1.z)),
      SIMD3<Double>(Double(m.columns.2.x), Double(m.columns.2.y), Double(m.columns.2.z)),
    ]
    let scales = rawAxes.map { max(simd_length($0), 1e-6) }
    let unitAR = zip(rawAxes, scales).map { $0 / $1 }

    let zRot3 = simd_double3x3(
      SIMD3<Double>(cos(sceneYawDelta), sin(sceneYawDelta), 0),
      SIMD3<Double>(-sin(sceneYawDelta), cos(sceneYawDelta), 0),
      SIMD3<Double>(0, 0, 1)
    )
    let v0 = zRot3 * arToMuJoCo(unitAR[0])
    let v1 = zRot3 * arToMuJoCo(unitAR[1])
    let v2 = zRot3 * arToMuJoCo(unitAR[2])

    let fullX = max(Double(object.dimensions.x) * scales[0], 0.04)
    let fullY = max(Double(object.dimensions.y) * scales[1], 0.04)
    let fullZ = max(Double(object.dimensions.z) * scales[2], 0.04)

    let centerAR = SIMD3<Double>(
      Double(m.columns.3.x),
      Double(m.columns.3.y),
      Double(m.columns.3.z)
    )
    var centerMJ = zRot3 * arToMuJoCo(centerAR)
    centerMJ.z -= floorZ

    let categorySlug = object.category.rawValue.lowercased()
    let name = String(format: "scan_obj_%@_%02d", categorySlug, index)
    let material = materialName(for: object.category)

    if abs(v1.z) >= 0.96 {
      var halfWidth = fullX * 0.5
      var halfDepth = fullZ * 0.5
      var halfHeight = fullY * 0.5

      let rawBottom = centerMJ.z - halfHeight
      let rawTop = centerMJ.z + halfHeight
      guard rawTop > 0.03 else { return nil }

      if rawBottom >= -0.30 && rawBottom <= 0.10 {
        halfHeight = rawTop * 0.5
        centerMJ.z = halfHeight
      } else if rawBottom < -0.30 {
        halfHeight = rawTop * 0.5
        centerMJ.z = halfHeight
      }

      let rawYaw = atan2(v0.y, v0.x)
      let minHoriz = min(halfWidth, halfDepth)
      let maxHoriz = max(halfWidth, halfDepth)

      if object.shapeHint == .circularCylinder, maxHoriz > 0, (minHoriz / maxHoriz) >= 0.78 {
        let radius = cleanMetric((halfWidth + halfDepth) * 0.5)
        return MJCFGeneratedGeom(
          name: name,
          kind: .furniture(object.category),
          shape: .cylinder(radius: max(radius, 0.02), halfHeight: cleanMetric(max(halfHeight, 0.02))),
          position: cleanVec3(centerMJ),
          quaternion: SIMD4<Double>(1, 0, 0, 0),
          yawRadians: 0,
          hasCollision: true,
          materialName: material
        )
      }

      let canonical = canonicalizeHorizontalBox(halfX: halfWidth, halfY: halfDepth, yaw: rawYaw)
      halfWidth = canonical.halfX
      halfDepth = canonical.halfY

      return MJCFGeneratedGeom(
        name: name,
        kind: .furniture(object.category),
        shape: .box(
          halfExtents: cleanVec3(
            SIMD3<Double>(max(halfWidth, 0.02), max(halfDepth, 0.02), max(halfHeight, 0.02))
          )
        ),
        position: cleanVec3(centerMJ),
        quaternion: yawQuaternion(canonical.yaw),
        yawRadians: canonical.yaw,
        hasCollision: true,
        materialName: material
      )
    }

    var rotMatrix = simd_double3x3(columns: (v0, -v2, v1))
    if simd_determinant(rotMatrix) < 0 {
      rotMatrix.columns.1 = -rotMatrix.columns.1
    }
    let quat = simd_normalize(simd_quatd(rotMatrix))
    let halfExtents = cleanVec3(SIMD3<Double>(fullX * 0.5, fullZ * 0.5, fullY * 0.5))
    let verticalReach =
      abs(rotMatrix.columns.0.z) * halfExtents.x +
      abs(rotMatrix.columns.1.z) * halfExtents.y +
      abs(rotMatrix.columns.2.z) * halfExtents.z
    if centerMJ.z - verticalReach < 0 {
      centerMJ.z = verticalReach
    }

    return MJCFGeneratedGeom(
      name: name,
      kind: .furniture(object.category),
      shape: .box(halfExtents: halfExtents),
      position: cleanVec3(centerMJ),
      quaternion: canonicalQuaternionVector(quat),
      yawRadians: atan2(v0.y, v0.x),
      hasCollision: true,
      materialName: material
    )
  }

  private static func materialName(for category: ScannedObjectCategory) -> String {
    switch category {
    case .sofa, .chair:
      "scan_mat_seating"
    case .table, .storage:
      "scan_mat_wood"
    case .bed:
      "scan_mat_bed"
    case .refrigerator, .stove, .oven, .dishwasher, .washerDryer, .television:
      "scan_mat_appliance"
    case .sink, .toilet, .bathtub:
      "scan_mat_ceramic"
    case .fireplace, .stairs, .other:
      "scan_mat_accent"
    }
  }

  private static func canonicalizeHorizontalBox(
    halfX: Double,
    halfY: Double,
    yaw: Double
  ) -> (halfX: Double, halfY: Double, yaw: Double) {
    var normalized = remainder(yaw, .pi)
    if normalized <= -.pi * 0.5 {
      normalized += .pi
    } else if normalized > .pi * 0.5 {
      normalized -= .pi
    }

    if abs(normalized) <= 1e-3 {
      return (halfX, halfY, 0)
    }
    if abs(abs(normalized) - .pi * 0.5) <= 1e-3 {
      return (halfY, halfX, 0)
    }
    return (halfX, halfY, normalized)
  }

  private static func yawQuaternion(_ yaw: Double) -> SIMD4<Double> {
    guard abs(yaw) > 1e-5 else {
      return SIMD4<Double>(1, 0, 0, 0)
    }
    let half = yaw * 0.5
    let w = cos(half)
    let z = sin(half)
    return w >= 0 ? SIMD4<Double>(w, 0, 0, z) : SIMD4<Double>(-w, 0, 0, -z)
  }

  private static func canonicalQuaternionVector(_ q: simd_quatd) -> SIMD4<Double> {
    let raw = SIMD4<Double>(q.real, q.imag.x, q.imag.y, q.imag.z)
    return raw.x >= 0 ? raw : -raw
  }

  private static func cleanMetric(_ value: Double) -> Double {
    let rounded = (value * 100_000).rounded() / 100_000
    return abs(rounded) < 1e-6 ? 0.0 : rounded
  }

  private static func cleanVec3(_ v: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3<Double>(cleanMetric(v.x), cleanMetric(v.y), cleanMetric(v.z))
  }

  private static func makeHorizontalBoxGeom(
    name: String,
    kind: MJCFGeomKind,
    center2D: SIMD2<Double>,
    yaw: Double,
    halfLength: Double,
    halfThickness: Double,
    bottomZ: Double,
    topZ: Double,
    hasCollision: Bool,
    materialName: String
  ) -> MJCFGeneratedGeom {
    let canonical = canonicalizeHorizontalBox(
      halfX: max(halfLength, 0.015),
      halfY: max(halfThickness, 0.015),
      yaw: yaw
    )
    let halfZ = max((topZ - bottomZ) * 0.5, 0.015)
    let centerZ = (topZ + bottomZ) * 0.5
    return MJCFGeneratedGeom(
      name: name,
      kind: kind,
      shape: .box(
        halfExtents: cleanVec3(SIMD3<Double>(canonical.halfX, canonical.halfY, halfZ))
      ),
      position: cleanVec3(SIMD3<Double>(center2D.x, center2D.y, centerZ)),
      quaternion: yawQuaternion(canonical.yaw),
      yawRadians: canonical.yaw,
      hasCollision: hasCollision,
      materialName: materialName
    )
  }

  private static func computePrimaryRoomCenter(
    capture: ScannedSceneCapture,
    floorZ: Double,
    sceneYawDelta: Double,
    fallbackFloors: [ExtractedFloorRegion],
    fallbackWalls: [OrientedVerticalSlab]
  ) -> SIMD2<Double> {
    if let firstRoom = capture.rooms.first {
      for surface in firstRoom.surfaces where surface.category == .floor {
        if let region = extractFloorRegion(surface: surface, floorZ: floorZ, sceneYawDelta: sceneYawDelta) {
          return polygonCentroid(region.polygon)
        }
      }
      let roomWalls = firstRoom.surfaces.compactMap { surface -> OrientedVerticalSlab? in
        guard surface.category == .wall else { return nil }
        return extractVerticalSlab(surface: surface, floorZ: floorZ, sceneYawDelta: sceneYawDelta, minimumThickness: 0.08)
      }
      if !roomWalls.isEmpty {
        let sum = roomWalls.reduce(SIMD2<Double>.zero) { $0 + $1.center }
        return sum / Double(roomWalls.count)
      }
    }

    if let firstFloor = fallbackFloors.first {
      return polygonCentroid(firstFloor.polygon)
    }
    if !fallbackWalls.isEmpty {
      let sum = fallbackWalls.reduce(SIMD2<Double>.zero) { $0 + $1.center }
      return sum / Double(fallbackWalls.count)
    }
    return .zero
  }

  private static func polygonCentroid(_ polygon: [SIMD2<Double>]) -> SIMD2<Double> {
    guard !polygon.isEmpty else { return .zero }
    let sum = polygon.reduce(SIMD2<Double>.zero, +)
    return sum / Double(polygon.count)
  }

  private static func findSafeSpawnPoint(
    preferredCenter: SIMD2<Double>,
    floorPolygons: [[SIMD2<Double>]],
    geoms: [MJCFGeneratedGeom]
  ) -> (point: SIMD2<Double>, clearance: Double) {
    let lowObstacles = geoms.filter { $0.hasCollision && $0.bottomZ < 0.45 }
    guard !lowObstacles.isEmpty else {
      return (preferredCenter, 2.0)
    }

    let preferredIndoor = floorPolygons.isEmpty || isInsideAnyPolygon(preferredCenter, polygons: floorPolygons)
    let preferredClearance = obstacleClearance(at: preferredCenter, geoms: lowObstacles)
    if preferredIndoor && preferredClearance >= 0.35 {
      return (preferredCenter, preferredClearance)
    }

    let bounds = computeSceneBounds(geoms: geoms, floorPolygons: floorPolygons)
    let step = 0.15
    var bestPoint = preferredCenter
    var bestClearance = preferredIndoor ? preferredClearance : -Double.infinity
    var bestScore = preferredIndoor ? (min(preferredClearance, 1.1) - 0.0) : -Double.infinity

    var x = bounds.min.x + step
    while x <= bounds.max.x - step + 1e-6 {
      var y = bounds.min.y + step
      while y <= bounds.max.y - step + 1e-6 {
        let candidate = SIMD2<Double>(x, y)
        let isIndoor = floorPolygons.isEmpty || isInsideAnyPolygon(candidate, polygons: floorPolygons)
        if isIndoor {
          let clearance = obstacleClearance(at: candidate, geoms: lowObstacles)
          let distPenalty = 0.04 * simd_distance(candidate, preferredCenter)
          let cappedClearance = min(clearance, 1.1)
          let score = cappedClearance - distPenalty
          if (clearance >= 0.32 && bestClearance < 0.32) ||
             ((clearance >= 0.32) == (bestClearance >= 0.32) && score > bestScore) {
            bestPoint = candidate
            bestClearance = clearance
            bestScore = score
          }
        }
        y += step
      }
      x += step
    }

    if !bestClearance.isFinite {
      return (preferredCenter, preferredClearance)
    }
    return (bestPoint, bestClearance)
  }

  private static func isInsideAnyPolygon(
    _ point: SIMD2<Double>,
    polygons: [[SIMD2<Double>]]
  ) -> Bool {
    polygons.contains { pointInPolygon(point, polygon: $0) }
  }

  private static func pointInPolygon(
    _ point: SIMD2<Double>,
    polygon: [SIMD2<Double>]
  ) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
      let pi = polygon[i]
      let pj = polygon[j]
      let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
        (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 1e-12) + pi.x)
      if intersects {
        inside.toggle()
      }
      j = i
    }
    return inside
  }

  private static func obstacleClearance(
    at point: SIMD2<Double>,
    geoms: [MJCFGeneratedGeom]
  ) -> Double {
    var minDist = Double.greatestFiniteMagnitude
    for geom in geoms where geom.hasCollision && geom.bottomZ < 0.45 {
      let d = signedDistance2D(from: point, to: geom)
      if d < minDist {
        minDist = d
      }
    }
    return minDist == Double.greatestFiniteMagnitude ? 2.0 : minDist
  }

  private static func signedDistance2D(
    from point: SIMD2<Double>,
    to geom: MJCFGeneratedGeom
  ) -> Double {
    let center = SIMD2<Double>(geom.position.x, geom.position.y)
    let delta = point - center
    switch geom.shape {
    case let .cylinder(radius, _):
      return simd_length(delta) - radius
    case let .box(halfExtents):
      let local = rotate2D(delta, by: -geom.yawRadians)
      let q = SIMD2<Double>(abs(local.x) - halfExtents.x, abs(local.y) - halfExtents.y)
      let outside = simd_length(simd_max(q, .zero))
      let inside = min(max(q.x, q.y), 0)
      return outside + inside
    }
  }

  private static func computeSceneBounds(
    geoms: [MJCFGeneratedGeom],
    floorPolygons: [[SIMD2<Double>]]
  ) -> (min: SIMD2<Double>, max: SIMD2<Double>) {
    var minPt = SIMD2<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
    var maxPt = SIMD2<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)

    for polygon in floorPolygons {
      for pt in polygon {
        minPt = simd_min(minPt, pt)
        maxPt = simd_max(maxPt, pt)
      }
    }

    for geom in geoms {
      let c = SIMD2<Double>(geom.position.x, geom.position.y)
      switch geom.shape {
      case let .cylinder(radius, _):
        let r = SIMD2<Double>(repeating: radius)
        minPt = simd_min(minPt, c - r)
        maxPt = simd_max(maxPt, c + r)
      case let .box(half):
        let ux = abs(cos(geom.yawRadians)) * half.x + abs(sin(geom.yawRadians)) * half.y
        let uy = abs(sin(geom.yawRadians)) * half.x + abs(cos(geom.yawRadians)) * half.y
        let ext = SIMD2<Double>(ux, uy)
        minPt = simd_min(minPt, c - ext)
        maxPt = simd_max(maxPt, c + ext)
      }
    }

    if !minPt.x.isFinite || !maxPt.x.isFinite {
      return (SIMD2<Double>(-2, -2), SIMD2<Double>(2, 2))
    }
    return (minPt, maxPt)
  }

  private static func doorwayClearanceDistance(
    from point: SIMD2<Double>,
    to doorway: FloorPlanDoorwayGap
  ) -> Double {
    let delta = point - doorway.center
    let halfWidth = doorway.width * 0.5
    let projected = min(max(simd_dot(delta, doorway.tangent), -halfWidth), halfWidth)
    let closestOnSegment = doorway.center + doorway.tangent * projected
    return simd_distance(point, closestOnSegment)
  }

  private static func placeInteractiveProps(
    bounds: (min: SIMD2<Double>, max: SIMD2<Double>),
    floorPolygons: [[SIMD2<Double>]],
    geoms: [MJCFGeneratedGeom],
    openDoorways: [FloorPlanDoorwayGap]
  ) -> [MJCFInteractiveProp] {
    let lowObstacles = geoms.filter { $0.hasCollision && $0.bottomZ < 0.45 }
    let step = 0.20

    struct CandidateSpot {
      var point: SIMD2<Double>
      var clearance: Double
      var polygonIndex: Int?
    }

    var candidates: [CandidateSpot] = []
    var x = bounds.min.x + 0.25
    while x <= bounds.max.x - 0.25 + 1e-6 {
      var y = bounds.min.y + 0.25
      while y <= bounds.max.y - 0.25 + 1e-6 {
        let pt = SIMD2<Double>(x, y)
        let polyIdx: Int?
        if floorPolygons.isEmpty {
          polyIdx = nil
        } else if let idx = floorPolygons.firstIndex(where: { pointInPolygon(pt, polygon: $0) }) {
          polyIdx = idx
        } else {
          y += step
          continue
        }

        let clearance = obstacleClearance(at: pt, geoms: lowObstacles)
        if clearance >= 0.28 {
          candidates.append(CandidateSpot(point: pt, clearance: clearance, polygonIndex: polyIdx))
        }
        y += step
      }
      x += step
    }

    guard !candidates.isEmpty else { return [] }

    func isClearOfDoorways(_ point: SIMD2<Double>, radius: Double) -> Bool {
      let minDoorwayDistance = 0.45 + radius
      return openDoorways.allSatisfy { doorway in
        doorwayClearanceDistance(from: point, to: doorway) >= minDoorwayDistance
      }
    }

    var placed: [MJCFInteractiveProp] = []
    var coveredPolygons: Set<Int> = []

    // 1. Kickable orange soccer ball matching `scene_playground.xml` dimensions & inertia.
    let ballRadius = 0.035
    let ballMinSpawnDistance = 0.35
    let ballMinObstacleClearance = ballRadius + 0.26

    let bestBallSpot = candidates
      .filter { spot in
        let spawnDist = simd_length(spot.point)
        return spawnDist >= ballMinSpawnDistance
          && spot.clearance >= ballMinObstacleClearance
          && isClearOfDoorways(spot.point, radius: ballRadius)
      }
      .max { lhs, rhs in
        ballPlacementScore(lhs.point, clearance: lhs.clearance)
          < ballPlacementScore(rhs.point, clearance: rhs.clearance)
      }

    if let ballSpot = bestBallSpot {
      placed.append(
        MJCFInteractiveProp(
          name: "soccer_ball",
          kind: .soccerBall,
          shape: .sphere(radius: ballRadius),
          position: cleanVec3(SIMD3<Double>(ballSpot.point.x, ballSpot.point.y, ballRadius)),
          mass: 0.015,
          diagInertia: SIMD3<Double>(1.225e-5, 1.225e-5, 1.225e-5),
          materialName: "prop_mat_ball",
          friction: "0.5 0.005 0.0001"
        )
      )
      if let idx = ballSpot.polygonIndex {
        coveredPolygons.insert(idx)
      }
    }

    // 2. Lightweight colorful pushable cones & toy blocks spread across open room spots.
    struct PropSpec {
      var name: String
      var kind: MJCFPropKind
      var shape: MJCFPropShape
      var centerZ: Double
      var mass: Double
      var diagInertia: SIMD3<Double>
      var materialName: String
    }

    let specs: [PropSpec] = [
      PropSpec(
        name: "prop_cone_teal_01",
        kind: .targetCone,
        shape: .cylinder(radius: 0.055, halfHeight: 0.11),
        centerZ: 0.11,
        mass: 0.04,
        diagInertia: SIMD3<Double>(1.91e-4, 1.91e-4, 6.05e-5),
        materialName: "prop_mat_teal"
      ),
      PropSpec(
        name: "prop_block_yellow_02",
        kind: .toyBlock,
        shape: .box(halfExtents: SIMD3<Double>(0.055, 0.055, 0.055)),
        centerZ: 0.055,
        mass: 0.035,
        diagInertia: SIMD3<Double>(7.06e-5, 7.06e-5, 7.06e-5),
        materialName: "prop_mat_yellow"
      ),
      PropSpec(
        name: "prop_cone_magenta_03",
        kind: .targetCone,
        shape: .cylinder(radius: 0.055, halfHeight: 0.11),
        centerZ: 0.11,
        mass: 0.04,
        diagInertia: SIMD3<Double>(1.91e-4, 1.91e-4, 6.05e-5),
        materialName: "prop_mat_magenta"
      ),
      PropSpec(
        name: "prop_block_red_04",
        kind: .toyBlock,
        shape: .box(halfExtents: SIMD3<Double>(0.055, 0.055, 0.055)),
        centerZ: 0.055,
        mass: 0.035,
        diagInertia: SIMD3<Double>(7.06e-5, 7.06e-5, 7.06e-5),
        materialName: "prop_mat_red"
      ),
    ]

    let maxSecondaryProps = min(specs.count, max(2, floorPolygons.count * 2))
    let minPropSpacing = 0.65
    let minSecondarySpawnDistance = 0.55

    for spec in specs.prefix(maxSecondaryProps) {
      let radius = spec.shape.footprintRadius
      let minClearance = radius + 0.28
      let validSpots = candidates.filter { spot in
        let spawnDist = simd_length(spot.point)
        guard spawnDist >= minSecondarySpawnDistance,
              spot.clearance >= minClearance,
              isClearOfDoorways(spot.point, radius: radius)
        else {
          return false
        }
        return placed.allSatisfy { existing in
          let existing2D = SIMD2<Double>(existing.position.x, existing.position.y)
          return simd_distance(spot.point, existing2D) >= minPropSpacing
        }
      }

      guard let chosen = validSpots.max(by: { lhs, rhs in
        secondaryPropScore(
          lhs.point,
          clearance: lhs.clearance,
          polygonIndex: lhs.polygonIndex,
          coveredPolygons: coveredPolygons,
          placed: placed
        ) < secondaryPropScore(
          rhs.point,
          clearance: rhs.clearance,
          polygonIndex: rhs.polygonIndex,
          coveredPolygons: coveredPolygons,
          placed: placed
        )
      }) else {
        continue
      }

      placed.append(
        MJCFInteractiveProp(
          name: spec.name,
          kind: spec.kind,
          shape: spec.shape,
          position: cleanVec3(SIMD3<Double>(chosen.point.x, chosen.point.y, spec.centerZ)),
          mass: spec.mass,
          diagInertia: spec.diagInertia,
          materialName: spec.materialName,
          friction: "0.6 0.005 0.0001"
        )
      )
      if let idx = chosen.polygonIndex {
        coveredPolygons.insert(idx)
      }
    }

    return placed
  }

  private static func ballPlacementScore(_ point: SIMD2<Double>, clearance: Double) -> Double {
    let distFromSpawn = simd_length(point)
    let idealDist = 0.55
    let distPenalty = abs(distFromSpawn - idealDist) * 0.9
    let forwardBonus = point.x > 0.15 && abs(point.y) <= max(point.x * 0.85, 0.35) ? 0.55 : 0.0
    return min(clearance, 0.85) + forwardBonus - distPenalty
  }

  private static func secondaryPropScore(
    _ point: SIMD2<Double>,
    clearance: Double,
    polygonIndex: Int?,
    coveredPolygons: Set<Int>,
    placed: [MJCFInteractiveProp]
  ) -> Double {
    let uncoveredRoomBonus = polygonIndex.map { coveredPolygons.contains($0) ? 0.0 : 1.5 } ?? 0.0
    let minExistingDist = placed.map {
      simd_distance(point, SIMD2<Double>($0.position.x, $0.position.y))
    }.min() ?? 1.5
    let spreadScore = min(minExistingDist, 2.2) * 0.45
    let spawnDist = simd_length(point)
    let farPenalty = max(0, spawnDist - 3.0) * 0.15
    return uncoveredRoomBonus + min(clearance, 0.95) * 0.8 + spreadScore - farPenalty
  }

  private static func formatInertia(_ v: SIMD3<Double>) -> String {
    let fmt: (Double) -> String = { String(format: "%.4g", $0) }
    return "\(fmt(v.x)) \(fmt(v.y)) \(fmt(v.z))"
  }

  private static func formatScalar(_ value: Double) -> String {
    let cleaned = abs(value) < 1e-5 ? 0.0 : value
    var formatted = String(format: "%.4f", cleaned)
    while formatted.contains(".") && (formatted.hasSuffix("0") || formatted.hasSuffix(".")) {
      let dropped = formatted.removeLast()
      if dropped == "." {
        break
      }
    }
    return formatted == "-0" ? "0" : formatted
  }

  private static func formatVec3(_ v: SIMD3<Double>) -> String {
    "\(formatScalar(v.x)) \(formatScalar(v.y)) \(formatScalar(v.z))"
  }

  private static func formatQuat(_ q: SIMD4<Double>) -> String? {
    let isIdentity =
      abs(q.x - 1.0) < 1e-4 &&
      abs(q.y) < 1e-4 &&
      abs(q.z) < 1e-4 &&
      abs(q.w) < 1e-4
    if isIdentity {
      return nil
    }
    return "\(formatScalar(q.x)) \(formatScalar(q.y)) \(formatScalar(q.z)) \(formatScalar(q.w))"
  }

  private static func renderMJCFXML(
    configuration: MJCFExportConfiguration,
    geoms: [MJCFGeneratedGeom],
    interactiveProps: [MJCFInteractiveProp],
    summary: MJCFExportSummary
  ) -> String {
    var lines: [String] = []
    lines.append("<mujoco model=\"scene\">")
    lines.append("    <include file=\"robot_groundcontact_backlash.xml\" />")
    lines.append("")
    lines.append("    <visual>")
    lines.append("        <headlight diffuse=\"0.6 0.6 0.6\" ambient=\"0.3 0.3 0.3\" specular=\"0 0 0\" />")
    lines.append("        <rgba haze=\"0.15 0.25 0.35 1\" />")
    lines.append("        <global azimuth=\"160\" elevation=\"-20\" />")
    lines.append("    </visual>")
    lines.append("")
    lines.append("    <asset>")
    lines.append("        <texture type=\"skybox\" builtin=\"gradient\" rgb1=\"0.3 0.5 0.7\" rgb2=\"0 0 0\" width=\"512\" height=\"3072\" />")
    lines.append("        <texture type=\"2d\" name=\"groundplane\" builtin=\"checker\" mark=\"edge\" rgb1=\"0.2 0.3 0.4\" rgb2=\"0.1 0.2 0.3\" markrgb=\"0.8 0.8 0.8\" width=\"300\" height=\"300\" />")
    lines.append("        <material name=\"groundplane\" texture=\"groundplane\" texuniform=\"true\" texrepeat=\"5 5\" reflectance=\"0.2\" />")
    lines.append("        <texture type=\"2d\" name=\"scan_tex_floor_a\" builtin=\"checker\" mark=\"edge\" rgb1=\"0.66 0.56 0.44\" rgb2=\"0.60 0.50 0.39\" markrgb=\"0.52 0.43 0.33\" width=\"256\" height=\"256\" />")
    lines.append("        <texture type=\"2d\" name=\"scan_tex_floor_b\" builtin=\"checker\" mark=\"cross\" rgb1=\"0.58 0.60 0.64\" rgb2=\"0.52 0.54 0.58\" markrgb=\"0.72 0.74 0.77\" width=\"256\" height=\"256\" />")
    lines.append("        <material name=\"scan_mat_floor_a\" texture=\"scan_tex_floor_a\" texuniform=\"true\" texrepeat=\"3 3\" reflectance=\"0.06\" />")
    lines.append("        <material name=\"scan_mat_floor_b\" texture=\"scan_tex_floor_b\" texuniform=\"true\" texrepeat=\"3 3\" reflectance=\"0.06\" />")
    lines.append("        <material name=\"scan_mat_wall\" rgba=\"0.88 0.87 0.84 1\" reflectance=\"0.03\" />")
    lines.append("        <material name=\"scan_mat_door\" rgba=\"0.58 0.42 0.28 1\" reflectance=\"0.05\" />")
    lines.append("        <material name=\"scan_mat_seating\" rgba=\"0.34 0.45 0.56 1\" reflectance=\"0.02\" />")
    lines.append("        <material name=\"scan_mat_wood\" rgba=\"0.55 0.39 0.25 1\" reflectance=\"0.06\" />")
    lines.append("        <material name=\"scan_mat_bed\" rgba=\"0.76 0.78 0.84 1\" reflectance=\"0.02\" />")
    lines.append("        <material name=\"scan_mat_appliance\" rgba=\"0.72 0.74 0.76 1\" reflectance=\"0.14\" />")
    lines.append("        <material name=\"scan_mat_ceramic\" rgba=\"0.90 0.92 0.94 1\" reflectance=\"0.16\" />")
    lines.append("        <material name=\"scan_mat_accent\" rgba=\"0.46 0.43 0.40 1\" reflectance=\"0.04\" />")
    if !interactiveProps.isEmpty {
      lines.append("        <material name=\"prop_mat_ball\" rgba=\"1.0 0.48 0.04 1\" reflectance=\"0.08\" />")
      lines.append("        <material name=\"prop_mat_teal\" rgba=\"0.08 0.76 0.74 1\" reflectance=\"0.08\" />")
      lines.append("        <material name=\"prop_mat_yellow\" rgba=\"0.96 0.80 0.10 1\" reflectance=\"0.08\" />")
      lines.append("        <material name=\"prop_mat_magenta\" rgba=\"0.92 0.28 0.64 1\" reflectance=\"0.08\" />")
      lines.append("        <material name=\"prop_mat_red\" rgba=\"0.88 0.18 0.16 1\" reflectance=\"0.08\" />")
    }
    lines.append("    </asset>")
    lines.append("")
    lines.append("    <worldbody>")
    let propCommentSuffix = interactiveProps.isEmpty
      ? ""
      : ", \(interactiveProps.count) interactive prop(s)"
    lines.append(
      String(
        format: "        <!-- Generated by MicroduckRemote RoomPlan exporter: %@ (%d room(s), %d wall segment(s), %d open doorway(s), %d furniture geom(s)%@) -->",
        configuration.fileName,
        summary.roomCount,
        summary.wallSegmentCount,
        summary.openDoorwayCount,
        summary.furnitureCount,
        propCommentSuffix
      )
    )
    lines.append("        <light pos=\"0 0 3.5\" dir=\"0 0 -1\" directional=\"true\" />")
    lines.append("        <geom name=\"floor\" size=\"0 0 0.05\" pos=\"0 0 0\" type=\"plane\" material=\"groundplane\" />")

    for geom in geoms {
      let typeAttr: String
      let sizeAttr: String
      switch geom.shape {
      case let .box(halfExtents):
        typeAttr = "box"
        sizeAttr = formatVec3(halfExtents)
      case let .cylinder(radius, halfHeight):
        typeAttr = "cylinder"
        sizeAttr = "\(formatScalar(radius)) \(formatScalar(halfHeight))"
      }

      var attrs: [String] = [
        "name=\"\(geom.name)\"",
        "type=\"\(typeAttr)\"",
        "pos=\"\(formatVec3(geom.position))\"",
        "size=\"\(sizeAttr)\"",
      ]
      if let quatStr = formatQuat(geom.quaternion) {
        attrs.append("quat=\"\(quatStr)\"")
      }
      attrs.append("material=\"\(geom.materialName)\"")
      if geom.hasCollision {
        attrs.append("contype=\"1\" conaffinity=\"1\"")
      } else {
        attrs.append("contype=\"0\" conaffinity=\"0\"")
      }
      lines.append("        <geom \(attrs.joined(separator: " ")) />")
    }

    if !interactiveProps.isEmpty {
      lines.append("")
      lines.append("        <!-- Interactive Playground Props -->")
      for prop in interactiveProps {
        let typeAttr: String
        let sizeAttr: String
        switch prop.shape {
        case let .sphere(radius):
          typeAttr = "sphere"
          sizeAttr = formatScalar(radius)
        case let .cylinder(radius, halfHeight):
          typeAttr = "cylinder"
          sizeAttr = "\(formatScalar(radius)) \(formatScalar(halfHeight))"
        case let .box(halfExtents):
          typeAttr = "box"
          sizeAttr = formatVec3(halfExtents)
        }
        lines.append("        <body name=\"\(prop.name)\" pos=\"\(formatVec3(prop.position))\">")
        lines.append("            <freejoint name=\"\(prop.name)_free\" />")
        lines.append("            <inertial pos=\"0 0 0\" mass=\"\(formatScalar(prop.mass))\" diaginertia=\"\(formatInertia(prop.diagInertia))\" />")
        lines.append("            <geom name=\"\(prop.name)_geom\" type=\"\(typeAttr)\" size=\"\(sizeAttr)\" material=\"\(prop.materialName)\" friction=\"\(prop.friction)\" contype=\"1\" conaffinity=\"1\" />")
        lines.append("        </body>")
      }
    }

    let propQposLines = interactiveProps.map { prop in
      "        \(formatVec3(prop.position)) 1 0 0 0"
    }

    func appendQposLines(_ baseLines: [String]) {
      let allLines = baseLines + propQposLines
      for (idx, line) in allLines.enumerated() {
        if idx == allLines.count - 1 {
          lines.append("\(line)\"")
        } else {
          lines.append(line)
        }
      }
    }

    lines.append("    </worldbody>")
    lines.append("    <keyframe>")
    lines.append("        <key name=\"INIT\" qpos=\"")
    appendQposLines([
      "        0 0 0.12 1 0 0 0",
      "        0 0 0 0 0 0 0 0 0 0",
      "        0 0 0 0 0 0 0 0",
      "        0 0 0 0 0 0 0 0 0 0",
    ])
    lines.append("        ctrl=\"0 0 0 0 0 0 0 0 0 0 0 0 0 0\"/>")
    lines.append("        <key name=\"STAND\" qpos=\"")
    appendQposLines([
      "        0 0 0.12 1 0 0 0",
      "",
      "        0 0 -0.08726646259971647 0 -0.457924 0 -0.004940 0 0.452984 0",
      "        0.3490658503988659 0 0.3490658503988659 0 0 0 0 0",
      "        0 0 0.08726646259971647 0 0.457924 0 0.004940 0 -0.452984 0",
    ])
    lines.append("         ctrl=\"")
    lines.append("        0 -0.08726646259971647 -0.457924 -0.004940 0.452984")
    lines.append("        0.3490658503988659 0.3490658503988659 0 0")
    lines.append("        0 0.08726646259971647 0.457924 0.004940 -0.452984\"")
    lines.append("        />")
    lines.append("        <key name=\"SIT\" qpos=\"")
    appendQposLines([
      "        0 0 0.07 1 0 0 0",
      "        0 0 0 0 -0.5236 0 1.0472 0 0 0",
      "        0.5 0 1.6 0 0 0 0 0",
      "        0 0 0 0 0.5236 0 -1.0472 0 0 0",
    ])
    lines.append("        ctrl=\"")
    lines.append("        0 0 -0.5236 1.0472 0")
    lines.append("        0.5 1.6 0 0 0")
    lines.append("        0 0.5236 -1.0472 0\"/>")
    lines.append("        <key name=\"FOLD\" qpos=\"")
    appendQposLines([
      "        0 0 0.07 1 0 0 0",
      "        0 0 0 0 1.57 0 1.57 0 0 0",
      "        1 0 1 0 0 0 0 0",
      "        0 0 0 0 -1.57 0 -1.57 0 0 0",
    ])
    lines.append("        ctrl=\"")
    lines.append("        0 0 1.57 1.57 0")
    lines.append("        1 1 0 0")
    lines.append("        0 0 -1.57 -1.57 0\"/>")
    lines.append("    </keyframe>")
    lines.append("</mujoco>")
    return lines.joined(separator: "\n") + "\n"
  }
}
