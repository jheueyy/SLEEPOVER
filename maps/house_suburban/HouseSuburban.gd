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
## Stair treads live on their OWN collision layer so the PLAYER never touches them.
## The player rides only the smooth invisible ramp (layer 2); the treads remain solid
## for the navmesh bake and the monster's floor-snap, which walk the visible steps.
## Without this, the capsule catches on 0.3m risers and stairs are unclimbable by
## shuffle — which forced players to spend their whole hop tank just to change floors.
const TREAD_LAYER := 4   # collision layer 3
## Small lift so the ramp reads as sitting on the step noses rather than inside them.
const RAMP_LIFT := 0.05
const WALL_H := 3.0
const DOOR_H := 2.0
const DOOR_W := 1.1  # pre-scale; S widens doors along with everything else

# Plan scale: all x/z layout data below is authored on the original 16x12
# grid and multiplied by S at build time. Raised after playtest feedback
# ("rooms too small, corridors too tight") — heights stay 1:1, so stairs
# also get shallower and easier to hop.
const S := 1.4

# Where players wake up (living room). Slot 0 = host/solo, clients pick 1+.
# (Already in world units — these are consts, so they're pre-scaled by hand.)
const SPAWNS: Array[Vector3] = [
	Vector3(-7.0, 1.0, 1.4), Vector3(-4.9, 1.0, 2.1), Vector3(-8.4, 1.0, 3.5),
	Vector3(-4.9, 1.0, 4.2), Vector3(-7.0, 1.0, 5.6), Vector3(-9.1, 1.0, 5.3),
]
# The ATTIC — it sleeps up there at round start, two staircases and half a
# house from the living room. Waking up is an event, not a spawn.
const MONSTER_SPAWN := Vector3(-7.7, 7.0, -4.9)

# ── Layout data ────────────────────────────────────────────────────────────
# Ground: front door opens into the HALL (stairs up + walkway). Living room off
# the hall by the entry; kitchen behind the living room; dining behind the hall;
# pantry links dining to the laundry; garage is the full east strip with the
# basement stairs in it (very suburban). Bath and laundry both open off the hall.
# Upper: a corridor runs along the back so every bedroom opens onto shared
# space — no walking through someone's room. Linen closet holds the chute.

