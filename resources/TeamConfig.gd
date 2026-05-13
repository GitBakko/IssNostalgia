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
