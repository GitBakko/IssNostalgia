extends GutTest

## Sprint 7 T04 — PassingController target selection + auto-spin tests.
## Drives `try_pass` / `select_pass_target` / `compute_pass_target_position`
## directly with explicit positions; no global Input poll.

const FORMATION_PATH := "res://resources/formations/formation_2_1_1.tres"
const TEAM_A_PATH := "res://resources/teams/team_a.tres"

var ball: BallPhysics
var team_a: TeamController
var controller_a: PlayerController
var bc: BallController
var launcher: BallLauncher
var pc: PassingController
var players_a: Array[Player] = []
var captured_target: Vector3 = Vector3.INF
var captured_distance: float = -1.0
var captured_target_player: Player = null


func before_each() -> void:
	var fa: FormationData = load(FORMATION_PATH) as FormationData
	var ta: TeamConfig = (load(TEAM_A_PATH) as TeamConfig).duplicate(true)
	ball = BallPhysics.new()
	ball.config = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	add_child(ball)
	ball.global_position = Vector3.ZERO
	for i in range(fa.role_count()):
		var p: Player = preload("res://scenes/Player.tscn").instantiate() as Player
		p.team_config = ta
		p.role_index = i
		p.is_goalkeeper = fa.is_goalkeeper_role(i)
		add_child(p)
		p.global_position = fa.role_anchors[i]
		players_a.append(p)
	controller_a = PlayerController.new()
	controller_a.player = players_a[0]  ## DEF_LEFT — active passer
	add_child(controller_a)
	team_a = TeamController.new()
	team_a.players = players_a
	team_a.team_config = ta
	team_a.controller = controller_a
	team_a.ball_ref = ball
	team_a.is_human = true
	add_child(team_a)
	bc = BallController.new()
	bc.ball = ball
	bc.teams = [team_a]
	add_child(bc)
	launcher = BallLauncher.new()
	launcher.ball_path = ball.get_path()
	add_child(launcher)
	pc = PassingController.new()
	pc.team_controller = team_a
	pc.ball_controller = bc
	pc.ball_launcher = launcher
	add_child(pc)
	pc.pass_fired.connect(_on_pass_fired)
	bc._assign_carrier(players_a[0])  ## active carries the ball
	captured_target = Vector3.INF
	captured_distance = -1.0
	captured_target_player = null


func after_each() -> void:
	for p in players_a:
		if is_instance_valid(p):
			p.queue_free()
	for n in [ball, team_a, controller_a, bc, launcher, pc]:
		if is_instance_valid(n):
			n.queue_free()
	players_a.clear()
	ball = null
	team_a = null
	controller_a = null
	bc = null
	launcher = null
	pc = null


func _on_pass_fired(target_position: Vector3, distance: float, target_player: Player) -> void:
	captured_target = target_position
	captured_distance = distance
	captured_target_player = target_player


# ---- target selection ---------------------------------------------------

func test_target_within_cone_selected() -> void:
	# Active at origin facing -Z. Place teammate forward (-Z direction).
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	# Default basis: -Z is forward — already correct for spawned Player.
	players_a[1].global_position = Vector3(0.0, 0.0, -10.0)  ## directly forward
	# Park other teammates far to the side / behind.
	players_a[2].global_position = Vector3(50.0, 0.0, 0.0)
	players_a[3].global_position = Vector3(0.0, 0.0, 50.0)   ## behind
	var picked: Player = pc.select_pass_target(active)
	assert_eq(picked, players_a[1], "Teammate directly ahead must be selected")


func test_target_outside_cone_ignored() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	# Place all other outfield teammates BEHIND the active.
	players_a[1].global_position = Vector3(0.0, 0.0, +10.0)
	players_a[2].global_position = Vector3(+50.0, 0.0, +50.0)
	players_a[3].global_position = Vector3(-50.0, 0.0, +50.0)
	var picked: Player = pc.select_pass_target(active)
	assert_null(picked,
		"No teammate in forward 90° cone → select_pass_target returns null")


func test_target_picks_nearest_in_cone() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	# Two teammates in cone — closer one should win.
	players_a[1].global_position = Vector3(0.0, 0.0, -8.0)   ## near
	players_a[2].global_position = Vector3(0.0, 0.0, -20.0)  ## far
	players_a[3].global_position = Vector3(50.0, 0.0, 50.0)  ## out
	var picked: Player = pc.select_pass_target(active)
	assert_eq(picked, players_a[1], "Nearest in-cone teammate wins")


func test_select_excludes_goalkeeper() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	# GK directly forward, no other teammate in cone.
	players_a[4].global_position = Vector3(0.0, 0.0, -5.0)   ## GK in cone
	for i in [1, 2, 3]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)  ## behind
	var picked: Player = pc.select_pass_target(active)
	assert_null(picked, "Goalkeeper must be excluded from pass targets")


# ---- fallback target ----------------------------------------------------

