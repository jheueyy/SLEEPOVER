class_name Item
extends Node3D
## A carryable gameplay item lying in the world — the counterpart to Fragment,
## but for the 2-slot inventory instead of the Scrapbook. Built identically on
## every peer from host round data (uid + kind + position); picking one up is
## the same hold-E unzip channel as a clue grab (reaching out of the bag is
## always slow and loud). Taking is host-authoritative: first claim wins, the
## prop vanishes for everyone, and only the claimant's inventory gains it.

enum Kind { CAN, POPPER, KEYS, JERKY }

const NEAR := 1.2   ## interaction reach (m), matches Objective/Fragment

## Display + gray-box prop data per kind. Tone law: creepy-cute household
## clutter, nothing that reads as a weapon.
const DEFS := {
	Kind.JERKY: {
		"name": "BEEF JERKY",
		"color": Color("c48a54"),
		"blurb": "carry it to the dog; use the slot away from it to set it down.",
	},
	Kind.CAN: {
		"name": "CAN OF DOG FOOD",
		"color": Color(0.75, 0.45, 0.28),
		"blurb": "heavy, and it lands LOUD. throw it to make noise somewhere else.",
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
var kind: int = Kind.CAN
var taken: bool = false

func setup(p_uid: int, p_kind: int, at: Vector3) -> void:
	uid = p_uid
	kind = p_kind
	position = at
	var col: Color = DEFS[kind]["color"]
	add_child(ItemVisual.build(kind))
	var label := Label3D.new()
	label.text = display_name()
	label.font_size = 30
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 2.8
	label.visibility_range_end_margin = 0.3
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
