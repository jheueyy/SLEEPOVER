class_name HouseSuburban
extends Object
## The shared suburban house — gray-box edition (spec 1.3). Data-driven per the
## launch plan's retention architecture (3.1): the layout below is pure data
## tables; the builder turns them into boxes. Redecorating = editing tables.
##
## 16 rooms across 4 levels. Plan coords are (x, z); floors are 3m apart:
##   basement y -3..0 | ground y 0..3 | upper y 3..6 | attic y 6..8.2
## Ground:  Kitchen | Dining | Garage (back row),  Living | Hall | Laundry | Bath
## Upper:   Kid1 | Kid2 | UpBath (back row),  Master | Landing | Closet | Office
## Stairs:  main (hall, up), basement (hall, down — stair sandwich), attic (kid2, steep)
## Chute:   closet floor hole -> drops into the laundry room. One-way. Comedy.

const WALL_T := 0.3
const WALL_H := 3.0
const DOOR_H := 2.0
const DOOR_W := 1.0

# Where players wake up (living room). Slot 0 = host/solo, clients pick 1+.
const SPAWNS: Array[Vector3] = [
	Vector3(-5.0, 1.0, 1.0), Vector3(-3.5, 1.0, 1.5), Vector3(-6.0, 1.0, 2.5),
	Vector3(-3.5, 1.0, 3.0), Vector3(-5.0, 1.0, 4.0), Vector3(-6.5, 1.0, 3.8),
]
# Living room far corner, clear of the spawn cluster (its idle patrol must not
# sweep through waking players). Stays in this room until navmesh (Phase 2).
const MONSTER_SPAWN := Vector3(-2.0, 1.0, 5.2)

# ── Layout data ────────────────────────────────────────────────────────────

# Walls: a/b are plan endpoints, base = floor height, gaps = [pos_along_wall, width]
const WALLS: Array = [
	# Ground outer shell
	{"a": Vector2(-8, -6), "b": Vector2(8, -6), "base": 0.0},
	{"a": Vector2(-8, 6), "b": Vector2(8, 6), "base": 0.0, "gaps": [[-4.0, 1.2]]},  # front door
	{"a": Vector2(-8, -6), "b": Vector2(-8, 6), "base": 0.0},
	{"a": Vector2(8, -6), "b": Vector2(8, 6), "base": 0.0},
	# Ground interior
	{"a": Vector2(-8, -1), "b": Vector2(8, -1), "base": 0.0, "gaps": [[-5.5, DOOR_W], [0.5, DOOR_W], [3.5, DOOR_W]]},
	{"a": Vector2(-3, -6), "b": Vector2(-3, -1), "base": 0.0, "gaps": [[-3.5, DOOR_W]]},
	{"a": Vector2(2, -6), "b": Vector2(2, -1), "base": 0.0, "gaps": [[-3.5, DOOR_W]]},
	{"a": Vector2(-1, -1), "b": Vector2(-1, 6), "base": 0.0, "gaps": [[2.5, DOOR_W]]},
	{"a": Vector2(2, -1), "b": Vector2(2, 6), "base": 0.0, "gaps": [[5.5, DOOR_W]]},
	{"a": Vector2(5, -1), "b": Vector2(5, 6), "base": 0.0, "gaps": [[2.5, DOOR_W]]},
	# Upper outer shell (garage is single-story: footprint stops at x=5)
	{"a": Vector2(-8, -6), "b": Vector2(5, -6), "base": 3.0},
	{"a": Vector2(-8, 6), "b": Vector2(5, 6), "base": 3.0},
	{"a": Vector2(-8, -6), "b": Vector2(-8, 6), "base": 3.0},
	{"a": Vector2(5, -6), "b": Vector2(5, 6), "base": 3.0},
	# Upper interior
	{"a": Vector2(-8, -1), "b": Vector2(5, -1), "base": 3.0, "gaps": [[-5.5, DOOR_W], [0.5, DOOR_W], [3.5, DOOR_W]]},
	{"a": Vector2(-1, -1), "b": Vector2(-1, 6), "base": 3.0, "gaps": [[2.5, DOOR_W]]},
	{"a": Vector2(-3, -6), "b": Vector2(-3, -1), "base": 3.0},
	{"a": Vector2(2, -6), "b": Vector2(2, -1), "base": 3.0},
	{"a": Vector2(2, -1), "b": Vector2(2, 6), "base": 3.0, "gaps": [[0.5, DOOR_W]]},
	{"a": Vector2(2, 2), "b": Vector2(5, 2), "base": 3.0, "gaps": [[3.5, DOOR_W]]},
	# Basement (under hall + laundry; sealed box, entered via the stair hole)
	{"a": Vector2(-1, -1), "b": Vector2(5, -1), "base": -3.0},
	{"a": Vector2(-1, 6), "b": Vector2(5, 6), "base": -3.0},
	{"a": Vector2(-1, -1), "b": Vector2(-1, 6), "base": -3.0},
	{"a": Vector2(5, -1), "b": Vector2(5, 6), "base": -3.0},
	# Attic (low walls, over the upper back row)
	{"a": Vector2(-8, -6), "b": Vector2(2, -6), "base": 6.0, "h": 2.2},
	{"a": Vector2(-8, -1), "b": Vector2(2, -1), "base": 6.0, "h": 2.2},
	{"a": Vector2(-8, -6), "b": Vector2(-8, -1), "base": 6.0, "h": 2.2},
	{"a": Vector2(2, -6), "b": Vector2(2, -1), "base": 6.0, "h": 2.2},
]