# Walls: a/b are plan endpoints, base = floor height, gaps = [pos_along_wall, width]
const WALLS: Array = [
	# Ground outer shell
	{"a": Vector2(-8, -6), "b": Vector2(8, -6), "base": 0.0, "gaps": [[-0.5, 1.4]]},  # back door -> dining (the dog's keys)
	{"a": Vector2(-8, 6), "b": Vector2(8, 6), "base": 0.0, "gaps": [[0.5, 1.2], [6.5, 1.4]]},  # front door -> hall, garage door
	{"a": Vector2(-8, -6), "b": Vector2(-8, 6), "base": 0.0},
	{"a": Vector2(8, -6), "b": Vector2(8, 6), "base": 0.0},
	# Ground interior
	{"a": Vector2(-8, -1), "b": Vector2(5, -1), "base": 0.0, "gaps": [[-5.5, DOOR_W], [0.5, DOOR_W], [3.5, DOOR_W]]},  # kitchen|living, dining|hall, pantry|laundry
	{"a": Vector2(-3, -6), "b": Vector2(-3, -1), "base": 0.0, "gaps": [[-3.5, DOOR_W]]},   # kitchen|dining
	{"a": Vector2(2, -6), "b": Vector2(2, -1), "base": 0.0, "gaps": [[-3.5, DOOR_W]]},     # dining|pantry
	{"a": Vector2(5, -6), "b": Vector2(5, 6), "base": 0.0, "gaps": [[-3.5, DOOR_W], [0.75, DOOR_W]]},  # pantry|garage, laundry|garage
	{"a": Vector2(-1, -1), "b": Vector2(-1, 6), "base": 0.0, "gaps": [[5.5, DOOR_W]]},     # living|hall, door by the entry
	{"a": Vector2(2, -1), "b": Vector2(2, 6), "base": 0.0, "gaps": [[0.5, DOOR_W], [4.5, DOOR_W]]},  # hall|laundry, hall|bath
	{"a": Vector2(2, 2.5), "b": Vector2(5, 2.5), "base": 0.0},                             # laundry|bath divider
	# Stair shaft (x -1..0.5, z 0..5): holds BOTH flights — the up-stairs above and
	# the basement stairs directly beneath them. Walled off from the hall's walking
	# lane; OPEN at its north end (that's the up-stairs mouth) and closed at its
	# south end by a wall carrying the BASEMENT DOOR, right beside the front entry.
	{"a": Vector2(0.5, 0), "b": Vector2(0.5, 5), "base": 0.0},                             # shaft | hall lane
	{"a": Vector2(-1, 5), "b": Vector2(0.5, 5), "base": 0.0, "gaps": [[-0.25, DOOR_W]]},   # THE BASEMENT DOOR
	# Upper outer shell (garage is single-story: footprint stops at x=5)
	{"a": Vector2(-8, -6), "b": Vector2(5, -6), "base": 3.0},
	{"a": Vector2(-8, 6), "b": Vector2(5, 6), "base": 3.0},
	{"a": Vector2(-8, -6), "b": Vector2(-8, 6), "base": 3.0},
	{"a": Vector2(5, -6), "b": Vector2(5, 6), "base": 3.0},
	# Upper interior — corridor along z -1..0.5 connects everything
	{"a": Vector2(-8, -1), "b": Vector2(5, -1), "base": 3.0, "gaps": [[-5.5, DOOR_W], [0.8, DOOR_W], [3.5, DOOR_W]]},  # kid1, kid2, upbath -> corridor (kid2 door sits east, clear of the attic stairs)
	{"a": Vector2(-8, 0.5), "b": Vector2(-1, 0.5), "base": 3.0, "gaps": [[-4.5, DOOR_W]]}, # master -> corridor
	{"a": Vector2(2, 0.5), "b": Vector2(5, 0.5), "base": 3.0, "gaps": [[3.0, DOOR_W]]},    # closet -> corridor
	{"a": Vector2(-1, 0.5), "b": Vector2(-1, 6), "base": 3.0, "gaps": [[3.0, DOOR_W]]},    # master|landing loop door
	{"a": Vector2(2, 0.5), "b": Vector2(2, 6), "base": 3.0, "gaps": [[4.5, DOOR_W]]},      # landing -> office
	{"a": Vector2(2, 2), "b": Vector2(5, 2), "base": 3.0},                                 # closet|office divider
	{"a": Vector2(-3, -6), "b": Vector2(-3, -1), "base": 3.0},                             # kid1|kid2
	{"a": Vector2(2, -6), "b": Vector2(2, -1), "base": 3.0},                               # kid2|upbath
	# Basement (x -8..2, z -6..6) — a gauntlet, not a corridor. The stairs land
	# north-centre; the WALKOUT is the far SW and the BREAKER is a dead-end pocket in
	# the far NE, so you fetch the thing that opens the door and then cross the whole
	# pitch-black floor to reach it. Two staggered chokepoints in between.
	{"a": Vector2(-8, -6), "b": Vector2(2, -6), "base": -3.0},                       # north
	{"a": Vector2(-8, 6), "b": Vector2(2, 6), "base": -3.0},                         # south
	{"a": Vector2(-8, -6), "b": Vector2(-8, 6), "base": -3.0, "gaps": [[4.5, 1.4]]}, # west — WALKOUT escape
	{"a": Vector2(2, -6), "b": Vector2(2, 6), "base": -3.0},                         # east
	{"a": Vector2(-3, -6), "b": Vector2(-3, 6), "base": -3.0, "gaps": [[1, DOOR_W]]},# divider 1: only way west
	{"a": Vector2(-8, 2), "b": Vector2(-3, 2), "base": -3.0, "gaps": [[-7, DOOR_W]]},# divider 2: only way to the SW walkout
	{"a": Vector2(0, -3), "b": Vector2(2, -3), "base": -3.0, "gaps": [[1, DOOR_W]]}, # breaker pocket entrance (far NE)
	{"a": Vector2(0, -6), "b": Vector2(0, -3), "base": -3.0},                        # breaker pocket west wall (dead-end)
	# Attic (low walls, over the upper back row)
	{"a": Vector2(-8, -6), "b": Vector2(2, -6), "base": 6.0, "h": 2.2},
	{"a": Vector2(-8, -1), "b": Vector2(2, -1), "base": 6.0, "h": 2.2},
	{"a": Vector2(-8, -6), "b": Vector2(-8, -1), "base": 6.0, "h": 2.2},
	{"a": Vector2(2, -6), "b": Vector2(2, -1), "base": 6.0, "h": 2.2},
]

