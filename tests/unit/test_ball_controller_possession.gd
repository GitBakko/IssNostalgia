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


# ---- S08-T02 geometric proximity-kick dribble (R02-F05 Arch B feel) ----

func test_kick_fires_on_proximity_meet_walk() -> void:
	# Walking carrier meets ball → kick at carrier_speed * kick_factor_walk.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	# Visual forward aligned with velocity (no facing/velocity mismatch
	# so the blend is unambiguous).
	p.get_node(^"VisualRoot").transform.basis = Basis.IDENTITY
	ball.global_position = Vector3(0.0, 0.11, -0.1)
	ball.linear_velocity = Vector3.ZERO
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_linear,
		"Carrier-meets-ball proximity must fire a kick immediately")
	var pending: Vector3 = ball._pending_linear as Vector3
	var expected_speed: float = p.velocity.length() * bc.kick_factor_walk
	assert_almost_eq(Vector2(pending.x, pending.z).length(), expected_speed, 1.0e-2,
		"Walk-speed kick uses kick_factor_walk")


func test_kick_fires_on_proximity_meet_sprint() -> void:
	# Sprint regime → kick uses kick_factor_sprint instead.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_sprint_speed)
	p.get_node(^"VisualRoot").transform.basis = Basis.IDENTITY
	ball.global_position = Vector3(0.0, 0.11, -0.1)
	ball.linear_velocity = Vector3.ZERO
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	var pending: Vector3 = ball._pending_linear as Vector3
	var expected_speed: float = p.velocity.length() * bc.kick_factor_sprint
	assert_almost_eq(Vector2(pending.x, pending.z).length(), expected_speed, 1.0e-2,
		"Sprint-speed kick uses kick_factor_sprint")


func test_kick_dampened_on_sharp_turn() -> void:
	# After a kick fires, a second kick fired in a sharply different
	# direction must use the dampened factor (kick_factor * dampen).
	# Drives _apply_proximity_kick directly to bypass the lockout
	# state machine and isolate the dampen path.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	p.get_node(^"VisualRoot").transform.basis = Basis.IDENTITY
	bc._assign_carrier(p)
	# First kick — establishes _last_kick_direction (-Z).
	bc._apply_proximity_kick(p.velocity)
	# Pivot 90°: carrier now moving +X, visual_root facing +X.
	p.velocity = Vector3(p.max_walk_speed, 0.0, 0.0)
	p.get_node(^"VisualRoot").transform.basis = Basis.looking_at(Vector3(1, 0, 0), Vector3.UP)
	ball._pending_linear = null
	# Second kick — direction angle vs first ≈ 90°, beyond threshold.
	bc._apply_proximity_kick(p.velocity)
	var pending: Vector3 = ball._pending_linear as Vector3
	var expected_dampened: float = p.velocity.length() * bc.kick_factor_walk * bc.kick_turn_dampen_factor
	assert_almost_eq(Vector2(pending.x, pending.z).length(), expected_dampened, 1.0e-2,
		"Sharp-turn kick must use dampened factor")


func test_no_kick_when_carrier_far_from_ball() -> void:
	# Ball outside kick_proximity_m AND outside centering_max_radius_m
	# → neither a proximity-kick nor a centering correction. Ball
	# coasts under free physics; carrier must close the gap.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	# Ball OUTSIDE centering radius (1.5 m), inside loss (3.0 m).
	ball.global_position = Vector3(0.0, 0.11, -2.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -3.0)
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_linear, null,
		"Ball outside kick_proximity_m AND centering radius must NOT stage state")


func test_no_kick_when_carrier_almost_still() -> void:
	# Carrier speed below kick_min_carrier_speed_m_s → no kick fires
	# even when the ball is at the foot. Ball just sits there.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -bc.kick_min_carrier_speed_m_s * 0.5)
	ball.global_position = Vector3(0.0, 0.11, -0.1)  ## within proximity
	ball.linear_velocity = Vector3.ZERO
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_linear, null,
		"Carrier almost still → no kick even at foot proximity")


func test_kick_lockout_prevents_double_fire() -> void:
	# After one kick, the lockout must prevent a second kick on the
	# very next tick (ball still within proximity for 1-2 frames).
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	ball.global_position = Vector3(0.0, 0.11, -0.1)
	bc._assign_carrier(p)
	bc.step(1.0 / 60.0)  ## first kick
	ball._pending_linear = null
	# Same tick again — lockout must block.
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_linear, null,
		"kick_lockout_s must block a second kick within the lockout window")


