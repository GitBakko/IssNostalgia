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


# ---- S08-T02 dribble impulse model (R02-F05 Architecture B) -----------

func test_no_position_copy_during_possession() -> void:
	# Architecture B invariant: the ball is NOT teleported every tick to
	# match the carrier — it's a live RigidBody3D the whole time. Setting
	# the carrier and stepping must NOT move the ball.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	ball.global_position = Vector3(0.7, 0.11, -0.5)
	ball.linear_velocity = Vector3.ZERO
	bc._assign_carrier(p)
	# Nothing should snap the ball to a carry-offset position.
	bc.step(1.0 / 60.0)
	assert_almost_eq(ball.global_position.x, 0.7, 1.0e-3,
		"Possession must NOT teleport the ball X")
	assert_almost_eq(ball.global_position.z, -0.5, 1.0e-3,
		"Possession must NOT teleport the ball Z")


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


# ---- post-release pickup lockout ---------------------------------------

func test_pickup_locked_out_immediately_after_release() -> void:
	# Regression for the T05 playtest bug: shoot/pass releases the ball,
	# then the same physics tick re-runs _try_pickup, the ball is still at
	# the carry offset (well within 0.8 m of the carrier), so it gets
	# instantly re-grabbed and the launch velocity is wiped.
	bc._assign_carrier(players_a[0])
	# Release with a real launch velocity, but DON'T let the ball move
	# (we're simulating the same-tick race condition).
	bc.request_release(Vector3(20.0, 0.0, 0.0))
	assert_null(bc.get_carrier(), "Sanity: release cleared the carrier")
	# Step IMMEDIATELY — pickup must NOT fire even though everyone is
	# in range.
	bc.step(0.0)
	assert_null(bc.get_carrier(),
		"Lockout must block pickup on the same physics tick as release")


func test_receiver_starts_facing_warp_toward_incoming_ball() -> void:
	# Receiver at origin facing -Z (default). Ball arrives moving in +X.
	# After pickup, receiver must START a facing warp toward -X (TOWARD
	# the passer). The warp converges over ~110 ms via update_facing —
	# we don't snap basis on the same tick (would read as a scatto;
	# R09-F04 FIFA Animation Warping pattern).
	players_a[0].global_position = Vector3.ZERO
	# Reset visual-root facing to -Z (default). S07-T06: rotation lives on
	# VisualRoot, not on the CharacterBody3D itself.
	players_a[0].get_node(^"VisualRoot").transform.basis = Basis.IDENTITY
	# Ball ARRIVING at player from -X (i.e. ball is at x=-0.4 heading +X
	# toward the player at origin). S08-T02 gate: warp only when
	# dot(ball_vel, player_pos - ball_pos) > 0 — i.e. ball is heading
	# TOWARD the player. Pure-receive scenario.
	ball.global_position = Vector3(-0.4, 0.0, 0.0)
	ball.linear_velocity = Vector3(8.0, 0.0, 0.0)  ## ball moving +X
	bc.step(0.0)  ## triggers _try_pickup → _assign_carrier
	assert_eq(bc.get_carrier(), players_a[0], "Sanity: pickup fired")
	assert_gt(players_a[0]._facing_warp_remaining_s, 0.0,
		"Pickup must arm a facing warp window")
	# After ~150 ms of update_facing ticks the receiver must be looking
	# (mostly) toward -X. Tolerate some residual error — warp is 99 % at
	# ~110 ms but the test stays loose to survive minor tuning changes.
	for _i in 18:  ## 18 ticks @ 1/120 ≈ 150 ms
		players_a[0].update_facing(1.0 / 120.0)
	var forward: Vector3 = players_a[0].get_visual_forward()
	assert_almost_eq(forward.x, -1.0, 0.05,
		"After warp window, receiver faces TOWARD the incoming ball")
	assert_almost_eq(forward.z, 0.0, 0.1, "Facing must be planar")


func test_receiver_keeps_facing_when_ball_at_rest() -> void:
	# Ball at rest → no orientation warp (first pickup, restarts).
	players_a[0].global_position = Vector3.ZERO
	players_a[0].get_node(^"VisualRoot").transform.basis = Basis.IDENTITY
	ball.global_position = Vector3(0.4, 0.0, 0.0)
	ball.linear_velocity = Vector3.ZERO
	bc.step(0.0)
	assert_eq(players_a[0]._facing_warp_remaining_s, 0.0,
		"Ball at rest must NOT arm a warp window")
	var forward: Vector3 = players_a[0].get_visual_forward()
	assert_almost_eq(forward.z, -1.0, 1.0e-3,
		"Ball at rest leaves the receiver's facing untouched")


