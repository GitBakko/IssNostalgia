class_name ShootingController
extends Node

## Sprint 7 T03 — Spacebar hold-charge → cubic-power shot.
##
## ONE per team — wires the team's PlayerController to BallController
## release. Reads `shoot_charge` action via the controller's prefix
## (so p1_/p2_ split in both_human mode just works). Cubic charge curve
## (R03-F02) gives a "weight-building" feel; release path (R03-F03) is
## instant velocity injection — no easing on the release itself.
##
## Public API:
##   fire_shot(hold_s, dir_input) — explicit-args entry point used by
##     tests AND by `_physics_process` internal release detection.
##
## Signals:
##   charge_changed(t_norm)     — every tick while charging, 0..1 (cubic-mapped)
##   shot_fired(speed, dir)     — emitted right after BallController.request_release

# ---- Tunables ------------------------------------------------------------
@export var team_controller: TeamController
@export var ball_controller: BallController

## Print charge start / release / fire-rejection. Off by default — flip on
## when diagnosing "Space does nothing" reports.
@export var debug_log: bool = false

@export_group("Charge")
## Below this hold the press is treated as a tap (no shot fires).
@export var charge_min_s: float = 0.3
## Hold time at which power saturates at 1.0.
@export var charge_max_s: float = 1.5
## Cubic by default (R03-F02). Exposed so calibration can tune 2.0-4.0
## without code changes (R03 thin-area note recommends `@export`).
@export var charge_curve_exponent: float = 3.0

@export_group("Power")
@export var speed_min: float = 15.0   ## m/s at minimum eligible hold
@export var speed_max: float = 30.0   ## m/s at full charge
@export var elev_min_deg: float = 8.0
@export var elev_max_deg: float = 12.0

@export_group("Lob (when lob_modifier action is held on release)")
## Higher elevation envelope used when the lob modifier (`L` key
## by default) is held during the shoot release. Lets the human
## sandbox-test lob saves / over-the-bar shots.
@export var lob_elev_min_deg: float = 30.0
@export var lob_elev_max_deg: float = 50.0
## Slower ceiling for lobs — keeps them readable, prevents the
## shot landing wide when the high arc converts speed to height.
@export var lob_speed_max: float = 22.0

@export_group("Spin")
## Above this launch speed apply auto-topspin (S07-D05).
@export var auto_topspin_threshold: float = 20.0
@export var auto_topspin_rad_s: float = 2.0

@export_group("Animation")
## Per S06 spec A2 — auto-switch is gated for 200 ms after a shot fires.
@export var shoot_anim_duration_s: float = 0.2

# ---- Signals -------------------------------------------------------------
signal charge_changed(t_norm: float)
signal shot_fired(speed: float, direction: Vector3)

# ---- Runtime state -------------------------------------------------------
var _charge_hold_s: float = 0.0
var _is_charging: bool = false
var _shoot_anim_remaining_s: float = 0.0


# ---- Public API ----------------------------------------------------------

## Fires a shot from the active player using `hold_s` as the (already
## clamped or raw) charge duration and `dir_input` as the analog WASD
## input vector. No-op when the active player isn't carrying the ball
## or when the hold is below `charge_min_s`. Returns true on success.
## When `is_lob` is true, uses `lob_elev_*` and `lob_speed_max` so the
## same charge curve produces a high-arc lob instead of a driven shot.
func fire_shot(hold_s: float, dir_input: Vector3, is_lob: bool = false) -> bool:
	if hold_s < charge_min_s:
		if debug_log:
			print("[ShootingController] reject: hold %.2fs < min %.2fs" % [hold_s, charge_min_s])
		return false
	if ball_controller == null or team_controller == null:
		return false
	var shooter: Player = _active_player()
	if shooter == null:
		return false
	if ball_controller.get_carrier() != shooter:
		if debug_log:
			var carrier_name: String = "<none>" if ball_controller.get_carrier() == null \
				else ball_controller.get_carrier().name
			print("[ShootingController] reject: active %s != carrier %s" % [
				shooter.name, carrier_name,
			])
		return false

	var t_norm: float = clampf(
		(hold_s - charge_min_s) / (charge_max_s - charge_min_s),
		0.0, 1.0,
	)
	var power_norm: float = pow(t_norm, charge_curve_exponent)
	var effective_speed_max: float = lob_speed_max if is_lob else speed_max
	var effective_elev_min: float = lob_elev_min_deg if is_lob else elev_min_deg
	var effective_elev_max: float = lob_elev_max_deg if is_lob else elev_max_deg
	var speed: float = lerpf(speed_min, effective_speed_max, power_norm)
	var elev_deg: float = lerpf(effective_elev_min, effective_elev_max,
		power_norm)
	var dir: Vector3 = _resolve_shot_direction(shooter, dir_input)

	var rad: float = deg_to_rad(elev_deg)
	var v_horizontal: float = speed * cos(rad)
	var v_vertical: float = speed * sin(rad)
	var launch_velocity: Vector3 = dir * v_horizontal + Vector3.UP * v_vertical

	var spin: Vector3 = Vector3.ZERO
	if speed > auto_topspin_threshold:
		spin = BallLauncher.compose_spin(dir, auto_topspin_rad_s, 0.0, 0.0)

	ball_controller.request_release(launch_velocity, spin, BallController.ReleaseKind.SHOOT)

	# Auto-switch gate (S06 spec A2) + Player state for HUD / debug
	_shoot_anim_remaining_s = shoot_anim_duration_s
	if team_controller.controller != null:
		team_controller.controller.is_shooting = true
	shooter.state = Player.State.SHOOTING

	shot_fired.emit(speed, dir)
	return true


