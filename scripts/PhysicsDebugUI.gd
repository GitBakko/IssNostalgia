class_name PhysicsDebugUI
extends CanvasLayer

## Sprint 04 — Debug UI for live tuning of PhysicsConfig parameters.
## Built with native Godot Control nodes (S04-A01 deviation from
## R2 8.1 imgui-godot lock — see docs/SPRINT_04_PLAN.md).
##
## Toggle visibility with F1. Each slider writes back into the live
## PhysicsConfig resource; the next physics tick picks up the change.

const USER_PRESET_DIR := "user://presets"

## Parameter spec: [key, label, min, max, step, group].
## Booleans use min=0, max=1, step=1 (rendered as checkbox row).
const PARAMS: Array = [
	# Universe
	["air_density",                  "air density (kg/m³)",      0.5,    2.0,    0.005,  "Universe"],
	["gravity",                       "gravity (m/s²)",           0.0,    20.0,   0.01,   "Universe"],
	# Ball
	["ball_mass",                     "mass (kg)",                0.2,    0.7,    0.005,  "Ball"],
	["ball_radius",                   "radius (m)",               0.05,   0.20,   0.001,  "Ball"],
	# Drag
	["drag_coeff",                    "Cd",                       0.0,    1.0,    0.005,  "Drag"],
	# Ground
	["restitution_base",              "e_base (dry)",             0.0,    1.0,    0.005,  "Ground"],
	["restitution_v_ref",             "v_ref (m/s)",              1.0,    60.0,   0.5,    "Ground"],
	["variable_restitution_enabled",  "variable restitution",     0,      1,      1,      "Ground"],
	["cross_2002_enabled",            "Cross-2002 spin transfer", 0,      1,      1,      "Ground"],
	["bounce_e_t",                    "e_t (tangential)",         0.0,    1.0,    0.005,  "Ground"],
	["bounce_mu_s",                   "μ_s (dry)",                0.0,    1.5,    0.005,  "Ground"],
	["friction",                      "friction (legacy)",        0.0,    1.0,    0.005,  "Ground"],
	["rolling_friction_coeff",        "rolling μ_r (dry)",        0.0,    1.0,    0.005,  "Ground"],
	["grass_roughness_enabled",       "grass roughness",          0,      1,      1,      "Ground"],
	["grass_roughness_min_speed",     "grass v_min (m/s)",        0.0,    20.0,   0.1,    "Ground"],
	["grass_roughness_threshold",     "grass threshold",          0.0,    1.0,    0.005,  "Ground"],
	["grass_roughness_kick",          "grass kick (m/s)",         0.0,    3.0,    0.01,   "Ground"],
	["grass_roughness_frequency",     "grass freq (per m)",       0.1,    5.0,    0.05,   "Ground"],
	# Surface
	["surface_wet",                   "wet surface",              0,      1,      1,      "Surface"],
	["bounce_mu_s_wet",               "μ_s (wet)",                0.0,    1.0,    0.005,  "Surface"],
	["rolling_friction_wet",          "rolling μ_r (wet)",        0.0,    1.0,    0.005,  "Surface"],
	["restitution_base_wet",          "e_base (wet)",             0.0,    1.0,    0.005,  "Surface"],
	["grass_roughness_kick_wet",      "grass kick (wet)",         0.0,    2.0,    0.01,   "Surface"],
	# Magnus
	["magnus_enabled",                "Magnus enabled",           0,      1,      1,      "Magnus"],
	["magnus_spin_param_cap",         "S cap",                    0.1,    5.0,    0.01,   "Magnus"],
	["magnus_min_speed",              "min speed (m/s)",          0.0,    5.0,    0.05,   "Magnus"],
	# Knuckleball
	["knuckle_enabled",               "knuckle enabled",          0,      1,      1,      "Knuckleball"],
	["knuckle_threshold_spin",        "max |ω| gate (rad/s)",     0.0,    10.0,   0.05,   "Knuckleball"],
	["knuckle_threshold_speed",       "min |v| gate (m/s)",       0.0,    40.0,   0.1,    "Knuckleball"],
	["knuckle_amplitude",             "amplitude (m/s²)",         0.0,    25.0,   0.1,    "Knuckleball"],
	["knuckle_noise_frequency",       "noise freq (Hz)",          0.1,    5.0,    0.05,   "Knuckleball"],
	["knuckle_spike_frequency_mul",   "spike freq mul",           1.0,    10.0,   0.1,    "Knuckleball"],
	["knuckle_spike_threshold",       "spike threshold",          0.0,    1.0,    0.005,  "Knuckleball"],
	["knuckle_spike_amplitude_mul",   "spike amp mul",            1.0,    5.0,    0.05,   "Knuckleball"],
]

