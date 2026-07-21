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

signal changed   ## emitted whenever collection / unlocks / selection change

var collected: Array[String] = []   ## fragment ids ever collected (the Scrapbook)
var selected_skin: int = 0          ## the bag skin the local player wears
var seen_intro: bool = false        ## bookends are skippable after the first view
var seen_outro: bool = false
# Voice prefs live here too — this is the player-prefs store, and a mic mode you
# have to re-pick every launch is a mic mode you'll end up hating.
var voice_enabled: bool = true
var voice_open_mic: bool = false    ## false = push-to-talk

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
	}

func _from_dict(d: Dictionary) -> void:
	collected.clear()
	for id: Variant in d.get("collected", []):
		if id is String and not collected.has(id):
			collected.append(id)
	selected_skin = int(d.get("selected_skin", 0))
	seen_intro = bool(d.get("seen_intro", false))
	seen_outro = bool(d.get("seen_outro", false))
	voice_enabled = bool(d.get("voice_enabled", true))
	voice_open_mic = bool(d.get("voice_open_mic", false))

func save_game() -> void:
	var bytes := JSON.stringify(_to_dict()).to_utf8_buffer()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	_cloud_write(bytes)

func load_game() -> void:
	# Prefer local; fall back to the Steam Cloud copy (fresh machine, same account).
	var bytes := PackedByteArray()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			bytes = f.get_buffer(f.get_length())
			f.close()
	if bytes.is_empty():
		bytes = _cloud_read()
	if bytes.is_empty():
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed is Dictionary:
		_from_dict(parsed)

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
