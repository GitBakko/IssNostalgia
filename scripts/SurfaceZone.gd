class_name SurfaceZone
extends Area3D

## Sprint 5 T05 — Per-zone surface state.
##
## Drop a SurfaceZone Area3D anywhere on the field, give it a
## CollisionShape3D bounding the wet patch, and the ball will switch
## to wet-surface coefficients (μ_s_wet, rolling_friction_wet,
## restitution_base_wet, grass_kick_wet) while it overlaps the zone.
## Outside any zone the ball falls back to the global `config.surface_wet`
## flag — backwards compat with Sprint 3 scenes / tests.
##
## Multiple zones stack: BallPhysics counts active wet-zone entries and
## stays wet until every overlapping zone has been exited. This lets
## adjacent wet patches behave correctly when the ball rolls along
## their boundary.

@export var wet: bool = true   ## a "dry zone" can also be authored
                               ## (`wet = false`) — currently a no-op
                               ## since the fallback IS dry, but the
                               ## API stays symmetric for future
                               ## per-zone parameter overrides


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not wet:
		return
	if body is BallPhysics:
		(body as BallPhysics).enter_wet_zone()


func _on_body_exited(body: Node3D) -> void:
	if not wet:
		return
	if body is BallPhysics:
		(body as BallPhysics).exit_wet_zone()
