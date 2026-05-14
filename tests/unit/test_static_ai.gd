extends GutTest

## Sprint 8 T04 — StaticAI tactical positioning tests.
## Drives `step()` / `tick_targets()` directly with explicit ball
## positions; no SceneTree timing.

const FORMATION_PATH := "res://resources/formations/formation_2_1_1.tres"
const TEAM_A_PATH := "res://resources/teams/team_a.tres"
const TEAM_B_PATH := "res://resources/teams/team_b.tres"

var formation: FormationData
var team_a: TeamController
var team_b: TeamController
var players_a: Array[Player] = []
var players_b: Array[Player] = []
var ball: Node3D
var ai: StaticAI


func before_each() -> void:
	formation = load(FORMATION_PATH) as FormationData
	var ta: TeamConfig = (load(TEAM_A_PATH) as TeamConfig).duplicate(true)
	var tb: TeamConfig = (load(TEAM_B_PATH) as TeamConfig).duplicate(true)
	players_a = _spawn_team(ta, false)  ## Team A defends -Z
	players_b = _spawn_team(tb, true)   ## Team B defends +Z (mirrored)
	team_a = _make_team(players_a, ta, true)
	team_b = _make_team(players_b, tb, false)
	# Stand-in ball — StaticAI only reads `global_position`.
	ball = Node3D.new()
	add_child(ball)
	ball.global_position = Vector3.ZERO
	ai = StaticAI.new()
	ai.team_controller = team_b
	ai.ball_ref = ball
	ai.formation = formation
	ai.mirror_anchors = true
	add_child(ai)


func after_each() -> void:
	for p in players_a + players_b:
		if is_instance_valid(p):
			p.queue_free()
	for n in [team_a, team_b, ball, ai]:
		if is_instance_valid(n):
			n.queue_free()
	players_a.clear()
	players_b.clear()
	formation = null
	team_a = null
	team_b = null
	ball = null
	ai = null


# ---- Helpers ------------------------------------------------------------

func _spawn_team(team: TeamConfig, mirror_z: bool) -> Array[Player]:
	var arr: Array[Player] = []
	for i in range(formation.role_count()):
		var p: Player = preload("res://scenes/Player.tscn").instantiate() as Player
		p.team_config = team
		p.role_index = i
		p.is_goalkeeper = formation.is_goalkeeper_role(i)
		p.name = "%s_%s" % [team.team_name.replace(" ", ""), formation.role_labels[i]]
		add_child(p)
		p.global_position = formation.get_anchor_mirrored(i) if mirror_z \
			else formation.role_anchors[i]
		arr.append(p)
	return arr


func _make_team(players: Array[Player], cfg: TeamConfig, is_human: bool) -> TeamController:
	var tc: TeamController = TeamController.new()
	tc.players = players
	tc.team_config = cfg
	tc.is_human = is_human
	add_child(tc)
	return tc


# ---- Role factor + anchor formula (R05-F02 / F03 / F05) ----------------

func test_target_uses_role_factor_for_each_outfield_role() -> void:
	# Ball at known position → each non-GK player must receive
	# target = anchor_mirrored + (ball - anchor_mirrored) * role_factor.
	ball.global_position = Vector3(10.0, 0.0, 20.0)
	ai.tick_targets()
	for i in range(formation.role_count()):
		var p: Player = players_b[i]
		if p.is_goalkeeper:
			# GK is owned by Goalkeeper.gd (T05) — StaticAI must skip it.
			assert_false(p._has_static_target,
				"Goalkeeper must NOT receive a static-AI target (T05 owns it)")
			continue
		var anchor: Vector3 = formation.get_anchor_mirrored(i)
		var factor: float = ai._role_factor_for(i)
		var expected: Vector3 = anchor + (ball.global_position - anchor) * factor
		expected.y = 0.0
		assert_true(p._has_static_target,
			"Outfield player %d must receive a static-AI target" % i)
		assert_almost_eq(p._static_target_pos.x, expected.x, 0.001,
			"Player %d target X must equal anchor+(ball-anchor)*factor" % i)
		assert_almost_eq(p._static_target_pos.z, expected.z, 0.001,
			"Player %d target Z must equal anchor+(ball-anchor)*factor" % i)


func test_role_factor_gradient_is_monotonic() -> void:
	# R05-F05 — gradient must remain GK < DEF < MID < ATT.
	assert_lt(StaticAI.ROLE_FACTOR_GK, StaticAI.ROLE_FACTOR_DEF,
		"GK factor must be lower than DEF")
	assert_lt(StaticAI.ROLE_FACTOR_DEF, StaticAI.ROLE_FACTOR_MID,
		"DEF factor must be lower than MID")
	assert_lt(StaticAI.ROLE_FACTOR_MID, StaticAI.ROLE_FACTOR_ATT,
		"MID factor must be lower than ATT")


# ---- Skip humans (R05 spec: humans driven by PlayerController) ---------

func test_skips_human_team_players() -> void:
	# Reconfigure AI to point at Team A (is_human = true) — defensive
	# guard against a wiring mistake.
	ai.team_controller = team_a
	ai.mirror_anchors = false
	ai.tick_targets()
	for p in players_a:
		assert_false(p._has_static_target,
			"Human-team player %s must NOT receive a static-AI target" % p.name)


# ---- 2 Hz tactical update rate (R05-F01) -------------------------------

func test_step_updates_at_2_hz_not_per_tick() -> void:
	# 5 calls of 0.05 s = 0.25 s total → strictly less than 0.5 s
	# (= 1 / update_hz at 2 Hz). NO target should be set yet.
	for _i in 5:
		ai.step(0.05)
	for p in players_b:
		if p.is_goalkeeper:
			continue
		assert_false(p._has_static_target,
			"No update should fire before the 2 Hz interval elapses")
	# One more 0.05 s step pushes total to 0.30 s — still under 0.5 s.
	ai.step(0.05)
	for p in players_b:
		if p.is_goalkeeper:
			continue
		assert_false(p._has_static_target,
			"Still no update at 0.30 s (interval = 0.50 s)")
	# Now jump past the interval.
	ai.step(0.25)  ## 0.55 s total — overflow
	for p in players_b:
		if p.is_goalkeeper:
			continue
		assert_true(p._has_static_target,
			"Update must fire once the 0.5 s interval elapses")
