class_name PlayerController
extends Node

## Sprint 6 T03 — human input → Player bridge.
##
## Design (S06-D25 / D26):
##   - **ActionMap abstraction**: actions are referenced by SUFFIX
##     (e.g. "move_forward"); the controller prepends `action_prefix`
##     ("p1_" / "p2_") so the SAME PlayerController class drives both
##     teams in the `both_human` debug mode (S06-D29) without hard-coded
##     key literals. Touch bindings (Sprint 10) attach to the same
##     suffixes — no controller code changes.
##   - **Input buffering** (R09-F05): every press of an action timestamped
##     into a small ring; `consume_buffered(suffix)` returns true if the
##     action was pressed within `buffer_window_ms` AND not already
##     consumed. Lets the game execute "what the player intended" rather
##     than what they literally pressed at frame N.
##   - **Coyote framework**: separate from buffer. `was_recently_valid(...)`
##     answers "was this action's context valid within the last N frames?"
##     (e.g. tackle window after losing possession). Sprint 6 wires the
##     framework but has no consumers yet — Sprint 7 tackles will use it.
##
## The controller does NOT run input outside `_physics_process`: the action
## suffix is appended to `action_prefix` once and the resulting full action
## name is checked against `Input.is_action_pressed`. No magic strings
## elsewhere — adding a new action requires editing `ACTION_SUFFIXES` AND
## adding the corresponding `<prefix><suffix>` row to `project.godot`.

const ACTION_SUFFIXES: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"switch_player",
	&"shoot_charge",
	&"pass_ball",
]

## Per-action ring of recent press times. ms since `Time.get_ticks_msec()`.
const BUFFER_RING_SIZE: int = 4

# ---- Exports -------------------------------------------------------------
@export var player: Player

## Action prefix — "p1_" for the human (Team A by default), "p2_" for the
## debug `both_human` Team B controller.
@export var action_prefix: String = "p1_"

@export_group("Forgiveness")
## Sliding window for input buffering (R09-F05). 100 ms is the canonical
## "feels right" value across mobile + desktop sports games.
@export var buffer_window_ms: float = 100.0

## Coyote window in physics frames. 6 frames @ 120 Hz = 50 ms — the player
## still triggers an action briefly after its valid context closed.
@export var coyote_window_frames: int = 6

# ---- Runtime state -------------------------------------------------------
## Last shoot/pass animation start tick (used by TeamController to gate
## auto-switch — S06 spec A2: 200 ms / 100 ms). Sprint 6 these stay 0.
var is_shooting: bool = false
var is_passing: bool = false

## Action-suffix → ring of last press timestamps (ms). Newest at head.
var _press_buffers: Dictionary = {}

## Frame counter (per-controller, in physics ticks). Used by
## `was_recently_valid` and `_buffer_press`.
var _frame: int = 0


func _ready() -> void:
	for suffix in ACTION_SUFFIXES:
		_press_buffers[suffix] = PackedFloat32Array()
		_press_buffers[suffix].resize(BUFFER_RING_SIZE)
		_press_buffers[suffix].fill(-INF)


# ---- Public API ----------------------------------------------------------

## Move/Sprint input poll, drives `Player.apply_movement_step`. Called from
## `_physics_process` — also exposed for tests so they can inject input
## without going through the global `Input` singleton.
func step_movement(input_dir: Vector3, sprint_held: bool, dt: float) -> void:
	if player == null:
		return
	player.apply_movement_step(input_dir, sprint_held, dt)


## Mark an action as pressed RIGHT NOW (current physics tick). Used by the
## controller's own input poll AND by tests / virtual joysticks (Sprint 10).
func record_press(suffix: StringName) -> void:
	if not _press_buffers.has(suffix):
		return
	var ring: PackedFloat32Array = _press_buffers[suffix]
	# Shift older entries one slot back, drop oldest.
	for i in range(BUFFER_RING_SIZE - 1, 0, -1):
		ring[i] = ring[i - 1]
	ring[0] = float(Time.get_ticks_msec())
	_press_buffers[suffix] = ring


## True if `suffix` was pressed within `buffer_window_ms` and the buffered
## entry has not been consumed yet. Consumes the most recent entry on hit
## so a single press can't double-fire across consecutive checks.
func consume_buffered(suffix: StringName) -> bool:
	if not _press_buffers.has(suffix):
		return false
	var ring: PackedFloat32Array = _press_buffers[suffix]
	var now_ms: float = float(Time.get_ticks_msec())
	if ring[0] >= 0.0 and (now_ms - ring[0]) <= buffer_window_ms:
		# Consume by pushing -INF to the head; older entries kept for
		# inspection but `consume_buffered` only ever reads head.
		ring[0] = -INF
		_press_buffers[suffix] = ring
		return true
	return false


## Coyote check: was `suffix` pressed within the last `coyote_window_frames`?
## Does NOT consume. Lets late-firing reactive logic ("tackle right after
## losing the ball") still work briefly after the valid context closed.
## Sprint 6 has no consumer; Sprint 7 tackle code will read it.
func was_recently_valid(suffix: StringName) -> bool:
	if not _press_buffers.has(suffix):
		return false
	var ring: PackedFloat32Array = _press_buffers[suffix]
	# coyote = N physics frames at the project's tick rate.
	var window_ms: float = (1000.0 / float(Engine.physics_ticks_per_second)) \
		* float(coyote_window_frames)
	var now_ms: float = float(Time.get_ticks_msec())
	for t in ring:
		if t >= 0.0 and (now_ms - t) <= window_ms:
			return true
	return false


# ---- Lifecycle -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_frame += 1
	if player == null:
		return
	# Input poll
	var input_dir: Vector3 = _read_movement_input()
	var sprint_held: bool = Input.is_action_pressed(_full(&"sprint"))
	step_movement(input_dir, sprint_held, delta)
	# Press capture for buffered actions (movement keys are stateful, not
	# buffered; only discrete actions need buffering).
	for suffix in [&"switch_player", &"shoot_charge", &"pass_ball"]:
		if Input.is_action_just_pressed(_full(suffix)):
			record_press(suffix)
			print("[PlayerCtrl %s] press detected: %s" % [action_prefix, suffix])


# ---- Internal -----------------------------------------------------------

func _full(suffix: StringName) -> StringName:
	return StringName(action_prefix + String(suffix))


func _read_movement_input() -> Vector3:
	# Right-handed, -Z forward (Godot default), +X right.
	var x: float = (
		Input.get_action_strength(_full(&"move_right"))
		- Input.get_action_strength(_full(&"move_left"))
	)
	var z: float = (
		Input.get_action_strength(_full(&"move_back"))
		- Input.get_action_strength(_full(&"move_forward"))
	)
	var raw: Vector3 = Vector3(x, 0.0, z)
	if raw.length_squared() > 1.0:
		return raw.normalized()
	return raw
