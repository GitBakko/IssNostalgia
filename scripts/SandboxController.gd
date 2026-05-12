class_name SandboxController
extends Node3D

## Root orchestration node for the Physics Sandbox scene.
## Sprint 01 (T01) — minimal: configure camera, log readiness, allow ESC to quit.
## Will grow over Sprint 01 tasks T02-T05.

@export var quit_on_escape: bool = true

## Camera placement. ISS-style "broadcast / corner" view, looking at field center.
## See PHYSICS_LOG.md (S01-A06) for the rationale of these values.
@export var camera_position: Vector3 = Vector3(0.0, 20.0, 40.0)
@export var camera_target: Vector3 = Vector3.ZERO
@export var camera_fov_degrees: float = 45.0

## Debug: capture a single screenshot and quit. Triggered by `--capture-screenshot` CLI arg.
const SCREENSHOT_FLAG := "--capture-screenshot"
const SCREENSHOT_DEFAULT_PATH := "user://t01_screenshot.png"
const AUTO_LAUNCH_FLAG := "--auto-launch"
var _screenshot_pending: bool = false
var _screenshot_path: String = ""
var _screenshot_frames_left: int = 0
var _auto_launch_kind: String = ""
var _auto_launch_frames_left: int = -1

@onready var _camera: Camera3D = $Camera3D
@onready var _ball: RigidBody3D = $Ball as RigidBody3D
@onready var _launcher: BallLauncher = $BallLauncher
@onready var _telemetry: Label = $HUD/Telemetry
@onready var _force_gizmo: Node3D = get_node_or_null("ForceGizmo")

# Orbit-camera state. Derived from the static initial camera_position
# at _ready (so launching the scene with the legacy `camera_position`
# exported value still works), then driven by RMB drag + wheel.
var _orbit_pitch_deg: float = 60.0   ## angle above horizontal (positive = look down)
var _orbit_yaw_deg: float = 0.0      ## around Y, 0 = facing -Z
var _orbit_distance: float = 40.0
var _orbit_target: Vector3 = Vector3.ZERO
var _rmb_dragging: bool = false
const ORBIT_PITCH_MIN: float = 5.0
const ORBIT_PITCH_MAX: float = 88.0
const ORBIT_DISTANCE_MIN: float = 4.0
const ORBIT_DISTANCE_MAX: float = 120.0
const ORBIT_DRAG_SPEED: float = 0.3   ## degrees per pixel
const ORBIT_WHEEL_STEP: float = 2.5   ## metres per wheel notch


func _ready() -> void:
	_setup_camera()
	_setup_screenshot_from_cli()
	_connect_ball_signals()
	print("[Sandbox] ready — IssNostalgia Phase 1, Sprint 01 T01")
	print("[Sandbox] field: 105 x 68 m, FIFA regulation")
	print("[Sandbox] physics tick: %d Hz" % Engine.physics_ticks_per_second)
	print("[Sandbox] camera pos %s -> target %s, fov %.1f deg" % [
		camera_position, camera_target, camera_fov_degrees,
	])


