extends Node
## Top-level scene manager: MAIN MENU -> LOBBY -> GAME, gray-box UI built in
## code. Owns the flow; the multiplayer peer (SteamManager) and roster
## (LobbyManager) persist across states because we only swap child scenes,
## never change_scene (which would reset the SceneTree multiplayer peer).

const GAME_SCENE := preload("res://games/sleepover/Main.tscn")

enum State { MENU, LOBBY, GAME }

var _state: State = State.MENU
var _is_test: bool = false
var _game: Node = null

# UI roots
var _ui_layer: CanvasLayer
var _menu: Control
var _lobby: Control
var _settings: Control
var _menu_status: Label
var _code_entry: LineEdit
var _roster_box: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _code_label: Label

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_test = args.has("--enet-host") or args.has("--enet-join")

	SteamManager.lobby_ready.connect(_on_lobby_ready)
	SteamManager.lobby_failed.connect(_on_lobby_failed)
	LobbyManager.roster_changed.connect(_refresh_roster)
	LobbyManager.game_started.connect(_on_game_started)

	_build_ui()

	if args.has("--selftest"):
		# Solo deterministic harness: straight into the game, no menu, and let
		# Main._ready drive the selftest itself (don't call begin()).
		_show(State.GAME)
		_game = GAME_SCENE.instantiate()
		add_child(_game)
		return
	_show(State.MENU)

# ── UI construction (gray-box) ─────────────────────────────────────────────

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.08)
	_ui_layer.add_child(bg)

	_menu = _build_menu()
	_ui_layer.add_child(_menu)
	_lobby = _build_lobby()
	_ui_layer.add_child(_lobby)
	_settings = _build_settings()
	_ui_layer.add_child(_settings)

func _build_menu() -> Control:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2(-160, -170)
	root.custom_minimum_size = Vector2(320, 340)
	root.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "SLEEPOVER"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var host_b := _button("HOST GAME", func() -> void: SteamManager.host_lobby())
	root.add_child(host_b)

	_code_entry = LineEdit.new()
	_code_entry.placeholder_text = "6-char code"
	_code_entry.max_length = 6
	_code_entry.custom_minimum_size = Vector2(0, 34)
	root.add_child(_code_entry)
	root.add_child(_button("JOIN GAME", func() -> void:
		var code := _code_entry.text.strip_edges()
		if code.length() == 6:
			SteamManager.join_by_code(code)
		else:
			_menu_status.text = "enter the 6-character code first"))

	root.add_child(_button("SETTINGS", func() -> void: _settings.visible = true))
	root.add_child(_button("QUIT", func() -> void: get_tree().quit()))

	_menu_status = Label.new()
	_menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_status.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	root.add_child(_menu_status)
	return root

func _build_lobby() -> Control:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2(-220, -210)
	root.custom_minimum_size = Vector2(440, 420)
	root.add_theme_constant_override("separation", 10)
	root.visible = false

	var title := Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	root.add_child(_code_label)

	var players_head := Label.new()
	players_head.text = "PLAYERS"
	root.add_child(players_head)
	_roster_box = VBoxContainer.new()
	_roster_box.custom_minimum_size = Vector2(0, 180)
	root.add_child(_roster_box)

	# Host-only stub controls (wired later).
	var host_row := HBoxContainer.new()
	host_row.add_child(_stub_option("Map", ["Maple St. House"]))
	host_row.add_child(_stub_option("Monster", ["AI", "Secret Player"]))
	host_row.add_child(_stub_option("House Rules", ["None", "Blackout", "Sugar High"]))
	root.add_child(host_row)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	_ready_btn = _button("READY", func() -> void: LobbyManager.toggle_ready())
	btns.add_child(_ready_btn)
	_start_btn = _button("START", func() -> void: LobbyManager.start_game())
	btns.add_child(_start_btn)
	btns.add_child(_button("INVITE", func() -> void: SteamManager.invite_overlay()))
	btns.add_child(_button("LEAVE", func() -> void: _leave_to_menu()))
	root.add_child(btns)
	return root

