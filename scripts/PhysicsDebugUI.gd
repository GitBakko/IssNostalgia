class_name PhysicsDebugUI
extends Node

## Sprint 04 — Debug UI for live tuning of PhysicsConfig parameters,
## powered by Dear ImGui via the imgui-godot GDExtension (S04-A06,
## closes the R2 8.1 lock and supersedes the native-Control-node
## prototype from S04-A01).
##
## Toggle visibility with F1. Each widget edits the live PhysicsConfig
## resource so the next physics tick picks up the change with no restart.

const USER_PRESET_DIR := "user://presets"
const BUILTIN_PRESET_DIR := "res://resources/presets"

## Parameter spec: [key, label, min, max, step, group, type].
## type: "f" = float slider; "b" = bool checkbox.
const PARAMS: Array = [
	# Universe
	["air_density",                  "air density (kg/m³)",      0.5,    2.0,    0.005,  "Universe",    "f"],
	["gravity",                       "gravity (m/s²)",           0.0,    20.0,   0.01,   "Universe",    "f"],
	# Ball
	["ball_mass",                     "mass (kg)",                0.2,    0.7,    0.005,  "Ball",        "f"],
	["ball_radius",                   "radius (m)",               0.05,   0.20,   0.001,  "Ball",        "f"],
	# Drag
	["drag_coeff",                    "Cd",                       0.0,    1.0,    0.005,  "Drag",        "f"],
	# Ground
	["restitution_base",              "e_base (dry)",             0.0,    1.0,    0.005,  "Ground",      "f"],
	["restitution_v_ref",             "v_ref (m/s)",              1.0,    60.0,   0.5,    "Ground",      "f"],
	["variable_restitution_enabled",  "variable restitution",     0,      1,      1,      "Ground",      "b"],
	["cross_2002_enabled",            "Cross-2002 spin transfer", 0,      1,      1,      "Ground",      "b"],
	["bounce_e_t",                    "e_t (tangential)",         0.0,    1.0,    0.005,  "Ground",      "f"],
	["bounce_mu_s",                   "μ_s (dry)",                0.0,    1.5,    0.005,  "Ground",      "f"],
	["friction",                      "friction (legacy)",        0.0,    1.0,    0.005,  "Ground",      "f"],
	["rolling_friction_coeff",        "rolling μ_r (dry)",        0.0,    1.0,    0.005,  "Ground",      "f"],
	["grass_roughness_enabled",       "grass roughness",          0,      1,      1,      "Ground",      "b"],
	["grass_roughness_min_speed",     "grass v_min (m/s)",        0.0,    20.0,   0.1,    "Ground",      "f"],
	["grass_roughness_threshold",     "grass threshold",          0.0,    1.0,    0.005,  "Ground",      "f"],
	["grass_roughness_kick",          "grass kick (m/s)",         0.0,    3.0,    0.01,   "Ground",      "f"],
	["grass_roughness_frequency",     "grass freq (per m)",       0.1,    5.0,    0.05,   "Ground",      "f"],
	# Surface
	["surface_wet",                   "wet surface",              0,      1,      1,      "Surface",     "b"],
	["bounce_mu_s_wet",               "μ_s (wet)",                0.0,    1.0,    0.005,  "Surface",     "f"],
	["rolling_friction_wet",          "rolling μ_r (wet)",        0.0,    1.0,    0.005,  "Surface",     "f"],
	["restitution_base_wet",          "e_base (wet)",             0.0,    1.0,    0.005,  "Surface",     "f"],
	["grass_roughness_kick_wet",      "grass kick (wet)",         0.0,    2.0,    0.01,   "Surface",     "f"],
	# Magnus
	["magnus_enabled",                "Magnus enabled",           0,      1,      1,      "Magnus",      "b"],
	["magnus_spin_param_cap",         "S cap",                    0.1,    5.0,    0.01,   "Magnus",      "f"],
	["magnus_min_speed",              "min speed (m/s)",          0.0,    5.0,    0.05,   "Magnus",      "f"],
	# Knuckleball
	["knuckle_enabled",               "knuckle enabled",          0,      1,      1,      "Knuckleball", "b"],
	["knuckle_threshold_spin",        "max |ω| gate (rad/s)",     0.0,    10.0,   0.05,   "Knuckleball", "f"],
	["knuckle_threshold_speed",       "min |v| gate (m/s)",       0.0,    40.0,   0.1,    "Knuckleball", "f"],
	["knuckle_amplitude",             "amplitude (m/s²)",         0.0,    25.0,   0.1,    "Knuckleball", "f"],
	["knuckle_noise_frequency",       "noise freq (Hz)",          0.1,    5.0,    0.05,   "Knuckleball", "f"],
	["knuckle_spike_frequency_mul",   "spike freq mul",           1.0,    10.0,   0.1,    "Knuckleball", "f"],
	["knuckle_spike_threshold",       "spike threshold",          0.0,    1.0,    0.005,  "Knuckleball", "f"],
	["knuckle_spike_amplitude_mul",   "spike amp mul",            1.0,    5.0,    0.05,   "Knuckleball", "f"],
]

