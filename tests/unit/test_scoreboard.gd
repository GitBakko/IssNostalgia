extends GutTest

## Sprint 9 T03 — Scoreboard tests.

var sb: Scoreboard


func before_each() -> void:
	sb = Scoreboard.new()
	add_child(sb)


func after_each() -> void:
	if is_instance_valid(sb):
		sb.queue_free()
	sb = null


func test_initial_state_is_zero_zero() -> void:
	assert_eq(sb.team_a_goals, 0)
	assert_eq(sb.team_b_goals, 0)


func test_register_goal_increments_team() -> void:
	sb.register_goal(Scoreboard.TEAM_A)
	assert_eq(sb.team_a_goals, 1)
	assert_eq(sb.team_b_goals, 0)
	sb.register_goal(Scoreboard.TEAM_B)
	sb.register_goal(Scoreboard.TEAM_B)
	assert_eq(sb.team_b_goals, 2)


func test_register_goal_emits_goal_scored_signal() -> void:
	var events: Array = []
	sb.goal_scored.connect(func(team, total): events.append([team, total]))
	sb.register_goal(Scoreboard.TEAM_A)
	sb.register_goal(Scoreboard.TEAM_A)
	sb.register_goal(Scoreboard.TEAM_B)
	assert_eq(events.size(), 3)
	assert_eq(events[0], [Scoreboard.TEAM_A, 1])
	assert_eq(events[1], [Scoreboard.TEAM_A, 2])
	assert_eq(events[2], [Scoreboard.TEAM_B, 1])


func test_register_goal_emits_score_changed_signal() -> void:
	var snapshots: Array = []
	sb.score_changed.connect(func(a, b): snapshots.append([a, b]))
	sb.register_goal(Scoreboard.TEAM_A)
	sb.register_goal(Scoreboard.TEAM_B)
	assert_eq(snapshots.size(), 2)
	assert_eq(snapshots[0], [1, 0])
	assert_eq(snapshots[1], [1, 1])


func test_goal_gap_from_team_perspective() -> void:
	sb.register_goal(Scoreboard.TEAM_B)
	sb.register_goal(Scoreboard.TEAM_B)
	# Team A is trailing by 2 → gap_from(A) = +2.
	assert_eq(sb.goal_gap_from(Scoreboard.TEAM_A), 2)
	# Team B is leading by 2 → gap_from(B) = -2.
	assert_eq(sb.goal_gap_from(Scoreboard.TEAM_B), -2)


func test_reset_clears_score_and_emits() -> void:
	sb.register_goal(Scoreboard.TEAM_A)
	var snapshots: Array = []
	sb.score_changed.connect(func(a, b): snapshots.append([a, b]))
	sb.reset()
	assert_eq(sb.team_a_goals, 0)
	assert_eq(sb.team_b_goals, 0)
	assert_eq(snapshots.size(), 1)
	assert_eq(snapshots[0], [0, 0])
