import CasePaths
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import IssueReporting
import Observation

@Observable
@MainActor
public final class CockpitModel {
  @CasePathable
  public enum AlertDestination: Equatable, Identifiable {
    case confirmRelax
    case errorMessage(String)

    public var id: String {
      switch self {
      case .confirmRelax: "confirmRelax"
      case let .errorMessage(msg): "error:\(msg)"
      }
    }
  }

  @ObservationIgnored @Dependency(\.duckSession) var duckSession
  @ObservationIgnored @Dependency(\.haptics) var haptics
  @ObservationIgnored @Dependency(\.gamepad) var gamepad
  @ObservationIgnored @Dependency(\.continuousClock) var clock

  public var snapshot = DuckSessionSnapshot()
  public var leftStickX = 0.0
  public var leftStickY = 0.0
  public var rightStickX = 0.0
  public var gamepadState = GamepadInputState()

  public var isLooking = false
  public var gazeNormalizedX = 0.0
  public var gazeNormalizedY = 0.0
  public var isGazeClamped = false

  public var showTofOverlay = false
  public var showSoundDrawer = false
  public var activeSkillName: String?
  public var isHoldingWheee = false
  public var isStandingBackUp = false
  public var autonomousEnabled = false
  public var flashlightEnabled = false
  public var laserTrackEnabled = false
  public var soccerEnabled = false
  public var alert: AlertDestination?

  public var onConnectionPillTapped: () -> Void

  public init(onConnectionPillTapped: @escaping () -> Void = {}) {
    self.onConnectionPillTapped = onConnectionPillTapped
  }

  public var currentTwist: RobotMoveParams {
    let padActive = abs(gamepadState.leftX) > 0.04
      || abs(gamepadState.leftY) > 0.04
      || abs(gamepadState.rightX) > 0.04

    let vxInput = padActive ? gamepadState.leftY : -leftStickY
    let vyInput = padActive ? -gamepadState.leftX : -leftStickX
    let vyawInput = padActive ? -gamepadState.rightX : -rightStickX

    let vx = vxInput >= 0
      ? vxInput * DuckConstants.maxLinearVelocity
      : DuckConstants.backwardLinearVelocity(magnitude: -vxInput)

    return RobotMoveParams(
      vx: vx,
      vy: vyInput * DuckConstants.maxLinearVelocity,
      vyaw: vyawInput * DuckConstants.maxAngularVelocity
    )
  }

  public var isMoving: Bool {
    let t = currentTwist
    return abs(t.vx) > 0.001 || abs(t.vy) > 0.001 || abs(t.vyaw) > 0.001
  }

  public var isEnabled: Bool {
    snapshot.policies?.enabled == true
  }

  public var isSitting: Bool {
    snapshot.policies?.sitting == true
  }

  public var isFallen: Bool {
    snapshot.latestState?.safety?.fallen == true
  }

  public func task() async {
    snapshot = await duckSession.currentSnapshot()
    async let snapshotsLoop: Void = observeSnapshots()
    async let gamepadLoop: Void = observeGamepad()
    async let intentLoop: Void = runIntentHeartbeat()
    _ = await (snapshotsLoop, gamepadLoop, intentLoop)
  }

  private func observeSnapshots() async {
    for await updated in duckSession.snapshots() {
      snapshot = updated
    }
  }

  private func observeGamepad() async {
    for await pad in gamepad.states() {
      let wasMoving = isMoving
      gamepadState = pad
      if wasMoving, !isMoving {
        await duckSession.sendMove(.zero)
      }
    }
  }

  private func runIntentHeartbeat() async {
    while !Task.isCancelled {
      try? await clock.sleep(for: .milliseconds(100))
      guard !Task.isCancelled else { break }
      if snapshot.controlOpen, isMoving {
        await duckSession.sendMove(currentTwist)
      }
      if snapshot.controlOpen, isLooking {
        let target = LookGeometry.lookTarget(
          normalizedX: gazeNormalizedX,
          normalizedY: gazeNormalizedY
        )
        if let result = await duckSession.sendLook(target) {
          let clamped = result.clamped == true
          if clamped, !isGazeClamped {
            haptics.warning()
          }
          isGazeClamped = clamped
        }
      }
      if snapshot.controlOpen, isHoldingWheee {
        await duckSession.playSound(.wheee, true)
      }
    }
  }

  public func connectionHeaderTapped() {
    haptics.selectionChanged()
    onConnectionPillTapped()
  }