# Floor slabs: rect = [x_min, z_min, x_max, z_max], top = slab top height.
# Holes (stairwells, chute) are simply not covered by any rect.
const SLABS: Array = [
	# Yard (a safety floor just below the ground floor so nobody falls into the
	# void) — BUT with a hole under the basement (x2..8, z0..6). Without this hole
	# the yard slab spans the whole map and a player stepping into the basement
	# stairwell lands on IT at y≈0 instead of descending — the bug that made the
	# basement unreachable on foot for every previous build. The basement floor
	# (y−3) is the safety net inside that hole.
	{"rect": [-12.0, -9.0, -8.0, 9.0], "top": -0.05},
	{"rect": [2.0, -9.0, 12.0, 9.0], "top": -0.05},
	{"rect": [-8.0, -9.0, 2.0, -6.0], "top": -0.05},
	{"rect": [-8.0, 6.0, 2.0, 9.0], "top": -0.05},
	# Ground floor — solid everywhere except the stair SHAFT (x -1..0.5, z 0..5),
	# which holds the up-flight above and the basement flight below. The hall keeps
	# a solid walking lane at x 0.5..2 so you can still pass north-south.
	{"rect": [-8.0, -6.0, -1.0, 6.0], "top": 0.0},
	{"rect": [0.5, -6.0, 8.0, 6.0], "top": 0.0},
	{"rect": [-1.0, -6.0, 0.5, 0.0], "top": 0.0},
	{"rect": [-1.0, 5.0, 0.5, 6.0], "top": 0.0},
	# Upper floor — holes: main stairwell x -1..0.5 z 0..5, chute x 3..4 z 1..2
	{"rect": [-8.0, -6.0, -1.0, 6.0], "top": 3.0},
	{"rect": [-1.0, -6.0, 0.5, 0.0], "top": 3.0},
	{"rect": [-1.0, 5.0, 0.5, 6.0], "top": 3.0},
	{"rect": [0.5, -6.0, 3.0, 6.0], "top": 3.0},
	{"rect": [3.0, -6.0, 5.0, 1.0], "top": 3.0},
	{"rect": [4.0, 1.0, 5.0, 2.0], "top": 3.0},
	{"rect": [3.0, 2.0, 5.0, 6.0], "top": 3.0},
	# Attic floor — hole at x -3..-1.4, z -6..-1 (attic stairwell; step off sideways)
	{"rect": [-8.0, -6.0, -3.0, -1.0], "top": 6.0},
	{"rect": [-1.4, -6.0, 2.0, -1.0], "top": 6.0},
	# Basement floor — the dread floor, under the west+centre of the house
	# (x -8..2, z -6..6 ≈ 14x17m). Stairs land north-centre; the walkout is the far
	# SW corner and the Breaker is a dead-end pocket in the far NE, so escaping
	# means crossing the whole dark floor twice.
	{"rect": [-8.0, -6.0, 2.0, 6.0], "top": -3.0},
	# Ceilings — the upper front row and the up-bath have the flat roof at y6;
	# the attic floor already ceils the back row. Garage gets its own roof.
	{"rect": [-8.0, -1.0, 5.0, 6.0], "top": 6.0},
	{"rect": [2.0, -6.0, 5.0, -1.0], "top": 6.0},
	{"rect": [5.0, -6.0, 8.0, 6.0], "top": 3.0},
]

# Stairs: start = plan pos of the first step's near edge center; dir = plan
# direction of climb; base = y of the floor you start from; signed rise.
const STAIRS: Array = [
	{"start": Vector2(-0.25, 0.0), "dir": Vector2(0, 1), "base": 0.0, "rise": 0.3, "run": 0.5, "steps": 10, "width": 1.5, "to": "UPSTAIRS"},  # hall -> upper (walkway stays beside it)
	{"start": Vector2(-0.25, 5.0), "dir": Vector2(0, -1), "base": 0.0, "rise": -0.3, "run": 0.5, "steps": 10, "width": 1.5, "to": "BASEMENT"}, # basement: runs DIRECTLY UNDER the up-flight in the same lane, descending the opposite way — the two stay a constant 3m apart. Entered by a real DOOR at the shaft's south end (by the front entry), not a hole in the floor.
	{"start": Vector2(-2.2, -1.0), "dir": Vector2(0, -1), "base": 3.0, "rise": 0.3, "run": 0.5, "steps": 10, "width": 1.8, "to": "ATTIC"}, # kid2 -> attic (wider than its hole: top tread overlaps the attic slab sideways)
	# NOTE: keep stair run >= 0.5 and width >= 1.5, clear of wall footprints —
	# narrower/shorter treads voxelize into a disconnected navmesh and the
	# monster can't change floors there. (The 2.1m-wide main stairs are the
	# reference that provably bakes connected.)
]

# Navmesh links: explicit bridges across the stairwells whose baked meshes
# don't connect (their ramps terminate into wall footprints). Each pair is
# [from, to] in plan coords with REAL heights (y is not scaled). Two hops per
# staircase: along the stairs, then sideways onto the destination floor. The
# monster's follower walks these horizontally while its floor-snap rides the
# visible treads, so traversal looks like ordinary stair walking.
const NAV_LINKS: Array = [
	# kid2 <-> attic
	{"from": Vector3(-1.0, 3.3, -3.0), "to": Vector3(-5.0, 6.3, -3.5)},
	# hall shaft <-> basement (the flight under the up-stairs; two hops: down the
	# flight from just inside the basement door, then out onto the basement floor)
	{"from": Vector3(-0.25, 0.3, 5.2), "to": Vector3(-0.25, -2.7, -0.2)},
	{"from": Vector3(-0.25, -2.7, -0.2), "to": Vector3(-1.5, -2.7, -1.5)},
]