# Floor slabs: rect = [x_min, z_min, x_max, z_max], top = slab top height.
# Holes (stairwells, chute) are simply not covered by any rect.
const SLABS: Array = [
	# Yard (slightly below ground floor so nobody falls into the void)
	{"rect": [-12.0, -9.0, 12.0, 9.0], "top": -0.05},
	# Ground floor — hole at x 1..2, z 0..5 (basement stairwell)
	{"rect": [-8.0, -6.0, 1.0, 6.0], "top": 0.0},
	{"rect": [1.0, -6.0, 2.0, 0.0], "top": 0.0},
	{"rect": [1.0, 5.0, 2.0, 6.0], "top": 0.0},
	{"rect": [2.0, -6.0, 8.0, 6.0], "top": 0.0},
	# Upper floor — holes: main stairwell x -1..1 z 0..5, chute x 3..4 z 0..1
	{"rect": [-8.0, -6.0, -1.0, 6.0], "top": 3.0},
	{"rect": [-1.0, -6.0, 1.0, 0.0], "top": 3.0},
	{"rect": [-1.0, 5.0, 1.0, 6.0], "top": 3.0},
	{"rect": [1.0, -6.0, 3.0, 6.0], "top": 3.0},
	{"rect": [3.0, -6.0, 5.0, 0.0], "top": 3.0},
	{"rect": [4.0, 0.0, 5.0, 1.0], "top": 3.0},
	{"rect": [3.0, 1.0, 5.0, 6.0], "top": 3.0},
	# Attic floor — hole at x -3..-2, z -5..-1 (attic stairwell)
	{"rect": [-8.0, -6.0, -3.0, -1.0], "top": 6.0},
	{"rect": [-3.0, -6.0, -2.0, -5.0], "top": 6.0},
	{"rect": [-2.0, -6.0, 2.0, -1.0], "top": 6.0},
	# Basement floor
	{"rect": [-1.0, -1.0, 5.0, 6.0], "top": -3.0},
]

# Stairs: start = plan pos of the first step's near edge center; dir = plan
# direction of climb; base = y of the floor you start from; signed rise.
const STAIRS: Array = [
	{"start": Vector2(0.0, 0.0), "dir": Vector2(0, 1), "base": 0.0, "rise": 0.3, "run": 0.5, "steps": 10, "width": 2.0},   # hall -> upper
	{"start": Vector2(1.5, 0.0), "dir": Vector2(0, 1), "base": 0.0, "rise": -0.3, "run": 0.5, "steps": 10, "width": 1.0},  # hall -> basement
	{"start": Vector2(-2.5, -1.0), "dir": Vector2(0, -1), "base": 3.0, "rise": 0.3, "run": 0.4, "steps": 10, "width": 1.0}, # kid2 -> attic (steep!)
]

# Room labels: gray-box wayfinding + playtest comms ("it's in the DINING ROOM")
const ROOMS: Array = [
	{"name": "LIVING ROOM", "at": Vector3(-4.5, 2.2, 2.5)},
	{"name": "KITCHEN", "at": Vector3(-5.5, 2.2, -3.5)},
	{"name": "DINING", "at": Vector3(-0.5, 2.2, -3.5)},
	{"name": "GARAGE", "at": Vector3(5.0, 2.2, -3.5)},
	{"name": "HALL", "at": Vector3(0.5, 2.2, 5.3)},
	{"name": "LAUNDRY", "at": Vector3(3.5, 2.2, 4.0)},
	{"name": "BATH", "at": Vector3(6.5, 2.2, 2.5)},
	{"name": "MASTER BED", "at": Vector3(-4.5, 5.2, 2.5)},
	{"name": "LANDING", "at": Vector3(0.5, 5.2, 5.3)},
	{"name": "CLOSET (CHUTE!)", "at": Vector3(3.5, 5.2, 0.5)},
	{"name": "OFFICE", "at": Vector3(3.5, 5.2, 4.0)},
	{"name": "KID ROOM 1", "at": Vector3(-5.5, 5.2, -3.5)},
	{"name": "KID ROOM 2", "at": Vector3(-0.5, 5.2, -3.5)},
	{"name": "UP BATH", "at": Vector3(3.5, 5.2, -3.5)},
	{"name": "BASEMENT", "at": Vector3(2.0, -0.8, 2.5)},
	{"name": "ATTIC", "at": Vector3(-3.0, 7.4, -3.5)},
]

