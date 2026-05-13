extends GutTest

## Sprint 6 T04 — TeamController auto-switch + hysteresis + manual cycle.
## All tests drive `step_autoswitch()` directly with explicit ball positions
## and player positions; no SceneTree timing dependency.

const FORMATION_PATH := "res://resources/formations/formation_2_1_1.tres"
const TEAM_A_PATH := "res://resources/teams/team_a.tres"

var team_ctrl: TeamController
var controller: PlayerController
var ball: Node3D
var players: Array[Player] = []


func before_each() -> void:
	var team: TeamConfig = (load(TEAM_A_PATH) as TeamConfig).duplicate(true)
	var formation: FormationData = load(FORMATION_PATH) as FormationData
	# Spawn 5 players (4 outfield + 1 GK) at formation anchors.
	players.clear()
	for i in range(formation.role_count()):
		var p: Player = preload("res://scenes/Player.tscn").instantiate() as Player
		p.team_config = team
		p.role_index = i
		p.is_goalkeeper = formation.is_goalkeeper_role(i)
		add_child(p)
		p.global_position = formation.role_anchors[i]
		players.append(p)
	ball = Node3D.new()
	add_child(ball)
	ball.global_position = Vector3.ZERO
	controller = PlayerController.new()
	controller.player = players[0]
	add_child(controller)
	team_ctrl = TeamController.new()
	team_ctrl.players = players
	team_ctrl.controller = controller
	team_ctrl.team_config = team
	team_ctrl.ball_ref = ball
	team_ctrl.is_human = true
	add_child(team_ctrl)
	# _ready picks first outfield as active.


func after_each() -> void:
	for p in players:
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	if is_instance_valid(controller):
		controller.queue_free()
	if is_instance_valid(team_ctrl):
		team_ctrl.queue_free()
	if is_instance_valid(ball):
		ball.queue_free()
	team_ctrl = null
	controller = null
	ball = null


# ---- threshold + hold frames ---------------------------------------------

func test_autoswitch_triggers_after_three_hold_frames() -> void:
	# Move active player far from ball; another player close. After 3
	# consecutive ticks of "wants_switch" → commit.
	players[team_ctrl.active_index].global_position = Vector3(20.0, 0.0, 0.0)
	# DEF_LEFT (index 0) is the active by default. Put DEF_RIGHT (1) right on the ball.
	players[1].global_position = Vector3(0.5, 0.0, 0.0)
	var initial_active: int = team_ctrl.active_index
	team_ctrl.step_autoswitch()  # frame 1
	team_ctrl.step_autoswitch()  # frame 2
	assert_eq(team_ctrl.active_index, initial_active,
		"Switch must NOT fire before SWITCH_HOLD_FRAMES (3) ticks elapse")
	team_ctrl.step_autoswitch()  # frame 3 — commits
	assert_ne(team_ctrl.active_index, initial_active,
		"Switch must commit on the 3rd consecutive eligible tick")


func test_autoswitch_dead_zone_holds_active() -> void:
	# Active at exactly 8.2 m — inside the dead zone [7.5, 8.5]. No switch
	# even with a closer player available.
	players[team_ctrl.active_index].global_position = Vector3(8.2, 0.0, 0.0)
	players[1].global_position = Vector3(0.5, 0.0, 0.0)
	var initial_active: int = team_ctrl.active_index
	for _i in 10:
		team_ctrl.step_autoswitch()
	assert_eq(team_ctrl.active_index, initial_active,
		"Active distance inside dead zone must hold selection")


func test_autoswitch_blocked_during_shoot() -> void:
	players[team_ctrl.active_index].global_position = Vector3(20.0, 0.0, 0.0)
	players[1].global_position = Vector3(0.5, 0.0, 0.0)
	controller.is_shooting = true  # block guard
	var initial_active: int = team_ctrl.active_index
	for _i in 10:
		team_ctrl.step_autoswitch()
	assert_eq(team_ctrl.active_index, initial_active,
		"Auto-switch must NOT fire while controller.is_shooting is true")


func test_autoswitch_blocked_during_pass() -> void:
	players[team_ctrl.active_index].global_position = Vector3(20.0, 0.0, 0.0)
	players[1].global_position = Vector3(0.5, 0.0, 0.0)
	controller.is_passing = true
	var initial_active: int = team_ctrl.active_index
	for _i in 10:
		team_ctrl.step_autoswitch()
	assert_eq(team_ctrl.active_index, initial_active,
		"Auto-switch must NOT fire while controller.is_passing is true")