# Monster patrol loop (plan x/z + REAL y of the floor): a lap through the
# house so the hum wanders the halls. Consumed scaled via patrol_points().
const PATROL_LOOP: Array = [
	Vector3(-0.5, 0.5, -3.5),   # dining
	Vector3(-5.5, 0.5, -3.5),   # kitchen
	Vector3(-4.5, 0.5, 2.5),    # living room
	Vector3(0.5, 0.5, 4.5),     # hall
	Vector3(-1.0, -2.7, -2.0),  # basement arrival (the hum wanders down there)
	Vector3(-6.0, -2.7, 4.0),   # basement SW, by the walkout
	Vector3(0.5, 3.5, 5.3),     # landing (upstairs)
	Vector3(-4.5, 3.5, 3.5),    # master bed
	Vector3(-2.0, 3.5, -0.2),   # corridor
	Vector3(0.5, 3.5, 5.3),     # landing again, then back down
]

# Hiding volumes (plan x/z + floor y, box ~1.6 wide). Inside one and unseen =
# the monster's sight can't find you; only a ping into your room betrays you.
const HIDE_SPOTS: Array = [
	Vector3(4.2, 0.0, -5.2),    # pantry corner
	Vector3(4.2, 3.0, 1.2),     # upstairs linen closet
	Vector3(-7.2, 3.0, 5.2),    # under the master bed
	Vector3(-7.0, -3.0, 0.0),   # basement NW corner (clear of the breaker)
]

# ── Objective spots (plan x/z + floor y; host picks one clue spot per round) ──
# The Landline: number note somewhere (any floor), dial at the hall wall phone.
const CLUE_SPOTS: Array = [
	Vector3(-7.4, 0.0, -5.4),   # kitchen fridge (ground)
	Vector3(1.5, 0.0, 3.0),     # hallway table (ground)
	Vector3(-4.5, 3.0, 3.5),    # master nightstand (upstairs)
	Vector3(3.5, 3.0, -3.5),    # up-bath cabinet (upstairs)
	Vector3(-6.0, -3.0, 4.0),   # basement, SW near the walkout (basement)
]
const PHONE_SPOT := Vector3(1.7, 0.0, 5.4)  # hall wall by the front door

# The Breaker: fuse-order diagram somewhere (any floor), fuse box in the basement.
const BREAKER_DIAGRAM_SPOTS: Array = [
	Vector3(7.4, 0.0, -3.0),    # garage wall (ground)
	Vector3(6.4, 0.0, 1.0),     # laundry (ground)
	Vector3(-5.0, 3.0, -3.5),   # kid room 1 wall (upstairs)
	Vector3(0.5, 3.0, 5.0),     # landing (upstairs)
	Vector3(-5.0, -3.0, -2.0),  # basement NW storage (basement)
]
const BREAKER_BOX_SPOT := Vector3(1.0, -3.0, -4.5)  # far-NE dead-end pocket, opposite the walkout

# The Dog Has The Keys: grab a snack from the pantry, then reach the wandering
# dog. The dog paces this ground-floor loop.
const DOG_SNACK_SPOT := Vector3(3.5, 0.0, -5.0)     # pantry shelf
const DOG_PATH: Array = [
	Vector3(-5.0, 0.0, -3.5), Vector3(-4.5, 0.0, 2.5),
	Vector3(0.5, 0.0, 4.0), Vector3(-0.5, 0.0, -3.5),
]

# The Deadbolt: two players at the back door (kitchen), both holding E.
const DEADBOLT_SPOT := Vector3(-6.5, 0.0, -5.6)

# The Garage Code: birthday clue somewhere (any floor), keypad by the garage door.
const GARAGE_CLUE_SPOTS: Array = [
	Vector3(-4.5, 0.0, 3.5),    # living room banner (ground)
	Vector3(-5.5, 0.0, -3.0),   # kitchen calendar (ground)
	Vector3(-0.5, 3.0, -3.5),   # kid room 2 cake photo (upstairs)
	Vector3(3.5, 3.0, 4.0),     # office (upstairs)
	Vector3(1.0, -3.0, 3.0),    # basement east arrival area (basement)
]
const GARAGE_KEYPAD_SPOT := Vector3(6.5, 0.0, 5.3)  # garage door wall

# The Glasses: the blurred player's glasses sit at one of these.
const GLASSES_SPOTS: Array = [
	Vector3(-5.0, 3.0, -3.5),   # kid room 1
	Vector3(-0.5, 3.0, -3.5),   # kid room 2
	Vector3(3.5, 3.0, 4.0),     # office
	Vector3(-6.5, 3.0, 3.5),    # master bed
]

