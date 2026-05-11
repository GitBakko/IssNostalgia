class_name SandboxController
extends Node3D

## Root orchestration node for the Physics Sandbox scene.
## Sprint 01 (T01) — minimal: configure camera, log readiness, allow ESC to quit.
## Will grow over Sprint 01 tasks T02-T05.

@export var quit_on_escape: bool = true

## Camera placement. ISS-style "broadcast / corner" view, looking at field center.
## See PHYSICS_LOG.md (S01-A06) for the rationale of these values.
@export var camera_position: Vector3 = Vector3(0.0, 35.0, 20.0)
@export var camera_target: Vector3 = Vector3.ZERO
@export var camera_fov_degrees: float = 45.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_setup_camera()
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


func _unhandled_input(event: InputEvent) -> void:
	if not quit_on_escape:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			get_tree().quit()