# ---- S08-T02 dribble impulse model (R02-F05 Architecture B) ------------

func test_dribble_impulse_fires_at_walk_interval() -> void:
	# Carrier walking — after touch_interval_walk_s the BallController
	# stages an apply_launch_state on the ball. Carrier flag remains
	# (no release; ball is just nudged). Ball must be inside
	# control_radius_m (1.0 m) but outside proximity radius (0.45 m).
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	ball.global_position = Vector3(0.0, 0.11, -0.7)  ## inside control radius
	ball.linear_velocity = Vector3(0.0, 0.0, -3.0)  ## same direction as carrier
	bc._assign_carrier(p)
	ball._pending_linear = null  ## set AFTER assign (which writes ZERO)
	# Pre-interval: no impulse, still carrying.
	bc.step(bc.touch_interval_walk_s * 0.5)
	assert_eq(ball._pending_linear, null,
		"Mid-interval no impulse staged")
	assert_eq(bc.get_carrier(), p, "Carrier flag preserved")
	# Cross the interval: impulse applied; carrier flag still set.
	bc.step(bc.touch_interval_walk_s * 0.6)
	assert_eq(bc.get_carrier(), p,
		"Dribble impulse must NOT release the carrier")
	assert_not_null(ball._pending_linear,
		"Touch interval crossed → impulse staged via apply_launch_state")
	# Peak kick velocity = carrier_speed * lead + drag * interval / 2.
	var expected_speed: float = (
		p.velocity.length() * bc.ball_avg_lead_factor
		+ bc.drag_compensation_m_s2 * bc.touch_interval_walk_s * 0.5
	)
	var pending: Vector3 = ball._pending_linear as Vector3
	var planar_speed: float = Vector2(pending.x, pending.z).length()
	assert_almost_eq(planar_speed, expected_speed, 1.0e-2,
		"Impulse XZ speed must equal lead*carrier + drag*interval/2 (formula)")


func test_dribble_impulse_uses_sprint_cadence_above_walk() -> void:
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_sprint_speed)
	# Inside control_radius_m but outside proximity radius.
	ball.global_position = Vector3(0.0, 0.11, -0.7)
	ball.linear_velocity = Vector3(0.0, 0.0, -5.0)
	bc._assign_carrier(p)
	# set_possessed clears pending_linear to ZERO (not null) — set to
	# null here so the test detects the impulse via != null.
	ball._pending_linear = null
	# Below sprint interval — no impulse yet.
	bc.step(bc.touch_interval_sprint_s * 0.5)
	assert_eq(ball._pending_linear, null)
	bc.step(bc.touch_interval_sprint_s * 0.6)
	assert_not_null(ball._pending_linear,
		"Sprint cadence (touch_interval_sprint_s) must drive the impulse")


func test_proximity_override_kicks_ball_about_to_be_overtaken() -> void:
	# Carrier moving onto a slow ball within kick_on_proximity_m
	# fires an immediate impulse — without it the ball ends up under
	# the player capsule until the next periodic touch.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	# Ball within proximity radius (0.45 m), nearly stopped.
	ball.global_position = Vector3(0.0, 0.11, -0.3)
	ball.linear_velocity = Vector3(0.0, 0.0, -0.5)  ## << carrier_speed * 0.5
	bc._assign_carrier(p)
	ball._pending_linear = null
	# A SINGLE small step — well under any periodic interval.
	bc.step(0.01)
	assert_not_null(ball._pending_linear,
		"Proximity override must fire impulse immediately, not wait for timer")


func test_direction_change_override_aligns_ball_with_carrier() -> void:
	# Carrier turns 90°; ball still rolling old direction. The
	# direction-change override must fire an impulse so the ball
	# tracks the new heading instead of lagging behind. Ball must be
	# INSIDE control_radius_m for the kick to fire.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(p.max_walk_speed, 0.0, 0.0)  ## carrier going +X
	ball.global_position = Vector3(0.6, 0.11, -0.4)  ## within control_radius
	ball.linear_velocity = Vector3(0.0, 0.0, -3.0)  ## stale -Z direction
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(0.01)
	assert_not_null(ball._pending_linear,
		"Direction change > 35° must fire an immediate kick to align ball")
	var pending: Vector3 = ball._pending_linear as Vector3
	assert_gt(pending.x, 0.0,
		"Re-aligned impulse must point in the carrier's new direction (+X)")


