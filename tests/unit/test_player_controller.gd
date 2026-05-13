extends GutTest

## Sprint 6 T03 — PlayerController input bridge + buffer + coyote tests.
## Drives the controller via its public APIs (record_press / consume /
## was_recently_valid / step_movement). No global Input poll, no
## scene-tick coupling.

const SUB_DT: float = 1.0 / 120.0

var player: Player
var controller: PlayerController
var team: TeamConfig


func before_each() -> void:
	team = (load("res://resources/teams/team_a.tres") as TeamConfig).duplicate(true)
	player = preload("res://scenes/Player.tscn").instantiate() as Player
	player.team_config = team
	add_child(player)
	controller = PlayerController.new()
	controller.player = player
	add_child(controller)


func after_each() -> void:
	if is_instance_valid(controller):
		controller.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	controller = null
	player = null
	team = null


# ---- step_movement bridge -------------------------------------------------

func test_step_movement_drives_player_velocity() -> void:
	var forward: Vector3 = Vector3(0.0, 0.0, -1.0)
	for _i in 60:
		controller.step_movement(forward, false, SUB_DT)
	assert_gt(player.velocity.length(), 5.0,
		"After 0.5 s of forward input the player should be moving")
	assert_lte(player.velocity.length(), player.max_walk_speed + 1.0e-3,
		"Walk-only must respect Player walk-speed clamp")


func test_step_movement_diagonal_normalised() -> void:
	# Forward + right at unit magnitudes — the controller's normalisation
	# happens inside `_read_movement_input`, but `step_movement` itself
	# accepts the vector as-is. Confirm Player's apply_movement_step
	# handles |input| > 1 correctly (defensive normalisation inside it).
	var diag: Vector3 = Vector3(1.0, 0.0, -1.0)  # |diag| = sqrt(2) ≈ 1.41
	for _i in 60:
		controller.step_movement(diag, false, SUB_DT)
	assert_lte(player.velocity.length(), player.max_walk_speed + 1.0e-3,
		"Diagonal input must NOT exceed walk-speed cap")


# ---- input buffer (R09-F05) -----------------------------------------------

func test_consume_buffered_returns_true_within_window() -> void:
	controller.record_press(&"shoot_charge")
	assert_true(controller.consume_buffered(&"shoot_charge"),
		"A press recorded right now must be consumable immediately")


func test_consume_buffered_consumes_so_double_fire_blocked() -> void:
	controller.record_press(&"shoot_charge")
	assert_true(controller.consume_buffered(&"shoot_charge"))
	assert_false(controller.consume_buffered(&"shoot_charge"),
		"After consuming once, the same press must not fire a second time")


func test_consume_buffered_expires_after_window() -> void:
	controller.buffer_window_ms = 50.0
	controller.record_press(&"shoot_charge")
	# Sleep past the window. OS.delay_msec is allowed in headless tests.
	OS.delay_msec(80)
	assert_false(controller.consume_buffered(&"shoot_charge"),
		"After 80 ms with a 50 ms window the buffered press must expire")


func test_consume_buffered_unknown_action_returns_false() -> void:
	assert_false(controller.consume_buffered(&"nonexistent_action"),
		"Querying an action not in ACTION_SUFFIXES must safely return false")


# ---- coyote (Sprint 7+ consumer; framework smoke test) -------------------

func test_was_recently_valid_within_coyote_window() -> void:
	controller.coyote_window_frames = 6  # 50 ms @ 120 Hz
	controller.record_press(&"pass_ball")
	assert_true(controller.was_recently_valid(&"pass_ball"),
		"Within 50 ms of a press, coyote check must report still valid")


func test_was_recently_valid_outside_window() -> void:
	controller.coyote_window_frames = 6  # 50 ms
	controller.record_press(&"pass_ball")
	OS.delay_msec(100)
	assert_false(controller.was_recently_valid(&"pass_ball"),
		"100 ms after press with a 50 ms coyote window must report invalid")


func test_was_recently_valid_does_not_consume() -> void:
	controller.record_press(&"pass_ball")
	assert_true(controller.was_recently_valid(&"pass_ball"))
	# Coyote check is non-destructive — a subsequent buffer consume must
	# still find the press.
	assert_true(controller.consume_buffered(&"pass_ball"),
		"Coyote check must not consume the buffered press")


# ---- ActionMap abstraction (S06-D25) -------------------------------------

func test_action_prefix_swap_does_not_break_buffer_lookup() -> void:
	# Two controllers — one p1_, one p2_ — must independently buffer actions
	# without interfering. (Actual InputMap binding belongs to T06.)
	var c2: PlayerController = PlayerController.new()
	c2.player = player
	c2.action_prefix = "p2_"
	add_child(c2)
	controller.record_press(&"shoot_charge")
	assert_true(controller.consume_buffered(&"shoot_charge"))
	assert_false(c2.consume_buffered(&"shoot_charge"),
		"p2 controller must not see p1's buffered press")
	c2.queue_free()
