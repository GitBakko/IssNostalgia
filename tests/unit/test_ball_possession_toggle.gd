extends GutTest

## Sprint 7 T01 — BallPhysics state-toggle API surface tests.
##
## Tests the public contract: set_possessed / release / is_possessed /
## released signal. Does NOT exercise _integrate_forces through Godot's
## physics pipeline (that requires the real engine tick); the early-return
## path inside the integrator is straight-line and verified by inspection.

var ball: BallPhysics
var cfg: PhysicsConfig
var stub_carrier: Node3D
var captured_releaser: Node = null
var captured_velocity: Vector3 = Vector3.INF


func before_each() -> void:
	cfg = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	ball = BallPhysics.new()
	ball.config = cfg
	add_child(ball)
	stub_carrier = Node3D.new()
	add_child(stub_carrier)
	captured_releaser = null
	captured_velocity = Vector3.INF
	ball.released.connect(_on_released)


func after_each() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	if is_instance_valid(stub_carrier):
		stub_carrier.queue_free()
	ball = null
	stub_carrier = null
	cfg = null


func _on_released(by: Node, velocity: Vector3) -> void:
	captured_releaser = by
	captured_velocity = velocity


# ---- default state -------------------------------------------------------

func test_is_possessed_default_false() -> void:
	assert_false(ball.is_possessed(), "Fresh ball must NOT report possessed")
	assert_null(ball.get_possessor(), "Fresh ball has no possessor")


# ---- set_possessed --------------------------------------------------------

func test_set_possessed_sets_state() -> void:
	ball.set_possessed(stub_carrier)
	assert_true(ball.is_possessed(),
		"After set_possessed, is_possessed() must return true")
	assert_eq(ball.get_possessor(), stub_carrier,
		"get_possessor returns the carrier passed in")


func test_set_possessed_clears_pending_launch() -> void:
	# Stage a launch first (simulating a stale velocity from a prior shot),
	# then set_possessed — pending fields must be zeroed so the carrier
	# doesn't inherit motion.
	ball.apply_launch_state(Vector3(10.0, 5.0, 0.0), Vector3(0.0, 4.0, 0.0))
	ball.set_possessed(stub_carrier)
	assert_eq(ball._pending_linear, Vector3.ZERO,
		"set_possessed must zero _pending_linear")
	assert_eq(ball._pending_angular, Vector3.ZERO,
		"set_possessed must zero _pending_angular")


# ---- release --------------------------------------------------------------

func test_release_clears_state() -> void:
	ball.set_possessed(stub_carrier)
	ball.release(Vector3(5.0, 2.0, 0.0))
	assert_false(ball.is_possessed(),
		"After release, is_possessed() must return false")
	assert_null(ball.get_possessor(),
		"After release, possessor must be null")


func test_release_stages_launch_velocity() -> void:
	ball.set_possessed(stub_carrier)
	ball.release(Vector3(7.0, 3.0, -2.0), Vector3(0.0, 4.0, 0.0))
	assert_eq(ball._pending_linear, Vector3(7.0, 3.0, -2.0),
		"release must stage the launch velocity for the next physics tick")
	assert_eq(ball._pending_angular, Vector3(0.0, 4.0, 0.0),
		"release must stage the angular velocity")


func test_release_emits_signal_with_velocity_and_releaser() -> void:
	ball.set_possessed(stub_carrier)
	ball.release(Vector3(8.0, 4.0, 0.0))
	# Signal is deferred — flush the deferred queue.
	await get_tree().process_frame
	assert_eq(captured_releaser, stub_carrier,
		"released signal must carry the prior possessor")
	assert_eq(captured_velocity, Vector3(8.0, 4.0, 0.0),
		"released signal must carry the launch velocity")


func test_release_with_no_possessor_still_stages_velocity() -> void:
	# Edge case: release without a prior set_possessed (e.g. initial kickoff).
	# Should be a no-op on the possession side but still stage the velocity.
	ball.release(Vector3(3.0, 0.0, 0.0))
	assert_false(ball.is_possessed())
	assert_eq(ball._pending_linear, Vector3(3.0, 0.0, 0.0))
	await get_tree().process_frame
	assert_eq(captured_releaser, null,
		"released signal carries null releaser when no prior possession")
