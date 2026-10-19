extends Node
## Top-level scene manager: MAIN MENU -> LOBBY -> GAME, gray-box UI built in
## code. Owns the flow; the multiplayer peer (SteamManager) and roster
## (LobbyManager) persist across states because we only swap child scenes,
## never change_scene (which would reset the SceneTree multiplayer peer).

const GAME_SCENE := preload("res://games/sleepover/Main.tscn")
const MENU_BACKDROP := preload("res://core/ui/MenuBackdrop.gd")

enum State { MENU, LOBBY, GAME }

var _state: State = State.MENU
var _is_test: bool = false
var _game: Node = null

# UI roots
var _ui_layer: CanvasLayer
var _menu: Control
var _lobby: Control
var _settings: Control
var _pause: Control
var _menu_bg: ColorRect
var _menu_status: Label
var _code_entry: LineEdit
var _roster_box: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _code_label: Label
var _scrapbook: Control
var _scrapbook_content: VBoxContainer
var _scrapbook_count: Label
var _skin_row: HBoxContainer
var _how_to: Control
var _credits: Control
var _backdrop: Control
var _menu_audio: AudioStreamPlayer
var _sound_preview: AudioStreamPlayer
var _last_focus_sound: int = -1000

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_test = args.has("--enet-host") or args.has("--enet-join")

	SteamManager.lobby_ready.connect(_on_lobby_ready)
	SteamManager.lobby_failed.connect(_on_lobby_failed)
	LobbyManager.roster_changed.connect(_refresh_roster)
	LobbyManager.game_started.connect(_on_game_started)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	_build_ui()

	if args.has("--selftest"):
		# Smoke-test the dynamic Scrapbook UI build (labels + skin swatches) so a
		# refresh-time error surfaces in the harness, then hand off to the game.
		_refresh_scrapbook()
		print("[SELFTEST] scrapbook UI: built %d rows, %d skins" % [
			_scrapbook_content.get_child_count(), _skin_row.get_child_count()])
		# Solo deterministic harness: straight into the game, no menu, and let
		# Main._ready drive the selftest itself (don't call begin()).
		_show(State.GAME)
		_game = GAME_SCENE.instantiate()
		add_child(_game)
		return
	_show(State.MENU)

# ── UI construction (gray-box) ─────────────────────────────────────────────

func _build_ui() -> void:
	_menu_audio = AudioStreamPlayer.new()
	_menu_audio.bus = SoundKit.EFFECTS_BUS
	_menu_audio.max_polyphony = 2
	add_child(_menu_audio)
	_sound_preview = AudioStreamPlayer.new()
	_sound_preview.bus = SoundKit.EFFECTS_BUS
	add_child(_sound_preview)
	_ui_layer = CanvasLayer.new()
	# Above the game's own HUD layer, which is added later and would otherwise
	# draw on top of the pause menu.
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# The opaque background is what used to force hiding this ENTIRE layer in
	# GAME — which is why there could be no pause menu. Only the background is
	# state-dependent now; the layer itself stays up so panels can overlay the
	# live 3D world.
	_menu_bg = ColorRect.new()
	_menu_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_bg.color = Color(0.05, 0.05, 0.08)
	_ui_layer.add_child(_menu_bg)
	_backdrop = MENU_BACKDROP.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_backdrop)

	_menu = _build_menu()
	_ui_layer.add_child(_menu)
	_lobby = _build_lobby()
	_ui_layer.add_child(_lobby)
	_settings = _build_settings()
	_settings.visibility_changed.connect(func() -> void:
		if not _settings.visible: _sound_preview.stop())
	_settings.z_index = 20  # settings must cover the pause panel as well as the menu
	_ui_layer.add_child(_settings)
	_pause = _build_pause()
	_ui_layer.add_child(_pause)
	_scrapbook = _build_scrapbook()
	_ui_layer.add_child(_scrapbook)
	_how_to = _build_how_to()
	_ui_layer.add_child(_how_to)
	_credits = _build_credits()
	_ui_layer.add_child(_credits)
	Scrapbook.changed.connect(func() -> void:
		if _scrapbook.visible:
			_refresh_scrapbook())