# Escape exits. Each door is unlocked by ONE specific objective (see Main's
# EXIT_OBJECTIVE map); the escape PHASE arms at 3-of-5, but which doors are open
# depends entirely on which objectives were completed. [name, plan center, y,
# half-extent, door-blocker group ("" = no physical blocker, logic-gated only)].
const EXITS: Array = [
	{"name": "FRONT DOOR", "at": Vector3(0.5, 1.0, 7.4), "half": Vector2(1.2, 1.2), "door": "front_door"},
	{"name": "BACK DOOR", "at": Vector3(-0.5, 1.0, -6.6), "half": Vector2(1.2, 1.2), "door": "back_door"},
	{"name": "GARAGE", "at": Vector3(6.5, 1.0, 7.4), "half": Vector2(1.4, 1.2), "door": "garage_door"},
	{"name": "BASEMENT WINDOW", "at": Vector3(-7.4, -2.0, 4.5), "half": Vector2(1.2, 1.2), "door": ""},
]

static func exits() -> Array:
	var out: Array = []
	for e: Dictionary in EXITS:
		out.append({
			"name": e["name"],
			"at": scaled(e["at"]),
			"half": Vector2(e["half"].x * S, e["half"].y * S),
			"door": e["door"],
		})
	return out

static func patrol_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in PATROL_LOOP:
		out.append(Vector3(p.x * S, p.y, p.z * S))
	return out

static func scaled(p: Vector3) -> Vector3:
	return Vector3(p.x * S, p.y, p.z * S)

## Anchor pool for lore fragments — the union of every objective's clue-spawn
## spots (spread across all 3 floors), so lore-hunting shares the exact same risk
## and traversal as objective clues. Returned scaled, deduped.
static func fragment_anchors() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pools: Array = [CLUE_SPOTS, GARAGE_CLUE_SPOTS, BREAKER_DIAGRAM_SPOTS,
		GLASSES_SPOTS, [DOG_SNACK_SPOT]]
	for pool: Array in pools:
		for p: Vector3 in pool:
			var s := scaled(p)
			if not out.has(s):
				out.append(s)
	return out

# ── Floors & distribution ────────────────────────────────────────────────────
enum Floor { BASEMENT, GROUND, UPSTAIRS }

## Which floor a REAL (unscaled-y) world height belongs to. Attic counts as up.
static func floor_of(y: float) -> Floor:
	if y < -1.0:
		return Floor.BASEMENT
	if y < 2.0:
		return Floor.GROUND
	return Floor.UPSTAIRS

# Monster LIGHTS-OUT spawn candidates (plan x/z + real y), spread across floors
# and clear of the staircases. Host picks the one farthest from players+clues.
const MONSTER_SPAWN_CANDIDATES: Array = [
	Vector3(-4.2, 6.4, -4.9),   # attic (far up)
	Vector3(-6.0, 3.5, -3.5),   # kid room 1 (upstairs far NW)
	Vector3(3.5, 3.5, 4.0),     # office (upstairs far SE)
	Vector3(-6.5, -3.0, -4.0),  # basement NW (far down)
	Vector3(-6.5, 0.5, -3.5),   # kitchen (ground far NW)
	Vector3(6.5, 0.5, -4.0),    # garage (ground far NE, clear of the basement stairs)
]

# Staircase plan positions the monster must NOT spawn on/next to (chokepoints).
const STAIR_PLAN_POINTS: Array = [
	Vector2(-0.25, 2.5),   # main up-stairs (hall <-> upstairs)
	Vector2(-0.25, 2.5),   # basement down-stairs (shaft under the up-stairs)
	Vector2(-2.2, -3.5),   # attic stairs (kid2 <-> attic)
]

static func monster_spawn_candidates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in MONSTER_SPAWN_CANDIDATES:
		out.append(Vector3(p.x * S, p.y, p.z * S))
	return out

## Nearest staircase distance (world, x/z) from a scaled point — for the spawn
## exclusion check.
static func dist_to_nearest_stair(world_pos: Vector3) -> float:
	var best := INF
	for s: Vector2 in STAIR_PLAN_POINTS:
		best = minf(best, Vector2(world_pos.x - s.x * S, world_pos.z - s.y * S).length())
	return best

# Room labels: gray-box wayfinding + playtest comms ("it's in the DINING ROOM")
const ROOMS: Array = [
	{"name": "LIVING ROOM", "at": Vector3(-4.5, 2.2, 2.5)},
	{"name": "KITCHEN", "at": Vector3(-5.5, 2.2, -3.5)},
	{"name": "DINING", "at": Vector3(-0.5, 2.2, -3.5)},
	{"name": "PANTRY", "at": Vector3(3.5, 2.2, -3.5)},
	{"name": "GARAGE", "at": Vector3(6.5, 2.2, 0.0)},
	{"name": "HALL", "at": Vector3(0.5, 2.2, 5.3)},
	{"name": "LAUNDRY", "at": Vector3(3.5, 2.2, 0.75)},
	{"name": "BATH", "at": Vector3(3.5, 2.2, 4.25)},
	{"name": "MASTER BED", "at": Vector3(-4.5, 5.2, 3.5)},
	{"name": "LANDING", "at": Vector3(0.5, 5.2, 5.3)},
	{"name": "CLOSET (CHUTE!)", "at": Vector3(3.5, 5.2, 1.25)},
	{"name": "OFFICE", "at": Vector3(3.5, 5.2, 4.0)},
	{"name": "KID ROOM 1", "at": Vector3(-5.5, 5.2, -3.5)},
	{"name": "KID ROOM 2", "at": Vector3(-0.5, 5.2, -3.5)},
	{"name": "UP BATH", "at": Vector3(3.5, 5.2, -3.5)},
	{"name": "OPEN REC ROOM", "at": Vector3(-1.0, -1.8, 2.0)},
	{"name": "STORAGE", "at": Vector3(-5.5, -1.8, -2.0)},
	{"name": "UTILITY (BREAKER)", "at": Vector3(1.0, -1.8, -4.5)},
	{"name": "WALKOUT", "at": Vector3(-6.5, -1.8, 4.5)},
	{"name": "ATTIC", "at": Vector3(-3.0, 7.4, -3.5)},
]