const GROUPS: Array[String] = [
	"Universe", "Ball", "Drag", "Ground", "Surface", "Magnus", "Knuckleball",
]

@export var config_path: NodePath
@export var ball_path: NodePath

var _config: PhysicsConfig
var _ball: Node
var _rows: Dictionary = {}   ## key -> {slider, label_value}
var _panel: Panel
var _preset_dropdown: OptionButton
var _telemetry_label: Label

func _ready() -> void:
	layer = 10
	_resolve_refs()
	_build_ui()
	_ensure_preset_dir()
	_refresh_all_widgets()
	_populate_presets()
	_panel.visible = false   ## start hidden; F1 toggles
	visible = true


func _resolve_refs() -> void:
	if get_parent() != null:
		var p: Node = get_parent()
		var ball: Node = p.get_node_or_null("Ball")
		if ball != null and "config" in ball:
			_config = ball.config
		if _config == null:
			var loaded: Resource = load("res://resources/PhysicsConfig.tres")
			if loaded is PhysicsConfig:
				_config = loaded
				if ball != null and "config" in ball:
					ball.config = _config
		_ball = ball


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -480.0
	_panel.offset_right = -12.0
	_panel.offset_top = 160.0
	_panel.offset_bottom = -12.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.86)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.anchor_right = 1.0
	root_vbox.anchor_bottom = 1.0
	root_vbox.offset_left = 10.0
	root_vbox.offset_right = -10.0
	root_vbox.offset_top = 10.0
	root_vbox.offset_bottom = -10.0
	root_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(root_vbox)

	var title: Label = Label.new()
	title.text = "Physics Debug UI  —  F1 toggle"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	root_vbox.add_child(title)

	var preset_row: HBoxContainer = HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(preset_row)

	var preset_label: Label = Label.new()
	preset_label.text = "preset:"
	preset_label.custom_minimum_size = Vector2(64, 0)
	preset_row.add_child(preset_label)

	_preset_dropdown = OptionButton.new()
	_preset_dropdown.custom_minimum_size = Vector2(180, 0)
	_preset_dropdown.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_dropdown)

	var save_btn: Button = Button.new()
	save_btn.text = "save user"
	save_btn.pressed.connect(_on_save_user_preset)
	preset_row.add_child(save_btn)

	var reload_btn: Button = Button.new()
	reload_btn.text = "reload"
	reload_btn.pressed.connect(_populate_presets)
	preset_row.add_child(reload_btn)

	_telemetry_label = Label.new()
	_telemetry_label.add_theme_font_size_override("font_size", 14)
	_telemetry_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	_telemetry_label.text = "forces: —"
	root_vbox.add_child(_telemetry_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var inner: VBoxContainer = VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)

	for group_name in GROUPS:
		var hdr: Label = Label.new()
		hdr.text = "— %s —" % group_name
		hdr.add_theme_font_size_override("font_size", 15)
		hdr.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1))
		inner.add_child(hdr)

		for spec in PARAMS:
			if String(spec[5]) != group_name:
				continue
			_build_row(inner, spec)