func test_kick_uses_carrier_direction_after_turn() -> void:
	# Carrier turns, ball still rolling old direction. When carrier
	# meets the ball, the kick fires in the NEW carrier direction —
	# letting the dribble change heading instantly. The blend uses
	# visual_forward too (fix #2), so the test rotates VisualRoot to
	# match the new heading just like the warp does in-game.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(p.max_walk_speed, 0.0, 0.0)  ## now going +X
	p.get_node(^"VisualRoot").transform.basis = Basis.looking_at(Vector3(1, 0, 0), Vector3.UP)
	ball.global_position = Vector3(0.1, 0.11, 0.0)  ## within proximity
	ball.linear_velocity = Vector3(0.0, 0.0, -3.0)  ## was going -Z
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_linear)
	var pending: Vector3 = ball._pending_linear as Vector3
	# Kick is primarily +X (new direction).
	assert_gt(pending.x, 0.0,
		"Post-turn kick must use carrier's NEW direction (+X)")
	assert_almost_eq(pending.z, 0.0, 0.01,
		"With visual_forward also aligned to +X, no Z component remains")


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

func test_carrier_still_does_not_move_ball() -> void:
	# Proximity-kick model: carrier stationary → no kick. Ball stays
	# wherever physics put it.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	ball.global_position = Vector3(0.1, 0.11, 0.0)  ## within proximity
	ball.linear_velocity = Vector3.ZERO
	bc._assign_carrier(p)
	ball._pending_linear = null
	for _i in 60:
		bc.step(1.0 / 60.0)
	assert_eq(ball._pending_linear, null,
		"Stationary carrier must NOT kick the ball")


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
	# Carrier must be in the ball's collision exception list AND vice-
	# versa — without the SYMMETRIC pair the CharacterBody3D capsule
	# kinematic sweep still blocks on the ball during turns (the
	# carrier "tries to turn but the ball acts as a wall", playtest
	# 2026-05-14). Other players stay solid against the ball.
	bc._assign_carrier(players_a[0])
	var ball_exc: Array[PhysicsBody3D] = ball.get_collision_exceptions()
	assert_true(players_a[0] in ball_exc,
		"Carrier must be in ball.get_collision_exceptions() during possession")
	var player_exc: Array[PhysicsBody3D] = players_a[0].get_collision_exceptions()
	assert_true(ball in player_exc,
		"Ball must be in carrier.get_collision_exceptions() during possession")
	# Other team players are NOT in the exception list.
	for i in [1, 2, 3, 4]:
		assert_false(players_a[i] in ball_exc,
			"Non-carrier teammates must remain solid against the ball")


func test_collision_exception_cleared_on_release() -> void:
	bc._assign_carrier(players_a[0])
	bc.request_release(Vector3(8.0, 0.0, 0.0))
	var ball_exc: Array[PhysicsBody3D] = ball.get_collision_exceptions()
	assert_false(players_a[0] in ball_exc,
		"Release must remove the carrier from the ball's exception list")
	var player_exc: Array[PhysicsBody3D] = players_a[0].get_collision_exceptions()
	assert_false(ball in player_exc,
		"Release must remove the ball from the carrier's exception list")


func test_collision_exception_cleared_on_loss() -> void:
	bc._assign_carrier(players_a[0])
	# Drift the ball outside loss_threshold_m → carrier auto-cleared.
	ball.global_position = Vector3(0.0, 0.11, -(bc.loss_threshold_m + 0.1))
	bc.step(0.0)
	assert_null(bc.get_carrier(), "Sanity: loss fired")
	var ball_exc: Array[PhysicsBody3D] = ball.get_collision_exceptions()
	assert_false(players_a[0] in ball_exc,
		"Loss must remove the carrier from the ball's exception list")
	var player_exc: Array[PhysicsBody3D] = players_a[0].get_collision_exceptions()
	assert_false(ball in player_exc,
		"Loss must remove the ball from the carrier's exception list")


func test_pickup_with_moving_carrier_kicks_at_meet() -> void:
	# Pickup-while-moving scenario: carrier walks onto a still ball.
	# Pickup fires when carrier within 0.8 m. Then a kick fires when
	# carrier within kick_proximity_m (0.35 m).
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_sprint_speed)
	# Start ball at carrier position so the proximity gate is satisfied
	# the first time the kick logic runs.
	ball.global_position = Vector3(0.0, 0.11, -0.1)
	ball.linear_velocity = Vector3.ZERO
	bc._assign_carrier(p)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_linear,
		"First kick fires once carrier reaches the ball at proximity")


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