func _build_menu() -> Control:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	root.position = Vector2(64, -280)
	root.custom_minimum_size = Vector2(340, 460)
	root.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "SLEEPOVER"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("eedfc3"))
	root.add_child(title)
	var invitation := _label("BRING A SLEEPING BAG.\nDON'T WAKE THE HOUSESITTER.")
	invitation.add_theme_color_override("font_color", Color("c3ad8b"))
	root.add_child(invitation)

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

	root.add_child(_button("SCRAPBOOK", func() -> void: _open_scrapbook()))
	root.add_child(_button("HOW TO PLAY", func() -> void: _how_to.visible = true))
	var extras := HBoxContainer.new()
	for entry: String in ["SETTINGS", "CREDITS"]:
		var button := _button(entry, func() -> void:
			if entry == "SETTINGS": _settings.visible = true
			else: _credits.visible = true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		extras.add_child(button)
	root.add_child(extras)
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

	root.add_child(_label("MAPLE ST. HOUSE  /  THE HOUSESITTER\nFinish any 3 tasks, then reach an unlocked exit.\nOr stay alive until sunrise. Stay close enough to help."))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	_ready_btn = _button("READY", func() -> void: LobbyManager.toggle_ready())
	btns.add_child(_ready_btn)
	_start_btn = _button("START", func() -> void: LobbyManager.start_game())
	btns.add_child(_start_btn)
	btns.add_child(_button("INVITE", func() -> void: SteamManager.invite_overlay()))
	btns.add_child(_button("LEAVE", func() -> void: _leave_to_menu()))
	root.add_child(btns)
	root.add_child(_button("SCRAPBOOK / SKINS", func() -> void: _open_scrapbook()))
	# Voice/mic settings belong here too — the lobby is where you sort your mic out
	# before a round, not the main menu you already walked past.
	root.add_child(_button("SETTINGS", func() -> void: _settings.visible = true))
	root.add_child(_button("HOW TO PLAY", func() -> void: _how_to.visible = true))
	return root

func _build_how_to() -> Control:
	var root := PanelContainer.new()
	_style_reading_panel(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	var title := _label("THE SLEEPOVER RULES")
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var rules := _label("GET HOME\nComplete any 3 of the 5 tasks to enable escape. A door also needs its own task completed. The back door needs the house keys turned in its lock. Survive until sunrise for another way to win.\n\nMOVE QUIETLY\nWASD shuffles. Space hops: faster, louder, and costs one stamina pip. Hopping empty makes you fall. Mash WASD to wriggle upright; rest on the ground to recover stamina.\n\nLOOK AND INTERACT\nMouse looks around. C switches camera. Hold E at clues and items to unzip and grab them. Follow the nearby prompt at tasks. Number keys enter codes when a keypad is open.\n\nPACK LIGHT\nYou have two inventory slots. Press 1 or 2 to use an item. A thrown can makes noise when it lands; a party popper buys a short chance to run. Getting caught spills your items for a friend to recover.\n\nTRADE WITH THE DOG\nFind the beef jerky and hold E to pick it up. Carry it to the dog, then press E or its inventory number to trade it for the keys. Carry the keys to the back door and press their number to turn the lock. Using jerky or keys away from their destination sets them down for a teammate.\n\nDON'T LEAVE A FRIEND\nHold E beside a cocooned friend to rescue them. The zipper is loud. If you are caught, F toggles spectating and [ / ] changes teammate. Everyone caught ends the night.\n\nTALK / TAKE A BREAK\nHold V to talk. M toggles open mic. Escape opens the menu, but the house keeps moving. Finishing a night opens the recap; the host can choose One More Night.")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rules)
	box.add_child(_button("GOT IT", func() -> void: _how_to.visible = false))
	return root

func _build_credits() -> Control:
	var root := PanelContainer.new()
	_style_reading_panel(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	var heading := _label("THANKS FOR STAYING OVER")
	heading.add_theme_font_size_override("font_size", 32)
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var credits := _label("SOUND RECORDINGS\n\nKenney — Impact Sounds, Interface Sounds, RPG Audio\nCloth, creaks, impacts, page turns and menu sounds.\nkenney.nl\n\nAntumDeluge — Zipper\nopengameart.org/content/zipper\n\nmikeask — Breathing Tired\nopengameart.org/content/breathing-tired\n\nBrandon Morris (HaelDB) — Dog barking mono\nopengameart.org/content/dog-barking-mono\n\nThese sound assets are released under Creative Commons Zero (CC0).\ncreativecommons.org/publicdomain/zero/1.0/\n\nBUILT WITH\nGodot Engine and GodotSteam\n\ngodotengine.org  /  godotsteam.com")
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(credits)
	box.add_child(_button("BACK", func() -> void: _credits.visible = false))
	return root

func _style_reading_panel(panel: PanelContainer) -> void:
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("1b2229")
	paper.border_color = Color("9d8060")
	paper.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", paper)
	panel.add_theme_color_override("font_color", Color("eedfc3"))

func _build_settings() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.04, 0.85)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	_style_reading_panel(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240, -285)
	panel.custom_minimum_size = Vector2(480, 570)
	overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var settings_layout := VBoxContainer.new()
	settings_layout.add_theme_constant_override("separation", 12)
	margin.add_child(settings_layout)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_layout.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

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
	vol.value = Scrapbook.master_volume
	_apply_audio_mix()
	vol.custom_minimum_size = Vector2(320, 0)
	vol.value_changed.connect(func(v: float) -> void:
		Scrapbook.master_volume = v
		_apply_audio_mix())
	box.add_child(vol)
	for setting: String in ["effects_volume", "voice_volume"]:
		box.add_child(_label("Sound effects" if setting == "effects_volume" else "Voice volume (incoming)"))
		var slider := HSlider.new()
		slider.name = setting
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = Scrapbook.get(setting)
		slider.custom_minimum_size = Vector2(320, 0)
		var preference := setting
		slider.value_changed.connect(func(v: float) -> void:
			Scrapbook.set(preference, v)
			_apply_audio_mix())
		box.add_child(slider)

	box.add_child(_label("Mouse sensitivity"))
	var sens := HSlider.new()
	sens.min_value = 0.001
	sens.max_value = 0.01
	sens.step = 0.0005
	sens.value = Scrapbook.mouse_sensitivity
	sens.custom_minimum_size = Vector2(320, 0)
	sens.value_changed.connect(func(v: float) -> void:
		Scrapbook.mouse_sensitivity = v
		if is_instance_valid(_game):
			_game.mouse_sensitivity = v)
	box.add_child(sens)

	# Voice chat — Steam voice API captures from the SYSTEM DEFAULT input device
	# (the Steam API has no per-device selection), so no misleading dropdown.
	box.add_child(_label("Voice chat — system default microphone"))
	var voice_on := CheckButton.new()
	voice_on.text = "Voice chat enabled"
	voice_on.button_pressed = VoiceManager.enabled
	voice_on.toggled.connect(func(v: bool) -> void: VoiceManager.set_enabled(v))
	box.add_child(voice_on)
	var open_mic := CheckButton.new()
	open_mic.text = "Open mic  (off = push-to-talk V)"
	open_mic.button_pressed = VoiceManager.open_mic
	open_mic.toggled.connect(func(v: bool) -> void: VoiceManager.set_open_mic(v))
	box.add_child(open_mic)
	# In-game M flips this too — keep the box honest if it changed elsewhere.
	VoiceManager.mic_mode_changed.connect(func(v: bool) -> void:
		open_mic.set_pressed_no_signal(v)
		voice_on.set_pressed_no_signal(VoiceManager.enabled))

	box.add_child(_label("Sound check"))
	var sound_row := HBoxContainer.new()
	var sound_choice := OptionButton.new()
	var sound_kinds := ["shuffle", "zipper", "breath", "creak", "can_land", "page", "bark"]
	for title: String in ["Bag shuffle", "Zipper", "Breathing", "House creak", "Can impact", "Page turn", "Dog bark"]:
		sound_choice.add_item(title)
	sound_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_row.add_child(sound_choice)
	sound_row.add_child(_button("PLAY", func() -> void: _preview_sound(sound_kinds[sound_choice.selected])))
	sound_row.add_child(_button("STOP", func() -> void: _sound_preview.stop()))
	box.add_child(sound_row)
	settings_layout.add_child(_button("BACK", func() -> void:
		Scrapbook.save_game()
		_settings.visible = false))
	return overlay

func _preview_sound(kind: String) -> void:
	_sound_preview.stop()
	_sound_preview.stream = SoundKit.get_stream(kind)
	_sound_preview.bus = "InBag" if kind == "breath" else SoundKit.EFFECTS_BUS
	_sound_preview.volume_db = -12.0 if kind == "breath" else -18.0
	_sound_preview.pitch_scale = 0.85 if kind == "shuffle" else 1.0
	_sound_preview.play()

func _apply_audio_mix() -> void:
	SoundKit.apply_mix(Scrapbook.master_volume, Scrapbook.effects_volume, Scrapbook.voice_volume)

# ── Pause ──────────────────────────────────────────────────────────────────

## Esc in-game. NOTE: this does NOT pause the tree. It's a co-op game — the
## Housesitter keeps hunting and your friends keep playing while you read this,
## so the panel says so out loud rather than implying a safety that isn't there.
func _build_pause() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false

	# A dim, not a blackout: you can still see the room you're standing in.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.03, 0.72)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-150, -140)
	panel.custom_minimum_size = Vector2(300, 280)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var t := Label.new()
	t.text = "PAUSED"
	t.add_theme_font_size_override("font_size", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)

	var warn := _label("(the house doesn't stop)")
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_color_override("font_color", Color(0.85, 0.6, 0.6))
	box.add_child(warn)

	box.add_child(_button("RESUME", func() -> void: _set_paused(false)))
	box.add_child(_button("SETTINGS", func() -> void: _settings.visible = true))
	box.add_child(_button("LEAVE GAME", func() -> void: _leave_to_menu()))
	return root

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _credits.visible:
		_credits.visible = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _settings.visible:
		Scrapbook.save_game()
		_settings.visible = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _how_to.visible:
		_how_to.visible = false
		get_viewport().set_input_as_handled()
		return
	if _state != State.GAME:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		# Handled HERE, not in Main: consume it so the game below never sees it.
		# Settings sits on top of pause, so Esc backs out of that first.
		if _settings.visible:
			Scrapbook.save_game()
			_settings.visible = false
		else:
			_set_paused(not _pause.visible)
		get_viewport().set_input_as_handled()

func _set_paused(on: bool) -> void:
	if not on and _settings.visible:
		Scrapbook.save_game()
	_pause.visible = on
	if not on:
		_settings.visible = false
	# Releasing the mouse IS the pause, as far as the player is concerned.
	if is_instance_valid(_game):
		_game.set_menu_open(on)
	var results: bool = is_instance_valid(_game) and _game.phase == _game.Phase.RESULTS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on or results else Input.MOUSE_MODE_CAPTURED

# ── The Scrapbook (lore + cosmetic unlocks) ────────────────────────────────

func _build_scrapbook() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "THE SCRAPBOOK"
	title.add_theme_font_size_override("font_size", 36)
	outer.add_child(title)
	_scrapbook_count = Label.new()
	_scrapbook_count.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	outer.add_child(_scrapbook_count)

	# The fragments, page by page — scrolls.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_scrapbook_content = VBoxContainer.new()
	_scrapbook_content.add_theme_constant_override("separation", 6)
	_scrapbook_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_scrapbook_content)

	# Cosmetics — the bag skins, unlocked by filling pages.
	outer.add_child(_label("BAG SKINS  (fill a page to unlock)"))
	_skin_row = HBoxContainer.new()
	_skin_row.add_theme_constant_override("separation", 6)
	outer.add_child(_skin_row)

	outer.add_child(_button("BACK", func() -> void: _scrapbook.visible = false))
	return panel

