class_name ForceGizmo
extends Node3D

## Sprint 04 T05 — 3D force gizmo drawing colour-coded arrows at the
## ball position for the active force vectors. Reads `last_force_*`
## fields on BallPhysics (populated by the integrator each substep).
##
## Toggle visibility with G in SandboxController.
##
## Geometry: each arrow is built from world-space triangles (a thin
## rectangular shaft + a triangular head) so the lines stay visible
## under the `gl_compatibility` renderer, where PRIMITIVE_LINES are
## clamped to 1 pixel wide and effectively invisible at editor zoom.
##
## Length scale: 0.04 m per Newton. A 10 N Magnus force at 30 m/s
## therefore draws a 40 cm arrow — readable next to a 22 cm-diameter
## ball without dominating the screen.

## Camera in the sandbox sits ~40 m from the ball, FOV 45°. To read an
## arrow we need it ≥ ~5 px on screen, which at that distance means
## ≥ ~15 cm width and ≥ ~50 cm length. Scaled accordingly.
const FORCE_SCALE: float = 0.15            ## 0.15 m / N (was 0.04 — too tiny at 40 m cam)
const SHAFT_HALF_WIDTH: float = 0.06       ## 12 cm thick shaft in world space
const HEAD_LEN_RATIO: float = 0.25
const HEAD_HALF_WIDTH: float = 0.22        ## 44 cm wide arrowhead
const MIN_LENGTH_DRAW: float = 0.15        ## skip arrows shorter than 15 cm

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
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Force the renderer to never frustum-cull the gizmo. ImmediateMesh's
	# AABB is computed from the first surface emitted; if the first frame
	# happens before _ball is resolved we'd never get a valid AABB and
	# the arrows would be silently culled. A huge cull margin sidesteps
	# the issue without paying per-frame AABB recomputation cost.
	_mesh_instance.extra_cull_margin = 16384.0
	add_child(_mesh_instance)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color.WHITE
	# Render both sides so the arrows are visible from any camera angle.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Draw on top of everything (ball mesh, field) so the gizmo stays
	# readable even when the ball passes in front. Slight overdraw cost,
	# acceptable for a debug overlay.
	_material.no_depth_test = true
	_material.disable_receive_shadows = true
	# Also assign as material_override on the MeshInstance3D — belt and
	# braces. surface_begin(material) sets the surface material; the
	# override guarantees the renderer picks it up even if Godot ever
	# changes how ImmediateMesh surface materials propagate.
	_mesh_instance.material_override = _material


func _process(_delta: float) -> void:
	if not visible or _ball == null:
		return
	_redraw()


func _redraw() -> void:
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	# Origin slightly above ball centre so the arrow tails don't dive
	# into the ground when the ball is at rest.
	var origin: Vector3 = _ball.global_position + Vector3(0, 0.04, 0)
	_draw_arrow(origin, _ball.last_force_gravity, COLOR_GRAVITY)
	_draw_arrow(origin, _ball.last_force_drag, COLOR_DRAG)
	_draw_arrow(origin, _ball.last_force_magnus, COLOR_MAGNUS)
	_draw_arrow(origin, _ball.last_force_knuckle, COLOR_KNUCKLE)
	_draw_arrow(origin, _ball.last_force_grass, COLOR_GRASS)
	# Skip the net arrow when it would just duplicate the gravity arrow
	# at rest — keeps the purple gravity vector visible alone instead of
	# being overdrawn by an identical white arrow.
	var f_net_minus_grav: Vector3 = _ball.last_force_net - _ball.last_force_gravity
	if f_net_minus_grav.length() > 0.5:
		_draw_arrow(origin, _ball.last_force_net, COLOR_NET)
	_imesh.surface_end()


## Draw one arrow as two quads:
##   - shaft: a thin rectangle along the force direction
##   - head:  a triangle at the tip
## All triangles are emitted in world space; vertex color carries the
## per-arrow tint. `up` for the rectangle perpendicular is chosen so
## the arrow stays readable from a top-down / broadcast camera.
func _draw_arrow(origin: Vector3, force: Vector3, color: Color) -> void:
	var length: float = force.length() * FORCE_SCALE
	if length < MIN_LENGTH_DRAW:
		return
	var dir: Vector3 = force.normalized()
	# Side vector — perpendicular to direction, lying roughly horizontal
	# when the force has a vertical component. Falls back to world RIGHT
	# when the direction is purely vertical (gravity arrow).
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var head_len: float = length * HEAD_LEN_RATIO
	var shaft_tip: Vector3 = origin + dir * (length - head_len)
	var arrow_tip: Vector3 = origin + dir * length

	# Shaft quad (two triangles)
	var sw: Vector3 = side * SHAFT_HALF_WIDTH
	_tri(origin - sw, origin + sw, shaft_tip + sw, color)
	_tri(origin - sw, shaft_tip + sw, shaft_tip - sw, color)

	# Arrowhead triangle
	var hw: Vector3 = side * HEAD_HALF_WIDTH
	_tri(shaft_tip - hw, shaft_tip + hw, arrow_tip, color)


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(a)
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(b)
	_imesh.surface_set_color(color)
	_imesh.surface_add_vertex(c)