func test_no_kick_when_ball_outside_control_radius() -> void:
	# Ball outside control_radius_m but inside loss_threshold — must
	# coast freely. NO periodic kick, NO direction-change override.
	# This is the "carrier chases escaped ball" state.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	# Ball outside control (1.0 m) but inside loss (2.0 m), going
	# perpendicular (would otherwise trigger direction-change kick).
	ball.global_position = Vector3(0.0, 0.11, -1.5)
	ball.linear_velocity = Vector3(3.0, 0.0, 0.0)  ## perpendicular
	bc._assign_carrier(p)
	ball._pending_linear = null
	# Tick well past any periodic interval.
	bc.step(bc.touch_interval_walk_s + 0.1)
	assert_eq(ball._pending_linear, null,
		"Ball outside control_radius must coast — no kick fires")
	assert_eq(bc.get_carrier(), p,
		"Carrier flag preserved while ball coasts in the chase band")


func test_dribble_skipped_when_carrier_almost_still() -> void:
	# Below the touch_min_speed_m_s gate, no impulse ever staged. Drag
	# + rolling friction stop the ball naturally near the player.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -bc.touch_min_speed_m_s * 0.5)
	ball.global_position = Vector3.ZERO
	bc._assign_carrier(p)
	# set_possessed clears pending_linear to ZERO (not null) — set to
	# null here so the test detects the impulse via != null.
	ball._pending_linear = null
	bc.step(bc.touch_interval_walk_s * 5.0)
	assert_eq(ball._pending_linear, null,
		"Carrier almost still → no dribble impulse")
	assert_eq(bc.get_carrier(), p, "Carrier flag preserved")


func test_loss_threshold_clears_carrier() -> void:
	# Ball drifts beyond loss_threshold_m → possession ends automatically.
	# (Tackle sim, foot-too-fast, or pre-pickup ball runaway.)
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	bc._assign_carrier(p)
	# Place the ball outside the loss radius.
	ball.global_position = Vector3(0.0, 0.11, -(bc.loss_threshold_m + 0.1))
	bc.step(0.0)
	assert_null(bc.get_carrier(),
		"Ball beyond loss_threshold_m must clear the carrier")


func test_loss_also_clears_ball_possessed_flag() -> void:
	# REGRESSION: previously _check_loss cleared BallController._carrier
	# but NOT BallPhysics._possessed_by. ball.is_possessed() stayed
	# true forever, _try_pickup gate 2 skipped every subsequent pickup
	# attempt, the ball became "immobile on the field" and the carrier
	# could never re-acquire. This test locks in the synchronization.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	bc._assign_carrier(p)
	assert_true(ball.is_possessed(), "Sanity: ball is possessed")
	# Trigger loss by drifting the ball outside the threshold.
	ball.global_position = Vector3(0.0, 0.11, -(bc.loss_threshold_m + 0.1))
	bc.step(0.0)
	assert_false(ball.is_possessed(),
		"Loss must also clear BallPhysics._possessed_by — otherwise "
		+ "_try_pickup blocks all re-acquisition forever")


func test_pickup_works_after_loss_event() -> void:
	# Full re-acquisition cycle: pickup → loss → walk back → re-pickup.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	bc._assign_carrier(p)
	# Force loss.
	ball.global_position = Vector3(0.0, 0.11, -(bc.loss_threshold_m + 0.1))
	bc.step(0.0)
	assert_null(bc.get_carrier(), "Sanity: loss fired")
	# Drain the post-loss lockout.
	bc.step(bc.touch_loss_lockout_s + 0.01)
	# Bring the player adjacent to the (now stopped) ball.
	p.global_position = ball.global_position + Vector3(0.0, 0.0, 0.5)
	ball.linear_velocity = Vector3.ZERO
	bc.step(0.0)
	assert_eq(bc.get_carrier(), p,
		"After loss + lockout drain, the player must be able to "
		+ "re-acquire the ball")


func test_ball_stays_unfrozen_during_possession() -> void:
	# R02-F05 Arch B invariant: the ball is NEVER frozen while possessed.
	bc._assign_carrier(players_a[0])
	assert_false(ball.freeze,
		"BallPhysics.freeze must stay false during possession (always live)")


