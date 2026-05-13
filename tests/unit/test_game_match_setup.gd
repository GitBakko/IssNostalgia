extends GutTest

## Sprint 6 T05 — GameMatch.tscn smoke tests.
## Verifies the scene boots, spawns 10 players in correct positions, wires
## controllers, and HUD updates. No visual / FPS check here (manual).

var scene_root: Node


## Spawn a fresh GameMatch with `both_human` forced to the given value.
## Used by every test so results don't depend on whatever flag value the
## scene file currently carries on disk.
func _spawn_match(both_human: bool) -> GameMatch:
	if is_instance_valid(scene_root):
		scene_root.queue_free()
	scene_root = preload("res://scenes/GameMatch.tscn").instantiate()
	(scene_root as GameMatch).both_human = both_human
	add_child(scene_root)
	return scene_root as GameMatch


func before_each() -> void:
	# Default fixture: single-human (Team A only). Tests that need
	# both_human override via _spawn_match(true).
	_spawn_match(false)


func after_each() -> void:
	if is_instance_valid(scene_root):
		scene_root.queue_free()
	scene_root = null


func test_scene_spawns_ten_players_total() -> void:
	var match_node: GameMatch = scene_root as GameMatch
	assert_not_null(match_node, "Root must be a GameMatch")
	assert_eq(match_node.players_a.size(), 5, "Team A: 5 players")
	assert_eq(match_node.players_b.size(), 5, "Team B: 5 players")


func test_team_a_human_team_b_ai_when_both_human_off() -> void:
	# Configuration intent — Team A is always human; Team B follows the
	# both_human flag. Tests the wiring at flag=false.
	var m: GameMatch = scene_root as GameMatch  # already spawned with false
	assert_true(m.team_a_ctrl.is_human, "Team A is always human")
	assert_false(m.team_b_ctrl.is_human, "Team B is AI when both_human=false")
	assert_not_null(m.team_a_player_ctrl,
		"Human team A must have a PlayerController")


func test_formation_anchors_used_for_team_a() -> void:
	var m: GameMatch = scene_root as GameMatch
	for i in range(m.formation.role_count()):
		var expected: Vector3 = m.formation.role_anchors[i]
		var actual: Vector3 = m.players_a[i].global_position
		assert_almost_eq(actual.x, expected.x, 1.0e-3,
			"Team A role %d X anchor" % i)
		assert_almost_eq(actual.z, expected.z, 1.0e-3,
			"Team A role %d Z anchor" % i)


func test_team_b_anchors_mirror_z() -> void:
	var m: GameMatch = scene_root as GameMatch
	for i in range(m.formation.role_count()):
		var src: Vector3 = m.formation.role_anchors[i]
		var actual: Vector3 = m.players_b[i].global_position
		assert_almost_eq(actual.x, src.x, 1.0e-3,
			"Team B role %d X mirrored (X kept)" % i)
		assert_almost_eq(actual.z, -src.z, 1.0e-3,
			"Team B role %d Z mirrored (Z negated)" % i)


func test_active_player_is_first_outfield() -> void:
	var m: GameMatch = scene_root as GameMatch
	# DEF_LEFT (index 0) is outfield → expected initial active.
	assert_eq(m.team_a_ctrl.active_index, 0,
		"Initial active should be the first outfield role")
	assert_eq(m.team_a_player_ctrl.player, m.players_a[0],
		"PlayerController should point to active player")


func test_goalkeepers_flagged_correctly() -> void:
	var m: GameMatch = scene_root as GameMatch
	# Index 4 is GK in 2-1-1.
	assert_true(m.players_a[4].is_goalkeeper,
		"Team A GK must have is_goalkeeper = true")
	assert_true(m.players_b[4].is_goalkeeper,
		"Team B GK must have is_goalkeeper = true")
	for i in range(4):
		assert_false(m.players_a[i].is_goalkeeper,
			"Team A outfield %d must NOT be goalkeeper" % i)