func _setup_camera() -> void:
	if _camera == null:
		push_warning("SandboxController: Camera3D child not found")
		return
	_camera.fov = camera_fov_degrees
	# Derive orbit state from the legacy camera_position so the scene
	# still opens at the broadcast view, then orbit takes over.
	var offset: Vector3 = camera_position - camera_target
	_orbit_target = camera_target
	_orbit_distance = clampf(offset.length(), ORBIT_DISTANCE_MIN, ORBIT_DISTANCE_MAX)
	if _orbit_distance > 1e-3:
		_orbit_pitch_deg = clampf(rad_to_deg(asin(offset.y / _orbit_distance)),
			ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
		_orbit_yaw_deg = rad_to_deg(atan2(offset.x, offset.z))
	_update_orbit_camera()


func _update_orbit_camera() -> void:
	if _camera == null:
		return
	var pitch_r: float = deg_to_rad(_orbit_pitch_deg)
	var yaw_r: float = deg_to_rad(_orbit_yaw_deg)
	var off: Vector3 = Vector3(
		cos(pitch_r) * sin(yaw_r),
		sin(pitch_r),
		cos(pitch_r) * cos(yaw_r),
	) * _orbit_distance
	_camera.global_position = _orbit_target + off
	_camera.look_at(_orbit_target, Vector3.UP)


func _connect_ball_signals() -> void:
	var ball: Node = get_node_or_null("Ball")
	if ball == null:
		return
	if ball.has_signal("bounced"):
		ball.connect("bounced", _on_ball_bounced)


func _on_ball_bounced(impact_speed: float, normal: Vector3, position: Vector3) -> void:
	print("[bounce] speed=%.2f m/s normal=%s pos=%s" % [impact_speed, normal, position])


func _setup_screenshot_from_cli() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if SCREENSHOT_FLAG in args:
		_screenshot_pending = true
		var idx: int = args.find(SCREENSHOT_FLAG)
		if idx >= 0 and idx + 1 < args.size() and not args[idx + 1].begins_with("--"):
			_screenshot_path = args[idx + 1]
		else:
			_screenshot_path = SCREENSHOT_DEFAULT_PATH
		# Wait a few frames so the renderer has flushed at least one full pass.
		# Default: 5 frames. Can be overridden by passing a number after the
		# path, e.g. `-- --capture-screenshot t.png 60`.
		_screenshot_frames_left = 5
		if idx + 2 < args.size():
			var maybe_frames: String = args[idx + 2]
			if maybe_frames.is_valid_int():
				_screenshot_frames_left = max(1, int(maybe_frames))
		print("[Sandbox] screenshot pending: %s (after %d frames)" % [
			_screenshot_path, _screenshot_frames_left,
		])
	if AUTO_LAUNCH_FLAG in args:
		var li: int = args.find(AUTO_LAUNCH_FLAG)
		if li + 1 < args.size():
			_auto_launch_kind = args[li + 1]
			_auto_launch_frames_left = 5
			print("[Sandbox] auto-launch scheduled: '%s' in %d frames" % [
				_auto_launch_kind, _auto_launch_frames_left,
			])


func _process(_delta: float) -> void:
	_update_telemetry()
	_tick_auto_launch()
	if not _screenshot_pending:
		return
	if _screenshot_frames_left > 0:
		_screenshot_frames_left -= 1
		if _screenshot_frames_left % 15 == 0 and _ball != null:
			print("[trace] frames_left=%d pos=%s vel=%s" % [
				_screenshot_frames_left, _ball.global_position, _ball.linear_velocity,
			])
		return
	_capture_screenshot()


func _tick_auto_launch() -> void:
	if _auto_launch_frames_left < 0:
		return
	if _auto_launch_frames_left > 0:
		_auto_launch_frames_left -= 1
		return
	_auto_launch_frames_left = -1
	if _launcher == null:
		return
	match _auto_launch_kind:
		"vertical":
			_launcher.launch_vertical()
		"horizontal":
			_launcher.launch_horizontal()
		"reset":
			_launcher.reset_ball()
		"curve":
			_launcher.launch_curve_shot()
		"deadleaf":
			_launcher.launch_dead_leaf()
		"grounder":
			_launcher.launch_grounder_topspin()
		"knuckle":
			_launcher.launch_knuckle()
		_:
			push_warning("Unknown --auto-launch kind: %s" % _auto_launch_kind)


func _update_telemetry() -> void:
	if _telemetry == null or _ball == null:
		return
	var v: Vector3 = _ball.linear_velocity
	var w: Vector3 = _ball.angular_velocity
	var speed_kmh: float = v.length() * 3.6
	var fps: float = Engine.get_frames_per_second()
	var phys_fps: int = Engine.physics_ticks_per_second
	var replay_line: String = ""
	if _ball is BallPhysics:
		var bp: BallPhysics = _ball as BallPhysics
		if bp.is_replay_active():
			replay_line = "\n[REPLAY  t=%+5.2f s]" % bp.replay_cursor_offset_seconds()
	_telemetry.text = "ball pos  %5.1f, %5.2f, %5.1f m\nspeed     %5.1f km/h  ( %5.2f m/s )\nspin      |w| %5.2f rad/s\nheight    %5.2f m\nFPS       %4.0f  /  phys %d Hz%s" % [
		_ball.global_position.x, _ball.global_position.y, _ball.global_position.z,
		speed_kmh, v.length(),
		w.length(),
		_ball.global_position.y,
		fps, phys_fps,
		replay_line,
	]


func _capture_screenshot() -> void:
	_screenshot_pending = false
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("Screenshot failed: viewport texture image is null")
		get_tree().quit(1)
		return
	var abs_path: String = ProjectSettings.globalize_path(_screenshot_path)
	var err: int = img.save_png(abs_path)
	if err == OK:
		print("[Sandbox] screenshot saved: %s" % abs_path)
		get_tree().quit(0)
	else:
		push_error("Screenshot save failed (err=%d): %s" % [err, abs_path])
		get_tree().quit(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _rmb_dragging:
		_handle_orbit_drag(event as InputEventMouseMotion)


func _handle_orbit_drag(event: InputEventMouseMotion) -> void:
	_orbit_yaw_deg -= event.relative.x * ORBIT_DRAG_SPEED
	_orbit_pitch_deg = clampf(_orbit_pitch_deg - event.relative.y * ORBIT_DRAG_SPEED,
		ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
	_update_orbit_camera()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			if quit_on_escape:
				get_tree().quit()
		KEY_SPACE:
			if _launcher: _launcher.launch_vertical()
		KEY_H:
			if _launcher: _launcher.launch_horizontal()
		KEY_R:
			if _launcher: _launcher.reset_ball()
		KEY_1:
			if _launcher: _launcher.launch_curve_shot(_aim_direction())
		KEY_2:
			if _launcher: _launcher.launch_dead_leaf(_aim_direction())
		KEY_3:
			if _launcher: _launcher.launch_grounder_topspin(_aim_direction())
		KEY_4:
			if _launcher: _launcher.launch_knuckle(_aim_direction())
		KEY_F5:
			_toggle_slowmo()
		KEY_W:
			_toggle_wet_surface()
		KEY_G:
			_toggle_force_gizmo()
		KEY_P:
			_replay_toggle()
		KEY_PERIOD:
			_replay_step(1)
		KEY_COMMA:
			_replay_step(-1)


## Horizontal world direction from the ball to the current mouse pointer's
## ground-plane intersection. Falls back to +X when the mouse points off
## the field (camera looking up).
func _aim_direction() -> Vector3:
	if _camera == null or _ball == null:
		return Vector3.RIGHT
	var screen_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir3: Vector3 = _camera.project_ray_normal(screen_pos)
	if dir3.y >= -0.001:
		return Vector3.RIGHT
	var t: float = -from.y / dir3.y
	var ground: Vector3 = from + dir3 * t
	var delta: Vector3 = ground - _ball.global_position
	delta.y = 0.0
	if delta.length() < 0.01:
		return Vector3.RIGHT
	return delta.normalized()


func _toggle_slowmo() -> void:
	var new_scale: float = 1.0 if Engine.time_scale < 1.0 else 0.25
	Engine.time_scale = new_scale
	print("[Sandbox] time_scale = %.2f" % new_scale)


func _replay_toggle() -> void:
	if _ball == null or not (_ball is BallPhysics):
		return
	var bp: BallPhysics = _ball as BallPhysics
	if bp.is_replay_active():
		bp.exit_replay()
		print("[Sandbox] replay OFF (resumed from cursor)")
	else:
		bp.enter_replay()
		print("[Sandbox] replay ON (cursor at newest entry)")


func _replay_step(delta: int) -> void:
	if _ball == null or not (_ball is BallPhysics):
		return
	var bp: BallPhysics = _ball as BallPhysics
	bp.step_replay(delta)


func _toggle_force_gizmo() -> void:
	if _force_gizmo == null:
		return
	_force_gizmo.visible = not _force_gizmo.visible
	if "enabled" in _force_gizmo:
		_force_gizmo.enabled = _force_gizmo.visible
	print("[Sandbox] force gizmo = %s" % _force_gizmo.visible)


func _toggle_wet_surface() -> void:
	if _ball == null:
		return
	var cfg: PhysicsConfig = (_ball as BallPhysics).config
	if cfg == null:
		return
	cfg.surface_wet = not cfg.surface_wet
	print("[Sandbox] surface_wet = %s" % cfg.surface_wet)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_lob_to_mouse(event.position)
		MOUSE_BUTTON_RIGHT:
			_rmb_dragging = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_orbit_distance = clampf(_orbit_distance - ORBIT_WHEEL_STEP,
					ORBIT_DISTANCE_MIN, ORBIT_DISTANCE_MAX)
				_update_orbit_camera()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_orbit_distance = clampf(_orbit_distance + ORBIT_WHEEL_STEP,
					ORBIT_DISTANCE_MIN, ORBIT_DISTANCE_MAX)
				_update_orbit_camera()


func _lob_to_mouse(screen_pos: Vector2) -> void:
	if _camera == null or _launcher == null:
		return
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if dir.y >= -0.001:
		return
	var t: float = -from.y / dir.y
	var ground_point: Vector3 = from + dir * t
	_launcher.launch_to_point(ground_point)