func _open_scrapbook() -> void:
	if _settings.visible:
		Scrapbook.save_game()
	_settings.visible = false
	_refresh_scrapbook()
	_scrapbook.visible = true

func _refresh_scrapbook() -> void:
	_scrapbook_count.text = "Collected  %d / %d fragments" % [
		Scrapbook.collected_count(), LoreFragments.count()]
	for c in _scrapbook_content.get_children():
		c.queue_free()
	var pages: Array = LoreFragments.PAGES
	for i in pages.size():
		var page: Dictionary = pages[i]
		var done := Scrapbook.page_complete(i)
		var skin_name: String = BagVisual.SKINS[int(page["unlocks_skin"]) % BagVisual.SKINS.size()]["name"]
		var head := Label.new()
		head.text = "\n📖 %s   —   %s %s" % [page["title"],
			("UNLOCKED: " + skin_name) if done else ("locked skin: " + skin_name),
			"✓" if done else ""]
		head.add_theme_font_size_override("font_size", 22)
		head.add_theme_color_override("font_color",
			Color(0.6, 1.0, 0.6) if done else Color(0.85, 0.85, 0.85))
		_scrapbook_content.add_child(head)
		for fid: String in page["fragments"]:
			_scrapbook_content.add_child(_fragment_entry(fid))
	_refresh_skins()

