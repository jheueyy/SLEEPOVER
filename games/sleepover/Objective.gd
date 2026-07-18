class_name Objective
extends Node3D
## Runtime instance of one ObjectiveDef. Owns its gray-box props (clue + action),
## runs the local player's interaction, and emits `completed` when solved. All
## six kinds share this node; behaviour branches on `def.kind`. Built identically
## on every peer from a host-chosen `seed`, so props line up across the network;
## interaction runs only against the LOCAL player, and completion is broadcast.

signal completed(id: String)
signal action_noise(pos: Vector3, loudness: float)
signal toast(text: String)
signal revealed(id: String)   ## a player read this objective's clue (HUD reveal)

enum Tracker { NOT_STARTED, IN_PROGRESS, DONE }

const NEAR := 2.0        ## interaction reach (m)
const DIAL_TIME := 1.5   ## landline per-digit rotary windup
const DOG_SPEED := 0.9   ## the dog's amble (m/s) — slow, wandering pet

var def: ObjectiveDef
var done: bool = false
var seed: Dictionary = {}
var blurred_is_me: bool = false   ## glasses: is the LOCAL player the blurred one

var _clue: Node3D
var _action: Node3D
var _dog: Node3D
var _dog_i: int = 0
var _dog_path: PackedVector3Array = []
var _dog_path_i: int = 0
var _dog_repath_cd: float = 0.0
var _has_snack: bool = false
var _entry: String = ""
var _entry_digit: int = -1
var _entry_t: float = 0.0
var _hold_t: float = 0.0
var _panel_open: bool = false
var _revealed: bool = false

func setup(d: ObjectiveDef, s: Dictionary, blurred: bool) -> void:
	def = d
	seed = s
	blurred_is_me = blurred
	match def.kind:
		ObjectiveDef.Kind.LANDLINE:
			_clue = _prop(def.clue_spots[seed.get("clue", 0)], Color(1, 0.95, 0.4), "NOTE")
			_action = _prop(def.action_spot + Vector3.UP * 0.9, Color(0.8, 0.3, 0.3), "PHONE")
		ObjectiveDef.Kind.GARAGE_CODE:
			_clue = _prop(def.clue_spots[seed.get("clue", 0)], Color(1, 0.7, 0.3), "BIRTHDAY")
			_action = _prop(def.action_spot + Vector3.UP * 0.9, Color(0.5, 0.5, 0.9), "KEYPAD")
		ObjectiveDef.Kind.BREAKER:
			_clue = _prop(def.clue_spots[seed.get("clue", 0)], Color(0.9, 0.9, 0.5), "DIAGRAM")
			_action = _prop(def.action_spot + Vector3.UP * 0.6, Color(0.6, 0.4, 0.2), "FUSE BOX")
		ObjectiveDef.Kind.DOG:
			_clue = _prop(def.clue_spots[0], Color(0.9, 0.8, 0.3), "SNACK")
			_dog = _prop(HouseSuburban.DOG_PATH[0] * HouseSuburban.S, Color(0.5, 0.35, 0.2), "DOG (keys!)")
			_dog.position.y = HouseSuburban.DOG_PATH[0].y
		ObjectiveDef.Kind.DEADBOLT:
			_action = _prop(def.action_spot + Vector3.UP * 0.4, Color(0.7, 0.5, 0.3), "DEADBOLT")
		ObjectiveDef.Kind.GLASSES:
			# Only the blurred player needs to find (and can complete) these.
			if blurred_is_me:
				_clue = _prop(def.clue_spots[seed.get("clue", 0)], Color(0.5, 0.9, 1.0), "GLASSES")

func force_done() -> void:
	# Marked done by a solve on another machine — hide the props, stop caring.
	done = true
	if _clue != null: _clue.visible = false
	if _action != null: _action.visible = false
	if _dog != null: _dog.visible = false
	_panel_open = false

