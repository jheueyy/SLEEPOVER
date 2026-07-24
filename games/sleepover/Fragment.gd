class_name Fragment
extends Node3D
## A collectible lore prop placed at a clue-spawn anchor for one round. Built
## identically on every peer from the host's round data; picking one up is a
## hold-E "unzip" (same risk + loud ping as grabbing a clue). Collection is
## host-authoritative and syncs to everyone (once per lobby per round), then the
## content flows into each player's persistent Scrapbook.

const NEAR := 2.0   ## interaction reach (m), matches Objective.NEAR

var data: Dictionary = {}   ## {id, type, title, body}
var collected: bool = false

# Type -> gray-box prop colour. Real props (tape, photo, drawing…) come in the art pass.
const TYPE_COLORS := {
	"tape": Color(0.85, 0.75, 0.25),
	"polaroid": Color(0.92, 0.92, 0.88),
	"crayon": Color(0.95, 0.45, 0.65),
	"clipping": Color(0.80, 0.80, 0.70),
	"flyer": Color(0.55, 0.85, 0.95),
}

func setup(frag: Dictionary, at: Vector3) -> void:
	data = frag
	position = at
	var col: Color = TYPE_COLORS.get(str(frag.get("type", "")), Color(0.9, 0.9, 0.9))
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.28, 0.05)   # slimmer than an objective prop
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, mat)
	mesh.position.y = 0.35
	add_child(mesh)
	var label := Label3D.new()
	label.text = "✦ %s" % str(frag.get("type", "lore")).to_upper()
	label.font_size = 34
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = col
	label.position.y = 0.75
	add_child(label)

func id() -> String:
	return str(data.get("id", ""))

func frag_type() -> String:
	return str(data.get("type", ""))

func title() -> String:
	return str(data.get("title", "Fragment"))

func body() -> String:
	return str(data.get("body", ""))

## Reach is a sphere PLUS a height gate: your grab must come from at-or-above
## the fragment's level. Floor fragments pass trivially (a standing bag's center
## sits ~0.45 above its floor); a fragment on a perch top does NOT — you cannot
## fish it down from the floor, you hop up to it. That's the whole hop-economy
## point of perches.
func near(player_pos: Vector3) -> bool:
	return not collected and position.distance_to(player_pos) < NEAR \
		and player_pos.y >= position.y + 0.1

func mark_collected() -> void:
	collected = true
	visible = false