func _fragment_entry(fid: String) -> Control:
	var box := VBoxContainer.new()
	var frag: Dictionary = LoreFragments.by_id(fid)
	if Scrapbook.has(fid):
		var t := Label.new()
		t.text = "  ✦ %s  [%s]" % [frag.get("title", fid), str(frag.get("type", "")).to_upper()]
		t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		box.add_child(t)
		var b := Label.new()
		b.text = "     " + str(frag.get("body", "")).replace("\n", "\n     ")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(640, 0)
		b.add_theme_color_override("font_color", Color(0.82, 0.82, 0.8))
		box.add_child(b)
	else:
		var t := Label.new()
		t.text = "  ✦ ??? — not yet found"
		t.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		box.add_child(t)
	return box

func _refresh_skins() -> void:
	for c in _skin_row.get_children():
		c.queue_free()
	for i in BagVisual.SKINS.size():
		var unlocked := Scrapbook.is_skin_unlocked(i)
		var b := Button.new()
		b.custom_minimum_size = Vector2(80, 54)
		var col: Color = BagVisual.SKINS[i]["base"]
		b.modulate = col if unlocked else col.darkened(0.6)
		b.disabled = not unlocked
		var mark := "◉ " if i == Scrapbook.selected_skin else ""
		b.text = "%s%s" % [mark, BagVisual.SKINS[i]["name"] if unlocked else "LOCKED"]
		if unlocked:
			var idx := i
			b.pressed.connect(func() -> void:
				Scrapbook.set_selected_skin(idx)
				_refresh_skins()
				_refresh_roster())
		_skin_row.add_child(b)