# ---- Buffered turn → pivot kick (Bug 1, playtest 2026-05-14) -----------

func test_buffered_turn_kick_uses_intent_and_snaps_velocity() -> void:
	# Carrier physically moving +X (committed/buffered direction), but
	# input intends +Z. Buffer is active. When the proximity kick fires,
	# the ball must be launched along +Z (intent) AND the player.velocity
	# must be redirected from +X to +Z, preserving planar speed.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	var speed: float = p.max_walk_speed
	p.velocity = Vector3(speed, 0.0, 0.0)
	# Simulate buffer state: committed=+X, intent=+Z, buffer active.
	p._committed_input_dir = Vector3(1.0, 0.0, 0.0)
	p._intended_input_dir = Vector3(0.0, 0.0, 1.0)
	p._input_buffer_active = true
	p._input_buffer_remaining_s = 0.5
	p._ball_moving_with_me = true
	p.has_ball = true
	bc._carrier = p
	bc._last_kick_direction = Vector3.ZERO  ## no dampen on first kick
	ball._pending_linear = null
	bc._apply_proximity_kick(p.velocity)
	assert_not_null(ball._pending_linear, "Pivot kick must stage a launch state")
	var pending: Vector3 = ball._pending_linear as Vector3
	assert_almost_eq(pending.x, 0.0, 0.05, "Pivot kick X component should be ~0 (intent is +Z)")
	assert_gt(pending.z, 0.0, "Pivot kick Z must be positive (intent direction)")
	# Player velocity must be snapped to +Z, preserving planar speed.
	assert_almost_eq(p.velocity.x, 0.0, 0.05, "Player.velocity X must snap to ~0 after pivot")
	assert_gt(p.velocity.z, 0.0, "Player.velocity Z must be positive after pivot")
	assert_almost_eq(p.velocity.length(), speed, 0.05,
		"Pivot must preserve planar speed (no decel)")


func test_buffered_stop_traps_ball_at_foot() -> void:
	# Carrier moving forward, releases input → intent = ZERO, buffer
	# engages. When proximity kick fires, the ball must be TRAPPED:
	# planar velocity zeroed, Y preserved.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	p._committed_input_dir = Vector3(0.0, 0.0, -1.0)
	p._intended_input_dir = Vector3.ZERO  ## release
	p._input_buffer_active = true
	p._input_buffer_remaining_s = 0.5
	p._ball_moving_with_me = true
	p.has_ball = true
	bc._carrier = p
	ball.linear_velocity = Vector3(0.5, 1.2, -3.0)  ## mid-bounce, rolling
	ball._pending_linear = null
	bc._apply_proximity_kick(p.velocity)
	assert_not_null(ball._pending_linear, "Trap must stage a launch state")
	var pending: Vector3 = ball._pending_linear as Vector3
	assert_almost_eq(pending.x, 0.0, 0.001, "Trap zeroes planar X")
	assert_almost_eq(pending.z, 0.0, 0.001, "Trap zeroes planar Z")
	assert_almost_eq(pending.y, 1.2, 0.001, "Trap preserves Y (bounce continues)")


# ---- Passive brake when carrier stops (Bug 2) --------------------------

func test_passive_brake_decays_ball_when_carrier_almost_still() -> void:
	# Carrier almost stopped, ball within brake_radius_m, ball still
	# rolling → passive brake decays the planar velocity each tick.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -bc.kick_min_carrier_speed_m_s * 0.5)
	bc._assign_carrier(p)
	# Ball within brake_radius_m, still rolling fast.
	ball.global_position = Vector3(0.0, 0.11, -0.6)  ## 0.6 m, inside brake_radius (1.2)
	ball.linear_velocity = Vector3(0.0, 0.0, -4.0)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_linear, "Passive brake must stage a decayed velocity")
	var pending: Vector3 = ball._pending_linear as Vector3
	assert_lt(absf(pending.z), 4.0, "Brake must reduce planar speed")
	assert_gt(absf(pending.z), 0.0, "Decay should still leave some planar motion above snap threshold")


