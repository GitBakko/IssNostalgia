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


# ---- S08 direction buffer is INERT after fix12 -----------------------
#
# The buffer was removed because turn-glue keeps the ball locked to
# the foot regardless of the carrier's velocity, which makes the
# "delay velocity to avoid losing the ball on a turn" hack
# unnecessary AND visibly wrong (it produced a drift feel — mesh
# faced new direction, body kept moving the old way). Velocity now
# tracks intended input directly. Q8 SHOOTING/PASSING freeze is
# preserved.

func test_velocity_tracks_intended_immediately_with_ball() -> void:
	# Sharp turn while carrying — committed direction must follow
	# intended same tick (no buffer delay).
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.on_dribble_touch()  ## previously armed the buffer; now no-op
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, -FORWARD,
		"Committed direction must follow intended immediately, even mid-carry")
	assert_false(player._input_buffer_active,
		"Buffer flag must remain inactive after fix12")


func test_velocity_tracks_intended_without_ball() -> void:
	player.has_ball = false
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, -FORWARD,
		"Without ball, commit always follows intended")


func test_facing_target_follows_intended_input() -> void:
	# Q1 still holds — facing tracks the latest intended direction.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._facing_target, -FORWARD,
		"Facing target follows intended direction immediately")


func test_busy_state_freezes_committed_direction() -> void:
	# Q8 preserved — during SHOOTING/PASSING the prior commit is held.
	player.has_ball = true
	player.apply_movement_step(FORWARD, false, SUB_DT)
	player.state = Player.State.PASSING
	player.apply_movement_step(-FORWARD, false, SUB_DT)
	assert_eq(player._committed_input_dir, FORWARD,
		"During busy ball-action, committed direction frozen (Q8)")


# ---- S09-T01 per-player attributes -------------------------------------

func test_player_attributes_default_to_midpoint() -> void:
	# A bare Player must expose neutral 0.5 attributes so legacy
	# tests / scenes that don't populate TeamConfig still get
	# midpoint-skill behaviour.
	assert_eq(player.close_control, 0.5,
		"Default close_control must be midpoint 0.5")
	assert_eq(player.dribble_skill, 0.5,
		"Default dribble_skill must be midpoint 0.5")
	assert_false(player.has_tight_control,
		"has_tight_control must default to false")


# ---- S09-T02 close-control modal API ---------------------------------

func test_carry_offset_collapses_to_min_when_stopped_with_tight_control() -> void:
	# At rest + tight_control held + max close_control → ball sits
	# at the foot (offset = min).
	player.close_control = 1.0
	player.has_tight_control = true
	var offset: float = player.get_effective_carry_offset(0.0, 0.55)
	assert_almost_eq(offset, 0.30, 0.001,
		"Stopped tight-control elite must collapse to min_offset (0.30)")


func test_carry_offset_uses_base_when_sprinting_and_low_skill() -> void:
	# Full speed + zero closeness → offset rides the base.
	player.close_control = 0.0
	player.has_tight_control = false
	var offset: float = player.get_effective_carry_offset(player.max_walk_speed, 0.55)
	assert_almost_eq(offset, 0.55, 0.005,
		"Sprinting low-skill carrier must ride the base offset")


func test_loss_threshold_extended_by_tight_control_modal() -> void:
	player.close_control = 0.0
	player.has_tight_control = true
	var threshold: float = player.get_effective_loss_threshold(3.0)
	assert_almost_eq(threshold, 3.75, 0.001,
		"Tight-control modal adds +25 % of base (3.0 → 3.75)")


func test_loss_threshold_extended_by_close_control_attribute() -> void:
	player.close_control = 1.0
	player.has_tight_control = false
	var threshold: float = player.get_effective_loss_threshold(3.0)
	assert_almost_eq(threshold, 3.45, 0.001,
		"Max close_control adds +15 % of base (3.0 → 3.45)")
