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


func test_decision_handles_diagonal_just_outside_post() -> void:
	# Regression: playtest 2026-05-15 — diagonal shot lands just
	# beyond the post at the kinematic level but inside the dive
	# reach (post + catch_radius). Must NOT give up.
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	# Ball at (0, 0.3, -45), vel (10, 0, -10). t_flight = 1.0 s,
	# kinematic intercept = 10 → way outside post. Pick a softer
	# vx that lands just beyond the post.
	# vx=3.5, t_flight=1.0 → kinematic intercept = 3.5. Outside
	# 3.2 post but inside 3.9 (3.2 + 0.7) save zone → must save.
	var d: Dictionary = gk.compute_save_decision(
		Vector3(0.0, 0.3, -42.5),
		Vector3(3.5, 0.0, -10.0))
	assert_ne(d.decision, &"idle",
		"Diagonal landing within post + catch_radius must NOT give up")


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
	# step() uses the drag-aware path, so GK X must match the drag-
	# aware intercept (slightly less than the kinematic 3.0 due to
	# air drag over the 0.3 s flight).
	var d: Dictionary = gk._predict_intercept_drag_aware(
		Vector3(0.0, 0.4, -45.0),
		Vector3(10.0, 0.0, -25.0))
	assert_almost_eq(gk_player.global_position.x, d.intercept_x, 0.01,
		"On snap, GK X must equal drag-aware intercept_x")


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


func test_idle_holds_position_when_giving_up_on_wide_shot() -> void:
	# Wide diagonal — intercept beyond save_zone → idle. GK must
	# HOLD position, not drift toward the off-target ball
	# (test 5 playtest 2026-05-15).
	gk_player.global_position = Vector3(0.0, 0.0, -51.5)
	# Trigger a give-up via predict: ball at (0, 0.3, -45), vel
	# (15, 0, -10) → t_flight = 1.0 s, intercept_x kinematic = 15.
	# Way outside save_zone (3.9). Decision = idle, but we stayed
	# in shot zone so _giving_up_on_shot must arm.
	ball.global_position = Vector3(0.0, 0.3, -45.0)
	ball.linear_velocity = Vector3(15.0, 0.0, -10.0)
	gk.step(1.0 / 120.0)
	assert_eq(gk.get_last_decision(), &"idle")
	assert_true(gk._giving_up_on_shot,
		"Wide-shot give-up must set _giving_up_on_shot")
	var x_before: float = gk_player.global_position.x
	# Now move ball further wide and tick — GK X must NOT drift.
	for _i in 30:  ## 0.25 s
		ball.global_position = Vector3(ball.global_position.x + 0.5,
			ball.global_position.y, ball.global_position.z)
		gk.step(1.0 / 120.0)
	assert_almost_eq(gk_player.global_position.x, x_before, 0.001,
		"Give-up hold must keep GK X frozen")


# ---- DEBUG auto-return-to-shooter (TEMP playtest aid) ------------------

func test_debug_return_kicks_ball_back_to_last_shooter() -> void:
	# Stub a ball_controller that reports a fake shooter.
	var shooter: Player = preload("res://scenes/Player.tscn").instantiate() as Player
	add_child(shooter)
	shooter.global_position = Vector3(0.0, 0.0, -10.0)  ## up-pitch from GK
	# Minimal BallController stand-in: only need get_last_released_carrier.
	var bc: BallController = BallController.new()
	bc.ball = ball
	bc._last_released_carrier = shooter
	add_child(bc)
	gk.ball_controller = bc
	gk.debug_return_ball_enabled = true
	gk.debug_return_delay_s = 0.1  ## tighten test
	gk.post_catch_hold_s = 0.05
	# Trigger a catch.
	gk_player.global_position = Vector3(2.0, 0.0, -51.5)
	ball.global_position = Vector3(2.0, 0.4, -51.5)
	ball.linear_velocity = Vector3.ZERO
	gk.step(1.0 / 120.0)
	assert_eq(gk.get_last_decision(), &"catch")
	assert_eq(gk._debug_return_target, shooter,
		"Debug return must capture the last shooter on catch")
	# Drain the timer.
	for _i in 30:  ## 0.25 s — well past 0.05 + 0.1 = 0.15 s
		ball._pending_linear = null
		gk.step(1.0 / 120.0)
		if gk.get_last_decision() == &"debug_return":
			break
	assert_eq(gk.get_last_decision(), &"debug_return",
		"Debug return must fire after post_catch_hold + debug_return_delay")
	assert_not_null(ball._pending_linear,
		"Debug return must stage a launch velocity")
	var v: Vector3 = ball._pending_linear as Vector3
	assert_gt(v.z, 0.0,
		"Pass velocity must point toward shooter (positive Z from GK at -Z goal)")
	assert_gt(v.y, 0.0,
		"Pass must include a small lift component")
	bc.queue_free()
	shooter.queue_free()