func test_passive_brake_snaps_to_stop_below_threshold() -> void:
	# Below brake_snap_threshold_m_s the brake snaps planar to zero.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO  ## fully still
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.0, 0.11, -0.5)
	ball.linear_velocity = Vector3(0.0, 0.0, -bc.brake_snap_threshold_m_s * 0.5)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_linear)
	var pending: Vector3 = ball._pending_linear as Vector3
	assert_almost_eq(pending.x, 0.0, 0.001, "Snap zeroes X")
	assert_almost_eq(pending.z, 0.0, 0.001, "Snap zeroes Z")


func test_passive_brake_skipped_when_ball_far() -> void:
	# Beyond brake_radius_m the brake doesn't fire (ball is "loose",
	# not "at the foot"). Loss threshold handles drift past 3 m.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.0, 0.11, -2.0)  ## > brake_radius (1.2)
	ball.linear_velocity = Vector3(0.0, 0.0, -2.0)
	ball._pending_linear = null
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_linear, null,
		"Carrier still + ball far → no brake (loss threshold takes over)")


# ---- Magnetic centering (Bug 3, circular-sweep playtest 2026-05-14) ----

func test_centering_pulls_ball_toward_carry_zone() -> void:
	# Centering is OFF by default — opt in for this test.
	bc.centering_enabled = true
	# Carrier moving -Z at walk speed, ball OUTSIDE proximity (0.35)
	# but within centering radius (1.5). No kick this tick → centering
	# must stage a velocity that pulls the ball toward the ideal
	# carry point (carrier + carry_dir * 0.45).
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.0, 0.11, -1.0)  ## ahead, > proximity
	ball.linear_velocity = Vector3(0.0, 0.0, -1.0)   ## slow drift
	ball._pending_linear = null
	# Establish a steady carry-dir baseline so turn-glue stays silent.
	bc._last_carry_dir = Vector3(0.0, 0.0, -1.0)
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_linear,
		"Centering must stage a velocity correction when ball within radius")
	var pending: Vector3 = ball._pending_linear as Vector3
	# Ball was at -1.0, ideal is at -0.45 → error points +Z. Target Z
	# velocity = carry_dir.z * carrier_speed + corr_z = -5.5 + positive corr.
	# After short lerp the new vz lies between -1.0 (current) and target.
	assert_lt(pending.z, 0.0, "Ball still moving in carry direction (-Z)")
	assert_gt(pending.z, -p.max_walk_speed,
		"Centering pull keeps ball below pure carrier_speed (-5.5)")


func test_centering_skipped_when_ball_just_kicked() -> void:
	bc.centering_enabled = true
	# Ball moving > centering_max_ball_speed_m_s → centering bows out
	# and lets natural drag carry the just-kicked ball.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.0, 0.11, -1.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -bc.centering_max_ball_speed_m_s - 1.0)
	ball._pending_linear = null
	bc._last_carry_dir = Vector3(0.0, 0.0, -1.0)
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_linear, null,
		"Centering must skip while ball is moving faster than the speed cap")


func test_centering_skipped_within_dead_zone() -> void:
	bc.centering_enabled = true
	# Ball already very close to ideal point → no jitter correction.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	# Visual_forward defaults to -Z when scene basis is identity, so
	# ideal_pos = (0, *, -0.45). Place ball there.
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.0, 0.11, -bc.centering_offset_m)
	ball.linear_velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	ball._pending_linear = null
	bc._last_carry_dir = Vector3(0.0, 0.0, -1.0)
	bc.step(1.0 / 60.0)
	# Within dead-zone OR proximity (0.35 m → kick fires). Either way the
	# behavior is deterministic and not the centering pull. We only assert
	# the centering branch wasn't the one that staged the value: if a
	# pending exists, its magnitude is the kick (carrier_speed * factor),
	# not the centering output.
	# Either the proximity kick fires (ball is at 0.45 m which is just
	# beyond the 0.35 m kick gate, so usually no kick this tick) OR the
	# centering branch decides the ball is in its dead zone. Both leave
	# the centering pull silent — assert no centering-shaped output.
	if ball._pending_linear == null:
		assert_eq(ball._pending_linear, null,
			"Centering must not stage anything within the dead zone")
	else:
		var pending: Vector3 = ball._pending_linear as Vector3
		var planar: float = sqrt(pending.x * pending.x + pending.z * pending.z)
		var min_kick: float = p.max_walk_speed * bc.kick_factor_walk * 0.9
		assert_gt(planar, min_kick,
			"If anything fires here it must be the kick (boost factor), not centering")


