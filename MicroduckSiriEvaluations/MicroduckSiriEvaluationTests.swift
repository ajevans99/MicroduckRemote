import SiriEvaluations
import Testing

struct MicroduckSiriEvaluation: Evaluation {
  let name: String
  let dataset: SiriScenarioLoader

  func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
    try await SiriService.run(scenario: sample)
  }

  var evaluators: Evaluators {
    SiriExpectationEvaluator()
  }

  func aggregateMetrics(using aggregator: inout MetricsAggregator) {
    Self.computeSiriMetrics(into: &aggregator)
  }
}

@Suite("Microduck - Siri", .serialized)
struct MicroduckSiriEvaluationTests {
  private static var targetBundleIdentifier: String {
    if let runnerID = Bundle.main.bundleIdentifier {
      for suffix in [".sirieval.xctrunner", ".sirieval"] where runnerID.hasSuffix(suffix) {
        return String(runnerID.dropLast(suffix.count))
      }
    }
    return "com.microduck.remote"
  }

  static let appDefinitions = IntentDefinitions(bundleIdentifier: targetBundleIdentifier)

  // Tool intents
  static let getDuckStatusIntent = appDefinitions.intents["GetDuckStatusIntent"]
  static let setDuckPostureIntent = appDefinitions.intents["SetDuckPostureIntent"]
  static let moveDuckStepIntent = appDefinitions.intents["MoveDuckStepIntent"]
  static let emergencyStopDuckIntent = appDefinitions.intents["EmergencyStopDuckIntent"]
  static let playDuckSoundIntent = appDefinitions.intents["PlayDuckSoundIntent"]
  static let setDuckLightIntent = appDefinitions.intents["SetDuckLightIntent"]
  static let setDuckModeIntent = appDefinitions.intents["SetDuckModeIntent"]
  static let directDuckGazeIntent = appDefinitions.intents["DirectDuckGazeIntent"]
  static let snapDuckPhotoIntent = appDefinitions.intents["SnapDuckPhotoIntent"]
  static let performDuckRoutineIntent = appDefinitions.intents["PerformDuckRoutineIntent"]

  // App enums
  static let duckPostureEnum = appDefinitions.enums["DuckPostureAction"]
  static let duckMoveDirectionEnum = appDefinitions.enums["DuckMoveDirection"]
  static let duckSoundEnum = appDefinitions.enums["DuckSound"]
  static let duckLightColorEnum = appDefinitions.enums["DuckLightColor"]
  static let duckModeEnum = appDefinitions.enums["DuckAutonomousMode"]

  // App entities
  static let duckStatusEntity = appDefinitions.entities["DuckStatusEntity"]
  static let duckPhotoEntity = appDefinitions.entities["DuckPhotoEntity"]
  static let duckRoutineEntity = appDefinitions.entities["DuckRoutine"]

  // App skills (Skills.skillsbundle)
  static let navigateAndWalkSkill = appDefinitions.skills["navigate-and-walk"]
  static let inspectSurroundingsSkill = appDefinitions.skills["inspect-surroundings"]
  static let expressiveChoreographySkill = appDefinitions.skills["expressive-choreography"]
  static let autonomousPlayModesSkill = appDefinitions.skills["autonomous-play-modes"]

  private static func enumCase(_ definition: AppEnumDefinition, _ rawValue: String) -> PredicateExpectation {
    let typeID = definition.typeIdentifier
    return .matches(
      #Predicate<AnyAppEnum> { $0.typeIdentifier == typeID && $0.rawValue == rawValue },
      requirement: "is \(rawValue)"
    )
  }

  // MARK: - Core single-tool actions

  static let checkStatusScenario = SiriScenario {
    UserTurn("Check status in Microduck") {
      Calls {
        getDuckStatusIntent.expect().result(duckStatusEntity)
      }
      Calls(.disallowed) {
        emergencyStopDuckIntent
        moveDuckStepIntent
      }
    }
  }

  static let playSoundScenario = SiriScenario {
    UserTurn("In Microduck, make the duck chirp") {
      Calls {
        playDuckSoundIntent.expect(sound: enumCase(duckSoundEnum, "chirp"))
      }
    }
  }