# ---- T06 NBA Jam catch-up boost (R09-F02 — schema only) ----------------

func test_catchup_boost_default_enabled_after_t04() -> void:
	# Sprint 9 T04 — runtime wired, boost enabled by default.
	# Without scoreboard / clock injection, eligibility still false
	# (NULL-safe), so effective buffer = raw buffer.
	assert_true(gk.catchup_boost_enabled,
		"catchup_boost_enabled defaults to true after T04 runtime wiring")
	assert_eq(gk.get_effective_reaction_buffer_s(), gk.reaction_buffer_s,
		"Without scoreboard/clock, eligibility false → raw buffer")


func test_catchup_inactive_when_score_gap_below_threshold() -> void:
	var sb: Scoreboard = Scoreboard.new()
	add_child(sb)
	var mc: MatchClock = MatchClock.new()
	mc.match_duration_s = 60.0
	mc.auto_start = false
	add_child(mc)
	gk.scoreboard = sb
	gk.match_clock = mc
	gk.my_team_id = Scoreboard.TEAM_A
	# Tied → gap = 0 < threshold (2) → not eligible.
	mc.current_time_remaining_s = 30.0  ## inside final-window
	assert_false(gk.is_catchup_eligible(),
		"Tied score must NOT trigger catch-up")
	sb.queue_free()
	mc.queue_free()


func test_catchup_inactive_when_time_above_threshold() -> void:
	var sb: Scoreboard = Scoreboard.new()
	add_child(sb)
	var mc: MatchClock = MatchClock.new()
	mc.auto_start = false
	add_child(mc)
	gk.scoreboard = sb
	gk.match_clock = mc
	gk.my_team_id = Scoreboard.TEAM_A
	# Trailing by 3 but match still has 120 s → not eligible
	# (time_remaining_threshold_s default = 60.0).
	sb.register_goal(Scoreboard.TEAM_B)
	sb.register_goal(Scoreboard.TEAM_B)
	sb.register_goal(Scoreboard.TEAM_B)
	mc.current_time_remaining_s = 120.0
	assert_false(gk.is_catchup_eligible(),
		"Trailing but outside final window → not eligible")
	sb.queue_free()
	mc.queue_free()


func test_catchup_active_when_trailing_in_final_window() -> void:
	var sb: Scoreboard = Scoreboard.new()
	add_child(sb)
	var mc: MatchClock = MatchClock.new()
	mc.auto_start = false
	add_child(mc)
	gk.scoreboard = sb
	gk.match_clock = mc
	gk.my_team_id = Scoreboard.TEAM_A
	sb.register_goal(Scoreboard.TEAM_B)
	sb.register_goal(Scoreboard.TEAM_B)  ## A trailing by 2
	mc.current_time_remaining_s = 30.0   ## inside 60 s window
	assert_true(gk.is_catchup_eligible(),
		"Trailing by ≥2 in final window must trigger catch-up")
	sb.queue_free()
	mc.queue_free()


func test_get_effective_reaction_buffer_uses_factor_when_eligible() -> void:
	var sb: Scoreboard = Scoreboard.new()
	add_child(sb)
	var mc: MatchClock = MatchClock.new()
	mc.auto_start = false
	add_child(mc)
	gk.scoreboard = sb
	gk.match_clock = mc
	gk.my_team_id = Scoreboard.TEAM_A
	sb.register_goal(Scoreboard.TEAM_B)
	sb.register_goal(Scoreboard.TEAM_B)
	mc.current_time_remaining_s = 30.0
	var expected: float = gk.reaction_buffer_s * gk.catchup_gk_reaction_factor
	assert_almost_eq(gk.get_effective_reaction_buffer_s(), expected, 0.001,
		"Eligible state must scale buffer by catchup_gk_reaction_factor")
	sb.queue_free()
	mc.queue_free()


func test_player_state_marks_saving_during_save_or_snap() -> void:
	gk_player.global_position = Vector3(0.0, 0.0, -51.0)
	ball.global_position = Vector3(0.5, 0.4, -42.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -10.0)
	gk.step(1.0 / 120.0)
	assert_eq(gk_player.state, Player.State.SAVING,
		"Player.state must read SAVING during a save action")
