extends GutTest

## Smoke tests for Sprint 6 T01 — TeamConfig + FormationData resources.
## Pure data validation; no scene needed.


func test_formation_2_1_1_loads() -> void:
	var fd: FormationData = load("res://resources/formations/formation_2_1_1.tres") as FormationData
	assert_not_null(fd, "formation_2_1_1.tres must load as FormationData")
	assert_eq(fd.formation_id, &"2-1-1", "formation_id matches preset name")
	assert_eq(fd.role_count(), 5, "2-1-1 = 4 outfield + 1 GK = 5 roles")


func test_formation_parallel_arrays_consistent() -> void:
	var fd: FormationData = load("res://resources/formations/formation_2_1_1.tres") as FormationData
	assert_eq(fd.role_anchors.size(), 5, "5 anchors")
	assert_eq(fd.role_offset_meters.size(), 5, "5 offsets")
	assert_eq(fd.role_names.size(), 5, "5 names")
	assert_eq(fd.role_labels.size(), 5, "5 labels")


func test_formation_role_offsets_per_decision_s06_d07() -> void:
	var fd: FormationData = load("res://resources/formations/formation_2_1_1.tres") as FormationData
	# S06-D07: DEF=6m, MID=4m, ATT=2m, GK=0m
	assert_eq(fd.role_offset_meters[0], 6.0, "def_left offset = 6 m")
	assert_eq(fd.role_offset_meters[1], 6.0, "def_right offset = 6 m")
	assert_eq(fd.role_offset_meters[2], 4.0, "mid offset = 4 m")
	assert_eq(fd.role_offset_meters[3], 2.0, "att offset = 2 m")
	assert_eq(fd.role_offset_meters[4], 0.0, "gk offset = 0 m (separate logic)")


func test_formation_gk_is_last_role() -> void:
	var fd: FormationData = load("res://resources/formations/formation_2_1_1.tres") as FormationData
	assert_true(fd.is_goalkeeper_role(4), "role index 4 = GK")
	assert_false(fd.is_goalkeeper_role(0), "role index 0 = outfield, not GK")
	assert_false(fd.is_goalkeeper_role(2), "role index 2 = MID, not GK")


func test_formation_mirror_negates_z_only() -> void:
	var fd: FormationData = load("res://resources/formations/formation_2_1_1.tres") as FormationData
	# DEF_LEFT anchor at (-15, 0, -35) → mirrored = (-15, 0, +35).
	# X preserved so left wing stays left for both teams.
	var mirrored: Vector3 = fd.get_anchor_mirrored(0)
	assert_eq(mirrored.x, -15.0, "mirror keeps X")
	assert_eq(mirrored.y, 0.0, "mirror keeps Y")
	assert_eq(mirrored.z, 35.0, "mirror negates Z")


func test_team_a_loads_blue_human() -> void:
	var tc: TeamConfig = load("res://resources/teams/team_a.tres") as TeamConfig
	assert_not_null(tc, "team_a.tres must load as TeamConfig")
	assert_eq(tc.team_name, "TEAM A")
	assert_true(tc.is_human_default, "Team A defaults to human")
	assert_eq(tc.defending_side, -1, "Team A defends -Z goal")
	assert_gt(tc.primary_color.b, tc.primary_color.r,
		"Team A is blue-dominant (b > r)")


func test_team_b_loads_red_ai() -> void:
	var tc: TeamConfig = load("res://resources/teams/team_b.tres") as TeamConfig
	assert_not_null(tc, "team_b.tres must load as TeamConfig")
	assert_eq(tc.team_name, "TEAM B")
	assert_false(tc.is_human_default, "Team B defaults to static AI")
	assert_eq(tc.defending_side, 1, "Team B defends +Z goal")
	assert_gt(tc.primary_color.r, tc.primary_color.b,
		"Team B is red-dominant (r > b)")


func test_both_teams_share_formation_id() -> void:
	var ta: TeamConfig = load("res://resources/teams/team_a.tres") as TeamConfig
	var tb: TeamConfig = load("res://resources/teams/team_b.tres") as TeamConfig
	assert_eq(ta.formation_id, tb.formation_id,
		"Phase 2 both teams use same formation 2-1-1")


# ---- S09-T01 per-player attribute accessors ---------------------------

func test_close_control_accessor_in_range() -> void:
	var tc: TeamConfig = TeamConfig.new()
	tc.close_control = [0.20, 0.40, 0.60, 0.80, 0.10]
	assert_almost_eq(tc.get_close_control(0), 0.20, 0.001)
	assert_almost_eq(tc.get_close_control(2), 0.60, 0.001)
	assert_almost_eq(tc.get_close_control(4), 0.10, 0.001)


func test_close_control_accessor_falls_back_when_out_of_range() -> void:
	var tc: TeamConfig = TeamConfig.new()
	tc.close_control = [0.7]  ## only 1 entry
	tc.default_close_control = 0.33
	assert_almost_eq(tc.get_close_control(0), 0.7, 0.001,
		"In-range index returns the array value")
	assert_almost_eq(tc.get_close_control(3), 0.33, 0.001,
		"Out-of-range index falls back to default_close_control")
	assert_almost_eq(tc.get_close_control(-1), 0.33, 0.001,
		"Negative index also falls back to default")


func test_dribble_skill_accessor_in_range_and_fallback() -> void:
	var tc: TeamConfig = TeamConfig.new()
	tc.dribble_skill = [0.9, 0.1]
	tc.default_dribble_skill = 0.5
	assert_almost_eq(tc.get_dribble_skill(0), 0.9, 0.001)
	assert_almost_eq(tc.get_dribble_skill(1), 0.1, 0.001)
	assert_almost_eq(tc.get_dribble_skill(4), 0.5, 0.001,
		"Out-of-range falls back to default_dribble_skill")
