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
##
## `mock_ball: Node3D` until Sprint 7 T05 — now the real Ball.tscn
## (RigidBody3D + BallPhysics custom integrator) from Phase 1. Tests +
## debug code reference it as `ball`.
@onready var ball: BallPhysics = $Ball
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

# ---- Sprint 7 controllers ------------------------------------------------
var ball_controller: BallController
var ball_launcher: BallLauncher
var team_a_shooter: ShootingController
var team_a_passer: PassingController
var team_b_shooter: ShootingController  ## non-null only when both_human
var team_b_passer: PassingController
var players_a: Array[Player] = []
var players_b: Array[Player] = []


func _ready() -> void:
	if team_a_config == null or team_b_config == null or formation == null:
		push_error("GameMatch: team_a_config / team_b_config / formation must be set")
		return
	if ball == null:
		push_warning("GameMatch: ball not wired — auto-switch / shoot / pass will be no-ops")
	_spawn_team_a()
	_spawn_team_b()
	_spawn_ball_controllers()
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
	team_a_ctrl.ball_ref = ball
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
	team_b_ctrl.ball_ref = ball
	team_b_ctrl.is_human = both_human
	team_b_root.add_child(team_b_ctrl)


func _spawn_ball_controllers() -> void:
	if ball == null:
		return
	# 1 BallController per match
	ball_controller = BallController.new()
	ball_controller.name = "BallController"
	ball_controller.ball = ball
	var teams_arr: Array[TeamController] = [team_a_ctrl, team_b_ctrl]
	ball_controller.teams = teams_arr
	ball_controller.debug_log = false  ## T05 diagnostic — flip true when re-debugging
	add_child(ball_controller)
	# 1 BallLauncher per match — used by PassingControllers to compute
	# lob velocity via the iterative drag-aware solver.
	ball_launcher = BallLauncher.new()
	ball_launcher.name = "BallLauncher"
	ball_launcher.ball_path = ball.get_path()
	add_child(ball_launcher)
	# Per-team shoot + pass controllers — only on teams that have a
	# PlayerController (Team A always; Team B only when both_human=true).
	var team_a_pair: Dictionary = _spawn_team_shoot_pass(team_a_root, team_a_ctrl, "A")
	team_a_shooter = team_a_pair.shoot
	team_a_passer = team_a_pair.pass_
	if both_human and team_b_player_ctrl != null:
		var team_b_pair: Dictionary = _spawn_team_shoot_pass(team_b_root, team_b_ctrl, "B")
		team_b_shooter = team_b_pair.shoot
		team_b_passer = team_b_pair.pass_


func _spawn_team_shoot_pass(root: Node3D, tc: TeamController, label: String) -> Dictionary:
	var sc: ShootingController = ShootingController.new()
	sc.name = "ShootingController" + label
	sc.team_controller = tc
	sc.ball_controller = ball_controller
	sc.debug_log = false  ## T05 diagnostic — flip true when re-debugging
	root.add_child(sc)
	var pc: PassingController = PassingController.new()
	pc.name = "PassingController" + label
	pc.team_controller = tc
	pc.ball_controller = ball_controller
	pc.ball_launcher = ball_launcher
	pc.debug_log = false  ## T05 diagnostic — flip true when re-debugging
	root.add_child(pc)
	return {"shoot": sc, "pass_": pc}


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
	if Input.is_action_just_pressed(&"ui_cancel"):
		get_tree().quit()


# ---- Debug ball-move helpers (T06) ---------------------------------------

func _handle_debug_ball_input() -> void:
	if ball == null:
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


## Nudge the ball by (dx, dz) metres on the ground plane. Public so tests
## / dev tooling can drive it without going through Input. Goes through
## `BallPhysics.teleport_to` so the integrator pipeline (and the
## release-from-carry case) stays consistent.
func move_ball_relative(dx: float, dz: float) -> void:
	if ball == null:
		return
	var p: Vector3 = ball.global_position
	ball.teleport_to(Vector3(p.x + dx, p.y, p.z + dz))


## Teleport the ball to a random pitch position. Useful to provoke
## auto-switch / formation transitions during playtests.
func randomize_ball_position() -> void:
	if ball == null:
		return
	var rx: float = randf_range(-debug_ball_field_half_x, debug_ball_field_half_x)
	var rz: float = randf_range(-debug_ball_field_half_z, debug_ball_field_half_z)
	ball.teleport_to(Vector3(rx, ball.global_position.y, rz))


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
	var ball_line: String = ""
	if ball_controller != null and ball_controller.is_carried():
		var carrier: Player = ball_controller.get_carrier()
		ball_line = "BALL: carried by %s" % carrier.name
	elif ball != null:
		ball_line = "BALL: |v| %.1f m/s" % ball.linear_velocity.length()
	var fps_line: String = "FPS %d   /  phys %d Hz" % [
		Engine.get_frames_per_second(),
		Engine.physics_ticks_per_second,
	]
	if both_human and team_b_player_ctrl != null:
		var b_active: Player = team_b_player_ctrl.player
		var b_role: String = ""
		if b_active != null and b_active.role_index < formation.role_labels.size():
			b_role = formation.role_labels[b_active.role_index]
		hud_active_label.text = "%s\nP2 %s — %s   stamina: %.2f\n%s\n%s" % [
			line_a, team_b_config.team_name,
			b_role,
			b_active.stamina if b_active else 0.0,
			ball_line,
			fps_line,
		]
	else:
		hud_active_label.text = "%s\n%s\n%s" % [line_a, ball_line, fps_line]


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
	print("[GameMatch] formation = %s, ball at %s, both_human=%s" % [
		formation.formation_id,
		ball.global_position if ball else Vector3.INF,
		both_human,
	])
