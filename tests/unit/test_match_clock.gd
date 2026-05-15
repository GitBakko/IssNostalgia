extends GutTest

## Sprint 9 T03 — MatchClock countdown tests.

var clock: MatchClock


func before_each() -> void:
	clock = MatchClock.new()
	clock.match_duration_s = 240.0
	clock.auto_start = false
	add_child(clock)


func after_each() -> void:
	if is_instance_valid(clock):
		clock.queue_free()
	clock = null


func test_clock_decrements_per_step_when_running() -> void:
	clock.start()
	clock.step(1.0)
	assert_almost_eq(clock.current_time_remaining_s, 239.0, 0.001,
		"After 1 s step, remaining = duration - 1")


func test_clock_does_not_decrement_when_paused() -> void:
	clock.start()
	clock.pause()
	clock.step(1.0)
	assert_eq(clock.current_time_remaining_s, 240.0,
		"Paused clock must not decrement")


func test_clock_emits_half_minute_signal_on_bucket_crossing() -> void:
	clock.start()
	var emitted: Array = []
	clock.half_minute_elapsed.connect(func(remaining): emitted.append(remaining))
	# Step 31 s — crosses from bucket 8 (240 s) to bucket 7 (≤210 s).
	clock.step(31.0)
	assert_eq(emitted.size(), 1,
		"Half-minute signal must fire once per bucket crossing")


func test_clock_does_not_double_emit_within_same_bucket() -> void:
	clock.start()
	var emitted: Array = []
	clock.half_minute_elapsed.connect(func(remaining): emitted.append(remaining))
	clock.step(15.0)  ## still bucket 8
	clock.step(10.0)  ## still bucket 8
	assert_eq(emitted.size(), 0,
		"No emission until bucket actually crosses")


func test_clock_clamps_to_zero_and_emits_match_ended() -> void:
	clock.match_duration_s = 1.0
	clock.reset(1.0)
	clock.start()
	var ended: Array = []
	clock.match_ended.connect(func(): ended.append(true))
	clock.step(2.0)
	assert_eq(clock.current_time_remaining_s, 0.0,
		"Clock must clamp at zero")
	assert_eq(ended.size(), 1, "match_ended must fire exactly once")
	assert_false(clock.is_running, "Clock stops on end")


func test_clock_reset_restarts_timer() -> void:
	clock.start()
	clock.step(60.0)
	clock.reset(120.0)
	assert_eq(clock.current_time_remaining_s, 120.0,
		"reset(120) sets remaining to 120")
	assert_false(clock.is_running, "reset stops the clock")
