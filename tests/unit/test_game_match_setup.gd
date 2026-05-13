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
	assert_true(lbl.text.contains("ACTIVE"), "HUD label must include 'ACTIVE' tag")
	assert_true(lbl.text.contains("TEAM A"), "HUD must show team A name")


func test_mock_ball_present_at_origin_height() -> void:
	var m: GameMatch = scene_root as GameMatch
	assert_not_null(m.mock_ball, "MockBall must be wired")
	assert_almost_eq(m.mock_ball.global_position.y, 0.11, 1.0e-3,
		"MockBall sits at ball-radius height (no physics yet, just visual)")