  public func leftThumbstickMoved(x: Double, y: Double) async {
    let clampedX = min(max(x, -1), 1)
    let clampedY = min(max(y, -1), 1)
    let crossedCenter = (leftStickX == 0 && leftStickY == 0) && (clampedX != 0 || clampedY != 0)
    if crossedCenter {
      haptics.impactLight()
    }
    leftStickX = clampedX
    leftStickY = clampedY
    if snapshot.controlOpen {
      await duckSession.sendMove(currentTwist)
    }
  }

  public func leftThumbstickReleased() async {
    leftStickX = 0
    leftStickY = 0
    if !isMoving, snapshot.controlOpen {
      await duckSession.sendMove(.zero)
    }
  }

  public func rightThumbstickMoved(x: Double) async {
    let clampedX = min(max(x, -1), 1)
    if rightStickX == 0, clampedX != 0 {
      haptics.impactLight()
    }
    rightStickX = clampedX
    if snapshot.controlOpen {
      await duckSession.sendMove(currentTwist)
    }
  }

  public func rightThumbstickReleased() async {
    rightStickX = 0
    if !isMoving, snapshot.controlOpen {
      await duckSession.sendMove(.zero)
    }
  }

  public func videoStageDragged(normalizedX: Double, normalizedY: Double) async {
    guard snapshot.controlOpen else { return }
    if !isLooking {
      haptics.selectionChanged()
    }
    isLooking = true
    gazeNormalizedX = min(max(normalizedX, -1), 1)
    gazeNormalizedY = min(max(normalizedY, -1), 1)
    let target = LookGeometry.lookTarget(
      normalizedX: gazeNormalizedX,
      normalizedY: gazeNormalizedY
    )
    if let result = await duckSession.sendLook(target) {
      isGazeClamped = result.clamped == true
    }
  }

  public func videoStageDragEnded() {
    isLooking = false
    isGazeClamped = false
  }

  public func standToggleButtonTapped() async {
    haptics.impactMedium()
    do {
      try await duckSession.toggleEnable()
      haptics.success()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func standBackUpButtonTapped() async {
    guard !isStandingBackUp else { return }
    haptics.impactMedium()
    isStandingBackUp = true
    defer { isStandingBackUp = false }
    do {
      try await duckSession.standBackUp()
      haptics.success()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func stopButtonTapped() async {
    haptics.impactMedium()
    leftStickX = 0
    leftStickY = 0
    rightStickX = 0
    await duckSession.sendMove(.zero)
    do {
      try await duckSession.stop()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func initPoseButtonTapped() async {
    haptics.selectionChanged()
    do {
      try await duckSession.initPose()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func relaxMenuButtonTapped() {
    alert = .confirmRelax
  }

  public func relaxConfirmedButtonTapped() async {
    alert = nil
    haptics.warning()
    do {
      try await duckSession.relax()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func rebootMotorsButtonTapped() async {
    haptics.selectionChanged()
    do {
      try await duckSession.rebootMotors()
      haptics.success()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func quickSkillButtonTapped(_ skill: String) async {
    haptics.impactMedium()
    activeSkillName = skill
    defer { activeSkillName = nil }
    do {
      try await duckSession.performSkill(skill)
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func soundDrawerToggleTapped() {
    haptics.selectionChanged()
    showSoundDrawer.toggle()
  }

  public func soundButtonTapped(_ tag: SoundTag) async {
    guard !tag.isHoldable else { return }
    haptics.impactLight()
    await duckSession.playSound(tag, nil)
  }

  public func wheeeHoldChanged(isPressed: Bool) async {
    if isPressed == isHoldingWheee { return }
    isHoldingWheee = isPressed
    if isPressed {
      haptics.impactMedium()
      await duckSession.playSound(.wheee, true)
    } else {
      await duckSession.playSound(.wheee, false)
    }
  }

  public func tofOverlayButtonTapped() async {
    haptics.selectionChanged()
    showTofOverlay.toggle()
    if showTofOverlay {
      await duckSession.subscribeTof()
    }
  }

  public func autonomousToggleTapped() async {
    let next = !autonomousEnabled
    do {
      try await duckSession.setAutonomous(next)
      autonomousEnabled = next
      haptics.selectionChanged()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func flashlightToggleTapped() async {
    let next = !flashlightEnabled
    do {
      try await duckSession.setFlashlight(next)
      flashlightEnabled = next
      haptics.selectionChanged()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func laserTrackToggleTapped() async {
    let next = !laserTrackEnabled
    do {
      try await duckSession.setLaserTrack(next)
      laserTrackEnabled = next
      haptics.selectionChanged()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }

  public func soccerToggleTapped() async {
    let next = !soccerEnabled
    do {
      try await duckSession.setSoccer(next)
      soccerEnabled = next
      haptics.selectionChanged()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }
}
