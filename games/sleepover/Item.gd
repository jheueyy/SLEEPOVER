class_name Item
extends Node3D
## A carryable gameplay item lying in the world — the counterpart to Fragment,
## but for the 2-slot inventory instead of the Scrapbook. Built identically on
## every peer from host round data (uid + kind + position); picking one up is
## the same hold-E unzip channel as a clue grab (reaching out of the bag is
## always slow and loud). Taking is host-authoritative: first claim wins, the
## prop vanishes for everyone, and only the claimant's inventory gains it.

enum Kind { SOCK, POPPER, KEYS }

const NEAR := 2.0   ## interaction reach (m), matches Objective/Fragment

## Display + gray-box prop data per kind. Tone law: creepy-cute household
## clutter, nothing that reads as a weapon.
const DEFS := {
	Kind.SOCK: {
		"name": "SOCK BALL",
		"color": Color(0.88, 0.86, 0.78),
		"blurb": "balled-up socks. throw to make noise SOMEWHERE ELSE.",
	},
	Kind.POPPER: {
		"name": "PARTY POPPER",
		"color": Color(0.95, 0.55, 0.75),
		"blurb": "one bang. she flinches — and knows exactly where you are.",
	},
	Kind.KEYS: {
		"name": "HOUSE KEYS",
		"color": Color(0.95, 0.83, 0.30),
		"blurb": "the back door keys. somebody has to carry them.",
	},
}

var uid: int = -1
var kind: int = Kind.SOCK
var taken: bool = false

func setup(p_uid: int, p_kind: int, at: Vector3) -> void:
	uid = p_uid
	kind = p_kind
	position = at
	var col: Color = DEFS[kind]["color"]
	var mesh := MeshInstance3D.new()
	if kind == Kind.SOCK:
		var ball := SphereMesh.new()
		ball.radius = 0.14
		ball.height = 0.24   # slightly squashed — socks, not a baseball
		mesh.mesh = ball
	elif kind == Kind.POPPER:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02
		cone.bottom_radius = 0.09
		cone.height = 0.3
		mesh.mesh = cone
	else:
		var keys := BoxMesh.new()
		keys.size = Vector3(0.22, 0.06, 0.14)
		mesh.mesh = keys
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, mat)
	mesh.position.y = 0.16
	add_child(mesh)
	var label := Label3D.new()
	label.text = display_name()
	label.font_size = 30
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = col
	label.position.y = 0.6
	add_child(label)

func display_name() -> String:
	return str(DEFS[kind]["name"])

func near(player_pos: Vector3) -> bool:
	return not taken and position.distance_to(player_pos) < NEAR

func mark_taken() -> void:
	taken = true
	visible = false

static func kind_name(k: int) -> String:
	return str(DEFS.get(k, {}).get("name", "?"))