const COL_FLOOR := Color(0.30, 0.30, 0.34)
const COL_WALL := Color(0.22, 0.22, 0.26)
const COL_STEP_A := Color(0.34, 0.28, 0.24)
const COL_STEP_B := Color(0.40, 0.33, 0.28)
const COL_CHUTE := Color(1.0, 0.9, 0.2)

# ── Builder ────────────────────────────────────────────────────────────────

static func build(parent: Node3D) -> void:
	for slab: Dictionary in SLABS:
		var r: Array = slab["rect"]
		var top: float = slab["top"]
		_box(parent,
			Vector3((r[0] + r[2]) * 0.5, top - 0.15, (r[1] + r[3]) * 0.5),
			Vector3(r[2] - r[0], 0.3, r[3] - r[1]), COL_FLOOR)

	for wall: Dictionary in WALLS:
		_build_wall(parent, wall)

	for stair: Dictionary in STAIRS:
		_build_stairs(parent, stair)

	# Chute rim: a glowing lip around the closet hole so it reads as a feature.
	for rim: Array in [[3.5, -0.05], [3.5, 1.05], [2.95, 0.5], [4.05, 0.5]]:
		var along_x: bool = absf(rim[1] - 0.5) > 0.3
		_box(parent, Vector3(rim[0], 3.1, rim[1]),
			Vector3(1.2 if along_x else 0.1, 0.2, 0.1 if along_x else 1.2),
			COL_CHUTE, true)

	for room: Dictionary in ROOMS:
		var label := Label3D.new()
		label.text = room["name"]
		label.font_size = 72
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1, 1, 1, 0.5)
		label.position = room["at"]
		parent.add_child(label)

static func _build_wall(parent: Node3D, wall: Dictionary) -> void:
	var a: Vector2 = wall["a"]
	var b: Vector2 = wall["b"]
	var base: float = wall["base"]
	var h: float = wall.get("h", WALL_H)
	var gaps: Array = wall.get("gaps", [])
	var along_x := absf(b.y - a.y) < 0.01  # wall runs along the x axis
	var lo := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var cross := a.y if along_x else a.x

	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort_custom(func(g1: Array, g2: Array) -> bool: return g1[0] < g2[0])

	var cursor := lo
	for gap: Array in sorted_gaps:
		var g_lo: float = gap[0] - gap[1] * 0.5
		var g_hi: float = gap[0] + gap[1] * 0.5
		if g_lo - cursor > 0.05:
			_wall_seg(parent, cursor, g_lo, cross, base, base + h, along_x)
		# Lintel above the doorway.
		if base + h - (base + DOOR_H) > 0.05:
			_wall_seg(parent, g_lo, g_hi, cross, base + DOOR_H, base + h, along_x)
		cursor = g_hi
	if hi - cursor > 0.05:
		_wall_seg(parent, cursor, hi, cross, base, base + h, along_x)

static func _wall_seg(parent: Node3D, lo: float, hi: float, cross: float,
		y_lo: float, y_hi: float, along_x: bool) -> void:
	var center := Vector3(
		(lo + hi) * 0.5 if along_x else cross,
		(y_lo + y_hi) * 0.5,
		cross if along_x else (lo + hi) * 0.5)
	var size := Vector3(
		hi - lo if along_x else WALL_T,
		y_hi - y_lo,
		WALL_T if along_x else hi - lo)
	_box(parent, center, size, COL_WALL)

static func _build_stairs(parent: Node3D, stair: Dictionary) -> void:
	var start: Vector2 = stair["start"]
	var dir: Vector2 = stair["dir"]
	var base: float = stair["base"]
	var rise: float = stair["rise"]
	var run: float = stair["run"]
	var steps: int = stair["steps"]
	var width: float = stair["width"]
	for i in range(steps):
		var plan := start + dir * (run * (i + 0.5))
		var top := base + rise * (i + 1) if rise > 0.0 else base + rise * i
		_box(parent,
			Vector3(plan.x, top - 0.15, plan.y),
			Vector3(width if absf(dir.y) > 0.5 else run,
				0.3,
				run if absf(dir.y) > 0.5 else width),
			COL_STEP_A if i % 2 == 0 else COL_STEP_B)

static func _box(parent: Node3D, center: Vector3, size: Vector3,
		color: Color, unshaded: bool = false) -> void:
	var body := StaticBody3D.new()
	body.position = center

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)

	parent.add_child(body)