func test_autoswitch_resets_hold_when_target_changes() -> void:
	# Frame 1+2 with player[1] closest, then ball moves so player[2] is
	# closest. Hold counter must restart — no switch on tick 3 to player[1].
	players[team_ctrl.active_index].global_position = Vector3(20.0, 0.0, 0.0)
	players[1].global_position = Vector3(2.0, 0.0, 0.0)
	players[2].global_position = Vector3(15.0, 0.0, 0.0)
	team_ctrl.step_autoswitch()  # target = player 1, frames = 1
	team_ctrl.step_autoswitch()  # target = player 1, frames = 2
	# Move ball so player 2 becomes closest.
	ball.global_position = Vector3(15.0, 0.0, 0.0)
	team_ctrl.step_autoswitch()  # target switches to player 2, frames = 1
	# active should still be the original.
	assert_ne(team_ctrl.active_index, 1,
		"Hold counter must reset when target changes — no switch to old target")


# ---- manual cycle Q -------------------------------------------------------

func test_manual_cycle_mutes_autoswitch_for_cooldown_window() -> void:
	# S06-D31: a manual cycle/set_active should suspend autoswitch for
	# MANUAL_OVERRIDE_FRAMES so the user's choice actually sticks.
	# Setup: ball near player[3] (F at +5,0,5); active = 0 (LB at -15,0,-35).
	players[0].global_position = Vector3(-15.0, 0.0, -35.0)
	players[3].global_position = Vector3(0.0, 0.0, 5.0)
	ball.global_position = Vector3(0.0, 0.0, 5.0)
	# Without manual override, autoswitch would target player 3 immediately.
	# Trigger a manual cycle (0 → 1 RB) and verify autoswitch is muted.
	team_ctrl.cycle_active_outfield()
	assert_eq(team_ctrl.active_index, 1, "Cycle moves active 0 → 1")
	# Run autoswitch many frames — must NOT revert to 3 within the cooldown.
	for _i in TeamController.MANUAL_OVERRIDE_FRAMES - 1:
		team_ctrl.step_autoswitch()
	assert_eq(team_ctrl.active_index, 1,
		"Autoswitch must stay muted during the manual-override cooldown")
	# After the cooldown expires, autoswitch resumes — needs an additional
	# SWITCH_HOLD_FRAMES ticks to commit the new target (player 3).
	for _i in TeamController.SWITCH_HOLD_FRAMES + 1:
		team_ctrl.step_autoswitch()
	assert_eq(team_ctrl.active_index, 3,
		"After cooldown + hold frames autoswitch reverts to closest (player 3)")


func test_cycle_active_outfield_skips_goalkeeper() -> void:
	# Default active index = 0 (DEF_LEFT). Cycle should hit 1, 2, 3, then
	# wrap back to 0 — never 4 (GK).
	var seen: Array[int] = []
	for _i in 5:
		team_ctrl.cycle_active_outfield()
		seen.append(team_ctrl.active_index)
	assert_false(seen.has(4), "GK index 4 must never be selected by cycle, got %s" % str(seen))
	assert_eq(seen, [1, 2, 3, 0, 1] as Array[int],
		"Cycle must visit outfield indices in order, wrapping past GK")


# ---- AI team has no auto-switch + no indicators --------------------------

func test_ai_team_has_no_indicators() -> void:
	team_ctrl.is_human = false
	team_ctrl._refresh_indicator_visuals()
	for p in players:
		var ring: Node = p.get_node_or_null("SelectionIndicator")
		assert_not_null(ring, "Indicator node still exists")
		assert_false((ring as MeshInstance3D).visible,
			"AI-team indicators must be hidden")


func test_human_team_active_indicator_more_opaque_than_others() -> void:
	team_ctrl.is_human = true
	team_ctrl.set_active(2)  # MID
	for i in range(players.size()):
		var ring: MeshInstance3D = players[i].get_node("SelectionIndicator")
		assert_true(ring.visible, "Human-team indicators must be visible (player %d)" % i)
		var mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
		assert_not_null(mat, "Material override set on indicator")
		var expected_alpha: float = (
			TeamController.INDICATOR_ACTIVE_ALPHA
			if i == 2
			else TeamController.INDICATOR_DIM_ALPHA
		)
		assert_almost_eq(mat.albedo_color.a, expected_alpha, 1.0e-3,
			"Indicator alpha must be %.2f for player %d (active = %d)" % [
				expected_alpha, i, team_ctrl.active_index,
			])


# ---- controller follows active player ------------------------------------

func test_controller_player_ref_updates_on_switch() -> void:
	team_ctrl.set_active(2)
	assert_eq(controller.player, players[2],
		"controller.player must point at the new active after switch")
	team_ctrl.cycle_active_outfield()
	assert_eq(controller.player, players[team_ctrl.active_index],
		"controller.player must follow cycle_active_outfield")
