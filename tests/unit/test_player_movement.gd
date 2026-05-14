extends GutTest

## Sprint 6 T02 — Player movement, sprint, stamina pure-function tests.
## Drives `Player.apply_movement_step()` directly with explicit dt; no scene
## tick coupling, no `move_and_slide()` involvement.

const SUB_DT: float = 1.0 / 120.0  ## same as live physics tick
const FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)

var player: Player
var team: TeamConfig


func before_each() -> void:
	team = (load("res://resources/teams/team_a.tres") as TeamConfig).duplicate(true)
	player = preload("res://scenes/Player.tscn").instantiate() as Player
	player.team_config = team
	add_child(player)


func after_each() -> void:
	if is_instance_valid(player):
		player.queue_free()
	player = null
	team = null


# ---- speed clamps --------------------------------------------------------

func test_walk_speed_clamp_no_sprint() -> void:
	# Drive forward 0.5 s with sprint OFF; velocity must converge to <=
	# max_walk_speed and never exceed it.
	for _i in 60:
		player.apply_movement_step(FORWARD, false, SUB_DT)
	assert_lte(player.velocity.length(), player.max_walk_speed + 1.0e-3,
		"Walk-only must clamp at %.2f m/s, got %.3f" % [
			player.max_walk_speed, player.velocity.length(),
		])


func test_sprint_speed_clamp_with_stamina() -> void:
	# Sprint with full stamina for 0.5 s — must reach exactly sprint speed.
	for _i in 60:
		player.apply_movement_step(FORWARD, true, SUB_DT)
	assert_almost_eq(player.velocity.length(), player.max_sprint_speed, 1.0e-2,
		"Sprint with stamina should reach %.2f m/s, got %.3f" % [
			player.max_sprint_speed, player.velocity.length(),
		])


func test_sprint_falls_back_to_walk_when_stamina_empty() -> void:
	# Drain stamina (~3 s + small slack), then keep holding sprint —
	# velocity must drop back to walk_speed.
	for _i in 400:
		player.apply_movement_step(FORWARD, true, SUB_DT)
	assert_eq(player.stamina, 0.0, "Stamina should be fully drained")
	# Run a few more ticks at empty stamina; velocity should clamp at walk.
	for _i in 60:
		player.apply_movement_step(FORWARD, true, SUB_DT)
	assert_lte(player.velocity.length(), player.max_walk_speed + 1.0e-2,
		"Sprint with 0 stamina must fall back to walk_speed, got %.3f" %
			player.velocity.length())


# ---- stamina --------------------------------------------------------------

func test_stamina_drains_in_three_seconds() -> void:
	# 3 s of continuous sprint should deplete stamina fully (within 5 %).
	var ticks: int = 360  ## 3.0 s @ 120 Hz
	for _i in ticks:
		player.apply_movement_step(FORWARD, true, SUB_DT)
	assert_almost_eq(player.stamina, 0.0, 0.05,
		"Stamina after 3 s sprint should be ~0, got %.3f" % player.stamina)


func test_stamina_recovers_in_five_seconds() -> void:
	# Drain first.
	for _i in 360:
		player.apply_movement_step(FORWARD, true, SUB_DT)
	# Then 5 s of NOT sprinting (zero input — test gate, not the input).
	for _i in 600:
		player.apply_movement_step(Vector3.ZERO, false, SUB_DT)
	assert_almost_eq(player.stamina, 1.0, 0.05,
		"Stamina after 5 s rest should be ~1, got %.3f" % player.stamina)


func test_stamina_recovery_blocked_while_sprint_held() -> void:
	# S06-D04: recovery only when sprint released. Even with zero input,
	# holding sprint at empty stamina must NOT recover.
	for _i in 400:
		player.apply_movement_step(FORWARD, true, SUB_DT)
	assert_eq(player.stamina, 0.0)
	for _i in 600:
		player.apply_movement_step(Vector3.ZERO, true, SUB_DT)
	assert_eq(player.stamina, 0.0,
		"Stamina must stay 0 while sprint button is held, even idle. Got %.3f" %
			player.stamina)


func test_stamina_clamped_to_unit_range() -> void:
	# Recover for far longer than 5 s — must NOT exceed 1.0.
	for _i in 2000:
		player.apply_movement_step(Vector3.ZERO, false, SUB_DT)
	assert_eq(player.stamina, 1.0,
		"Stamina must clamp to 1.0 max, got %.3f" % player.stamina)