# ── Per-frame ──────────────────────────────────────────────────────────────

func update(delta: float, player_pos: Vector3, body_count_near_action: int) -> void:
	if done:
		return
	match def.kind:
		ObjectiveDef.Kind.DOG:
			_update_dog(delta)
		ObjectiveDef.Kind.DEADBOLT:
			# Two bodies at the door + the local player holding E = progress.
			if body_count_near_action >= 2 and _near(def.action_spot, player_pos) \
					and Input.is_key_pressed(KEY_E):
				_hold_t += delta
				if _hold_t >= def.solve_secs:
					_finish()
			else:
				_hold_t = 0.0
		ObjectiveDef.Kind.LANDLINE:
			_tick_rotary(delta, player_pos)

func _update_dog(delta: float) -> void:
	# The dog ambles its loop, navmesh-routed so it walks through DOORWAYS
	# instead of phasing through walls, and barks on a timer (a ping you don't
	# control). Slow — a wandering pet, not a whippet.
	var path := HouseSuburban.DOG_PATH
	var wp: Vector3 = path[_dog_i] * HouseSuburban.S
	wp.y = path[_dog_i].y
	if Vector2(wp.x - _dog.position.x, wp.z - _dog.position.z).length() < 0.6:
		_dog_i = (_dog_i + 1) % path.size()
		_dog_path = PackedVector3Array()  # force a repath to the new waypoint
	if _dog_path.size() - _dog_path_i < 2 or _dog_repath_cd <= 0.0:
		_dog_path = NavigationServer3D.map_get_path(
			get_world_3d().navigation_map, _dog.position, wp, true)
		_dog_path_i = 0
		_dog_repath_cd = 1.0
	_dog_repath_cd -= delta
	while _dog_path_i < _dog_path.size() \
			and Vector2(_dog_path[_dog_path_i].x - _dog.position.x,
				_dog_path[_dog_path_i].z - _dog.position.z).length() < 0.3:
		_dog_path_i += 1
	if _dog_path_i < _dog_path.size():
		var step := _dog_path[_dog_path_i] - _dog.position
		step.y = 0.0
		if step.length() > 0.02:
			_dog.position += step.normalized() * DOG_SPEED * delta
	_entry_t += delta
	if _entry_t >= 4.0:  # bark cadence
		_entry_t = 0.0
		action_noise.emit(_dog.global_position, def.noise_loudness)
		SoundKit.play_at(self, _dog.global_position, "bark")

func _tick_rotary(delta: float, player_pos: Vector3) -> void:
	if _entry_digit == -1:
		return
	if not _near(def.action_spot, player_pos):
		_entry_digit = -1
		return
	_entry_t += delta
	if _entry_t >= DIAL_TIME:
		action_noise.emit(def.action_spot, def.noise_loudness)
		SoundKit.play_at(self, def.action_spot, "click")
		var want := int(String(str(seed.get("code", "0000"))[_entry.length()]))
		if _entry_digit == want:
			_entry += str(_entry_digit)
			if _entry.length() == def.code_len:
				_finish()
		else:
			_entry = ""
			toast.emit("...wrong number. The dial spins back.")
		_entry_digit = -1

# ── Interaction ────────────────────────────────────────────────────────────

func prompt(player_pos: Vector3) -> String:
	if done:
		return ""
	match def.kind:
		ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE, ObjectiveDef.Kind.BREAKER:
			if _clue != null and _near(_clue.position, player_pos):
				return "E: READ CLUE"
			if _action != null and _near(_action.position, player_pos):
				return def.action_prompt
		ObjectiveDef.Kind.DOG:
			if not _has_snack and _near(_clue.position, player_pos):
				return "E: GRAB SNACK"
			if _has_snack and _dog != null and _near(_dog.position, player_pos):
				return "E: GIVE SNACK (get keys)"
		ObjectiveDef.Kind.DEADBOLT:
			if _near(def.action_spot, player_pos):
				return "HOLD E — needs a second player"
		ObjectiveDef.Kind.GLASSES:
			if blurred_is_me and _clue != null and _near(_clue.position, player_pos):
				return "E: GRAB GLASSES"
	return ""

