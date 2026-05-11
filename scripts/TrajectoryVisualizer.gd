class_name TrajectoryVisualizer
extends Node3D

## Renders the ball's recent past trajectory as a 3D ribbon plus the
## forward-prediction line (Sprint 2 T05).
##
## Past samples are stored in a ring buffer sampled at physics tick (120 Hz).
## The ribbon is rebuilt every frame from the buffer; on Compatibility
## renderer with ~600 samples this is well under 1 ms.
## Width decreases toward the tail and the ribbon is vertex-coloured by
## the speed measured at each sample (red = fast, blue = slow).
##
## A "teleport" (sample displacement > TELEPORT_THRESHOLD between physics
## frames) clears the buffer automatically — this is what the launcher
## triggers when it relocates the ball.

const SAMPLE_HISTORY: int = 600                  ## 5 s @ 120 Hz
const MIN_SEGMENT_LENGTH: float = 0.05           ## m, ignore micro-jitter
const TELEPORT_THRESHOLD: float = 3.0            ## m, treat as launch / reset

# ---- Forward predictor (M06 / M07 / M08) ---------------------------------
const PREDICTOR_UPDATE_FRAMES: int = 4           ## refresh every 4 render
                                                 ## frames (~15 Hz @ 60 fps)
const PREDICTOR_SUBSTEP_DT: float = 1.0 / 120.0  ## same tick rate as the
                                                 ## live integrator
@export var predictor_enabled: bool = true
@export var predictor_seconds: float = 1.5       ## forward horizon
@export var predictor_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var predictor_width: float = 0.05        ## m, slim line

@export var ball_path: NodePath
@export var ribbon_width_max: float = 0.18       ## m, head (newest) end
@export var ribbon_width_min: float = 0.02       ## m, tail (oldest) end
@export var color_slow: Color = Color(0.20, 0.45, 1.00, 0.85)   ## ≤ speed_low
@export var color_mid: Color = Color(1.00, 0.95, 0.10, 0.85)    ## ≈ speed_mid
@export var color_fast: Color = Color(1.00, 0.15, 0.10, 0.85)   ## ≥ speed_high
@export var speed_low: float = 2.0                              ## m/s
@export var speed_mid: float = 12.0                             ## m/s
@export var speed_high: float = 28.0                            ## m/s


var _ball: RigidBody3D
var _ball_physics: BallPhysics                   ## same node, typed view
var _mesh_instance: MeshInstance3D
var _immediate: ImmediateMesh
var _material: StandardMaterial3D
var _predict_mesh_instance: MeshInstance3D
var _predict_immediate: ImmediateMesh
var _predict_material: StandardMaterial3D

var _positions: PackedVector3Array = PackedVector3Array()
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0
var _filled: int = 0

var _predictor_frame_counter: int = 0
var _predicted_positions: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	_positions.resize(SAMPLE_HISTORY)
	_speeds.resize(SAMPLE_HISTORY)
	var ball_node: Node = get_node_or_null(ball_path)
	_ball = ball_node as RigidBody3D
	_ball_physics = ball_node as BallPhysics
	_setup_mesh()
	_setup_predict_mesh()


func _setup_mesh() -> void:
	_immediate = ImmediateMesh.new()
	_immediate.resource_local_to_scene = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)


func _setup_predict_mesh() -> void:
	_predict_immediate = ImmediateMesh.new()
	_predict_immediate.resource_local_to_scene = true
	_predict_material = StandardMaterial3D.new()
	_predict_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_predict_material.albedo_color = predictor_color
	_predict_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_predict_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_predict_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_predict_mesh_instance = MeshInstance3D.new()
	_predict_mesh_instance.mesh = _predict_immediate
	_predict_mesh_instance.material_override = _predict_material
	add_child(_predict_mesh_instance)


func _physics_process(_delta: float) -> void:
	if _ball == null:
		return
	_record_sample(_ball.global_position, _ball.linear_velocity.length())


func _process(_delta: float) -> void:
	_rebuild_mesh()
	_predictor_frame_counter += 1
	if predictor_enabled and _predictor_frame_counter >= PREDICTOR_UPDATE_FRAMES:
		_predictor_frame_counter = 0
		_refresh_prediction()
	_rebuild_prediction_mesh()


func reset() -> void:
	_head = 0
	_filled = 0
	if _immediate != null:
		_immediate.clear_surfaces()