const GROUPS: Array[String] = [
	"Universe", "Ball", "Drag", "Ground", "Surface", "Magnus", "Knuckleball",
]

@export var ball_path: NodePath

var _config: PhysicsConfig
var _ball: Node
var _refs: Dictionary = {}        ## key -> single-element ref array
var _preset_paths: Array[String] = []   ## index 0 = "(current)" placeholder
var _preset_labels: Array[String] = []
var _preset_index: Array = [0]
var _visible: bool = false


func _ready() -> void:
	_resolve_refs()
	_build_widget_refs()
	_populate_presets()


func _resolve_refs() -> void:
	var parent: Node = get_parent()
	var ball: Node = null
	if not ball_path.is_empty():
		ball = get_node_or_null(ball_path)
	if ball == null and parent != null:
		ball = parent.get_node_or_null("Ball")
	_ball = ball
	if ball != null and "config" in ball:
		_config = ball.config
	if _config == null:
		var loaded: Resource = load("res://resources/PhysicsConfig.tres")
		if loaded is PhysicsConfig:
			_config = loaded
			if ball != null and "config" in ball:
				ball.config = _config


func _build_widget_refs() -> void:
	if _config == null:
		return
	for spec in PARAMS:
		var key: String = String(spec[0])
		var t: String = String(spec[6])
		if t == "b":
			_refs[key] = [bool(_config.get(key))]
		else:
			_refs[key] = [float(_config.get(key))]


# ---- Presets -------------------------------------------------------------

func _ensure_preset_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_PRESET_DIR):
		DirAccess.make_dir_recursive_absolute(USER_PRESET_DIR)


func _populate_presets() -> void:
	_ensure_preset_dir()
	_preset_paths.clear()
	_preset_labels.clear()
	_preset_paths.append("")
	_preset_labels.append("(current)")
	_scan_preset_dir(BUILTIN_PRESET_DIR, "[builtin] ")
	_scan_preset_dir(USER_PRESET_DIR, "[user] ")
	_preset_index[0] = 0


func _scan_preset_dir(dir_path: String, label_prefix: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".tres"):
			_preset_paths.append(dir_path.path_join(f))
			_preset_labels.append("%s%s" % [label_prefix, f.get_basename()])
		f = d.get_next()


func _apply_preset(src: PhysicsConfig) -> void:
	if _config == null:
		return
	for spec in PARAMS:
		var key: String = String(spec[0])
		_config.set(key, src.get(key))
	_sync_refs_from_config()


func _sync_refs_from_config() -> void:
	for spec in PARAMS:
		var key: String = String(spec[0])
		var t: String = String(spec[6])
		var ref: Array = _refs.get(key, [])
		if ref.is_empty():
			continue
		if t == "b":
			ref[0] = bool(_config.get(key))
		else:
			ref[0] = float(_config.get(key))