# ---- facing rotation ------------------------------------------------------

func test_facing_target_updates_only_with_movement_input() -> void:
	# No input → facing target stays at the initial -Z.
	var before: Vector3 = player._facing_target
	player.apply_movement_step(Vector3.ZERO, false, SUB_DT)
	assert_eq(player._facing_target, before,
		"Zero input must NOT change facing target")
	# Input +X → facing target snaps to +X.
	player.apply_movement_step(Vector3(1.0, 0.0, 0.0), false, SUB_DT)
	assert_almost_eq(player._facing_target.x, 1.0, 1.0e-3)
	assert_almost_eq(player._facing_target.z, 0.0, 1.0e-3)


func test_update_facing_rotates_basis_toward_target() -> void:
	# Force a 90° turn and check the visual basis converges (S07-T06:
	# rotation now lives on VisualRoot, not on the CharacterBody3D).
	player._facing_target = Vector3(1.0, 0.0, 0.0)  # face +X
	for _i in 240:  ## 2 s — plenty even at baseline rotation_speed
		player.update_facing(SUB_DT)
	var forward: Vector3 = player.get_visual_forward()
	assert_almost_eq(forward.x, 1.0, 0.05,
		"VisualRoot -Z must rotate to +X, got %s" % forward)


func test_t06_collision_basis_stays_identity_while_visual_rotates() -> void:
	# S07-T06 invariant: update_facing rotates the VisualRoot ONLY. The
	# CharacterBody3D basis stays at identity so the rotationally-
	# symmetric capsule collider isn't pointlessly transformed every
	# tick. This is the visual-vs-physics decoupling that R01-F07 and
	# R09-F04 call for.
	player._facing_target = Vector3(1.0, 0.0, 0.0)
	for _i in 60:
		player.update_facing(SUB_DT)
	# Visual moved.
	var vf: Vector3 = player.get_visual_forward()
	assert_gt(vf.x, 0.1,
		"VisualRoot must have rotated noticeably toward +X")
	# Collision body did not.
	var body_basis: Basis = player.transform.basis
	assert_true(body_basis.x.is_equal_approx(Vector3.RIGHT),
		"CharacterBody3D basis.x must stay at world +X, got %s" % body_basis.x)
	assert_true(body_basis.z.is_equal_approx(Vector3.BACK),
		"CharacterBody3D basis.z must stay at world +Z, got %s" % body_basis.z)


# ---- team-colour application ----------------------------------------------

func test_player_decelerates_when_left_undriven() -> void:
	# S06-D32: an inactive player (no apply_movement_step calls from any
	# controller) must NOT coast on its last velocity — Player._physics_process
	# applies a zero-drive step automatically.
	# Simulate a sprint to full speed first.
	for _i in 60:
		player.apply_movement_step(Vector3(0.0, 0.0, -1.0), true, SUB_DT)
	assert_almost_eq(player.velocity.length(), player.max_sprint_speed, 1.0e-2,
		"Player must reach sprint speed before release test")
	# Now stop driving — _physics_process should auto-apply zero input.
	# We can't easily await physics ticks in GUT; emulate by directly calling
	# the same fallback path (zero input) for many ticks.
	for _i in 120:
		player.apply_movement_step(Vector3.ZERO, false, SUB_DT)
	assert_lt(player.velocity.length(), 0.5,
		"Released player should be near-stationary after ~1 s of decel, got %.3f" %
			player.velocity.length())


func test_team_colour_applied_to_body_mesh() -> void:
	# S07-T06: BodyMesh now lives under VisualRoot.
	var body: MeshInstance3D = player.get_node("VisualRoot/BodyMesh") as MeshInstance3D
	assert_not_null(body)
	var mat: StandardMaterial3D = body.material_override as StandardMaterial3D
	assert_not_null(mat,
		"Body mesh material_override must be set after _ready()")
	assert_eq(mat.albedo_color, team.primary_color,
		"Body mesh albedo must match team primary colour")


# ---- S08 direction-input buffer (Q1-Q8) -------------------------------

func test_buffer_inactive_when_no_ball() -> void:
	# No has_ball → buffer never engages; every input applies immediately.
	player.has_ball = false
	player.apply_movement_step(FORWARD, false, SUB_DT)
	# Sharp turn 180° → committed must follow intended same tick.
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, -FORWARD,
		"No buffer when not carrying — commit follows intended")