func _build_row(parent: Control, spec: Array) -> void:
	var key: String = String(spec[0])
	var label_text: String = String(spec[1])
	var lo: float = float(spec[2])
	var hi: float = float(spec[3])
	var step: float = float(spec[4])
	var is_bool: bool = (step == 1.0 and lo == 0.0 and hi == 1.0
		and typeof(_config.get(key)) == TYPE_BOOL)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var name_label: Label = Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(190, 0)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	row.add_child(name_label)

	if is_bool:
		var cb: CheckButton = CheckButton.new()
		cb.button_pressed = bool(_config.get(key))
		cb.toggled.connect(_on_bool_toggled.bind(key))
		row.add_child(cb)
		_rows[key] = {"slider": cb, "value": null}
		return

	var slider: HSlider = HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = float(_config.get(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(150, 0)
	slider.value_changed.connect(_on_slider_changed.bind(key))
	row.add_child(slider)

	var value_label: Label = Label.new()
	value_label.text = _fmt_value(float(_config.get(key)), step)
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	row.add_child(value_label)

	_rows[key] = {"slider": slider, "value": value_label, "step": step}


func _fmt_value(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(v))
	if step >= 0.1:
		return "%.2f" % v
	if step >= 0.01:
		return "%.3f" % v
	return "%.4f" % v


func _on_slider_changed(value: float, key: String) -> void:
	if _config == null:
		return
	_config.set(key, value)
	var row: Dictionary = _rows.get(key, {})
	if row.has("value") and row["value"] != null:
		var step: float = float(row.get("step", 0.01))
		(row["value"] as Label).text = _fmt_value(value, step)


func _on_bool_toggled(pressed: bool, key: String) -> void:
	if _config == null:
		return
	_config.set(key, pressed)


func _refresh_all_widgets() -> void:
	if _config == null:
		return
	for key in _rows.keys():
		var row: Dictionary = _rows[key]
		var w: Object = row["slider"]
		var v = _config.get(key)
		if w is HSlider:
			(w as HSlider).set_value_no_signal(float(v))
			if row.get("value") != null:
				var step: float = float(row.get("step", 0.01))
				(row["value"] as Label).text = _fmt_value(float(v), step)
		elif w is CheckButton:
			(w as CheckButton).set_pressed_no_signal(bool(v))


func _process(_delta: float) -> void:
	_update_telemetry()


func _update_telemetry() -> void:
	if _telemetry_label == null or _ball == null or not (_ball is BallPhysics):
		return
	var bp: BallPhysics = _ball as BallPhysics
	var f_drag: Vector3 = bp.last_force_drag if "last_force_drag" in bp else Vector3.ZERO
	var f_mag: Vector3 = bp.last_force_magnus if "last_force_magnus" in bp else Vector3.ZERO
	var f_kn: Vector3 = bp.last_force_knuckle if "last_force_knuckle" in bp else Vector3.ZERO
	var f_grass: Vector3 = bp.last_force_grass if "last_force_grass" in bp else Vector3.ZERO
	var f_net: Vector3 = bp.last_force_net if "last_force_net" in bp else Vector3.ZERO
	var s_param: float = bp.last_spin_param if "last_spin_param" in bp else 0.0
	_telemetry_label.text = (
		"|F| drag=%5.2f  magnus=%5.2f  knuckle=%5.2f  grass=%5.2f  net=%5.2f N\nS (spin)= %5.3f"
		% [f_drag.length(), f_mag.length(), f_kn.length(), f_grass.length(), f_net.length(), s_param]
	)


# ---- Presets -------------------------------------------------------------

func _ensure_preset_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_PRESET_DIR):
		DirAccess.make_dir_recursive_absolute(USER_PRESET_DIR)


func _populate_presets() -> void:
	_preset_dropdown.clear()
	_preset_dropdown.add_item("(current)")
	# Built-in presets
	var builtin_dir := "res://resources/presets"
	if DirAccess.dir_exists_absolute(builtin_dir):
		var d: DirAccess = DirAccess.open(builtin_dir)
		if d != null:
			d.list_dir_begin()
			var f: String = d.get_next()
			while f != "":
				if not d.current_is_dir() and f.ends_with(".tres"):
					_preset_dropdown.add_item("[builtin] %s" % f.get_basename())
					_preset_dropdown.set_item_metadata(_preset_dropdown.item_count - 1,
						builtin_dir.path_join(f))
				f = d.get_next()
	# User presets
	if DirAccess.dir_exists_absolute(USER_PRESET_DIR):
		var d2: DirAccess = DirAccess.open(USER_PRESET_DIR)
		if d2 != null:
			d2.list_dir_begin()
			var f2: String = d2.get_next()
			while f2 != "":
				if not d2.current_is_dir() and f2.ends_with(".tres"):
					_preset_dropdown.add_item("[user] %s" % f2.get_basename())
					_preset_dropdown.set_item_metadata(_preset_dropdown.item_count - 1,
						USER_PRESET_DIR.path_join(f2))
				f2 = d2.get_next()


func _on_preset_selected(idx: int) -> void:
	if idx == 0:
		return
	var path: Variant = _preset_dropdown.get_item_metadata(idx)
	if typeof(path) != TYPE_STRING:
		return
	var res: Resource = load(path)
	if not (res is PhysicsConfig):
		push_warning("preset is not a PhysicsConfig: %s" % path)
		return
	_apply_preset(res as PhysicsConfig)
	print("[debug-ui] applied preset: %s" % path)


func _apply_preset(src: PhysicsConfig) -> void:
	if _config == null:
		return
	for spec in PARAMS:
		var key: String = String(spec[0])
		_config.set(key, src.get(key))
	_refresh_all_widgets()


func _on_save_user_preset() -> void:
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


# ---- Input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_F1:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()