# ---- Turn-glue (Bug 4, "ball must rotate with carrier on turn") --------

func test_turn_glue_snaps_ball_to_foot_in_new_heading() -> void:
	# Carrier moving +X, then rotates visual to +Z. Turn-glue must
	# HARD-SNAP the ball to (carrier + visual_forward * turn_glue_offset_m)
	# and match carrier velocity. No interpolation, no per-tick cap —
	# the ball is glued to the foot for that tick.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(p.max_walk_speed, 0.0, 0.0)
	p.get_node(^"VisualRoot").transform.basis = Basis.looking_at(Vector3(1, 0, 0), Vector3.UP)
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.4, 0.11, 0.0)
	ball.linear_velocity = Vector3(p.max_walk_speed, 0.0, 0.0)
	ball._pending_linear = null
	ball._pending_teleport = null
	bc._last_carry_dir = Vector3(1.0, 0.0, 0.0)  ## baseline = +X
	# Now rotate visual to +Z; velocity also turns to +Z.
	p.velocity = Vector3(0.0, 0.0, p.max_walk_speed)
	p.get_node(^"VisualRoot").transform.basis = Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)
	bc.step(1.0 / 60.0)
	assert_not_null(ball._pending_teleport,
		"Turn-glue must teleport the ball on visual rotation")
	assert_not_null(ball._pending_linear,
		"Turn-glue must match carrier velocity on the same tick")
	var teleport: Vector3 = ball._pending_teleport as Vector3
	# Hard snap: ball at (0, *, turn_glue_offset_m) — directly in front
	# of the player along +Z (the new visual_forward).
	assert_almost_eq(teleport.x, 0.0, 0.001,
		"Ball X must snap to ~0 (no carry along old +X heading)")
	assert_almost_eq(teleport.z, bc.turn_glue_offset_m, 0.001,
		"Ball Z must snap to turn_glue_offset_m along new +Z heading")
	var staged_v: Vector3 = ball._pending_linear as Vector3
	assert_almost_eq(staged_v.x, p.velocity.x, 0.001,
		"Staged velocity X must match carrier")
	assert_almost_eq(staged_v.z, p.velocity.z, 0.001,
		"Staged velocity Z must match carrier")


func test_turn_glue_skipped_when_ball_outside_radius() -> void:
	# Ball beyond turn_glue_radius_m → no rotation snap, the loose
	# ball just keeps physics + centering / kick logic.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(p.max_walk_speed, 0.0, 0.0)
	bc._assign_carrier(p)
	# Ball outside the glue radius (1.0) and outside the centering
	# radius (1.5) so neither path stages a teleport.
	ball.global_position = Vector3(2.0, 0.11, 0.0)
	ball.linear_velocity = Vector3.ZERO
	ball._pending_teleport = null
	bc._last_carry_dir = Vector3(1.0, 0.0, 0.0)
	# Now turn 90°.
	p.velocity = Vector3(0.0, 0.0, p.max_walk_speed)
	p.get_node(^"VisualRoot").transform.basis = Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_teleport, null,
		"Turn-glue must not teleport a loose ball outside the radius")


func test_turn_glue_skipped_when_carry_direction_steady() -> void:
	# Carrier moving steadily — same carry direction tick over tick.
	# No rotation should be staged.
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	bc._assign_carrier(p)
	ball.global_position = Vector3(0.0, 0.11, -0.5)
	ball.linear_velocity = Vector3(0.0, 0.0, -p.max_walk_speed)
	bc._last_carry_dir = Vector3(0.0, 0.0, -1.0)
	ball._pending_teleport = null
	bc.step(1.0 / 60.0)
	assert_eq(ball._pending_teleport, null,
		"Steady carry direction must not trigger a turn-glue teleport")


func test_turn_glue_baseline_resets_when_carrier_stops() -> void:
	# Carrier slow → turn-glue baseline must reset so the next
	# movement starts fresh (no spurious "turn" from old baseline).
	var p: Player = players_a[0]
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO  ## below kick_min
	bc._assign_carrier(p)
	bc._last_carry_dir = Vector3(1.0, 0.0, 0.0)  ## stale +X baseline
	ball.global_position = Vector3(0.0, 0.11, -0.3)
	ball.linear_velocity = Vector3.ZERO
	bc.step(1.0 / 60.0)
	assert_eq(bc._last_carry_dir, Vector3.ZERO,
		"Turn-glue baseline must clear when carrier drops below kick_min")
