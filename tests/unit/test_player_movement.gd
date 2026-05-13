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
	# Force a 90° turn and check the basis converges over multiple ticks.
	player._facing_target = Vector3(1.0, 0.0, 0.0)  # face +X
	# Initial: -Z basis vector points along world -Z (default capsule basis).
	for _i in 240:  ## 2 s
		player.update_facing(SUB_DT)
	# After 2 s the slerp should have nearly completed (alpha per tick
	# ≈ 0.045 with rotation_speed=8). -Z of basis should now point ~+X.
	var forward: Vector3 = -player.transform.basis.z
	assert_almost_eq(forward.x, 1.0, 0.05,
		"Basis -Z must rotate to +X, got %s" % forward)


# ---- team-colour application ----------------------------------------------

func test_team_colour_applied_to_body_mesh() -> void:
	var body: MeshInstance3D = player.get_node("BodyMesh") as MeshInstance3D
	assert_not_null(body)
	var mat: StandardMaterial3D = body.material_override as StandardMaterial3D
	assert_not_null(mat,
		"Body mesh material_override must be set after _ready()")
	assert_eq(mat.albedo_color, team.primary_color,
		"Body mesh albedo must match team primary colour")
