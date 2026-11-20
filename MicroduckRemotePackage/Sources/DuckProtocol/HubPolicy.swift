import Foundation

public struct HubPolicy: Codable, Equatable, Identifiable, Sendable {
  public var id: String { key }
  public var key: String
  public var repo: String
  public var file: String?
  public var name: String
  public var description: String?
  public var kind: String?
  public var encoding: String?
  public var durationS: Double?
  public var unwindS: Double?
  public var idle: [Double]?
  public var official: Bool
  public var forRobot: String?
  public var videoURL: String?
  public var likes: Int

  public init(
    key: String,
    repo: String,
    file: String? = nil,
    name: String,
    description: String? = nil,
    kind: String? = nil,
    encoding: String? = "constant",
    durationS: Double? = nil,
    unwindS: Double? = nil,
    idle: [Double]? = nil,
    official: Bool = false,
    forRobot: String? = nil,
    videoURL: String? = nil,
    likes: Int = 0
  ) {
    self.key = key
    self.repo = repo
    self.file = file
    self.name = name
    self.description = description
    self.kind = kind
    self.encoding = encoding
    self.durationS = durationS
    self.unwindS = unwindS
    self.idle = idle
    self.official = official
    self.forRobot = forRobot
    self.videoURL = videoURL
    self.likes = likes
  }

  public var authorName: String {
    repo.split(separator: "/").first.map(String.init) ?? repo
  }

  public var notATrickReason: String? {
    let normalized = (encoding ?? "constant").lowercased()
    if normalized == "phase" {
      return "Your duck drives this one itself. It is part of how it moves, not a trick."
    }
    if normalized == "posture_flag" {
      return "This is how your duck sits down and stands up, not a trick."
    }
    if normalized != "constant" {
      return "Your duck does not know how to drive this one."
    }
    return nil
  }

  public var isTrick: Bool {
    if notATrickReason != nil { return false }
    return durationS != nil || idle != nil || unwindS != nil
  }

  public var needsHoldDuration: Bool {
    durationS == nil
  }

  public var durationLabel: String {
    if let durationS {
      return durationS < 1.5 ? "About 1s" : "About \(Int(durationS.rounded()))s"
    }
    return "Runs until stopped"
  }

  public static func parseManifestEntries(
    manifestJSON: Data,
    repo: String,
    likes: Int = 0,
    videoURL: String? = nil
  ) -> [HubPolicy] {
    guard
      let manifest = (try? JSONSerialization.jsonObject(with: manifestJSON)) as? [String: Any]
    else {
      return []
    }

    let inheritedKeys = ["schema_version", "model_api", "obs_len", "action_len", "robot"]
    if let entries = manifest["policies"] as? [[String: Any]], !entries.isEmpty {
      return entries.compactMap { entry in
        guard let file = entry["file"] as? String, !file.contains("/"), !file.hasPrefix(".") else {
          return nil
        }
        var merged = entry
        for key in inheritedKeys where merged[key] == nil {
          merged[key] = manifest[key]
        }
        return policyFrom(fields: merged, repo: repo, file: file, likes: likes, videoURL: videoURL)
      }
    }

    return [policyFrom(fields: manifest, repo: repo, file: nil, likes: likes, videoURL: videoURL)]
  }

  private static func policyFrom(
    fields: [String: Any],
    repo: String,
    file: String?,
    likes: Int,
    videoURL: String?
  ) -> HubPolicy {
    let command = fields["command"] as? [String: Any] ?? [:]
    let robot = fields["robot"] as? [String: Any] ?? [:]
    let rawName = (fields["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackFile = stem(file)
    let fallbackRepo = stem(repo.split(separator: "/").dropFirst().first.map(String.init))
    let chosenName = [rawName, fallbackFile, fallbackRepo, repo]
      .compactMap { $0 }
      .first { !$0.isEmpty } ?? repo

    let prettyName = chosenName
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")

    let description = fields["description"] as? String
    let kind = fields["kind"] as? String
    let encoding = (command["encoding"] as? String) ?? (fields["encoding"] as? String)
    let durationS = finiteDouble(fields["duration_s"]) ?? finiteDouble(command["duration_s"])
    let unwindS = finiteDouble(fields["unwind_s"]) ?? finiteDouble(command["unwind_s"])
    let idle = (command["idle"] as? [Any] ?? fields["idle"] as? [Any])?.compactMap(finiteDouble)
    let official = repo.hasPrefix("\(DuckConstants.officialOrg)/")
    let robotVariant = (robot["variant"] as? String) ?? (robot["name"] as? String)
    let forRobot = (robotVariant == nil || robotVariant == "microduck") ? nil : robotVariant
    let key = file.map { "\(repo):\($0)" } ?? repo

    return HubPolicy(
      key: key,
      repo: repo,
      file: file,
      name: prettyName,
      description: description,
      kind: kind,
      encoding: encoding,
      durationS: durationS,
      unwindS: unwindS,
      idle: idle?.isEmpty == true ? nil : idle,
      official: official,
      forRobot: forRobot,
      videoURL: videoURL,
      likes: likes
    )
  }

  public static func stem(_ text: String?) -> String {
    guard var base = text, !base.isEmpty else { return "" }
    if base.hasSuffix(".onnx") || base.hasSuffix(".json") {
      if let dot = base.lastIndex(of: ".") {
        base = String(base[..<dot])
      }
    }
    if base.hasPrefix("microduck-") {
      base.removeFirst("microduck-".count)
    }
    return base
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
  }

  private static func finiteDouble(_ value: Any?) -> Double? {
    if let double = value as? Double, double.isFinite { return double }
    if let int = value as? Int { return Double(int) }
    if let num = value as? NSNumber {
      let double = num.doubleValue
      return double.isFinite ? double : nil
    }
    return nil
  }
}

extension SetSkillParams {
  public static func from(
    fetched: PolicyFetchResult,
    holdSeconds: Double = DuckConstants.defaultHoldSeconds
  ) -> SetSkillParams {
    let rawName = fetched.name
      ?? (HubPolicy.stem(fetched.file).isEmpty ? "policy" : HubPolicy.stem(fetched.file))
    let normalizedName = rawName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: " ", with: "-")
    return SetSkillParams(
      name: normalizedName,
      path: fetched.path,
      duration: fetched.durationS ?? holdSeconds,
      chain: fetched.chain ?? false,
      unwind: fetched.idle,
      unwindS: fetched.unwindS,
      actionScale: fetched.actionScale
    )
  }
}
