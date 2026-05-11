class_name BallLauncher
extends Node3D

## Parametric launcher for the sandbox.
##
## Sprint 1 (T05) exposes three keyboard launches (vertical, horizontal,
## reset) plus a "click the ground" mouse mode. Magnus and knuckle remain
## off this sprint; the spin set here only drives the kinematic rotation
## of the mesh, not curved trajectories.
## Sprint 2 will hand the launcher the predicted trajectory overlay and a
## proper sidespin / topspin / rifling decomposition.

@export var spawn_position: Vector3 = Vector3(0.0, 1.5, 0.0)
@export var ball_path: NodePath

@export_group("Defaults")
@export var vertical_speed: float = 15.0          ## m/s, upward
@export var vertical_spin_z: float = 4.0          ## rad/s, around Z so the
                                                  ## pentagons visibly rotate
@export var horizontal_speed: float = 20.0        ## m/s, along +X
@export var horizontal_topspin: float = 6.0       ## rad/s, around -Z so the
                                                  ## ball "rolls forward"
@export var ground_click_speed: float = 25.0      ## m/s magnitude
@export var ground_click_arc_height: float = 5.0  ## peak height above spawn

var _ball: BallPhysics


func _ready() -> void:
	_ball = _resolve_ball()
	if _ball == null:
		push_warning("BallLauncher: target ball not found (set ball_path or place a sibling 'Ball').")


func _resolve_ball() -> BallPhysics:
	if not ball_path.is_empty():
		return get_node_or_null(ball_path) as BallPhysics
	var sibling: Node = get_parent().get_node_or_null("Ball") if get_parent() else null
	return sibling as BallPhysics


## Hard reset: place at spawn, zero velocity and spin.
func reset_ball() -> void:
	if _ball == null:
		return
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = spawn_position
	print("[launcher] reset to %s" % spawn_position)


## Primitive launch: teleport ball to spawn, apply linear+angular velocity.
func launch(velocity: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	if _ball == null:
		return
	_ball.global_position = spawn_position
	_ball.linear_velocity = velocity
	_ball.angular_velocity = spin
	print("[launcher] launch v=%s |v|=%.2f m/s spin=%s |w|=%.2f rad/s" % [
		velocity, velocity.length(), spin, spin.length(),
	])


func launch_vertical(speed: float = -1.0, spin_z: float = INF) -> void:
	var v: float = speed if speed > 0.0 else vertical_speed
	var sz: float = vertical_spin_z if spin_z == INF else spin_z
	launch(Vector3(0.0, v, 0.0), Vector3(0.0, 0.0, sz))


func launch_horizontal(speed: float = -1.0, direction: Vector3 = Vector3.RIGHT,
		topspin: float = INF) -> void:
	var v: float = speed if speed > 0.0 else horizontal_speed
	var ts: float = horizontal_topspin if topspin == INF else topspin
	var dir: Vector3 = direction.normalized()
	# Topspin axis: perpendicular to direction in the horizontal plane.
	# For dir = +X, topspin axis = -Z so the ball rotates "forward" in flight.
	var spin_axis: Vector3 = Vector3.UP.cross(dir).normalized()
	launch(dir * v, spin_axis * ts)


## Aim the ball at `target_xz` (point on the ground plane) with a fixed
## launch speed and an arc height. Computes a simple ballistic vertical
## component that ignores drag — Sprint 1 only, Sprint 2 predictor will
## refine.
func launch_to_point(target_xz: Vector3, speed: float = -1.0,
		arc_height: float = -1.0) -> void:
	var s: float = speed if speed > 0.0 else ground_click_speed
	var h: float = arc_height if arc_height > 0.0 else ground_click_arc_height
	var horizontal: Vector3 = Vector3(target_xz.x - spawn_position.x, 0.0,
		target_xz.z - spawn_position.z)
	var dist: float = horizontal.length()
	if dist < 0.001:
		return
	var dir: Vector3 = horizontal / dist
	# Vertical speed that produces apex at +h above spawn (ignoring drag).
	var v_vertical: float = sqrt(2.0 * 9.81 * h)
	var v_horizontal: float = s
	# Mild sidespin for visual interest (no Magnus this sprint).
	var spin_axis: Vector3 = Vector3.UP.cross(dir).normalized()
	launch(dir * v_horizontal + Vector3.UP * v_vertical, spin_axis * 5.0)
