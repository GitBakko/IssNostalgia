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
## When true, Team B is also human (debug only — alt InputMap binds added in
## T06). Sprint 6 default = false; the human-only flow is the primary loop.
@export var both_human: bool = false

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
	# T05: Team B is AI — no PlayerController. T06 adds the p2_ controller
	# under the both_human flag.
	team_b_ctrl = TeamController.new()
	team_b_ctrl.name = "TeamControllerB"
	team_b_ctrl.players = players_b
	team_b_ctrl.controller = null
	team_b_ctrl.team_config = team_b_config
	team_b_ctrl.ball_ref = mock_ball
	team_b_ctrl.is_human = false
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
	hud_active_label.text = "ACTIVE: %s — %s   stamina: %.2f" % [
		team_a_config.team_name,
		role,
		active.stamina,
	]


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
	# InputMap diagnostic — confirms project.godot actions are registered.
	for suffix in PlayerController.ACTION_SUFFIXES:
		var full: StringName = StringName("p1_" + String(suffix))
		print("[GameMatch] InputMap.has_action(%s) = %s" % [full, InputMap.has_action(full)])