func test_hud_label_updates_with_active_player() -> void:
	var m: GameMatch = scene_root as GameMatch
	m._update_hud()
	var lbl: Label = m.hud_active_label
	assert_not_null(lbl)
	assert_true(lbl.text.begins_with("P1 "),
		"HUD line for human player 1 must start with 'P1 ', got: %s" % lbl.text)
	assert_true(lbl.text.contains("TEAM A"), "HUD must show team A name")
	assert_true(lbl.text.contains("stamina"), "HUD must show stamina")


func test_mock_ball_present_at_origin_height() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_not_null(m.ball, "Ball must be wired")
	assert_almost_eq(m.ball.global_position.y, 0.11, 1.0e-3,
		"Ball sits at ball-radius height on spawn")


# ---- T05 — real Ball.tscn integration -----------------------------------

func test_real_ball_is_ballphysics_instance() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_true(m.ball is BallPhysics,
		"Ball node must be a BallPhysics RigidBody3D (real Ball.tscn)")
	assert_not_null(m.ball.config,
		"BallPhysics must carry a PhysicsConfig from the .tscn")


func test_ball_controller_wired() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_not_null(m.ball_controller, "BallController must be spawned")
	assert_eq(m.ball_controller.ball, m.ball,
		"BallController.ball must point at the scene Ball")
	assert_eq(m.ball_controller.teams.size(), 2,
		"BallController must arbitrate between both teams")


func test_shoot_pass_controllers_wired_team_a_only_when_ai_b() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_not_null(m.team_a_shooter, "Team A ShootingController must spawn")
	assert_not_null(m.team_a_passer, "Team A PassingController must spawn")
	assert_eq(m.team_a_shooter.team_controller, m.team_a_ctrl)
	assert_eq(m.team_a_shooter.ball_controller, m.ball_controller)
	assert_eq(m.team_a_passer.ball_launcher, m.ball_launcher)
	# both_human=false → Team B has no shoot/pass controllers
	assert_null(m.team_b_shooter,
		"Team B must NOT have a ShootingController when AI-driven")
	assert_null(m.team_b_passer,
		"Team B must NOT have a PassingController when AI-driven")


func test_both_human_spawns_team_b_shoot_pass() -> void:
	var m: GameMatch = _spawn_match(true)
	assert_not_null(m.team_b_shooter,
		"both_human=true must spawn Team B ShootingController")
	assert_not_null(m.team_b_passer,
		"both_human=true must spawn Team B PassingController")
	assert_eq(m.team_b_shooter.team_controller, m.team_b_ctrl)
	assert_eq(m.team_b_passer.team_controller, m.team_b_ctrl)


func test_ball_launcher_wired_to_ball() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_not_null(m.ball_launcher, "BallLauncher must spawn")
	assert_eq(m.ball_launcher.ball_path, m.ball.get_path(),
		"BallLauncher.ball_path must point at the scene Ball")


# ---- T01 (S08) — camera follow ------------------------------------------

func test_camera_rig_present_with_camera_child() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_not_null(m.camera_rig, "CameraRig Node3D must be wired")
	var cam: Camera3D = m.camera_rig.get_node_or_null(^"Camera3D") as Camera3D
	assert_not_null(cam,
		"Camera3D must be a child of CameraRig (rig translates, camera keeps offset)")


func test_camera_rig_follows_weighted_centroid_after_steps() -> void:
	var m: GameMatch = scene_root as GameMatch
	# Force ball + active player to known positions, then tick until
	# the rig converges. Initial rig position is (0,0,0) per .tscn.
	await get_tree().physics_frame
	m.ball.teleport_to(Vector3(20.0, 0.11, -10.0))
	m.players_a[0].global_position = Vector3(10.0, 0.0, -20.0)
	# Wait one physics frame so the staged teleport actually lands.
	await get_tree().physics_frame
	# Many small _process ticks to let the FR-independent lerp converge.
	for _i in 200:
		m._update_camera(1.0 / 60.0)
	# Expected centroid (0.6 ball + 0.4 player):
	#   x = 20*0.6 + 10*0.4 = 16
	#   z = -10*0.6 + -20*0.4 = -14
	assert_almost_eq(m.camera_rig.global_position.x, 16.0, 0.5,
		"CameraRig X must converge to weighted centroid X")
	assert_almost_eq(m.camera_rig.global_position.z, -14.0, 0.5,
		"CameraRig Z must converge to weighted centroid Z")
	assert_almost_eq(m.camera_rig.global_position.y, 0.0, 1.0e-3,
		"CameraRig Y stays on the pitch plane")


