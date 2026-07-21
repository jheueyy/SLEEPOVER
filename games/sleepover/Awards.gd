class_name Awards
extends Object
## End-of-round awards for the recap screen. Screenshot-bait: the recap is the
## shareable artifact that ends every session (build spec 3.x), so every line on it
## has to be TRUE — an award nobody earned is simply not shown, never
## "Clutch Rescue — nobody".
##
## This is a PURE function of the round-stats dictionary: same input, same output, no
## node/scene access. That makes it exhaustively testable headless, and keeps award
## tuning (which will churn after playtests) out of the 2k-line Main.gd.
##
## Stats shape — { pid: { tumbles, noise_total, noise_pings, rescues, fragments,
##                        escaped: bool, cocooned_order: int (-1 = never) } }

## [title, stat key, "high"/"low" wins, requirement to qualify at all]
const DEFS: Array = [
	{"title": "MOST FALLS",       "key": "tumbles",     "want": "high", "min": 1,
		"blurb": "down the stairs, repeatedly"},
	{"title": "LOUDEST ZIPPER",   "key": "noise_total", "want": "high", "min": 0.01,
		"blurb": "the Housesitter thanks you"},
	{"title": "CLUTCH RESCUE",    "key": "rescues",     "want": "high", "min": 1,
		"blurb": "unzipped a friend"},
	{"title": "LORE HOUND",       "key": "fragments",   "want": "high", "min": 1,
		"blurb": "read what shouldn't be read"},
	{"title": "QUIET AS A MOUSE", "key": "noise_pings", "want": "low",  "min": 0,
		"blurb": "barely made a sound"},
]

static func blank_stats() -> Dictionary:
	return {
		"tumbles": 0, "noise_total": 0.0, "noise_pings": 0,
		"rescues": 0, "fragments": 0, "escaped": false, "cocooned_order": -1,
	}

## Returns [{title, pid, value, blurb}] — only awards someone actually earned.
## Ties break on the LOWEST pid so every machine renders an identical card.
static func compute(stats: Dictionary) -> Array:
	var out: Array = []
	if stats.is_empty():
		return out
	for d: Dictionary in DEFS:
		var key: String = d["key"]
		var high: bool = d["want"] == "high"
		var best_pid := -1
		var best_val: float = 0.0
		for pid: int in stats:
			var v := float((stats[pid] as Dictionary).get(key, 0))
			if best_pid == -1 or (v > best_val if high else v < best_val) \
					or (is_equal_approx(v, best_val) and pid < best_pid):
				best_pid = pid
				best_val = v
		# "High" awards need someone to have actually done the thing. "Low" awards
		# (quietest) need a real round to have happened, not a lobby of statues.
		if high:
			if best_val < float(d["min"]):
				continue
		elif stats.size() < 2 or not _anyone_made_noise(stats):
			continue
		out.append({"title": d["title"], "pid": best_pid, "value": best_val,
			"blurb": d["blurb"]})
	# FIRST TUCKED IN is ordinal, not a max — whoever the Housesitter got first.
	var first_pid := -1
	var first_order := 1 << 30
	for pid: int in stats:
		var o := int((stats[pid] as Dictionary).get("cocooned_order", -1))
		if o >= 0 and (o < first_order or (o == first_order and pid < first_pid)):
			first_order = o
			first_pid = pid
	if first_pid != -1:
		out.append({"title": "FIRST TUCKED IN", "pid": first_pid, "value": 0.0,
			"blurb": "tucked in before anyone else"})
	return out

static func _anyone_made_noise(stats: Dictionary) -> bool:
	for pid: int in stats:
		if int((stats[pid] as Dictionary).get("noise_pings", 0)) > 0:
			return true
	return false

## Per-player fate line for the recap ("2 escaped, 1 survived, 1 tucked in").
static func fate_of(s: Dictionary, outcome: String) -> String:
	if bool(s.get("escaped", false)):
		return "escaped"
	if int(s.get("cocooned_order", -1)) >= 0:
		return "tucked in"
	return "survived till sunrise" if outcome == "SUNRISE" else "still in the house"
