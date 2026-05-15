extends GutTest

## Sprint 8 T05 — Goalkeeper decision + movement tests.
## All assertions hit `compute_save_decision()` (pure) or call
## `step()` directly; no SceneTree timing.

var ball: BallPhysics
var gk_player: Player
var gk: Goalkeeper


func before_each() -> void:
	ball = BallPhysics.new()
	ball.config = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	add_child(ball)
	ball.global_position = Vector3.ZERO
	gk_player = preload("res://scenes/Player.tscn").instantiate() as Player
	gk_player.is_goalkeeper = true
	gk_player.name = "GK_TEST"
	add_child(gk_player)
	# Place GK on the -Z goal line, slightly forward.
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	gk = Goalkeeper.new()
	gk.goalkeeper = gk_player
	gk.ball = ball
	gk.goal_z = -52.5  ## Team A defends -Z
	add_child(gk)


func after_each() -> void:
	for n in [gk, gk_player, ball]:
		if is_instance_valid(n):
			n.queue_free()
	gk = null
	gk_player = null
	ball = null


# ---- Idle position (R04-F05) -------------------------------------------

func test_idle_target_uses_half_ball_x() -> void:
	# Ball passing across the field (no Z velocity toward our goal)
	# → idle behaviour. After many lerp steps, GK X should converge
	# to clamp(ball.x * 0.5, -3.2, 3.2).
	ball.global_position = Vector3(4.0, 0.11, 0.0)
	ball.linear_velocity = Vector3(2.0, 0.0, 0.0)  ## sideways, not toward goal
	for _i in 200:
		gk.step(1.0 / 120.0)
	assert_almost_eq(gk_player.global_position.x, 2.0, 0.05,
		"After convergence GK X = ball.x * 0.5 (within idle clamp)")
	assert_eq(gk.get_last_decision(), &"idle",
		"Sideways ball must keep GK in idle mode")


func test_idle_clamps_to_post_width() -> void:
	# Wild ball X far outside posts → clamp to post inner.
	ball.global_position = Vector3(20.0, 0.11, 0.0)
	ball.linear_velocity = Vector3(0.0, 0.0, 0.0)
	for _i in 200:
		gk.step(1.0 / 120.0)
	assert_almost_eq(gk_player.global_position.x, gk.goal_half_width_m, 0.05,
		"Idle target X must clamp to goal_half_width_m on the +X side")


# ---- Decision branch — pure compute_save_decision ----------------------

func test_decision_idle_when_ball_not_heading_toward_goal() -> void:
	# Ball moving AWAY from -Z goal (positive Z velocity) → idle.
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.5, -10.0),
		Vector3(0.0, 0.0, 5.0))
	assert_eq(d.decision, &"idle")


func test_decision_idle_when_ball_too_slow_in_z() -> void:
	# Ball heading toward goal but below save_min_ball_speed_z_m_s.
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.3, -10.0),
		Vector3(0.0, 0.0, -1.0))  ## |vz|=1, below 4 m/s threshold
	assert_eq(d.decision, &"idle",
		"Slow ball toward goal = pass / loose, not a save scenario")


func test_decision_save_when_reachable_within_budget() -> void:
	# Ball heading at -Z, intercept_x close to GK, plenty of t_flight.
	# GK at x=0, intercept ~0.5 m off, t_flight ~1 s → easily reachable.
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.5, 0.4, -42.0),
		Vector3(0.0, 0.0, -10.0))  ## intercept_x = 0.5
	assert_eq(d.decision, &"save",
		"Easy lateral within walking budget → SAVE branch")
	assert_almost_eq(d.intercept_x, 0.5, 0.001)


func test_decision_snap_when_unreachable_by_walking() -> void:
	# Ball heading at goal with vx that puts intercept_x at the inside
	# of a post (3.0 m from GK at x=0). Short t_flight (0.3 s) leaves
	# t_av = 0.25 s. Walk budget at 6 m/s with d_eff = 2.3 m needs
	# 0.38 s — exceeds t_av → SNAP.
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.4, -45.0),
		Vector3(10.0, 0.0, -25.0))  ## intercept_x = 3.0, t_flight = 0.3 s
	assert_eq(d.decision, &"snap",
		"Far intercept inside response budget → teleport SNAP")
	assert_true(absf(d.intercept_x) <= gk.goal_half_width_m,
		"Intercept must still be inside the goal mouth to trigger snap")