# ---- Lifecycle -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if team_controller == null or ball_controller == null:
		return
	# Tick down the shoot animation — releases the auto-switch gate.
	if _shoot_anim_remaining_s > 0.0:
		_shoot_anim_remaining_s -= delta
		if _shoot_anim_remaining_s <= 0.0:
			_shoot_anim_remaining_s = 0.0
			if team_controller.controller != null:
				team_controller.controller.is_shooting = false
			var p: Player = _active_player()
			if p != null and p.state == Player.State.SHOOTING:
				p.state = Player.State.IDLE
	# Charge poll requires a controller (only human teams) and the
	# active player must currently carry the ball.
	if team_controller.controller == null:
		return
	var ctrl: PlayerController = team_controller.controller
	var shooter: Player = _active_player()
	if shooter == null or ball_controller.get_carrier() != shooter:
		_reset_charge()
		return

	var pressed: bool = Input.is_action_pressed(_full_action(ctrl, &"shoot_charge"))
	if pressed:
		if not _is_charging:
			_is_charging = true
			_charge_hold_s = 0.0
			if debug_log:
				print("[ShootingController] CHARGE start (action=%s)" % _full_action(ctrl, &"shoot_charge"))
		_charge_hold_s += delta
		var t_norm: float = clampf(
			(_charge_hold_s - charge_min_s) / (charge_max_s - charge_min_s),
			0.0, 1.0,
		)
		charge_changed.emit(t_norm)
	elif _is_charging:
		# Released — fire if eligible, then reset. Lob modifier is
		# polled at release so the player can decide grounder vs
		# lob mid-charge by holding/releasing the modifier key.
		var is_lob: bool = Input.is_action_pressed(_full_action(ctrl,
			&"lob_modifier"))
		if debug_log:
			print("[ShootingController] RELEASE after %.2fs (lob=%s)" % [
				_charge_hold_s, is_lob,
			])
		fire_shot(_charge_hold_s, ctrl.read_movement_input(), is_lob)
		_reset_charge()
		charge_changed.emit(0.0)


# ---- Internal -----------------------------------------------------------

func _active_player() -> Player:
	if team_controller == null or team_controller.controller == null:
		return null
	return team_controller.controller.player


func _reset_charge() -> void:
	_is_charging = false
	_charge_hold_s = 0.0


## Direction = facing * 0.6 + WASD * 0.4 (S07-D04). When WASD input is
## zero the result collapses to player facing. Always normalised before
## use; an all-zero result falls back to the player's forward axis.
func _resolve_shot_direction(shooter: Player, dir_input: Vector3) -> Vector3:
	# Use VisualRoot facing (S07-T06): the shot goes in the direction the
	# RENDERED player is pointing, not the always-identity collision basis.
	var facing: Vector3 = shooter.get_visual_forward()
	var input_xz: Vector3 = Vector3(dir_input.x, 0.0, dir_input.z)
	var combined: Vector3 = facing * 0.6 + input_xz * 0.4
	if combined.length_squared() < 1.0e-4:
		return facing
	return combined.normalized()


func _full_action(ctrl: PlayerController, suffix: StringName) -> StringName:
	return StringName(ctrl.action_prefix + String(suffix))
