extends GutTest

## Sprint 6 T05 — GameMatch.tscn smoke tests.
## Verifies the scene boots, spawns 10 players in correct positions, wires
## controllers, and HUD updates. No visual / FPS check here (manual).

var scene_root: Node


func before_each() -> void:
	scene_root = preload("res://scenes/GameMatch.tscn").instantiate()
	add_child(scene_root)
	# Wait one frame so _ready runs; GUT add_child triggers _ready immediately,
	# but extra await is harmless.


func after_each() -> void:
	if is_instance_valid(scene_root):
		scene_root.queue_free()
	scene_root = null


func test_scene_spawns_ten_players_total() -> void:
	var match_node: GameMatch = scene_root as GameMatch
	assert_not_null(match_node, "Root must be a GameMatch")
	assert_eq(match_node.players_a.size(), 5, "Team A: 5 players")
	assert_eq(match_node.players_b.size(), 5, "Team B: 5 players")


func test_team_a_is_human_team_b_is_ai_by_default() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_true(m.team_a_ctrl.is_human, "Team A defaults to human")
	assert_false(m.team_b_ctrl.is_human, "Team B defaults to AI")
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
	assert_not_null(m.mock_ball, "MockBall must be wired")
	assert_almost_eq(m.mock_ball.global_position.y, 0.11, 1.0e-3,
		"MockBall sits at ball-radius height (no physics yet, just visual)")


# ---- T06 — debug ball move + both_human ---------------------------------

func test_debug_move_ball_relative_updates_position() -> void:
	var m: GameMatch = scene_root as GameMatch
	var p0: Vector3 = m.mock_ball.global_position
	m.move_ball_relative(2.0, -3.0)
	assert_almost_eq(m.mock_ball.global_position.x, p0.x + 2.0, 1.0e-3)
	assert_almost_eq(m.mock_ball.global_position.z, p0.z - 3.0, 1.0e-3)
	assert_almost_eq(m.mock_ball.global_position.y, p0.y, 1.0e-3,
		"Y stays at ball-radius height (debug move is XZ only)")


func test_debug_random_ball_inside_field_bounds() -> void:
	var m: GameMatch = scene_root as GameMatch
	# Run several randomisations — each must land within the configured
	# half-field bounds.
	for _i in 20:
		m.randomize_ball_position()
		var p: Vector3 = m.mock_ball.global_position
		assert_lte(absf(p.x), m.debug_ball_field_half_x + 1.0e-3,
			"Random ball X must respect debug_ball_field_half_x cap")
		assert_lte(absf(p.z), m.debug_ball_field_half_z + 1.0e-3,
			"Random ball Z must respect debug_ball_field_half_z cap")


func test_both_human_disabled_team_b_has_no_player_controller() -> void:
	# Default scene has both_human=false.
	var m: GameMatch = scene_root as GameMatch
	assert_false(m.both_human, "Scene default: both_human=false")
	assert_null(m.team_b_player_ctrl,
		"Without both_human, Team B must NOT spawn a PlayerController")
	assert_false(m.team_b_ctrl.is_human,
		"Without both_human, Team B is AI side")


func test_both_human_enabled_spawns_p2_controller() -> void:
	# Tear down the default scene and rebuild with both_human=true.
	scene_root.queue_free()
	scene_root = preload("res://scenes/GameMatch.tscn").instantiate()
	(scene_root as GameMatch).both_human = true
	add_child(scene_root)
	var m: GameMatch = scene_root as GameMatch
	assert_true(m.both_human)
	assert_not_null(m.team_b_player_ctrl,
		"both_human=true must spawn a PlayerController for Team B")
	assert_eq(m.team_b_player_ctrl.action_prefix, "p2_",
		"Team B controller must use the p2_ action prefix")
	assert_true(m.team_b_ctrl.is_human,
		"both_human=true flips Team B to human-driven")
	assert_eq(m.team_b_ctrl.controller, m.team_b_player_ctrl,
		"Team B controller wired to its own PlayerController")