func test_buffer_inactive_until_first_dribble_touch() -> void:
	# has_ball=true but no on_dribble_touch yet → still no buffer.
	# (Q4: starting from rest is immediate.)
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, -FORWARD,
		"Before first touch, even with ball, input passes through")


func test_buffer_engages_on_sharp_turn_after_first_touch() -> void:
	# Pickup + first touch → buffer arms. Sharp turn (>15°) → committed
	# stays at OLD direction, intended captures the new one.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()  ## first touch — _ball_moving_with_me = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	# Now turn 180° (well above 15° dead zone).
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, FORWARD,
		"Sharp-turn committed direction stays OLD until next touch")
	assert_eq(player._intended_input_dir, -FORWARD,
		"Intended captures the new direction immediately")
	assert_true(player._input_buffer_active,
		"Buffer flag must be active during turn delay")


func test_buffer_passes_through_within_dead_zone() -> void:
	# Direction change < 15° → no buffer (R01-F05 dead zone).
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	# Tiny rotation: ~10° from -Z.
	var slight: Vector3 = Vector3(sin(deg_to_rad(10.0)), 0.0, -cos(deg_to_rad(10.0)))
	player.apply_movement_step(slight, false, SUB_DT)
	assert_almost_eq(player._committed_input_dir.x, slight.x, 0.01,
		"Within dead zone, committed must follow intended")


func test_buffer_flushes_on_dribble_touch() -> void:
	# Buffer engages on turn → next touch snapshots intended → committed
	# updates and buffer disengages.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)  ## buffer engages
	assert_true(player._input_buffer_active)
	# Touch fires.
	player.on_dribble_touch()
	assert_false(player._input_buffer_active,
		"Touch must clear the buffer flag")
	assert_eq(player._committed_input_dir, -FORWARD,
		"Touch snapshots latest intended into committed (Q3)")


func test_buffer_flushes_on_possession_lost() -> void:
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)  ## buffer engages
	# Possession lost.
	player.on_possession_lost()
	assert_false(player._input_buffer_active,
		"Possession loss must clear buffer flag")
	assert_eq(player._committed_input_dir, -FORWARD,
		"Possession loss snapshots intended into committed (Q7 flush)")


func test_buffer_caps_at_max_duration() -> void:
	# Q7: buffer caps at DIRECTION_BUFFER_MAX_S (0.8 s) even if no touch.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)  ## engage
	assert_true(player._input_buffer_active)
	# Tick well past the cap (0.8 s) without firing a touch.
	for _i in 110:  ## 110 * 1/120 ≈ 0.916 s > 0.8 s cap
		player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_false(player._input_buffer_active,
		"Buffer must auto-flush after MAX_S timeout (Q7 safety cap)")
	assert_eq(player._committed_input_dir, -FORWARD,
		"Cap timeout commits intended")


func test_facing_uses_intended_during_buffer() -> void:
	# Q1: even while velocity stays buffered, mesh facing rotates
	# toward intended direction immediately.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	# Sharp turn — buffer engages.
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._facing_target, -FORWARD,
		"Facing target follows INTENDED direction during buffer (Q1)")


func test_sprint_immediate_during_buffer() -> void:
	# Q6: sprint toggle is NOT buffered, applies same tick.
	player.has_ball = true
	player.stamina = 1.0
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	# Engage buffer with a turn AND simultaneously start sprinting.
	player.apply_movement_step(-FORWARD, true, SUB_DT)
	# Velocity follows OLD direction (FORWARD = -Z) but at SPRINT speed.
	assert_lt(player.velocity.z, 0.0,
		"Velocity still in OLD direction (-Z) during buffer")
	# Sprint applied — stamina drained this tick.
	assert_lt(player.stamina, 1.0, "Sprint immediate even during buffer")


func test_buffer_inactive_during_busy_state() -> void:
	# Q8: during SHOOTING / PASSING anim window, input frozen — buffer
	# never engages, committed stays at whatever it was.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()
	player.apply_movement_step(FORWARD, false, SUB_DT)
	# Enter PASSING state — input now ignored regardless.
	player.state = Player.State.PASSING
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, FORWARD,
		"During busy ball-action, committed direction frozen (Q8)")