func _record_sample(pos: Vector3, speed: float) -> void:
	if _filled > 0:
		var last_idx: int = (_head - 1 + SAMPLE_HISTORY) % SAMPLE_HISTORY
		var last_pos: Vector3 = _positions[last_idx]
		var delta: float = pos.distance_to(last_pos)
		if delta > TELEPORT_THRESHOLD:
			reset()
		elif delta < MIN_SEGMENT_LENGTH:
			# tiny step — overwrite last sample, don't grow the buffer
			_positions[last_idx] = pos
			_speeds[last_idx] = speed
			return
	_positions[_head] = pos
	_speeds[_head] = speed
	_head = (_head + 1) % SAMPLE_HISTORY
	if _filled < SAMPLE_HISTORY:
		_filled += 1


func _rebuild_mesh() -> void:
	if _immediate == null:
		return
	_immediate.clear_surfaces()
	if _filled < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var start_idx: int = (_head - _filled + SAMPLE_HISTORY) % SAMPLE_HISTORY
	for i in range(_filled - 1):
		var ia: int = (start_idx + i) % SAMPLE_HISTORY
		var ib: int = (start_idx + i + 1) % SAMPLE_HISTORY
		var pa: Vector3 = _positions[ia]
		var pb: Vector3 = _positions[ib]
		var direction: Vector3 = pb - pa
		if direction.length_squared() < 1e-8:
			continue
		direction = direction.normalized()
		var perp: Vector3 = direction.cross(Vector3.UP)
		if perp.length_squared() < 1e-6:
			perp = direction.cross(Vector3.RIGHT)
		perp = perp.normalized()
		var t_a: float = float(i) / float(_filled - 1)
		var t_b: float = float(i + 1) / float(_filled - 1)
		var w_a: float = lerp(ribbon_width_min, ribbon_width_max, t_a)
		var w_b: float = lerp(ribbon_width_min, ribbon_width_max, t_b)
		var c_a: Color = _color_for_speed(_speeds[ia])
		var c_b: Color = _color_for_speed(_speeds[ib])
		var pa1: Vector3 = pa + perp * w_a * 0.5
		var pa2: Vector3 = pa - perp * w_a * 0.5
		var pb1: Vector3 = pb + perp * w_b * 0.5
		var pb2: Vector3 = pb - perp * w_b * 0.5
		_immediate.surface_set_color(c_a); _immediate.surface_add_vertex(pa1)
		_immediate.surface_set_color(c_b); _immediate.surface_add_vertex(pb1)
		_immediate.surface_set_color(c_a); _immediate.surface_add_vertex(pa2)
		_immediate.surface_set_color(c_a); _immediate.surface_add_vertex(pa2)
		_immediate.surface_set_color(c_b); _immediate.surface_add_vertex(pb1)
		_immediate.surface_set_color(c_b); _immediate.surface_add_vertex(pb2)
	_immediate.surface_end()


func _refresh_prediction() -> void:
	if _ball_physics == null:
		_predicted_positions = PackedVector3Array()
		return
	var steps: int = int(predictor_seconds / PREDICTOR_SUBSTEP_DT)
	_predicted_positions = _ball_physics.predict_forward(
		_ball_physics.global_position,
		_ball_physics.linear_velocity,
		_ball_physics.angular_velocity,
		_ball_physics._sim_time,
		steps,
		PREDICTOR_SUBSTEP_DT,
	)


func _rebuild_prediction_mesh() -> void:
	if _predict_immediate == null:
		return
	_predict_immediate.clear_surfaces()
	var n: int = _predicted_positions.size()
	if n < 2:
		return
	# Draw as line strip (cheap, no width). For mobile fidelity later
	# this can be upgraded to a thin ribbon similar to the past trail.
	_predict_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(n - 1):
		_predict_immediate.surface_add_vertex(_predicted_positions[i])
		_predict_immediate.surface_add_vertex(_predicted_positions[i + 1])
	_predict_immediate.surface_end()


func _color_for_speed(speed: float) -> Color:
	if speed <= speed_low:
		return color_slow
	if speed <= speed_mid:
		var t: float = (speed - speed_low) / max(speed_mid - speed_low, 1e-3)
		return color_slow.lerp(color_mid, t)
	if speed <= speed_high:
		var t2: float = (speed - speed_mid) / max(speed_high - speed_mid, 1e-3)
		return color_mid.lerp(color_fast, t2)
	return color_fast
