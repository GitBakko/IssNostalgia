class_name TeamConfig
extends Resource

## Per-team configuration. Pure data Resource — no logic.
## See GAME_DESIGN_LOG S06-D23 (single responsibility).

@export var team_name: String = "TEAM"

## Primary team colour. Applied to player capsule `material_override` and to
## the selection-indicator ring under each controllable player.
@export var primary_color: Color = Color.WHITE

## Identifier of the FormationData resource this team uses.
## Lookup happens at runtime in StaticAI / TeamController.
@export var formation_id: StringName = &"2-1-1"

## True when this team is controlled by a human player (Team A by default).
## Static-AI teams have this false. Debug `both_human` flag flips both teams
## to true (see MatchManager / SPRINT_06_PLAN T06).
@export var is_human_default: bool = false

## Side of the pitch this team defends.
##   - `-1` defends the -Z goal (Team A default)
##   - `+1` defends the +Z goal (Team B default)
## Used to mirror formation anchors at instantiation time.
@export var defending_side: int = -1

## Sprint 9 T01 — per-player attribute arrays. Parallel to
## `FormationData.role_anchors` (5 entries: DEF_LEFT, DEF_RIGHT,
## MID, ATT, GK). When the array is shorter than the formation
## role count, the accessor falls back to the per-team default.
##
## `close_control` ∈ [0, 1] — R02-F07. High value = ball is held
## tighter at low speed (smaller carry offset, higher loss
## threshold). Drives `Player.get_effective_carry_offset`
## modulation in T02.
##
## `dribble_skill` ∈ [0, 1] — R02-F04. High value = closer touches
## (smaller kick factor) so elite dribblers keep the ball under
## their nose; low value = looser touches (larger factor) so
## physical strikers take longer touches in space.
## `BallController._apply_proximity_kick` lerps the walk/sprint
## kick factor between `*_high_skill` and `*_low_skill` based on
## the carrier's `dribble_skill`.
@export var close_control: Array[float] = [0.5, 0.5, 0.5, 0.5, 0.5]
@export var dribble_skill: Array[float] = [0.5, 0.5, 0.5, 0.5, 0.5]
## Default applied when the array doesn't cover a role index.
@export var default_close_control: float = 0.5
@export var default_dribble_skill: float = 0.5


## Safe accessor — returns `default_close_control` when role_index
## is out of range, so a partially-filled array doesn't crash.
func get_close_control(role_index: int) -> float:
	if role_index < 0 or role_index >= close_control.size():
		return default_close_control
	return close_control[role_index]


func get_dribble_skill(role_index: int) -> float:
	if role_index < 0 or role_index >= dribble_skill.size():
		return default_dribble_skill
	return dribble_skill[role_index]
