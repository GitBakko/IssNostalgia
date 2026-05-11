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
var _screenshot_pending: bool = false
var _screenshot_path: String = ""
var _screenshot_frames_left: int = 0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_setup_camera()
	_setup_screenshot_from_cli()
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
	_camera.global_position = camera_position
	_camera.look_at(camera_target, Vector3.UP)
	_camera.fov = camera_fov_degrees


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
		_screenshot_frames_left = 5
		print("[Sandbox] screenshot pending, target: %s" % _screenshot_path)


func _process(_delta: float) -> void:
	if not _screenshot_pending:
		return
	if _screenshot_frames_left > 0:
		_screenshot_frames_left -= 1
		return
	_capture_screenshot()


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
	if not quit_on_escape:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			get_tree().quit()