func test_decision_idle_on_give_up_outside_post() -> void:
	# Predicted intercept_x > post_half_width → give up (R04-F06).
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.4, -42.0),
		Vector3(8.0, 0.0, -10.0))  ## intercept_x = 8.0 m off-post
	assert_eq(d.decision, &"idle",
		"Intercept outside post → give-up gate fires")


func test_decision_idle_on_give_up_above_crossbar() -> void:
	# Predicted height > crossbar → give up.
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	# Pick vy so predicted_height at t_flight ~1 s > 2.44 m.
	# ball.y0=0.11; vy=8 → height at 1 s = 0.11 + 8 - 0.5*9.81 ≈ 3.2 m.
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.11, -42.0),
		Vector3(0.0, 8.0, -10.0))
	assert_eq(d.decision, &"idle",
		"Predicted height above crossbar → give-up gate fires")


# ---- Snap behaviour: GK actually teleports -----------------------------

func test_snap_teleports_gk_to_intercept_x() -> void:
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	ball.global_position = Vector3(0.0, 0.4, -45.0)
	ball.linear_velocity = Vector3(10.0, 0.0, -25.0)
	gk.step(1.0 / 120.0)
	assert_eq(gk.get_last_decision(), &"snap")
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.4, -45.0),
		Vector3(10.0, 0.0, -25.0))
	assert_almost_eq(gk_player.global_position.x, d.intercept_x, 0.01,
		"On snap, GK X must equal intercept_x")


func test_catch_intercepts_ball_inside_radius() -> void:
	# Ball at GK position, low Y, with velocity → catch fires and
	# zeroes velocity, snaps ball to GK chest. Place ball where it
	# stays within catch_radius even after _perform_idle moves the
	# GK to (small_lerp_x, *, goal_z + idle_forward_offset).
	gk_player.global_position = Vector3(0.0, 0.0, -51.5)
	ball.global_position = Vector3(0.1, 0.4, -51.5)  ## directly at GK
	ball.linear_velocity = Vector3(5.0, 0.0, -3.0)
	ball._pending_linear = null
	ball._pending_teleport = null
	gk.step(1.0 / 120.0)
	assert_eq(ball._pending_linear, Vector3.ZERO,
		"Catch must zero ball velocity")
	assert_not_null(ball._pending_teleport,
		"Catch must teleport ball to GK chest")
	var tp: Vector3 = ball._pending_teleport as Vector3
	assert_almost_eq(tp.x, gk_player.global_position.x, 0.001,
		"Caught ball X must equal GK X")
	assert_almost_eq(tp.y, gk.catch_hold_height_m, 0.001,
		"Caught ball Y must equal catch_hold_height_m")
	assert_eq(gk.get_last_decision(), &"catch",
		"_last_decision should reflect the catch")


func test_catch_skipped_when_ball_above_max_height() -> void:
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	ball.global_position = Vector3(0.2, 3.0, -50.8)  ## above catch_max_height
	ball.linear_velocity = Vector3(0.0, 0.0, 0.0)
	ball._pending_linear = null
	ball._pending_teleport = null
	gk.step(1.0 / 120.0)
	# State machine still ran (idle), but no catch.
	assert_ne(gk.get_last_decision(), &"catch",
		"Ball above catch_max_height_m must NOT be caught")


func test_catch_skipped_when_ball_outside_radius() -> void:
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	ball.global_position = Vector3(3.0, 0.4, -50.0)  ## > catch_radius (0.7)
	ball.linear_velocity = Vector3.ZERO
	ball._pending_linear = null
	ball._pending_teleport = null
	gk.step(1.0 / 120.0)
	assert_ne(gk.get_last_decision(), &"catch",
		"Ball outside catch_radius must NOT be caught")


func test_player_state_marks_saving_during_save_or_snap() -> void:
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	ball.global_position = Vector3(0.5, 0.4, -42.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -10.0)
	gk.step(1.0 / 120.0)
	assert_eq(gk_player.state, Player.State.SAVING,
		"Player.state must read SAVING during a save action")