func test_ball_collision_active_during_possession() -> void:
	# R02-F05 Arch B invariant: collision_layer / mask are NOT zeroed.
	# Ball stays solid against world + other players.
	var saved_layer: int = ball.collision_layer
	var saved_mask: int = ball.collision_mask
	bc._assign_carrier(players_a[0])
	assert_eq(ball.collision_layer, saved_layer,
		"collision_layer must be preserved during possession")
	assert_eq(ball.collision_mask, saved_mask,
		"collision_mask must be preserved during possession")


func test_carrier_added_to_collision_exception_on_pickup() -> void:
	# Carrier must be in the ball's collision exception list — without
	# this the CharacterBody3D capsule blocks at 0.51 m from the ball,
	# the carrier's velocity drops to ~0, the dribble impulse never
	# fires, and the ball ends up an unmovable boulder (regression
	# observed 2026-05-13). Other players stay solid against the ball.
	bc._assign_carrier(players_a[0])
	var exceptions: Array[PhysicsBody3D] = ball.get_collision_exceptions()
	assert_true(players_a[0] in exceptions,
		"Carrier must be in ball.get_collision_exceptions() during possession")
	# Other team players are NOT in the exception list.
	for i in [1, 2, 3, 4]:
		assert_false(players_a[i] in exceptions,
			"Non-carrier teammates must remain solid against the ball")


func test_collision_exception_cleared_on_release() -> void:
	bc._assign_carrier(players_a[0])
	bc.request_release(Vector3(8.0, 0.0, 0.0))
	var exceptions: Array[PhysicsBody3D] = ball.get_collision_exceptions()
	assert_false(players_a[0] in exceptions,
		"Release must remove the carrier from the exception list")


func test_collision_exception_cleared_on_loss() -> void:
	bc._assign_carrier(players_a[0])
	# Drift the ball outside loss_threshold_m → carrier auto-cleared.
	ball.global_position = Vector3(0.0, 0.11, -(bc.loss_threshold_m + 0.1))
	bc.step(0.0)
	assert_null(bc.get_carrier(), "Sanity: loss fired")
	var exceptions: Array[PhysicsBody3D] = ball.get_collision_exceptions()
	assert_false(players_a[0] in exceptions,
		"Loss must remove the carrier from the exception list")


func test_pickup_primes_ball_when_carrier_already_moving() -> void:
	# Player approaches a still ball at sprint speed. On pickup the
	# ball must immediately match the carrier's velocity (× factor),
	# otherwise the carrier walks PAST the ball before the first
	# scheduled touch impulse and the loss-threshold gate trips.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_sprint_speed)
	ball.global_position = Vector3(0.0, 0.11, 0.0)
	ball._pending_linear = null
	bc._assign_carrier(p)
	# A prime impulse must have staged the carrier-velocity * factor.
	assert_not_null(ball._pending_linear,
		"Pickup with moving carrier must prime the ball velocity")
	var pending: Vector3 = ball._pending_linear as Vector3
	var planar_speed: float = Vector2(pending.x, pending.z).length()
	# Sprint regime → uses sprint interval for drag compensation.
	var interval: float = bc.touch_interval_sprint_s if p.velocity.length() > p.max_walk_speed \
		else bc.touch_interval_walk_s
	var expected: float = (
		p.velocity.length() * bc.ball_avg_lead_factor
		+ bc.drag_compensation_m_s2 * interval * 0.5
	)
	assert_almost_eq(planar_speed, expected, 1.0e-2,
		"Prime impulse must follow the same drag-compensated formula")


func test_shoot_release_still_arms_lockout() -> void:
	# Sanity: SHOOT release path keeps the Sprint 7 lockout behaviour.
	bc._assign_carrier(players_a[0])
	bc.request_release(Vector3(20.0, 0.0, 0.0))  ## default kind = SHOOT
	bc.step(0.0)
	assert_null(bc.get_carrier(),
		"SHOOT lockout must still block immediate re-pickup")


func test_pickup_resumes_after_lockout_expires() -> void:
	bc._assign_carrier(players_a[0])
	bc.request_release(Vector3(20.0, 0.0, 0.0))
	# Drain the lockout. post_release_lockout_s default = 0.3 s, so
	# stepping 0.31 s in one chunk fully drains it.
	bc.step(0.31)
	# Move a player back into range with the ball at rest.
	ball.linear_velocity = Vector3.ZERO
	ball.global_position = Vector3.ZERO
	players_a[0].global_position = Vector3(0.4, 0.0, 0.0)
	bc.step(0.0)
	assert_eq(bc.get_carrier(), players_a[0],
		"After lockout drains, normal pickup resumes")