# ── Flow ───────────────────────────────────────────────────────────────────

func _show(s: State) -> void:
	if s == State.GAME and _settings and _settings.visible:
		Scrapbook.save_game()
	_state = s
	# Only the opaque BACKGROUND is state-dependent — the layer itself stays up so
	# the pause menu can overlay the live 3D world. The game draws its HUD on its
	# own CanvasLayer, below this one.
	_menu_bg.visible = s != State.GAME
	_backdrop.visible = s == State.MENU
	if _how_to:
		_how_to.visible = false
	if _credits:
		_credits.visible = false
	_menu.visible = s == State.MENU
	_lobby.visible = s == State.LOBBY
	# Settings is available from the menu AND the lobby (mic setup happens there).
	if s == State.GAME:
		_settings.visible = false
	if s == State.GAME and _scrapbook:
		_scrapbook.visible = false
	if s != State.GAME and _pause:
		_pause.visible = false

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
	_game.mouse_sensitivity = Scrapbook.mouse_sensitivity
	_game.leave_requested.connect(_leave_to_menu)
	add_child(_game)
	if _game.has_method("begin"):
		_game.begin(is_host, _is_test, LobbyManager.players.get(_my_id_safe(), {}).get("spectator", false))

## The single way out of a round — used by the pause menu, by the recap, and by a
## host quitting out from under us. Tears the game scene down before dropping the
## peer so nothing is left running against a dead connection.
func _leave_to_menu() -> void:
	if _settings.visible:
		Scrapbook.save_game()
	if _game != null:
		_game.queue_free()
		_game = null
	if _pause:
		_pause.visible = false
	_settings.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SteamManager.leave_lobby()
	LobbyManager.leave()
	_show(State.MENU)

## Host quit / crashed / lost connection. v1 has no host migration (launch plan),
## so the round is simply over — but it must END, not strand everyone in a world
## that has stopped updating.
func _on_server_disconnected() -> void:
	print("[NETTEST] server disconnected — returning to menu")
	_leave_to_menu()
	_menu_status.text = "the host left — everyone went home."

func _on_connection_failed() -> void:
	_leave_to_menu()
	_menu_status.text = "Couldn't reach the host. Check the invitation or try joining again."

func _my_id_safe() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

# ── UI helpers ─────────────────────────────────────────────────────────────

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("252e36")
	normal.border_color = Color("665d51")
	normal.set_border_width_all(1)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("eedfc3")
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("c99b52")
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", Color("eedfc3"))
	b.add_theme_color_override("font_hover_color", Color("252e36"))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			_play_menu_sound("ui_focus"))
	b.focus_entered.connect(func() -> void: _play_menu_sound("ui_focus"))
	b.pressed.connect(func() -> void: _play_menu_sound("ui_click"))
	b.pressed.connect(cb)
	return b

func _play_menu_sound(kind: String) -> void:
	if kind == "ui_focus":
		var now := Time.get_ticks_msec()
		if now - _last_focus_sound < 90:
			return
		_last_focus_sound = now
	_menu_audio.stream = SoundKit.get_stream(kind)
	_menu_audio.volume_db = -22.0 if kind == "ui_focus" else -14.0
	_menu_audio.play()

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