func _build_settings() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-190, -160)
	panel.custom_minimum_size = Vector2(380, 320)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var t := Label.new()
	t.text = "SETTINGS"
	t.add_theme_font_size_override("font_size", 28)
	box.add_child(t)

	# Master volume — real (wired to the master bus).
	box.add_child(_label("Master volume"))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	vol.custom_minimum_size = Vector2(320, 0)
	vol.value_changed.connect(func(v: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001))))
	box.add_child(vol)

	# Mouse sensitivity — stub value stored globally for the game to read later.
	box.add_child(_label("Mouse sensitivity  (stub)"))
	var sens := HSlider.new()
	sens.min_value = 0.001
	sens.max_value = 0.01
	sens.step = 0.0005
	sens.value = 0.004
	sens.custom_minimum_size = Vector2(320, 0)
	box.add_child(sens)

	# Mic device — real device list, selection is a stub for now.
	box.add_child(_label("Microphone device  (stub)"))
	var mic := OptionButton.new()
	for dev: String in AudioServer.get_input_device_list():
		mic.add_item(dev)
	if mic.item_count == 0:
		mic.add_item("Default")
	box.add_child(mic)

	box.add_child(_label("Key rebinds — coming soon"))
	box.add_child(_button("BACK", func() -> void: _settings.visible = false))
	return panel

# ── Flow ───────────────────────────────────────────────────────────────────

func _show(s: State) -> void:
	_state = s
	# The whole UI layer (incl. its opaque background) hides in-game so the 3D
	# world is visible; the game draws its own HUD on its own CanvasLayer.
	_ui_layer.visible = s != State.GAME
	_menu.visible = s == State.MENU
	_lobby.visible = s == State.LOBBY
	if s != State.MENU:
		_settings.visible = false

func _on_lobby_ready(_lobby_id: int, is_host: bool) -> void:
	LobbyManager.enter_lobby(SteamManager.persona())
	_code_label.text = "JOIN CODE:  %s        (you are %s)" % [
		SteamManager.join_code, "HOST" if is_host else "CLIENT"]
	_show(State.LOBBY)
	if _is_test:
		# Auto-ready; the host auto-starts once everyone is ready (see _refresh).
		LobbyManager.set_ready(true)

func _on_lobby_failed(reason: String) -> void:
	_menu_status.text = reason
	_show(State.MENU)

func _refresh_roster() -> void:
	if _state != State.LOBBY:
		return
	for c in _roster_box.get_children():
		c.queue_free()
	for pid: int in LobbyManager.players:
		var p: Dictionary = LobbyManager.players[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(26, 20)
		swatch.color = BagVisual.SKINS[int(p.get("skin", 0)) % BagVisual.SKINS.size()]["base"]
		row.add_child(swatch)
		var name_l := Label.new()
		var tag := "  (HOST)" if pid == 1 else ""
		if p.get("spectator", false):
			tag += "  (spectating)"
		name_l.text = str(p.get("name", "?")) + tag
		row.add_child(name_l)
		var ready_l := Label.new()
		ready_l.text = "   ✓ READY" if p.get("ready", false) else "   …"
		ready_l.add_theme_color_override("font_color",
			Color(0.4, 1, 0.5) if p.get("ready", false) else Color(0.7, 0.7, 0.7))
		row.add_child(ready_l)
		_roster_box.add_child(row)

	_ready_btn.text = "UNREADY" if LobbyManager.my_ready() else "READY"
	var is_host := SteamManager.is_host
	_start_btn.disabled = not (is_host and LobbyManager.can_start())
	_start_btn.visible = is_host

	# Test mode: host auto-starts once BOTH loopback instances are readied in
	# (the harness is always 2 processes; real solo play uses the START button).
	if _is_test and is_host and not LobbyManager.started \
			and LobbyManager.players.size() >= 2 and LobbyManager.can_start():
		LobbyManager.start_game()

func _on_game_started() -> void:
	_load_game(SteamManager.is_host)

func _load_game(is_host: bool) -> void:
	_show(State.GAME)
	_menu.visible = false
	_lobby.visible = false
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	if _game.has_method("begin"):
		_game.begin(is_host, _is_test, LobbyManager.players.get(_my_id_safe(), {}).get("spectator", false))

func _leave_to_menu() -> void:
	SteamManager.leave_lobby()
	LobbyManager.leave()
	_show(State.MENU)

func _my_id_safe() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

# ── UI helpers ─────────────────────────────────────────────────────────────

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(cb)
	return b

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _stub_option(prefix: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it: String in items:
		o.add_item("%s: %s" % [prefix, it])
	o.disabled = not SteamManager.is_host  # host-only (still a stub)
	return o
