class_name GameMatch
extends Node3D

## Sprint 6 T05 — root scene script. Instantiates two teams of 5 from
## formation + team configs, spawns the human-team PlayerController,
## wires both TeamControllers to a shared MockBall (Node3D, no physics
## yet — real RigidBody3D arrives in Sprint 7), updates a minimal HUD.
##
## MatchManager.both_human debug flag (S06-D29) lives here as well — wired
## and enriched in T06; T05 just exposes the export so the scene file can
## set it from the editor.

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")

@export var team_a_config: TeamConfig
@export var team_b_config: TeamConfig
@export var formation: FormationData

## Scene-internal refs — resolved at _ready via @onready (typed Node export
## from .tscn doesn't auto-resolve cleanly across Godot 4.x versions).
@onready var mock_ball: Node3D = $MockBall
@onready var hud_active_label: Label = $HUD/ActiveLabel

@export_group("Debug")
## When true, Team B is also human-driven via the `p2_*` action set
## (Arrow keys / RShift / Numpad-Enter). S06-D29 — debug-only, never
## ships to a real match. Toggle in the editor before launching the
## scene; runtime toggling is not supported in Sprint 6.
@export var both_human: bool = false

## How many metres a single debug ball-move keypress nudges the MockBall.
## Tasti `[` `]` `;` `'` per ±X / ±Z; `B` per posizione random sul campo.
@export var debug_ball_step_m: float = 1.0
@export var debug_ball_field_half_x: float = 30.0   ## random clamp X
@export var debug_ball_field_half_z: float = 45.0   ## random clamp Z

# ---- Runtime state -------------------------------------------------------
var team_a_root: Node3D
var team_b_root: Node3D
var team_a_ctrl: TeamController
var team_b_ctrl: TeamController
var team_a_player_ctrl: PlayerController
var team_b_player_ctrl: PlayerController  ## non-null only when both_human
var players_a: Array[Player] = []
var players_b: Array[Player] = []


func _ready() -> void:
	if team_a_config == null or team_b_config == null or formation == null:
		push_error("GameMatch: team_a_config / team_b_config / formation must be set")
		return
	if mock_ball == null:
		push_warning("GameMatch: mock_ball not wired — auto-switch will be a no-op")
	_spawn_team_a()
	_spawn_team_b()
	_print_setup_summary()


# ---- Team spawning -------------------------------------------------------

func _spawn_team_a() -> void:
	team_a_root = Node3D.new()
	team_a_root.name = "TeamA"
	add_child(team_a_root)
	players_a = _instantiate_players(team_a_root, team_a_config, false)
	team_a_player_ctrl = PlayerController.new()
	team_a_player_ctrl.name = "PlayerControllerA"
	team_a_player_ctrl.action_prefix = "p1_"
	team_a_root.add_child(team_a_player_ctrl)
	team_a_ctrl = TeamController.new()
	team_a_ctrl.name = "TeamControllerA"
	team_a_ctrl.players = players_a
	team_a_ctrl.controller = team_a_player_ctrl
	team_a_ctrl.team_config = team_a_config
	team_a_ctrl.ball_ref = mock_ball
	team_a_ctrl.is_human = true
	team_a_root.add_child(team_a_ctrl)


func _spawn_team_b() -> void:
	team_b_root = Node3D.new()
	team_b_root.name = "TeamB"
	add_child(team_b_root)
	players_b = _instantiate_players(team_b_root, team_b_config, true)
	if both_human:
		team_b_player_ctrl = PlayerController.new()
		team_b_player_ctrl.name = "PlayerControllerB"
		team_b_player_ctrl.action_prefix = "p2_"
		team_b_root.add_child(team_b_player_ctrl)
	team_b_ctrl = TeamController.new()
	team_b_ctrl.name = "TeamControllerB"
	team_b_ctrl.players = players_b
	team_b_ctrl.controller = team_b_player_ctrl  ## null when both_human=false
	team_b_ctrl.team_config = team_b_config
	team_b_ctrl.ball_ref = mock_ball
	team_b_ctrl.is_human = both_human
	team_b_root.add_child(team_b_ctrl)


