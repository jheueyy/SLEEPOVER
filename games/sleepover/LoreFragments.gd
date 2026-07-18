class_name LoreFragments
extends Object
## Loads the lore-fragment catalog from a DATA FILE (not hardcoded) and defines
## how fragments group into Scrapbook pages, each of which unlocks a bag skin.
##
## The content lives in games/sleepover/data/lore_fragments.json (20 fragments,
## with deliberate gaps + contradictions). This class is the read-only loader +
## the page/skin mapping the Scrapbook and its UI consume.

const DATA_PATH := "res://games/sleepover/data/lore_fragments.json"

## Scrapbook pages. Each page: a title, the 4 fragment ids that fill it, and the
## BagVisual skin index completing it unlocks. Skin 0 is the default (always on);
## finishing ALL pages additionally unlocks the bonus skins 6 & 7 (see Scrapbook).
const PAGES: Array = [
	{ "title": "The Service",        "unlocks_skin": 1,
		"fragments": ["flyer_wren", "tape_booking", "clipping_estab", "polaroid_porch"] },
	{ "title": "The Sleepovers",     "unlocks_skin": 2,
		"fragments": ["polaroid_pile", "crayon_nicelady", "tape_giggles", "crayon_dontlook"] },
	{ "title": "The Rules",          "unlocks_skin": 3,
		"fragments": ["clipping_norule", "tape_rules", "crayon_sunrise", "flyer_backside"] },
	{ "title": "The Contradiction",  "unlocks_skin": 4,
		"fragments": ["clipping_missing", "tape_parents_late", "polaroid_empty", "crayon_two"] },
	{ "title": "The House Remembers", "unlocks_skin": 5,
		"fragments": ["clipping_resold", "tape_hum_only", "polaroid_window", "flyer_new"] },
]
const BONUS_SKINS: Array[int] = [6, 7]   ## unlocked when every page is complete

static var _cache: Array = []
static var _by_id: Dictionary = {}

## All fragments as an Array of {id, type, title, body}. Loaded + cached once.
static func all() -> Array:
	if _cache.is_empty():
		_load()
	return _cache

static func by_id(id: String) -> Dictionary:
	if _by_id.is_empty():
		_load()
	return _by_id.get(id, {})

static func ids() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in all():
		out.append(f["id"])
	return out

static func count() -> int:
	return all().size()

## Which page (index) a fragment belongs to, or -1 if unlisted.
static func page_of(id: String) -> int:
	for i in PAGES.size():
		if id in PAGES[i]["fragments"]:
			return i
	return -1

## Host round-roll: pick `n` distinct fragment ids at random from the pool.
static func pick(n: int, rng: RandomNumberGenerator) -> Array[String]:
	var pool := ids()
	# Fisher-Yates on a copy using the caller's seeded RNG (deterministic per round).
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, clampi(n, 0, pool.size()))

static func _load() -> void:
	_cache = []
	_by_id = {}
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("LoreFragments: data file missing at %s" % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not parsed.has("fragments"):
		push_warning("LoreFragments: malformed data file")
		return
	for entry: Variant in parsed["fragments"]:
		if entry is Dictionary and entry.has("id"):
			_cache.append(entry)
			_by_id[entry["id"]] = entry