## True when an E press here would GRAB a clue/item (reach into the bag) — the
## cases that go through the slow, loud unzip channel rather than firing instantly.
## Panels, the dog hand-off, and hold-actions are NOT grabs.
func grab_available(player_pos: Vector3) -> bool:
	if done:
		return false
	match def.kind:
		ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE, ObjectiveDef.Kind.BREAKER:
			return not _revealed and _clue != null and _near(_clue.position, player_pos)
		ObjectiveDef.Kind.DOG:
			return not _has_snack and _clue != null and _near(_clue.position, player_pos)
		ObjectiveDef.Kind.GLASSES:
			return blurred_is_me and _clue != null and _near(_clue.position, player_pos)
	return false

## Returns true if this objective grabbed the E press (so Main stops looking).
func try_interact(player_pos: Vector3) -> bool:
	if done:
		return false
	match def.kind:
		ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE, ObjectiveDef.Kind.BREAKER:
			if _clue != null and _near(_clue.position, player_pos):
				toast.emit("%s: %s" % [def.display_name, _clue_text()])
				if not _revealed:
					_revealed = true
					revealed.emit(def.id)  # HUD reveals the action detail everywhere
				return true
			if _action != null and _near(_action.position, player_pos):
				_panel_open = not _panel_open
				_entry = ""
				_entry_digit = -1
				return true
		ObjectiveDef.Kind.DOG:
			if not _has_snack and _near(_clue.position, player_pos):
				_has_snack = true
				_clue.visible = false
				toast.emit("Grabbed the snack. Now find the dog.")
				return true
			if _has_snack and _dog != null and _near(_dog.position, player_pos):
				action_noise.emit(_dog.global_position, def.noise_loudness)
				SoundKit.play_at(self, _dog.global_position, "bark")
				_finish()
				return true
		ObjectiveDef.Kind.GLASSES:
			if blurred_is_me and _clue != null and _near(_clue.position, player_pos):
				_finish()
				return true
	return false

func on_key(digit: int) -> void:
	if done or not _panel_open:
		return
	match def.kind:
		ObjectiveDef.Kind.LANDLINE:
			if _entry_digit == -1:
				_entry_digit = digit  # rotary windup handled in _tick_rotary
				_entry_t = 0.0
		ObjectiveDef.Kind.GARAGE_CODE:
			_entry += str(digit)
			action_noise.emit(def.action_spot, def.noise_loudness)
			SoundKit.play_at(self, def.action_spot, "beep")
			if _entry.length() >= def.code_len:
				if _entry == str(seed.get("code", "")):
					_finish()
				else:
					_entry = ""
					toast.emit("WRONG CODE. *loud beep*")
		ObjectiveDef.Kind.BREAKER:
			if digit < 1 or digit > 3:
				return  # fuses are colours 1-3
			_entry += str(digit)
			action_noise.emit(def.action_spot, def.noise_loudness)
			SoundKit.play_at(self, def.action_spot, "clatter")
			if _entry.length() >= def.code_len:
				if _entry == str(seed.get("code", "")):
					toast.emit("The lights snap ON.")
					_finish()
				else:
					_entry = ""
					toast.emit("The fuses spark and reset.")

func panel_text() -> String:
	if not _panel_open or done:
		return ""
	var shown := ""
	for _c in _entry:
		shown += "* "
	match def.kind:
		ObjectiveDef.Kind.LANDLINE:
			if _entry_digit != -1:
				shown += "%d(%d%%)" % [_entry_digit, int(_entry_t / DIAL_TIME * 100.0)]
			return "OLD ROTARY PHONE — dial the number (keys 0-9)\n[ %s ]" % shown
		ObjectiveDef.Kind.GARAGE_CODE:
			return "GARAGE KEYPAD — enter the code (keys 0-9)\n[ %s ]" % shown
		ObjectiveDef.Kind.BREAKER:
			return "FUSE BOX — set the colour order (keys 1=RED 2=GRN 3=BLU)\n[ %s ]" % shown
	return ""

