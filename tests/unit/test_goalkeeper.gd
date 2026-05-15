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


func test_decision_idle_when_ball_essentially_still_in_z() -> void:
	# Ball heading toward goal but below save_min_ball_speed_z_m_s
	# (loose-ball settling). With save_min lowered to 0.5 m/s in
	# fix2, the threshold catches only essentially-still balls.
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.3, -10.0),
		Vector3(0.0, 0.0, -0.2))  ## |vz|=0.2, below 0.5 m/s threshold
	assert_eq(d.decision, &"idle",
		"Essentially still ball = loose, not a save scenario")


func test_decision_idle_when_ball_outside_shot_zone() -> void:
	# Ball heading toward goal at a savable speed BUT far from goal
	# line (> shot_zone_m). Midfield clearance — GK stays idle.
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.3, -10.0),  ## |dz| = 42.5 m, > 25 m shot zone
		Vector3(0.0, 0.0, -10.0))
	assert_eq(d.decision, &"idle",
		"Ball outside shot_zone_m must NOT trigger save mode")


func test_decision_save_for_slow_shot_near_post() -> void:
	# Regression: playtest 2026-05-15 — slow shot near post, GK was
	# idle and let it pass. Slow vz (-2 m/s) inside shot zone with
	# intercept near post must trigger save (not idle).
	gk_player.global_position = Vector3(1.0, 0.0, -51.0)
	var d: Dictionary = gk.compute_save_decision(
		Vector3(2.5, 0.3, -45.0),
		Vector3(0.0, 0.0, -2.0))
	assert_ne(d.decision, &"idle",
		"Slow shot near post inside shot zone must trigger save / snap")
	assert_almost_eq(d.intercept_x, 2.5, 0.001,
		"Intercept X must equal ball.x + vx*t = 2.5 (vx=0)")


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


# ---- Post-catch hold + speed-clamped idle (fix3) -----------------------

func test_idle_uses_speed_clamped_step_not_lerp() -> void:
	# After fix3, idle re-positioning uses idle_max_speed_m_s (2.0)
	# instead of a per-tick lerp. Travel from x=0 to clamped target
	# 2.0 (ball at x=4) must take ~1.0 s, not a single-tick snap.
	gk_player.global_position = Vector3(0.0, 0.0, -51.5)
	ball.global_position = Vector3(4.0, 0.11, 0.0)
	ball.linear_velocity = Vector3.ZERO  ## sideways = idle
	# After 0.10 s of 1/120 s ticks: max possible drift = 2.0 * 0.10 = 0.20 m.
	for _i in 12:
		gk.step(1.0 / 120.0)
	assert_lt(gk_player.global_position.x, 0.25,
		"After 0.10 s GK must have drifted ≤ idle_max_speed_m_s * dt total")


func test_post_catch_hold_freezes_gk_position() -> void:
	# Catch arms post_catch_hold_s window — during it, GK stays put
	# even if ball.x changes radically.
	gk_player.global_position = Vector3(2.0, 0.0, -51.5)
	ball.global_position = Vector3(2.0, 0.4, -51.5)  ## triggers catch
	ball.linear_velocity = Vector3.ZERO
	gk.step(1.0 / 120.0)
	assert_eq(gk.get_last_decision(), &"catch", "Sanity: catch fired")
	assert_gt(gk._post_catch_hold_remaining_s, 0.0,
		"Catch must arm the post-catch hold timer")
	# Move ball way off (simulates pickup or rebound) and tick — GK
	# must not slide.
	ball.global_position = Vector3(-3.0, 0.11, -45.0)
	ball.linear_velocity = Vector3.ZERO
	var x_before: float = gk_player.global_position.x
	for _i in 30:  ## 0.25 s — well inside hold (0.6 s default)
		gk.step(1.0 / 120.0)
	assert_almost_eq(gk_player.global_position.x, x_before, 0.001,
		"During hold, GK X must not change despite ball X change")


# ---- T06 NBA Jam catch-up boost (R09-F02 — schema only) ----------------

func test_catchup_boost_disabled_by_default() -> void:
	# Default ctor → catchup_boost_enabled = false. Effective reaction
	# buffer must equal the raw reaction_buffer_s.
	assert_false(gk.catchup_boost_enabled,
		"catchup_boost_enabled must default to false in Sprint 8")
	assert_eq(gk.get_effective_reaction_buffer_s(), gk.reaction_buffer_s,
		"With boost disabled, effective buffer = raw buffer")


func test_catchup_eligibility_returns_false_without_scoreboard() -> void:
	# Sprint 8 stub — eligibility always false (no scoreboard yet).
	# Even when catchup_boost_enabled is on, the boost stays inert.
	gk.catchup_boost_enabled = true
	assert_false(gk.is_catchup_eligible(),
		"Sprint 8 eligibility stub must always return false")
	assert_eq(gk.get_effective_reaction_buffer_s(), gk.reaction_buffer_s,
		"Effective buffer unchanged while eligibility returns false")


func test_player_state_marks_saving_during_save_or_snap() -> void:
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	ball.global_position = Vector3(0.5, 0.4, -42.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -10.0)
	gk.step(1.0 / 120.0)
	assert_eq(gk_player.state, Player.State.SAVING,
		"Player.state must read SAVING during a save action")