func test_fallback_when_no_teammate_in_cone() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	# All teammates behind.
	for i in [1, 2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
	var target_pos: Vector3 = pc.compute_pass_target_position(active, null)
	# Default facing -Z, fallback distance 10 → expect (0, 0, -10).
	assert_almost_eq(target_pos.x, 0.0, 0.05)
	assert_almost_eq(target_pos.z, -10.0, 0.05)


func test_target_position_uses_teammate_when_present() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	players_a[1].global_position = Vector3(0.0, 0.0, -7.5)
	var target_pos: Vector3 = pc.compute_pass_target_position(active, players_a[1])
	assert_eq(target_pos, players_a[1].global_position)


# ---- spin auto by distance ---------------------------------------------

func test_pass_short_distance_uses_backspin() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	# Place teammate at 5 m — grounder range (< 8 m).
	players_a[1].global_position = Vector3(0.0, 0.0, -5.0)
	for i in [2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
	var ok: bool = pc.try_pass()
	assert_true(ok)
	var spin: Vector3 = ball._pending_angular as Vector3
	# compose_spin with topspin = -3 → top axis = UP × dir = UP × -Z = +X
	# spin = +X * -3 = (-3, 0, 0). Magnitude 3.
	assert_almost_eq(spin.length(), 3.0, 0.1,
		"Short-distance pass (< 8 m) must use backspin |ω| = 3 rad/s, got %s" % spin)


func test_pass_long_distance_uses_topspin() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	players_a[1].global_position = Vector3(0.0, 0.0, -20.0)  ## > 15 m lob
	for i in [2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
	var ok: bool = pc.try_pass()
	assert_true(ok)
	var spin: Vector3 = ball._pending_angular as Vector3
	assert_almost_eq(spin.length(), 4.0, 0.1,
		"Long-distance pass (> 15 m) must use topspin |ω| = 4 rad/s, got %s" % spin)


func test_pass_mid_distance_uses_zero_spin() -> void:
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	players_a[1].global_position = Vector3(0.0, 0.0, -11.0)  ## 8 < d < 15
	for i in [2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
	var ok: bool = pc.try_pass()
	assert_true(ok)
	assert_eq(ball._pending_angular, Vector3.ZERO,
		"Mid-distance pass must have ZERO spin")


# ---- requires possession ------------------------------------------------

func test_pass_noop_when_active_does_not_carry_ball() -> void:
	bc._clear_carrier_flag()
	bc._carrier = null
	var ok: bool = pc.try_pass()
	assert_false(ok, "Pass without possession returns false")


# ---- receiver pre-orientation (R09-F04) --------------------------------

func test_pass_arms_facing_warp_on_target_receiver() -> void:
	# Real-football realism: when the pass FIRES, the targeted teammate
	# starts turning toward the passer BEFORE the ball arrives.
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	players_a[1].global_position = Vector3(0.0, 0.0, -10.0)  ## target ahead
	for i in [2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
	# Sanity: receiver starts with NO warp armed.
	assert_eq(players_a[1]._facing_warp_remaining_s, 0.0)
	var ok: bool = pc.try_pass()
	assert_true(ok)
	assert_gt(players_a[1]._facing_warp_remaining_s, 0.0,
		"Pass-fire must arm a facing warp on the target receiver")
	# After ~150 ms of update_facing the receiver should be looking
	# (mostly) toward the passer (+Z direction in this fixture).
	# S07-T06: read VisualRoot facing, not the CharacterBody3D basis.
	for _i in 18:
		players_a[1].update_facing(1.0 / 120.0)
	var forward: Vector3 = players_a[1].get_visual_forward()
	assert_almost_eq(forward.z, 1.0, 0.05,
		"Receiver must end up facing toward the passer (+Z here)")


func test_pass_switches_active_to_receiver_after_anim_ends() -> void:
	# Glitch from playtest: after pass-fire, manual_override on the
	# passer kept the user stuck on the passer for ~2 s while the ball
	# was already at the receiver. Fix: PassingController explicitly
	# switches the team's active player to the target receiver when
	# the pass-anim window expires.
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	players_a[1].global_position = Vector3(0.0, 0.0, -10.0)
	for i in [2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
	# Sanity — controller starts on players_a[0].
	assert_eq(team_a.active_index, 0)
	pc.try_pass()
	# Drain the pass-anim window (default 100 ms). 18 ticks ≈ 150 ms.
	for _i in 18:
		pc._physics_process(1.0 / 120.0)
	assert_eq(team_a.active_index, 1,
		"After pass-anim ends, active must switch to the target receiver")
	assert_eq(controller_a.player, players_a[1],
		"PlayerController must be re-pointed at the new active")


func test_pass_does_not_warp_anyone_on_fallback() -> void:
	# No teammate in cone → fallback pass to "10 m forward". No specific
	# receiver, so no facing warp on any teammate.
	var active: Player = players_a[0]
	active.global_position = Vector3.ZERO
	for i in [1, 2, 3, 4]:
		players_a[i].global_position = Vector3(0.0, 0.0, +50.0)
		players_a[i].get_node(^"VisualRoot").transform.basis = Basis.IDENTITY
	pc.try_pass()
	for i in [1, 2, 3, 4]:
		assert_eq(players_a[i]._facing_warp_remaining_s, 0.0,
			"Fallback pass must NOT warp any teammate's facing")


# ---- pass-anim gate -----------------------------------------------------

func test_pass_sets_is_passing_flag_for_anim_duration() -> void:
	players_a[1].global_position = Vector3(0.0, 0.0, -7.0)
	pc.try_pass()
	assert_true(controller_a.is_passing,
		"try_pass must set controller.is_passing (auto-switch gate)")
	assert_eq(players_a[0].state, Player.State.PASSING)
	for _i in 18:  ## ~150 ms > 100 ms anim
		pc._physics_process(1.0 / 120.0)
	assert_false(controller_a.is_passing)