const COL_FLOOR := Color(0.30, 0.30, 0.34)
const COL_WALL := Color(0.22, 0.22, 0.26)
const COL_ROOF := Color(0.34, 0.20, 0.18)
const COL_STEP_A := Color(0.34, 0.28, 0.24)
const COL_STEP_B := Color(0.40, 0.33, 0.28)
const COL_CHUTE := Color(1.0, 0.9, 0.2)

# Room lamps: the basement is the intentionally-darkest floor (dread + the
# Breaker turns lights up later). Any room below ground uses the dim value.
const ROOM_LIGHT_ENERGY := 0.7
const BASEMENT_LIGHT_ENERGY := 0.18

# ── Builder ────────────────────────────────────────────────────────────────

static func build(parent: Node3D) -> void:
	for slab: Dictionary in SLABS:
		var r: Array = slab["rect"]
		var top: float = slab["top"]
		_box(parent,
			Vector3((r[0] + r[2]) * 0.5 * S, top - 0.15, (r[1] + r[3]) * 0.5 * S),
			Vector3((r[2] - r[0]) * S, 0.3, (r[3] - r[1]) * S), COL_FLOOR)

	for wall: Dictionary in WALLS:
		_build_wall(parent, wall)

	for stair: Dictionary in STAIRS:
		_build_stairs(parent, stair)

	# Chute rim: a glowing lip around the closet hole so it reads as a feature.
	for rim: Array in [[3.5, 0.95], [3.5, 2.05], [2.95, 1.5], [4.05, 1.5]]:
		var along_x: bool = absf(rim[1] - 1.5) > 0.3
		_box(parent, Vector3(rim[0] * S, 3.1, rim[1] * S),
			Vector3(1.2 * S if along_x else 0.1, 0.2, 0.1 if along_x else 1.2 * S),
			COL_CHUTE, true)

	# Gable roof over the attic — two slanted slabs meeting at a ridge, with
	# rectangular end caps. Purely so the thing reads as a HOUSE from outside.
	var eave_y := 8.2   # attic wall tops (base 6 + h 2.2)
	var ridge_y := 9.2
	for side_z: float in [-6.0, -1.0]:
		var a := Vector3(-3.0 * S, eave_y, side_z * S)
		var b := Vector3(-3.0 * S, ridge_y, -3.5 * S)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(10.0 * S + 0.4, 0.15, a.distance_to(b) + 0.3)
		cs.shape = bx
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bx.size
		mi.mesh = bm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = COL_ROOF
		mi.set_surface_override_material(0, rmat)
		body.add_child(mi)
		parent.add_child(body)
		body.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	for gable_x: float in [-8.0, 2.0]:
		_box(parent, Vector3(gable_x * S, (eave_y + ridge_y) * 0.5, -3.5 * S),
			Vector3(WALL_T, ridge_y - eave_y, 5.0 * S), COL_WALL)

	# Exit doors: real blockers in the doorways. [group, plan x, plan width, plan z].
	# Each is hidden + collision-disabled when ITS objective is completed (Main's
	# EXIT_OBJECTIVE map); escaping = walking out through an open one.
	for door_def: Array in [
			["front_door", 0.5, 1.2, 6.0, "FRONT DOOR"],
			["garage_door", 6.5, 1.4, 6.0, "GARAGE DOOR"],
			["back_door", -0.5, 1.4, -6.0, "BACK DOOR"]]:
		var door := StaticBody3D.new()
		door.add_to_group(door_def[0])
		door.position = Vector3(door_def[1] * S, 1.0, door_def[3] * S)
		var door_shape := CollisionShape3D.new()
		var door_box := BoxShape3D.new()
		door_box.size = Vector3(door_def[2] * S, 2.0, 0.25)
		door_shape.shape = door_box
		door.add_child(door_shape)
		var door_mesh := MeshInstance3D.new()
		var door_bm := BoxMesh.new()
		door_bm.size = door_box.size
		door_mesh.mesh = door_bm
		var door_mat := StandardMaterial3D.new()
		door_mat.albedo_color = Color(0.45, 0.30, 0.16)
		door_mesh.set_surface_override_material(0, door_mat)
		door.add_child(door_mesh)
		# Label so a locked exit reads as a DOOR, not a stray brown block. It's a
		# child of the blocker, so it hides with the door when the exit unlocks.
		var door_label := Label3D.new()
		door_label.text = door_def[4]
		door_label.font_size = 40
		door_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		door_label.modulate = Color(0.95, 0.85, 0.6, 0.85)
		door_label.position = Vector3(0, 1.3, 0)
		door.add_child(door_label)
		parent.add_child(door)

	# Hiding volumes: translucent green nooks. Main wires their signals.
	for hs: Vector3 in HIDE_SPOTS:
		var area := Area3D.new()
		area.add_to_group("hide_spot")
		area.position = Vector3(hs.x * S, hs.y + 0.7, hs.z * S)
		var a_shape := CollisionShape3D.new()
		var a_box := BoxShape3D.new()
		a_box.size = Vector3(1.7, 1.4, 1.7)
		a_shape.shape = a_box
		area.add_child(a_shape)
		var a_mesh := MeshInstance3D.new()
		var a_bm := BoxMesh.new()
		a_bm.size = Vector3(1.7, 1.4, 1.7)
		a_mesh.mesh = a_bm
		var a_mat := StandardMaterial3D.new()
		a_mat.albedo_color = Color(0.2, 0.8, 0.4, 0.18)
		a_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		a_mesh.set_surface_override_material(0, a_mat)
		area.add_child(a_mesh)
		var a_label := Label3D.new()
		a_label.text = "HIDE"
		a_label.font_size = 40
		a_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		a_label.modulate = Color(0.5, 1.0, 0.6, 0.6)
		a_label.position = Vector3(0, 1.0, 0)
		area.add_child(a_label)
		parent.add_child(area)

	for link_def: Dictionary in NAV_LINKS:
		var link := NavigationLink3D.new()
		var f: Vector3 = link_def["from"]
		var t: Vector3 = link_def["to"]
		link.start_position = Vector3(f.x * S, f.y, f.z * S)
		link.end_position = Vector3(t.x * S, t.y, t.z * S)
		parent.add_child(link)

	for room: Dictionary in ROOMS:
		var at: Vector3 = room["at"]
		var label := Label3D.new()
		label.text = room["name"]
		label.font_size = 72
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1, 1, 1, 0.5)
		label.position = Vector3(at.x * S, at.y, at.z * S)
		parent.add_child(label)

		# One warm lamp per room — with real ceilings, the sun stays outside.
		# The basement (below ground) is dim: the darkest, dreadiest floor.
		var below_ground := at.y < -1.0
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(at.x * S, at.y + 0.3, at.z * S)
		lamp.omni_range = 5.0 if below_ground else 6.5
		lamp.light_energy = BASEMENT_LIGHT_ENERGY if below_ground else ROOM_LIGHT_ENERGY
		lamp.light_color = Color(0.7, 0.75, 0.95) if below_ground else Color(1.0, 0.9, 0.75)
		lamp.shadow_enabled = false
		parent.add_child(lamp)

