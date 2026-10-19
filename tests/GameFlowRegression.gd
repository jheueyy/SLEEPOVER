extends Node

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
	print("[FLOW] %s: %s" % [label, condition])

func _ready() -> void:
	Scrapbook.use_test_path("user://flow_regression.save")
	var app := preload("res://core/ui/AppRoot.tscn").instantiate()
	add_child(app)
	if OS.get_cmdline_user_args().has("--capture-menu") or OS.get_cmdline_user_args().has("--capture-settings") or OS.get_cmdline_user_args().has("--capture-credits"):
		var settings := OS.get_cmdline_user_args().has("--capture-settings")
		app._settings.visible = settings
		var credits := OS.get_cmdline_user_args().has("--capture-credits")
		app._credits.visible = credits
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var output := "res://tests/credits-preview.png" if credits else ("res://tests/settings-preview.png" if settings else "res://tests/menu-preview.png")
		var result := get_viewport().get_texture().get_image().save_png(output)
		get_tree().quit(result)
		return
	check(app._menu.visible and not app._how_to.visible, "title screen is the entry point")
	app._how_to.visible = true
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app._input(escape)
	check(not app._how_to.visible, "rules close with Escape from menu")
	app._credits.visible = true
	app._input(escape)
	check(not app._credits.visible and app._menu.visible, "credits close back to menu with Escape")
	app._settings.visible = true
	app._preview_sound("zipper")
	check(app._sound_preview.stream is AudioStreamOggVorbis, "sound check plays recorded zipper")
	check(app._settings.z_index > app._pause.z_index, "settings overlays pause controls")
	var effects: HSlider = app._settings.find_child("effects_volume", true, false)
	var voice: HSlider = app._settings.find_child("voice_volume", true, false)
	effects.value = 0.0
	voice.value = 0.6
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))
		and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice"))), 0.6), "settings sliders apply independent live mix")
	app._input(escape)
	check(not app._sound_preview.playing, "closing settings stops sound check")
	Scrapbook.effects_volume = 1.0
	Scrapbook.voice_volume = 1.0
	Scrapbook.load_game()
	check(not app._settings.visible and is_zero_approx(Scrapbook.effects_volume)
		and is_equal_approx(Scrapbook.voice_volume, 0.6), "Escape closes settings and persists mix")
	SteamManager.is_host = true
	LobbyManager.enter_lobby("Flow tester")
	app._load_game(true)
	var game: Node = app._game
	game._apply_phase(game.Phase.ROUND, {})
	if OS.get_cmdline_user_args().has("--capture-game"):
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var capture_result := get_viewport().get_texture().get_image().save_png("res://tests/gameplay-preview.png")
		get_tree().quit(capture_result)
		return
	var dog_test := Objective.new()
	game.add_child(dog_test)
	dog_test.setup(ObjectiveDef._dog(), {}, false)
	dog_test.update(0.1, Vector3.ZERO, 0, false)
	dog_test.update(0.1, Vector3.ZERO, 0, false)
	check(is_equal_approx(dog_test._dog_bark_t, 0.2), "dog bark timer continues when interaction is blocked")
	var dog_position: Vector3 = dog_test._dog.global_position
	dog_test.update(1.0, Vector3.ZERO, 0, false, false)
	check(is_equal_approx(dog_test._dog_bark_t, 0.2) and dog_test._dog.global_position == dog_position,
		"client dog does not simulate independent movement or bark cadence")
	dog_test.queue_free()
	var noise_before_bark: float = game._stat(game._my_id()).get("noise_total", 0.0)
	var bark_events := [0]
	var count_bark := func(_at: Vector3, _volume: float) -> void: bark_events[0] += 1
	NoiseBus.noise_emitted.connect(count_bark)
	game._on_dog_barked(game._player.global_position)
	NoiseBus.noise_emitted.disconnect(count_bark)
	check(bark_events[0] == 1 and is_equal_approx(game._stat(game._my_id()).get("noise_total", 0.0), noise_before_bark),
		"ambient dog bark alerts the house without charging host noise score")
	game._net_monster_footstep()
	check(game._monster._creak.stream is AudioStreamOggVorbis, "remote monster footstep plays licensed sample")
	game._spawn_remote_bag(9877)
	var fragment: Fragment = game._fragments[0]
	game._authoritative_collect_fragment("unknown-fragment", 9877)
	game._authoritative_collect_fragment(fragment.id(), 9999)
	game._remote_bags[9877].global_position = fragment.global_position + Vector3(100, 0, 0)
	game._authoritative_collect_fragment(fragment.id(), 9877)
	check(not fragment.collected and not game._frag_collected_ids.has("unknown-fragment"),
		"unknown and distant fragment claims rejected")
	game._remote_bags[9877].global_position = fragment.global_position - Vector3.UP * 0.2
	game._authoritative_collect_fragment(fragment.id(), 9877)
	check(not fragment.collected, "fragment perch cannot be collected from below")
	game._remote_bags[9877].global_position = fragment.global_position + Vector3.UP * 0.2
	game._remote_bags[9877].set_meta("cocooned", true)
	game._authoritative_collect_fragment(fragment.id(), 9877)
	check(not fragment.collected, "captured peer cannot collect lore")
	game._remote_bags[9877].set_meta("cocooned", false)
	game._authoritative_collect_fragment(fragment.id(), 9877)
	game._authoritative_collect_fragment(fragment.id(), 9877)
	check(fragment.collected and int(game._stat(9877).get("fragments", 0)) == 1,
		"valid lore pickup credited once")
	var before_keys_position: Vector3 = game._player.global_position
	game._inv[0] = Item.Kind.KEYS
	game._inv[1] = -1
	game._keys_door_open = false
	game._authoritative_keys_turned(9999)
	game._player.global_position = Vector3(100, 100, 100)
	game._authoritative_keys_turned(game._my_id())
	check(not game._keys_door_open and game._inv_has(Item.Kind.KEYS),
		"invalid key turn preserves keys and keeps door locked")
	for exit_def: Dictionary in HouseSuburban.exits():
		if exit_def["name"] == "BACK DOOR":
			game._player.global_position = exit_def["at"]
	game._remote_bags[9877].global_position = game._player.global_position
	game._remote_bags[9877].set_meta("cocooned", true)
	game._authoritative_keys_turned(9877)
	check(not game._keys_door_open, "captured peer cannot turn keys")
	game._remote_bags[9877].set_meta("cocooned", false)
	game._use_slot(-1)
	game._use_slot(2)
	check(game._inv_has(Item.Kind.KEYS), "invalid inventory slots are ignored")
	game._use_slot(0)
	check(game._keys_door_open and not game._inv_has(Item.Kind.KEYS),
		"confirmed key turn opens door and consumes keys")
	game._keys_door_open = false
	game._authoritative_keys_turned(game._my_id())
	check(not game._keys_door_open, "local player without keys cannot unlock door")
	game._player.global_position = before_keys_position
	game._refresh_exit_doors()
	check(not game._receive_remote_noise(9999, Vector3.ZERO, 1.0)
		and not game._receive_remote_noise(9877, Vector3.INF, 1.0)
		and not game._receive_remote_noise(9877, Vector3.ZERO, INF), "invalid noise reports rejected")
	var host_noise: float = game._stat(game._my_id()).get("noise_total", 0.0)
	var remote_noise: float = game._stat(9877).get("noise_total", 0.0)
	game._receive_remote_noise(9877, game._player.global_position, 0.5)
	check(is_equal_approx(game._stat(game._my_id()).get("noise_total", 0.0), host_noise)
		and is_equal_approx(game._stat(9877).get("noise_total", 0.0), remote_noise + 0.5), "remote noise credited only to its sender")
	var pickup: Item = game._items[0]
	game._authoritative_take_item(pickup.uid, 9999)
	check(not pickup.taken, "unknown peer cannot take item")
	game._remote_bags[9877].global_position = pickup.global_position + Vector3(100, 0, 0)
	game._authoritative_take_item(pickup.uid, 9877)
	check(not pickup.taken, "distant peer cannot take item")
	game._remote_bags[9877].global_position = pickup.global_position
	game._remote_bags[9877].set_meta("cocooned", true)
	game._authoritative_take_item(pickup.uid, 9877)
	check(not pickup.taken, "captured peer cannot take item")
	game._remote_bags[9877].set_meta("cocooned", false)
	game._authoritative_take_item(pickup.uid, 9877)
	check(pickup.taken, "nearby living peer can take item")
	game._authoritative_complete("not-a-task")
	check(not game._done_ids.has("not-a-task"), "unknown objective cannot advance escape")
	check(not game._can_report_objective(9999, game._objectives[0].def.id), "unknown peer cannot report task")
	game._remote_bags[9877].global_position = Vector3(100, 100, 100)
	check(not game._can_report_objective(9877, game._objectives[0].def.id), "distant peer cannot report task")
	for task: Objective in game._objectives:
		if task.def.kind in [ObjectiveDef.Kind.LANDLINE, ObjectiveDef.Kind.GARAGE_CODE, ObjectiveDef.Kind.BREAKER]:
			game._remote_bags[9877].global_position = task.def.action_spot
			check(game._can_report_objective(9877, task.def.id), "nearby live peer can report task")
			game._remote_bags[9877].set_meta("cocooned", true)
			check(not game._can_report_objective(9877, task.def.id), "captured peer cannot report task")
			game._remote_bags[9877].set_meta("cocooned", false)
			break
	game._remote_bags[9877].global_position = game._player.global_position
	game._remote_bags[9877].set_meta("cocooned", true)
	check(game._bodies_near(game._player.global_position, 1.2) == 1, "captured bag cannot help deadbolt")
	game._remote_bags[9877].set_meta("cocooned", false)
	var interrupted: Objective = game._objectives[0]
	interrupted.force_done()
	interrupted._entry = "1234"
	game._net_objective_rejected(interrupted.def.id)
	check(not interrupted.done and interrupted._entry.is_empty(), "rejected solve becomes retryable")
	interrupted._hold_t = 1.0
	interrupted._entry_digit = 2
	interrupted._panel_open = true
	interrupted.update(0.1, game._player.global_position, 2, false)
	check(interrupted._hold_t == 0.0 and interrupted._entry_digit == -1 and not interrupted._panel_open,
		"blocked interaction cancels objective timers and panel")
	check(not game._apply_remote_bag_state(9998, Vector3.INF, Quaternion.IDENTITY, 0, 0, 0)
		and not game._remote_bags.has(9998), "invalid transform cannot create a ghost")
	check(not game._apply_remote_bag_state(9877, Vector3.ZERO, Quaternion(0, 0, 0, 0), 0, 0, 0),
		"zero quaternion cannot enter interpolation")
	check(game._apply_remote_bag_state(9877, Vector3.ZERO, Quaternion.IDENTITY, 0, -10, 0)
		and game._remote_bags[9877].get_meta("tumbles") == 0, "valid transform accepted and counter bounded")
	var opened: String = game._selftest_arm_via_door()
	check(not game._can_peer_escape(9999), "unknown peer cannot escape")
	game._remote_bags[9877].global_position = Vector3(1000, 1000, 1000)
	check(not game._can_peer_escape(9877), "distant peer cannot escape")
	for exit_def: Dictionary in HouseSuburban.exits():
		if exit_def["name"] == opened:
			game._remote_bags[9877].global_position = exit_def["at"]
	check(game._can_peer_escape(9877), "living peer at open exit can escape")
	game._net_report_escape(9877)
	check(game.phase == game.Phase.ROUND, "claimed identity cannot escape for another peer")
	check(game._play_remote_landing(9877), "remote landing plays")
	check(not game._play_remote_landing(9877) and not game._play_remote_landing(9999), "duplicate and unknown landing rejected")
	game._remote_bags[9877].set_meta("last_landing_msec", -1000)
	game._remote_bags[9877].set_meta("cocooned", true)
	game._apply_remote_bag_state(9877, game._remote_bags[9877].global_position, Quaternion.IDENTITY, 0, 0, 0)
	check(game._remote_bags[9877].get_meta("cocooned"), "movement packet cannot undo host capture")
	check(not game._can_peer_escape(9877), "captured peer cannot escape")
	check(not game._play_remote_landing(9877), "cocooned landing rejected")
	check(not game._authoritative_rescue(9877, 9877)
		and not game._authoritative_rescue(9999, 9877), "self and unknown rescues rejected")
	game._remote_bags[9877].global_position = game._player.global_position + Vector3(100, 0, 0)
	check(not game._authoritative_rescue(game._my_id(), 9877), "distant rescue rejected")
	game._remote_bags[9877].global_position = game._player.global_position + Vector3(0.2, 0, 0)
	var rescues_before: int = game._stat(game._my_id()).get("rescues", 0)
	check(not game._authoritative_rescue(game._my_id(), 9877), "nearby rescue cannot skip hold time")
	game._receive_rescue_hold(game._my_id(), 9877)
	game._tick_rescue_holds(0.7)
	check(game._host_rescues.is_empty(), "missing hold heartbeat cancels rescue")
	for step in 26:
		game._receive_rescue_hold(game._my_id(), 9877)
		game._tick_rescue_holds(0.2)
	check(not game._remote_bags[9877].get_meta("cocooned"), "host completes sustained five-second rescue")
	game._apply_remote_bag_state(9877, game._remote_bags[9877].global_position, Quaternion.IDENTITY, game.FLAG_COCOONED, 0, 0)
	check(not game._remote_bags[9877].get_meta("cocooned"), "stale captured packet cannot undo rescue")
	check(not game._authoritative_rescue(game._my_id(), 9877)
		and game._stat(game._my_id()).get("rescues", 0) == rescues_before + 1, "duplicate rescue cannot duplicate credit")
	game._on_peer_disconnected(9877)
	game._player.test_move = Vector3.FORWARD
	game._player._hop_queued = true
	app._set_paused(true)
	check(game._player._input_dir() == Vector3.ZERO and not game._player._hop_queued,
		"pause blocks movement and clears queued hop")
	check(game.is_processing() and game._monster.is_physics_processing(), "co-op simulation stays live")
	app._set_paused(false)
	check(game._player._input_dir() != Vector3.ZERO, "resume restores controls")
	game._player.test_move = Vector3.ZERO
	game._host_end_round("SUNRISE")
	check(game._results_overlay.visible and not game._player.controls_enabled
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "recap releases cursor and blocks movement")
	game.replay_round()
	check(game.phase == game.Phase.RESULTS, "replay waits for outro")
	game._outro_active = false
	game.replay_round()
	check(game.phase == game.Phase.LIGHTS_OUT and not game._results_overlay.visible
		and game._done_ids.is_empty() and game._inv == [-1, -1], "one-click replay resets into next night")
	game.leave_requested.emit()
	check(app._game == null and app._menu.visible, "leave returns to title")
	SteamManager.is_host = false
	SteamManager.lobby_id = -1
	app._show(app.State.LOBBY)
	app._on_connection_failed()
	check(app._menu.visible and SteamManager.lobby_id == 0 and LobbyManager.players.is_empty()
		and app._menu_status.text.contains("Couldn't reach"), "failed connection restores retryable menu")
	await get_tree().process_frame
	var baseline_nodes := get_tree().get_node_count()
	for cycle in 3:
		SteamManager.is_host = true
		LobbyManager.enter_lobby("Cycle tester")
		app._load_game(true)
		var old_game: Node = app._game
		app._leave_to_menu()
		await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout
		check(not is_instance_valid(old_game) and app._game == null
			and get_tree().get_node_count() == baseline_nodes and VoiceManager._players.is_empty(),
			"scene cycle %d releases game nodes and voice players" % (cycle + 1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Scrapbook.save_path()))
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	print("[FLOW] RESULT: %s" % ("PASS" if failures.is_empty() else str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)