func _instantiate_players(root: Node3D, team: TeamConfig, mirror_z: bool) -> Array[Player]:
	var arr: Array[Player] = []
	for i in range(formation.role_count()):
		var p: Player = PLAYER_SCENE.instantiate() as Player
		p.team_config = team
		p.role_index = i
		p.is_goalkeeper = formation.is_goalkeeper_role(i)
		p.name = "%s_%s" % [team.team_name.replace(" ", ""), formation.role_labels[i]]
		root.add_child(p)
		# Placement after add_child so global_position is well-defined.
		p.global_position = formation.get_anchor_mirrored(i) if mirror_z else formation.role_anchors[i]
		arr.append(p)
	return arr


# ---- HUD -----------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_hud()
	_handle_debug_ball_input()


# ---- Debug ball-move helpers (T06) ---------------------------------------

func _handle_debug_ball_input() -> void:
	if mock_ball == null:
		return
	if Input.is_action_just_pressed(&"debug_ball_xm"):
		move_ball_relative(-debug_ball_step_m, 0.0)
	if Input.is_action_just_pressed(&"debug_ball_xp"):
		move_ball_relative(debug_ball_step_m, 0.0)
	if Input.is_action_just_pressed(&"debug_ball_zm"):
		move_ball_relative(0.0, -debug_ball_step_m)
	if Input.is_action_just_pressed(&"debug_ball_zp"):
		move_ball_relative(0.0, debug_ball_step_m)
	if Input.is_action_just_pressed(&"debug_ball_random"):
		randomize_ball_position()


## Nudge the MockBall by (dx, dz) metres on the ground plane. Public so
## tests / other dev tooling can drive it without going through Input.
func move_ball_relative(dx: float, dz: float) -> void:
	if mock_ball == null:
		return
	var p: Vector3 = mock_ball.global_position
	mock_ball.global_position = Vector3(p.x + dx, p.y, p.z + dz)


## Teleport the MockBall to a random pitch position. Useful to provoke
## auto-switch / formation transitions during T05/T06 playtests.
func randomize_ball_position() -> void:
	if mock_ball == null:
		return
	var rx: float = randf_range(-debug_ball_field_half_x, debug_ball_field_half_x)
	var rz: float = randf_range(-debug_ball_field_half_z, debug_ball_field_half_z)
	mock_ball.global_position = Vector3(rx, mock_ball.global_position.y, rz)


func _update_hud() -> void:
	if hud_active_label == null:
		return
	var active: Player = team_a_player_ctrl.player if team_a_player_ctrl else null
	if active == null or formation == null:
		hud_active_label.text = "—"
		return
	var role: String = ""
	if active.role_index < formation.role_labels.size():
		role = formation.role_labels[active.role_index]
	var line_a: String = "P1 %s — %s   stamina: %.2f" % [
		team_a_config.team_name, role, active.stamina,
	]
	if both_human and team_b_player_ctrl != null:
		var b_active: Player = team_b_player_ctrl.player
		var b_role: String = ""
		if b_active != null and b_active.role_index < formation.role_labels.size():
			b_role = formation.role_labels[b_active.role_index]
		hud_active_label.text = "%s\nP2 %s — %s   stamina: %.2f" % [
			line_a, team_b_config.team_name,
			b_role,
			b_active.stamina if b_active else 0.0,
		]
	else:
		hud_active_label.text = line_a


# ---- Diagnostics ---------------------------------------------------------

func _print_setup_summary() -> void:
	print("[GameMatch] ready — Team A '%s' (%d players, human=%s) vs Team B '%s' (%d players, human=%s)" % [
		team_a_config.team_name,
		players_a.size(),
		team_a_ctrl.is_human,
		team_b_config.team_name,
		players_b.size(),
		team_b_ctrl.is_human,
	])
	print("[GameMatch] formation = %s, mock_ball at %s, both_human=%s" % [
		formation.formation_id,
		mock_ball.global_position if mock_ball else Vector3.INF,
		both_human,
	])
