class_name MatchClock
extends Node

## Sprint 9 T03 — match countdown clock.
##
## Counts `match_duration_s` down to zero. Emits:
##   - `half_minute_elapsed(remaining_s)` every 30 s of remaining time
##     (used by HUD pulses + AI difficulty curves)
##   - `match_ended` once `current_time_remaining_s` hits zero
##
## Pause / resume API reserved for Sprint 10 goal celebrations + the
## eventual half-time / kick-off interlude. Tests drive `step(delta)`
## directly; production runs via `_physics_process`.

# ---- Exports -------------------------------------------------------------
@export var match_duration_s: float = 240.0  ## 4 min default
@export var auto_start: bool = true

# ---- Signals -------------------------------------------------------------
signal half_minute_elapsed(remaining_s: float)
signal match_ended()

# ---- Runtime state -------------------------------------------------------
var current_time_remaining_s: float = 0.0
var is_running: bool = false
var _last_half_minute_bucket: int = -1


func _ready() -> void:
	current_time_remaining_s = match_duration_s
	_last_half_minute_bucket = int(ceilf(match_duration_s / 30.0))
	if auto_start:
		start()


# ---- Public API ----------------------------------------------------------

func start() -> void:
	is_running = true


func pause() -> void:
	is_running = false


func resume() -> void:
	is_running = true


func reset(duration_s: float = -1.0) -> void:
	if duration_s >= 0.0:
		match_duration_s = duration_s
	current_time_remaining_s = match_duration_s
	_last_half_minute_bucket = int(ceilf(match_duration_s / 30.0))
	is_running = false


## Pure-on-instance step. Tests drive this directly.
func step(delta: float) -> void:
	if not is_running:
		return
	if current_time_remaining_s <= 0.0:
		return
	current_time_remaining_s = maxf(0.0, current_time_remaining_s - delta)
	# Half-minute bucket detection: emit once per crossing.
	var bucket: int = int(ceilf(current_time_remaining_s / 30.0))
	if bucket < _last_half_minute_bucket:
		_last_half_minute_bucket = bucket
		half_minute_elapsed.emit(current_time_remaining_s)
	if current_time_remaining_s <= 0.0:
		is_running = false
		match_ended.emit()


# ---- Lifecycle ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	step(delta)
