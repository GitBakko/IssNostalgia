class_name ForceGizmo
extends Node3D

## Sprint 04 T05 — 3D force gizmo drawing colour-coded arrows at the
## ball position for the active force vectors. Reads `last_force_*`
## fields on BallPhysics (populated by the integrator each substep).
##
## Toggle visibility with G in SandboxController. Lines drawn with
## ImmediateMesh + a single unshaded ORM_StandardMaterial3D per colour.
##
## Length scale: 0.04 m per Newton. A 10 N Magnus force at 30 m/s
## therefore draws a 40 cm arrow — readable next to a 22 cm-diameter
## ball without dominating the screen.

const FORCE_SCALE: float = 0.04
const HEAD_LEN_RATIO: float = 0.18
const HEAD_HALF_WIDTH: float = 0.04
const MIN_LENGTH_DRAW: float = 0.03   ## skip arrows shorter than 3 cm

@export var ball_path: NodePath
@export var enabled: bool = true

const COLOR_DRAG    := Color(1.0, 0.35, 0.25)
const COLOR_MAGNUS  := Color(0.30, 1.0, 0.40)
const COLOR_KNUCKLE := Color(1.0, 0.85, 0.20)
const COLOR_GRASS   := Color(0.40, 0.70, 1.0)
const COLOR_NET     := Color(1.0, 1.0, 1.0)
const COLOR_GRAVITY := Color(0.60, 0.45, 1.0)

var _ball: BallPhysics
var _mesh_instance: MeshInstance3D
var _imesh: ImmediateMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_resolve_ball()
	_init_mesh()
	visible = enabled


func _resolve_ball() -> void:
	if not ball_path.is_empty():
		_ball = get_node_or_null(ball_path) as BallPhysics
		return
	var parent: Node = get_parent()
	if parent != null:
		_ball = parent.get_node_or_null("Ball") as BallPhysics


func _init_mesh() -> void:
	_imesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _imesh
	# Don't cast shadows for HUD-like overlay geometry.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = false
	_material.albedo_color = Color.WHITE


func _process(_delta: float) -> void:
	if not visible or _ball == null:
		return
	_redraw()


func _redraw() -> void:
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	var origin: Vector3 = _ball.global_position + Vector3(0, 0.02, 0)
	_draw_arrow(origin, _ball.last_force_gravity, COLOR_GRAVITY)
	_draw_arrow(origin, _ball.last_force_drag, COLOR_DRAG)
	_draw_arrow(origin, _ball.last_force_magnus, COLOR_MAGNUS)
	_draw_arrow(origin, _ball.last_force_knuckle, COLOR_KNUCKLE)
	_draw_arrow(origin, _ball.last_force_grass, COLOR_GRASS)
	_draw_arrow(origin, _ball.last_force_net, COLOR_NET)
	_imesh.surface_end()


func _draw_arrow(origin: Vector3, force: Vector3, color: Color) -> void:
	var length: float = force.length() * FORCE_SCALE
	if length < MIN_LENGTH_DRAW:
		return
	var dir: Vector3 = force.normalized()
	var tip: Vector3 = origin + dir * length
	# Shaft
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(origin)
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(tip)
	# Arrowhead — two short backward segments forming a V.
	var head_len: float = length * HEAD_LEN_RATIO
	var perp: Vector3 = dir.cross(Vector3.UP)
	if perp.length_squared() < 1e-6:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized() * HEAD_HALF_WIDTH
	var back: Vector3 = tip - dir * head_len
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(tip)
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(back + perp)
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(tip)
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(back - perp)