func panel_open() -> bool:
	return _panel_open and not done

func close_panel() -> void:
	_panel_open = false

# ── Helpers ────────────────────────────────────────────────────────────────

func _clue_text() -> String:
	match def.kind:
		ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE:
			return "the number is  %s" % seed.get("code", "????")
		ObjectiveDef.Kind.BREAKER:
			return "fuse order:  %s" % _colour_order()
	return "?"

func _colour_order() -> String:
	var names := ["", "RED", "GRN", "BLU"]
	var order := ""
	for ch in str(seed.get("code", "")):
		order += names[int(String(ch))] + " "
	return order.strip_edges()

# ── HUD tracker (WHAT + WHETHER; never WHERE) ──────────────────────────────

func set_revealed() -> void:
	_revealed = true  # synced reveal from another player finding the clue

func has_secret() -> bool:
	# Code objectives hide their action detail until a clue is found; the rest
	# have no secret, so the tracker shows their instruction from the start.
	return def.kind in [ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE,
		ObjectiveDef.Kind.BREAKER]

func is_revealed() -> bool:
	return _revealed or not has_secret()

func tracker_state() -> Tracker:
	if done:
		return Tracker.DONE
	match def.kind:
		ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE, ObjectiveDef.Kind.BREAKER:
			return Tracker.IN_PROGRESS if (_revealed or _entry.length() > 0) else Tracker.NOT_STARTED
		ObjectiveDef.Kind.DOG:
			return Tracker.IN_PROGRESS if _has_snack else Tracker.NOT_STARTED
		ObjectiveDef.Kind.DEADBOLT:
			return Tracker.IN_PROGRESS if _hold_t > 0.0 else Tracker.NOT_STARTED
		ObjectiveDef.Kind.GLASSES:
			return Tracker.IN_PROGRESS if blurred_is_me else Tracker.NOT_STARTED
	return Tracker.NOT_STARTED

## Action detail line for the HUD — only meaningful once is_revealed(). Never
## contains a location; it is WHAT to do, discovered by finding the clue.
func tracker_detail() -> String:
	match def.kind:
		ObjectiveDef.Kind.LANDLINE:
			return "dial %s" % _spaced(str(seed.get("code", "")))
		ObjectiveDef.Kind.GARAGE_CODE:
			return "code %s" % _spaced(str(seed.get("code", "")))
		ObjectiveDef.Kind.BREAKER:
			return "fuses %s" % _colour_order()
		ObjectiveDef.Kind.DOG:
			return "lure the dog with the pantry snack"
		ObjectiveDef.Kind.DEADBOLT:
			return "back door — 2 players, hold E"
		ObjectiveDef.Kind.GLASSES:
			return "you're the blurry one — find your glasses" if blurred_is_me \
				else "someone lost their glasses"
	return ""

func _spaced(s: String) -> String:
	var out := ""
	for ch in s:
		out += ch + " "
	return out.strip_edges()

func _finish() -> void:
	if done:
		return
	done = true
	if _clue != null: _clue.visible = false
	if _action != null: _action.visible = false
	if _dog != null: _dog.visible = false
	_panel_open = false
	completed.emit(def.id)

func _near(pos: Vector3, player_pos: Vector3) -> bool:
	return pos.distance_to(player_pos) < NEAR

func _prop(at: Vector3, color: Color, text: String) -> Node3D:
	var prop := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.14)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, mat)
	mesh.position.y = 0.4
	prop.add_child(mesh)
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.9
	prop.add_child(label)
	prop.position = at
	add_child(prop)
	return prop