func _save_user_preset() -> void:
	_ensure_preset_dir()
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = USER_PRESET_DIR.path_join("preset_%s.tres" % stamp)
	var copy: PhysicsConfig = PhysicsConfig.new()
	for spec in PARAMS:
		var key: String = String(spec[0])
		copy.set(key, _config.get(key))
	var err: int = ResourceSaver.save(copy, path)
	if err == OK:
		print("[debug-ui] saved preset: %s" % path)
		_populate_presets()
	else:
		push_error("preset save failed (err=%d): %s" % [err, path])


# ---- ImGui frame ---------------------------------------------------------

func _process(_delta: float) -> void:
	if not _visible or _config == null:
		return
	ImGui.SetNextWindowSize(Vector2(520, 720), ImGui.Cond_FirstUseEver)
	ImGui.SetNextWindowPos(Vector2(20, 20), ImGui.Cond_FirstUseEver)
	if ImGui.Begin("Physics Debug — F1 toggle"):
		_draw_preset_row()
		ImGui.Separator()
		_draw_telemetry()
		ImGui.Separator()
		for g in GROUPS:
			if ImGui.CollapsingHeader(g):
				_draw_group(g)
	ImGui.End()


func _draw_preset_row() -> void:
	ImGui.Text("preset:")
	ImGui.SameLine()
	ImGui.SetNextItemWidth(220)
	if ImGui.Combo("##preset", _preset_index, _preset_labels):
		var idx: int = _preset_index[0]
		if idx > 0 and idx < _preset_paths.size():
			var path: String = _preset_paths[idx]
			var res: Resource = load(path)
			if res is PhysicsConfig:
				_apply_preset(res as PhysicsConfig)
				print("[debug-ui] applied preset: %s" % path)
			else:
				push_warning("preset is not a PhysicsConfig: %s" % path)
	ImGui.SameLine()
	if ImGui.Button("save user"):
		_save_user_preset()
	ImGui.SameLine()
	if ImGui.Button("reload"):
		_populate_presets()


func _draw_telemetry() -> void:
	if _ball == null or not (_ball is BallPhysics):
		ImGui.Text("forces: (ball not found)")
		return
	var bp: BallPhysics = _ball as BallPhysics
	ImGui.Text("|F_drag|    %6.2f N" % bp.last_force_drag.length())
	ImGui.Text("|F_magnus|  %6.2f N" % bp.last_force_magnus.length())
	ImGui.Text("|F_knuckle| %6.2f N" % bp.last_force_knuckle.length())
	ImGui.Text("|F_grass|   %6.2f N" % bp.last_force_grass.length())
	ImGui.Text("|F_net|     %6.2f N" % bp.last_force_net.length())
	ImGui.Text("spin S      %6.3f"   % bp.last_spin_param)
	if bp is RigidBody3D:
		var rb: RigidBody3D = bp as RigidBody3D
		var v: Vector3 = rb.linear_velocity
		var w: Vector3 = rb.angular_velocity
		ImGui.Text("|v|         %6.2f m/s   (%5.1f km/h)" % [v.length(), v.length() * 3.6])
		ImGui.Text("|ω|         %6.2f rad/s" % w.length())
		ImGui.Text("height y    %6.2f m" % rb.global_position.y)


func _draw_group(group_name: String) -> void:
	for spec in PARAMS:
		if String(spec[5]) != group_name:
			continue
		var key: String = String(spec[0])
		var label: String = String(spec[1])
		var t: String = String(spec[6])
		var ref: Array = _refs.get(key, [])
		if ref.is_empty():
			continue
		if t == "b":
			if ImGui.Checkbox(label, ref):
				_config.set(key, bool(ref[0]))
		else:
			var lo: float = float(spec[2])
			var hi: float = float(spec[3])
			# Sync widget to underlying value (preset / external code may have
			# changed it). One-direction copy; the slider then mutates the ref.
			if not is_equal_approx(float(ref[0]), float(_config.get(key))):
				ref[0] = float(_config.get(key))
			if ImGui.SliderFloat(label, ref, lo, hi):
				_config.set(key, float(ref[0]))


# ---- Input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_F1:
			_visible = not _visible
			get_viewport().set_input_as_handled()
