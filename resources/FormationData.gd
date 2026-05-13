class_name FormationData
extends Resource

## Formation layout data. Pure data Resource — actual positioning logic lives
## in StaticAI.gd / TeamController.gd (Sprint 8). Sprint 6 only reads
## `role_anchors` to place players at scene load.
##
## Anchors are expressed for the team that defends the `-Z` goal. The mirror
## team (defends `+Z`) negates the Z component of every anchor at instantiation
## (see GAME_DESIGN_LOG S06-D16 — no physical side swap at halftime in Phase 2).
##
## Field convention: FIFA regulation 105 m × 68 m, origin at centre.
##   X axis = pitch width  (-34 .. +34)
##   Z axis = pitch length (-52.5 .. +52.5)
##   Goals at Z = ±52.5

@export var formation_id: StringName = &"2-1-1"

## World-space anchor for each role (5 entries: 4 outfield + 1 GK).
## Convention: order in array matches `role_names`. Z values are for the
## team defending the -Z goal — mirror at Team B instantiation time.
@export var role_anchors: Array[Vector3] = [
	Vector3(-15.0, 0.0, -35.0),  # 0: DEF_LEFT
	Vector3( 15.0, 0.0, -35.0),  # 1: DEF_RIGHT
	Vector3(  0.0, 0.0, -15.0),  # 2: MID
	Vector3(  0.0, 0.0,   5.0),  # 3: ATT
	Vector3(  0.0, 0.0, -50.0),  # 4: GK (Z=-50 = 2.5 m off the goal line)
]

## Reactive offset magnitude in metres (S06-D07). Applied by StaticAI when the
## ball crosses into the opposite half — step function, NOT proportional.
##   DEF advances 6 m towards the ball half,
##   MID  4 m,
##   ATT  2 m (stays as counter-attack threat),
##   GK   0 m (separate logic, this entry is ignored at runtime).
@export var role_offset_meters: Array[float] = [
	6.0,  # 0: DEF_LEFT
	6.0,  # 1: DEF_RIGHT
	4.0,  # 2: MID
	2.0,  # 3: ATT
	0.0,  # 4: GK (separate X-axis tracking logic)
]

## Role identifiers — parallel array to anchors / offsets. Code reads these
## to branch on goalkeeper vs outfield behaviour.
@export var role_names: Array[StringName] = [
	&"def_left",
	&"def_right",
	&"mid",
	&"att",
	&"gk",
]

## Display label per role for HUD / debug.
@export var role_labels: Array[String] = [
	"LB",
	"RB",
	"M",
	"F",
	"GK",
]


## Returns the anchor mirrored for the team defending +Z (Team B by default).
## Z is negated; X stays — keeps left/right wings consistent across both teams.
func get_anchor_mirrored(role_index: int) -> Vector3:
	var a: Vector3 = role_anchors[role_index]
	return Vector3(a.x, a.y, -a.z)


## Role count = always 5 in 2-1-1 (4 outfield + 1 GK). Helper for iteration.
func role_count() -> int:
	return role_anchors.size()


## True when the role at `role_index` is the goalkeeper. Convention: GK is the
## last entry (`role_names[-1] == "gk"`), but check by name for safety in case
## a future formation reorders.
func is_goalkeeper_role(role_index: int) -> bool:
	return role_names[role_index] == &"gk"
