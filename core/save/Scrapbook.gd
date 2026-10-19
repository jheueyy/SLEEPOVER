extends Node
## Persistent meta-progression: the Scrapbook. Autoload.
##
## Story is delivered through systems, not cutscenes — the Scrapbook is where the
## lore fragments players collect mid-round accumulate BETWEEN rounds and sessions.
## Filling a page unlocks a bag skin (the existing cosmetic table in BagVisual).
##
## Persistence: a small JSON blob saved to `user://` AND mirrored to Steam Cloud
## (GodotSteam Remote Storage) when Steam is up. Local is the source of truth in
## solo / headless / no-Steam; the cloud copy is loaded on first run of a fresh
## machine. Everything fails soft — a missing or corrupt save just starts empty.

const SAVE_PATH := "user://scrapbook.save"
const CLOUD_FILE := "scrapbook.save"
const SAVE_VERSION := 1

## Selftest redirects persistence to a scratch file so tests NEVER touch the
## player's real Scrapbook (they used to — the harness collects fragments through
## the real code path, which silently awarded unearned progression). "" = real save.
var _path_override: String = ""

func save_path() -> String:
	return _path_override if _path_override != "" else SAVE_PATH

func use_test_path(p: String) -> void:
	_path_override = p

signal changed   ## emitted whenever collection / unlocks / selection change

var collected: Array[String] = []   ## fragment ids ever collected (the Scrapbook)
var selected_skin: int = 0          ## the bag skin the local player wears
var seen_intro: bool = false        ## bookends are skippable after the first view
var seen_outro: bool = false
# Voice prefs live here too — this is the player-prefs store, and a mic mode you
# have to re-pick every launch is a mic mode you'll end up hating.
var voice_enabled: bool = true
var voice_open_mic: bool = false    ## false = push-to-talk
var mouse_sensitivity: float = 0.004
var master_volume: float = 1.0
var effects_volume: float = 1.0
var voice_volume: float = 1.0
# Career totals — the recap's "identity investment" hook: a number that only goes up
# is what makes "run it back" stick.
var career_rounds: int = 0
var career_tumbles: int = 0
var career_rescues: int = 0
var career_fragments: int = 0

## Bank one round's personal stats. Called once per round-end, host or client.
func add_career(tumbles: int, rescues: int, fragments: int) -> void:
	career_rounds += 1
	career_tumbles += tumbles
	career_rescues += rescues
	career_fragments += fragments
	save_game()

func _ready() -> void:
	load_game()

# ── Collection ─────────────────────────────────────────────────────────────

## Record a fragment. Returns true only the FIRST time it's collected (so callers
## can fire a "new!" toast). Collecting the last fragment of a page may unlock a skin.
func collect(id: String) -> bool:
	if id == "" or collected.has(id):
		return false
	collected.append(id)
	save_game()
	changed.emit()
	return true

func has(id: String) -> bool:
	return collected.has(id)

func collected_count() -> int:
	return collected.size()

# ── Pages & cosmetic unlocks ───────────────────────────────────────────────

## A page is complete when every fragment id on it has been collected.
func page_complete(page_index: int) -> bool:
	var pages := LoreFragments.PAGES
	if page_index < 0 or page_index >= pages.size():
		return false
	for fid: String in pages[page_index]["fragments"]:
		if not collected.has(fid):
			return false
	return true

func all_pages_complete() -> bool:
	for i in LoreFragments.PAGES.size():
		if not page_complete(i):
			return false
	return true

## Skin 0 is always unlocked; each completed page unlocks its page's skin; the
## bonus skins unlock once the whole Scrapbook is filled.
func is_skin_unlocked(skin: int) -> bool:
	if skin == 0:
		return true
	if skin in LoreFragments.BONUS_SKINS:
		return all_pages_complete()
	var pages := LoreFragments.PAGES
	for i in pages.size():
		if int(pages[i]["unlocks_skin"]) == skin and page_complete(i):
			return true
	return false

func unlocked_skins() -> Array[int]:
	var out: Array[int] = [0]
	var pages := LoreFragments.PAGES
	for i in pages.size():
		var skin := int(pages[i]["unlocks_skin"])
		if page_complete(i) and not out.has(skin):
			out.append(skin)
	if all_pages_complete():
		for s: int in LoreFragments.BONUS_SKINS:
			if not out.has(s):
				out.append(s)
	out.sort()
	return out

func set_selected_skin(skin: int) -> void:
	if skin == selected_skin or not is_skin_unlocked(skin):
		return
	selected_skin = skin
	save_game()
	changed.emit()

# ── Bookends (skippable after first view) ──────────────────────────────────

func mark_intro_seen() -> void:
	if not seen_intro:
		seen_intro = true
		save_game()

func mark_outro_seen() -> void:
	if not seen_outro:
		seen_outro = true
		save_game()

# ── Persistence ────────────────────────────────────────────────────────────