  static let setLightScenario = SiriScenario {
    UserTurn("In Microduck, set the face light to cyan") {
      Calls {
        setDuckLightIntent.expect(color: enumCase(duckLightColorEnum, "cyan"))
      }
    }
  }

  static let coreActionsEvaluation = MicroduckSiriEvaluation(
    name: "Microduck - Core single-tool actions",
    dataset: SiriScenarioLoader {
      checkStatusScenario
      playSoundScenario
      setLightScenario
    }
  )

  @Test("Siri routes single-tool status, sound, and light requests", .evaluates(coreActionsEvaluation))
  func coreActions() {
    let result = EvaluationContext.current.result
    #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
  }

  // MARK: - Compound multi-step requests

  static let standAndWalkScenario = SiriScenario {
    UserTurn("In Microduck, stand up and walk forward for 2 seconds") {
      Loads(.required) { navigateAndWalkSkill }
      Calls(.ordered) {
        setDuckPostureIntent
          .expect(posture: enumCase(duckPostureEnum, "standUp"))
          .result(duckStatusEntity)
        moveDuckStepIntent
          .expect(
            direction: enumCase(duckMoveDirectionEnum, "forward"),
            durationSeconds: .matches(#Predicate<Double> { $0 >= 1.5 && $0 <= 2.5 }, requirement: "around 2 seconds")
          )
      }
    }
  }

  static let walkTurnAndSnapScenario = SiriScenario {
    UserTurn("In Microduck, walk forward a bit, turn around, and take a photo") {
      Loads(.preferred) { navigateAndWalkSkill }
      Calls(.ordered) {
        moveDuckStepIntent.expect(direction: enumCase(duckMoveDirectionEnum, "forward"))
        moveDuckStepIntent
        snapDuckPhotoIntent.expect().result(duckPhotoEntity)
      }
    }
  }

  static let compoundRequestsEvaluation = MicroduckSiriEvaluation(
    name: "Microduck - Compound multi-step requests",
    dataset: SiriScenarioLoader {
      standAndWalkScenario
      walkTurnAndSnapScenario
    }
  )

  @Test("Siri chains multiple tools for compound requests", .evaluates(compoundRequestsEvaluation))
  func compoundRequests() {
    let result = EvaluationContext.current.result
    #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
    #expect(result.aggregateValue(.mean(of: .skillsLoadedAllPass)) == 1.0)
  }

  // MARK: - App Skills coverage

  static let inspectSurroundingsScenario = SiriScenario {
    UserTurn("In Microduck, look to the left and tell me what you see") {
      Loads(.required) { inspectSurroundingsSkill }
      Calls(.ordered) {
        directDuckGazeIntent
        snapDuckPhotoIntent.expect().result(duckPhotoEntity)
      }
    }
  }

  static let expressiveChoreographyScenario = SiriScenario {
    UserTurn("In Microduck, act suspicious and look around") {
      Loads(.required) { expressiveChoreographySkill }
      Calls {
        performDuckRoutineIntent.expect().result(duckRoutineEntity)
      }
    }
  }

  static let autonomousPlayModesScenario = SiriScenario {
    UserTurn("In Microduck, turn on soccer mode") {
      Loads(.required) { autonomousPlayModesSkill }
      Calls {
        setDuckModeIntent.expect(
          mode: enumCase(duckModeEnum, "soccer"),
          enabled: .matches(#Predicate<Bool> { $0 == true }, requirement: "enabled is true")
        )
      }
    }
  }

  static let appSkillsEvaluation = MicroduckSiriEvaluation(
    name: "Microduck - App Skills orchestration",
    dataset: SiriScenarioLoader {
      inspectSurroundingsScenario
      expressiveChoreographyScenario
      autonomousPlayModesScenario
    }
  )

  @Test("Siri loads Microduck's App Skills and picks the right tools", .evaluates(appSkillsEvaluation))
  func appSkillsOrchestration() {
    let result = EvaluationContext.current.result
    #expect(result.aggregateValue(.mean(of: .skillsLoadedAllPass)) == 1.0)
    #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1.0)
  }
}
