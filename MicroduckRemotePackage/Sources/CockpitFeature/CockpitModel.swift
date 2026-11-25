import CasePaths
import Dependencies
import DuckDependencies
import DuckProtocol
import Foundation
import IssueReporting
import Observation
import WingmanFeature

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
  public var showCompassHUD = true
  public var showSoundDrawer = false
  public var showExpressiveDrawer = false
  public var showManualPads = false
  public var showWingmanInspector = true
  public var showWingmanSheet = false
  public var inlineWingmanPrompt = ""
  public var wingmanModel = WingmanModel()
  public var odomTrail: [OdomBreadcrumb] = []
  public var activeQuickMotionLabel: String?
  public var activeSkillName: String?
  public var isHoldingWheee = false
  public var isHoldingChomp = false
  public var beakOpening = 0.0
  public var headTilt = 0.0
  public var crouchDepth = 0.0
  public var isStandingBackUp = false
  public var autonomousEnabled = false
  public var flashlightEnabled = false
  public var laserTrackEnabled = false
  public var soccerEnabled = false
  public var thereminEnabled = false
  public var alert: AlertDestination?

  @ObservationIgnored private var chompTick = 0
  @ObservationIgnored private var didSubscribeTofForConnection = false
  @ObservationIgnored private var quickMotionTask: Task<Void, Never>?

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

  public var hasActiveExpression: Bool {
    beakOpening > 0.001 || isHoldingChomp || abs(headTilt) > 0.001 || crouchDepth > 0.001
  }

  public func task() async {
    snapshot = await duckSession.currentSnapshot()
    await syncTelemetryForSnapshot(snapshot)
    async let snapshotsLoop: Void = observeSnapshots()
    async let gamepadLoop: Void = observeGamepad()
    async let intentLoop: Void = runIntentHeartbeat()
    _ = await (snapshotsLoop, gamepadLoop, intentLoop)
  }

  private func observeSnapshots() async {
    for await updated in duckSession.snapshots() {
      snapshot = updated
      await syncTelemetryForSnapshot(updated)
    }
  }

  private func syncTelemetryForSnapshot(_ updated: DuckSessionSnapshot) async {
    if updated.controlOpen {
      if !didSubscribeTofForConnection {
        didSubscribeTofForConnection = true
        await duckSession.subscribeTof()
      }
    } else {
      didSubscribeTofForConnection = false
    }

    if let odom = updated.latestState?.odom {
      let point = OdomBreadcrumb(x: odom.x, y: odom.y)
      if let last = odomTrail.last {
        if hypot(point.x - last.x, point.y - last.y) >= 0.025 {
          odomTrail.append(point)
          if odomTrail.count > 80 {
            odomTrail.removeFirst(odomTrail.count - 80)
          }
        }
      } else {
        odomTrail = [point]
      }
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
      if snapshot.controlOpen, isHoldingChomp {
        chompTick += 1
        let openLevel = (chompTick / 2).isMultiple(of: 2) ? 1.0 : 0.0
        beakOpening = openLevel
        await duckSession.sendMouth(RobotMouthParams(open: openLevel))
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
    quickMotionTask?.cancel()
    quickMotionTask = nil
    activeQuickMotionLabel = nil
    if wingmanModel.isRunning || wingmanModel.isExecutingPlan {
      await wingmanModel.stopButtonTapped()
    }
    leftStickX = 0
    leftStickY = 0
    rightStickX = 0
    let hadExpression = hasActiveExpression
    if hadExpression {
      isHoldingChomp = false
      chompTick = 0
      beakOpening = 0
      headTilt = 0
      crouchDepth = 0
    }
    await duckSession.sendMove(.zero)
    if hadExpression, snapshot.controlOpen {
      await duckSession.sendMouth(.closed)
      await duckSession.sendPose(.nominal)
    }
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
    if showSoundDrawer {
      showExpressiveDrawer = false
    }
  }

  public func expressiveDrawerToggleTapped() {
    haptics.selectionChanged()
    showExpressiveDrawer.toggle()
    if showExpressiveDrawer {
      showSoundDrawer = false
    }
  }

  public func wingmanButtonTapped(isWideLayout: Bool = false) {
    haptics.selectionChanged()
    if isWideLayout {
      showWingmanInspector.toggle()
    } else {
      showWingmanSheet = true
    }
  }

  public func inlineWingmanSubmitted(isWideLayout: Bool) {
    let trimmed = inlineWingmanPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    inlineWingmanPrompt = ""
    wingmanModel.promptText = trimmed
    if isWideLayout {
      showWingmanInspector = true
    } else {
      showWingmanSheet = true
    }
    wingmanModel.runButtonTapped()
  }

  public func manualPadsToggleTapped() {
    haptics.selectionChanged()
    showManualPads.toggle()
  }

  public func compassHUDToggleTapped() {
    haptics.selectionChanged()
    showCompassHUD.toggle()
  }

  public func resetOdomTrailTapped() {
    haptics.selectionChanged()
    if let odom = snapshot.latestState?.odom {
      odomTrail = [OdomBreadcrumb(x: odom.x, y: odom.y)]
    } else {
      odomTrail = []
    }
  }

  public func quickMotionButtonTapped(label: String, goal: DuckMotionGoal) {
    guard snapshot.controlOpen, activeQuickMotionLabel == nil else { return }
    haptics.impactMedium()
    activeQuickMotionLabel = label
    quickMotionTask?.cancel()
    quickMotionTask = Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await self.duckSession.performMotion(goal)
        self.haptics.success()
      } catch is CancellationError {
        // Cancelled cleanly via Stop button.
      } catch {
        self.alert = .errorMessage(error.localizedDescription)
      }
      self.activeQuickMotionLabel = nil
    }
  }

  public func beakOpeningChanged(_ value: Double) async {
    let clamped = min(max(value, 0.0), 1.0)
    isHoldingChomp = false
    chompTick = 0
    beakOpening = clamped
    if snapshot.controlOpen {
      await duckSession.sendMouth(RobotMouthParams(open: clamped))
    }
  }

  public func chompHoldChanged(isPressed: Bool) async {
    if isPressed == isHoldingChomp { return }
    isHoldingChomp = isPressed
    chompTick = 0
    if isPressed {
      haptics.impactMedium()
      beakOpening = 1.0
      if snapshot.controlOpen {
        await duckSession.sendMouth(.wideOpen)
      }
    } else {
      beakOpening = 0.0
      if snapshot.controlOpen {
        await duckSession.sendMouth(.closed)
      }
    }
  }

  public func headTiltChanged(_ normalized: Double) async {
    let clamped = min(max(normalized, -1.0), 1.0)
    headTilt = clamped
    if snapshot.controlOpen {
      await duckSession.sendHead(
        RobotHeadParams(headRoll: clamped * DuckConstants.maxHeadRollRadians)
      )
    }
  }

  public func crouchDepthChanged(_ normalized: Double) async {
    let clamped = min(max(normalized, 0.0), 1.0)
    crouchDepth = clamped <= 0.001 ? 0.0 : clamped
    guard snapshot.controlOpen else { return }
    if crouchDepth == 0.0 {
      await duckSession.sendPose(.nominal)
    } else {
      await duckSession.sendPose(RobotPoseParams.crouch(percent: crouchDepth * 100.0))
    }
  }

  public func resetExpressionTapped() async {
    haptics.selectionChanged()
    isHoldingChomp = false
    chompTick = 0
    beakOpening = 0.0
    headTilt = 0.0
    crouchDepth = 0.0
    if snapshot.controlOpen {
      await duckSession.sendMouth(.closed)
      await duckSession.sendHead(.neutral)
      await duckSession.sendPose(.nominal)
    }
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

  public func thereminToggleTapped() async {
    let next = !thereminEnabled
    do {
      try await duckSession.setTheremin(next)
      thereminEnabled = next
      haptics.selectionChanged()
    } catch {
      alert = .errorMessage(error.localizedDescription)
    }
  }
}
