extends GutTest

## Sprint 7 T02 — BallController possession arbitration tests.
## Drives `step()` directly with explicit positions; no SceneTree timing.

const FORMATION_PATH := "res://resources/formations/formation_2_1_1.tres"
const TEAM_A_PATH := "res://resources/teams/team_a.tres"
const TEAM_B_PATH := "res://resources/teams/team_b.tres"

var ball: BallPhysics
var team_a: TeamController
var team_b: TeamController
var controller_a: PlayerController
var bc: BallController
var players_a: Array[Player] = []
var players_b: Array[Player] = []


func before_each() -> void:
	var fa: FormationData = load(FORMATION_PATH) as FormationData
	var ta: TeamConfig = (load(TEAM_A_PATH) as TeamConfig).duplicate(true)
	var tb: TeamConfig = (load(TEAM_B_PATH) as TeamConfig).duplicate(true)
	# Spawn ball
	ball = BallPhysics.new()
	ball.config = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	add_child(ball)
	ball.global_position = Vector3.ZERO
	# Spawn teams (5 players each, formation anchors)
	players_a = _spawn_team(ta, fa, false)
	players_b = _spawn_team(tb, fa, true)
	# Per-team controllers (PlayerController only for human side; B has none in T05 default)
	controller_a = PlayerController.new()
	controller_a.player = players_a[0]
	add_child(controller_a)
	team_a = _make_team_ctrl(players_a, ta, controller_a, true)
	team_b = _make_team_ctrl(players_b, tb, null, false)
	# BallController
	bc = BallController.new()
	bc.ball = ball
	bc.teams = [team_a, team_b]
	add_child(bc)
	# _ready re-orders teams (humans first).


func after_each() -> void:
	for p in players_a + players_b:
		if is_instance_valid(p):
			p.queue_free()
	for n in [ball, team_a, team_b, controller_a, bc]:
		if is_instance_valid(n):
			n.queue_free()
	players_a.clear()
	players_b.clear()
	ball = null
	team_a = null
	team_b = null
	controller_a = null
	bc = null


func _spawn_team(team_cfg: TeamConfig, fa: FormationData, mirror: bool) -> Array[Player]:
	var arr: Array[Player] = []
	for i in range(fa.role_count()):
		var p: Player = preload("res://scenes/Player.tscn").instantiate() as Player
		p.team_config = team_cfg
		p.role_index = i
		p.is_goalkeeper = fa.is_goalkeeper_role(i)
		add_child(p)
		var anchor: Vector3 = fa.get_anchor_mirrored(i) if mirror else fa.role_anchors[i]
		p.global_position = anchor
		arr.append(p)
	return arr


func _make_team_ctrl(players: Array[Player], cfg: TeamConfig,
		ctrl: PlayerController, is_human: bool) -> TeamController:
	var tc: TeamController = TeamController.new()
	tc.players = players
	tc.team_config = cfg
	tc.controller = ctrl
	tc.ball_ref = ball
	tc.is_human = is_human
	add_child(tc)
	return tc


# ---- pickup gates -------------------------------------------------------

func test_pickup_when_in_range_and_slow() -> void:
	# Park player[0] right on the ball, ball at rest.
	players_a[0].global_position = Vector3(0.0, 0.0, 0.0)
	ball.global_position = Vector3(0.5, 0.11, 0.0)  # 0.5 m offset, inside 0.8
	ball.linear_velocity = Vector3.ZERO
	bc.step(0.0)
	assert_eq(bc.get_carrier(), players_a[0],
		"Slow ball within 0.8 m must be picked up")
	assert_true(players_a[0].has_ball, "Player.has_ball flag mirrored true")


func test_no_pickup_when_ball_too_fast() -> void:
	players_a[0].global_position = Vector3.ZERO
	ball.global_position = Vector3(0.3, 0.11, 0.0)  # in range
	ball.linear_velocity = Vector3(15.0, 0.0, 0.0)  # > 12 m/s gate
	bc.step(0.0)
	assert_null(bc.get_carrier(),
		"Fast ball (> 12 m/s) must NOT trigger pickup")


func test_no_pickup_when_player_far() -> void:
	players_a[0].global_position = Vector3(10.0, 0.0, 0.0)
	for p in players_a + players_b:
		if p != players_a[0]:
			p.global_position = Vector3(50.0, 0.0, 50.0)  # park far
	ball.global_position = Vector3.ZERO
	ball.linear_velocity = Vector3.ZERO
	bc.step(0.0)
	assert_null(bc.get_carrier(),
		"No player within 0.8 m must result in no pickup")


func test_pickup_skips_goalkeepers() -> void:
	# Park GK on the ball; outfield far away.
	for p in players_a + players_b:
		p.global_position = Vector3(50.0, 0.0, 50.0)
	players_a[4].global_position = Vector3.ZERO  # GK index = 4
	ball.global_position = Vector3(0.3, 0.11, 0.0)
	ball.linear_velocity = Vector3.ZERO
	bc.step(0.0)
	assert_null(bc.get_carrier(),
		"GK must NOT be selectable as carrier in Sprint 7")


# ---- tie-breaker --------------------------------------------------------

func test_human_team_wins_simultaneous_pickup() -> void:
	# Park one player from each team equally close to the ball.
	players_a[0].global_position = Vector3(0.4, 0.0, 0.0)
	players_b[0].global_position = Vector3(-0.4, 0.0, 0.0)
	for p in players_a + players_b:
		if p != players_a[0] and p != players_b[0]:
			p.global_position = Vector3(50.0, 0.0, 50.0)
	ball.global_position = Vector3.ZERO
	ball.linear_velocity = Vector3.ZERO
	bc.step(0.0)
	assert_eq(bc.get_carrier(), players_a[0],
		"Human team A must win tie against AI team B (S06-D03)")


# ---- carry sync --------------------------------------------------------

func test_carry_position_offset_in_front_of_player() -> void:
	# Force possession, then step and check teleport target.
	players_a[0].global_position = Vector3(0.0, 0.0, 0.0)
	# Default basis: -Z is forward. carry_offset = (0, -0.2, 0.5).
	# After basis * offset, world offset = (0, -0.2, 0.5).
	bc._assign_carrier(players_a[0])
	bc.step(0.0)
	# teleport_to stages _pending_teleport on the ball.
	assert_eq(ball._pending_teleport,
		players_a[0].global_position + Vector3(0.0, -0.2, 0.5),
		"Carry sync must stage teleport to player_pos + basis*offset")


# ---- release proxy ------------------------------------------------------

func test_request_release_clears_carrier_and_calls_ball_release() -> void:
	bc._assign_carrier(players_a[0])
	assert_true(bc.is_carried())
	assert_true(players_a[0].has_ball)
	bc.request_release(Vector3(8.0, 4.0, 0.0))
	assert_null(bc.get_carrier(),
		"After request_release, BallController carrier must be null")
	assert_false(players_a[0].has_ball,
		"Player.has_ball flag must clear on release")
	assert_eq(ball._pending_linear, Vector3(8.0, 4.0, 0.0),
		"BallPhysics.release stages the launch velocity")


func test_request_release_noop_when_no_carrier() -> void:
	# Should not crash when no one carries the ball.
	bc.request_release(Vector3(8.0, 4.0, 0.0))
	assert_null(bc.get_carrier())
	assert_eq(ball._pending_linear, null,
		"No carrier → no launch state staged")