static func _build_wall(parent: Node3D, wall: Dictionary) -> void:
	var a: Vector2 = wall["a"]
	var b: Vector2 = wall["b"]
	var base: float = wall["base"]
	var h: float = wall.get("h", WALL_H)
	var gaps: Array = wall.get("gaps", [])
	var along_x := absf(b.y - a.y) < 0.01  # wall runs along the x axis
	var lo := (minf(a.x, b.x) if along_x else minf(a.y, b.y)) * S
	var hi := (maxf(a.x, b.x) if along_x else maxf(a.y, b.y)) * S
	var cross := (a.y if along_x else a.x) * S

	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort_custom(func(g1: Array, g2: Array) -> bool: return g1[0] < g2[0])

	var cursor := lo
	for gap: Array in sorted_gaps:
		var g_lo: float = (gap[0] - gap[1] * 0.5) * S
		var g_hi: float = (gap[0] + gap[1] * 0.5) * S
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
	var start: Vector2 = stair["start"] * S
	var dir: Vector2 = stair["dir"]
	var base: float = stair["base"]
	var rise: float = stair["rise"]
	var run: float = stair["run"] * S   # plan scales, rise doesn't: shallower stairs
	var steps: int = stair["steps"]
	var width: float = stair["width"] * S
	for i in range(steps):
		# First/last treads extend 0.4 into the neighboring floor so the
		# navmesh voxels MERGE across the junction — flush edges at different
		# heights bake as disconnected islands (learned the hard way).
		var ext_back := 0.4 if i == 0 else 0.0
		var ext_fwd := 0.4 if i == steps - 1 else 0.0
		var length := run + ext_back + ext_fwd
		var plan := start + dir * (run * (i + 0.5) + (ext_fwd - ext_back) * 0.5)
		var top := base + rise * (i + 1) if rise > 0.0 else base + rise * i
		_box(parent,
			Vector3(plan.x, top - 0.15, plan.y),
			Vector3(width if absf(dir.y) > 0.5 else length,
				0.3,
				length if absf(dir.y) > 0.5 else width),
			COL_STEP_A if i % 2 == 0 else COL_STEP_B, false, TREAD_LAYER)

	# Invisible ramp over the treads so bags can SHUFFLE up and down stairs —
	# hopping stays the fast option, but a chase no longer dies at the bottom
	# step when the tank is empty. Layer 2: players collide with it; the
	# monster's rays and the navmesh bake (mask 1) ignore it and keep walking
	# the real treads.
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var total_rise := rise * steps
	var bottom: Vector3
	var top_end: Vector3
	if rise > 0.0:
		# Ride the step-nose line: starts one run early so it meets the floor.
		bottom = Vector3(start.x, base, start.y) - fwd * run
		top_end = Vector3(start.x, base + total_rise, start.y) + fwd * (run * (steps - 1))
	else:
		bottom = Vector3(start.x, base, start.y)
		top_end = Vector3(start.x, base + total_rise, start.y) + fwd * (run * steps)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 2
	ramp.collision_mask = 0
	var rshape := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(width, 0.12, bottom.distance_to(top_end) + 0.3)
	rshape.shape = rbox
	ramp.add_child(rshape)
	parent.add_child(ramp)
	# Ride slightly ABOVE the step-nose line. The player collides with the treads too
	# (mask includes the world layer), so a ramp flush with the noses lets the capsule
	# swing into a 0.3m riser and stop dead — the "can't climb" half of the stairs
	# problem. Lifting it gives the bag clearance over every riser.
	#
	# Descending flights need an extra half-rise: their treads sit at base+rise*i while
	# ascending ones sit at base+rise*(i+1), so the same endpoints leave a DOWN ramp
	# half a step BELOW its own tread tops — the bag then rides the steps, not the ramp,
	# and can't climb at all (measured: 0.04m in 4s vs 1.97m on an up-flight).
	# Down-flights lay their treads at base+rise*i (up-flights use i+1), so the same
	# endpoints leave a down ramp half a step below its own tread tops. Correct it so
	# the ramp visually sits on the steps rather than sunk into them.
	var lift := RAMP_LIFT + (absf(rise) * 0.5 if rise < 0.0 else 0.0)
	var center := (bottom + top_end) * 0.5 + Vector3.UP * lift
	ramp.look_at_from_position(center, top_end, Vector3.UP)

	# Flat landing pads at both floor ends, flush with the floors and touching
	# the ramp ends. The ramps bake into the navmesh (they're the monster's
	# stair surface too — its feet still snap to the visible treads), and these
	# pads guarantee the baked chain floor -> ramp -> floor actually connects:
	# identical-height overlaps merge; flush edges at differing heights don't.
	var low_pt := bottom if rise > 0.0 else top_end
	var high_pt := top_end if rise > 0.0 else bottom
	var away_low := -fwd if rise > 0.0 else fwd
	var away_high := fwd if rise > 0.0 else -fwd
	for pad_data: Array in [[low_pt, away_low], [high_pt, away_high]]:
		var pt: Vector3 = pad_data[0]
		var away: Vector3 = pad_data[1]
		var pad_center: Vector3 = pt + away * 0.3
		_box(parent, Vector3(pad_center.x, pt.y - 0.15, pad_center.z),
			Vector3(width if absf(dir.y) > 0.5 else 1.2, 0.3,
				1.2 if absf(dir.y) > 0.5 else width),
			COL_FLOOR)

	# Wayfinding: a floating label + a small warm light at the stair MOUTH so the
	# way down/up is findable in the dark. The back-of-garage basement stairwell
	# was effectively invisible before this — players thought there was no basement.
	var to_name: String = stair.get("to", "")
	if to_name != "":
		var mouth := Vector3(start.x, base, start.y)
		var sign := Label3D.new()
		sign.text = ("▼ " if rise < 0.0 else "▲ ") + to_name
		sign.font_size = 56
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.modulate = Color(1.0, 0.85, 0.4, 0.9)
		sign.position = mouth + Vector3(0, 1.7, 0)
		parent.add_child(sign)
		var lamp := OmniLight3D.new()
		lamp.position = mouth + Vector3(0, 1.3, 0)
		lamp.omni_range = 4.5
		lamp.light_energy = 0.9
		lamp.light_color = Color(1.0, 0.88, 0.6)
		lamp.shadow_enabled = false
		parent.add_child(lamp)

static func _box(parent: Node3D, center: Vector3, size: Vector3,
		color: Color, unshaded: bool = false, layer: int = 1) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = layer

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