func test_camera_rig_clamped_to_bounds() -> void:
	var m: GameMatch = scene_root as GameMatch
	# Drag both ball and player far past the bounds — rig must clamp.
	await get_tree().physics_frame
	m.ball.teleport_to(Vector3(200.0, 0.11, 200.0))
	m.players_a[0].global_position = Vector3(200.0, 0.0, 200.0)
	await get_tree().physics_frame
	for _i in 200:
		m._update_camera(1.0 / 60.0)
	assert_almost_eq(m.camera_rig.global_position.x,
		m.camera_bounds_half_x_m, 1.0e-3,
		"CameraRig X must clamp to +camera_bounds_half_x_m")
	assert_almost_eq(m.camera_rig.global_position.z,
		m.camera_bounds_half_z_m, 1.0e-3,
		"CameraRig Z must clamp to +camera_bounds_half_z_m")


# ---- T06 — debug ball move + both_human ---------------------------------

func test_debug_move_ball_relative_updates_position() -> void:
	var m: GameMatch = scene_root as GameMatch
	# Let the ball settle from spawn before sampling (pending_teleport from
	# scene_root spawn applies on first physics tick).
	await get_tree().physics_frame
	var p0: Vector3 = m.ball.global_position
	m.move_ball_relative(2.0, -3.0)
	# teleport_to stages a pending position applied inside the integrator;
	# wait one physics tick for it to land.
	await get_tree().physics_frame
	assert_almost_eq(m.ball.global_position.x, p0.x + 2.0, 1.0e-3)
	assert_almost_eq(m.ball.global_position.z, p0.z - 3.0, 1.0e-3)
	assert_almost_eq(m.ball.global_position.y, p0.y, 1.0e-3,
		"Y stays at ball-radius height (debug move is XZ only)")


func test_debug_random_ball_inside_field_bounds() -> void:
	var m: GameMatch = scene_root as GameMatch
	# Run several randomisations — each must land within the configured
	# half-field bounds.
	for _i in 20:
		m.randomize_ball_position()
		await get_tree().physics_frame
		var p: Vector3 = m.ball.global_position
		assert_lte(absf(p.x), m.debug_ball_field_half_x + 1.0e-3,
			"Random ball X must respect debug_ball_field_half_x cap")
		assert_lte(absf(p.z), m.debug_ball_field_half_z + 1.0e-3,
			"Random ball Z must respect debug_ball_field_half_z cap")


func test_both_human_disabled_team_b_has_no_player_controller() -> void:
	var m: GameMatch = _spawn_match(false)
	assert_false(m.both_human)
	assert_null(m.team_b_player_ctrl,
		"both_human=false → Team B must NOT spawn a PlayerController")
	assert_false(m.team_b_ctrl.is_human,
		"both_human=false → Team B is AI side")


func test_both_human_enabled_spawns_p2_controller() -> void:
	var m: GameMatch = _spawn_match(true)
	assert_true(m.both_human)
	assert_not_null(m.team_b_player_ctrl,
		"both_human=true must spawn a PlayerController for Team B")
	assert_eq(m.team_b_player_ctrl.action_prefix, "p2_",
		"Team B controller must use the p2_ action prefix")
	assert_true(m.team_b_ctrl.is_human,
		"both_human=true flips Team B to human-driven")
	assert_eq(m.team_b_ctrl.controller, m.team_b_player_ctrl,
		"Team B controller wired to its own PlayerController")