func _to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"collected": collected,
		"selected_skin": selected_skin,
		"seen_intro": seen_intro,
		"seen_outro": seen_outro,
		"voice_enabled": voice_enabled,
		"voice_open_mic": voice_open_mic,
		"mouse_sensitivity": mouse_sensitivity,
		"master_volume": master_volume,
		"effects_volume": effects_volume,
		"voice_volume": voice_volume,
		"career_rounds": career_rounds,
		"career_tumbles": career_tumbles,
		"career_rescues": career_rescues,
		"career_fragments": career_fragments,
	}

func _from_dict(d: Dictionary) -> void:
	collected.clear()
	var entries: Variant = d.get("collected", [])
	if entries is Array:
		for id: Variant in entries:
			if id is String and not LoreFragments.by_id(id).is_empty() and not collected.has(id):
				collected.append(id)
	selected_skin = _read_count(d, "selected_skin")
	if not is_skin_unlocked(selected_skin):
		selected_skin = 0
	seen_intro = _read_bool(d, "seen_intro", false)
	seen_outro = _read_bool(d, "seen_outro", false)
	voice_enabled = _read_bool(d, "voice_enabled", true)
	voice_open_mic = _read_bool(d, "voice_open_mic", false)
	mouse_sensitivity = _read_number(d, "mouse_sensitivity", 0.004, 0.001, 0.01)
	master_volume = _read_number(d, "master_volume", 1.0, 0.0, 1.0)
	effects_volume = _read_number(d, "effects_volume", 1.0, 0.0, 1.0)
	voice_volume = _read_number(d, "voice_volume", 1.0, 0.0, 1.0)
	career_rounds = _read_count(d, "career_rounds")
	career_tumbles = _read_count(d, "career_tumbles")
	career_rescues = _read_count(d, "career_rescues")
	career_fragments = _read_count(d, "career_fragments")

func _read_count(d: Dictionary, key: String) -> int:
	var value: Variant = d.get(key, 0)
	if (value is int or value is float) and is_finite(float(value)):
		return int(clampf(float(value), 0.0, 2147483647.0))
	return 0

func _read_number(d: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = d.get(key, fallback)
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback

func _read_bool(d: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = d.get(key, fallback)
	return value if value is bool else fallback

func save_game() -> void:
	var bytes := JSON.stringify(_to_dict()).to_utf8_buffer()
	# Write alongside the destination, then replace it only after a complete write.
	# A failed open/write must not truncate the last good save or update the cloud.
	var temporary := save_path() + ".tmp"
	var f := FileAccess.open(temporary, FileAccess.WRITE)
	if f == null:
		push_warning("Scrapbook: cannot open save (%s)" % FileAccess.get_open_error())
		return
	f.store_buffer(bytes)
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		push_warning("Scrapbook: write failed (%s)" % write_error)
		return
	# Never replace a good backup with a damaged primary file.
	if _read_local_save(save_path()) is Dictionary:
		var backup_temp := ProjectSettings.globalize_path(save_path() + ".bak.tmp")
		var backup_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path()), backup_temp)
		if backup_error == OK:
			backup_error = DirAccess.rename_absolute(backup_temp, ProjectSettings.globalize_path(save_path() + ".bak"))
		if backup_error != OK:
			push_warning("Scrapbook: backup failed; keeping previous save (%s)" % backup_error)
			return
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path()))
	if rename_error != OK:
		push_warning("Scrapbook: save replacement failed (%s)" % rename_error)
		return
	if _path_override == "":   # never sync test data to the cloud
		_cloud_write(bytes)

func load_game() -> void:
	for path: String in [save_path(), save_path() + ".bak"]:
		var local: Variant = _read_local_save(path)
		if local is Dictionary:
			_from_dict(local)
			if path.ends_with(".bak"):
				push_warning("Scrapbook: recovered the previous save from backup.")
			return
	if _path_override != "":
		return
	var bytes := _cloud_read()
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
	if parsed is Dictionary:
		_from_dict(parsed)

func _read_local_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return null
	return parser.data

# ── Steam Cloud (Remote Storage) — no-ops without Steam ────────────────────

func _cloud_write(bytes: PackedByteArray) -> void:
	if not _cloud_ready():
		return
	Steam.fileWrite(CLOUD_FILE, bytes, bytes.size())

func _cloud_read() -> PackedByteArray:
	if not _cloud_ready() or not Steam.fileExists(CLOUD_FILE):
		return PackedByteArray()
	var size: int = Steam.getFileSize(CLOUD_FILE)
	if size <= 0:
		return PackedByteArray()
	var res: Dictionary = Steam.fileRead(CLOUD_FILE, size)
	return res.get("buffer", PackedByteArray())

func _cloud_ready() -> bool:
	# Guarded so headless / no-Steam builds never touch the Steam API.
	return SteamManager.steam_ok and Steam.isCloudEnabledForAccount() \
		and Steam.isCloudEnabledForApp()
