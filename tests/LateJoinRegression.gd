extends Node
## Start host first, then a client with --enet-host / --enet-join.
var app: Node
var game: Node
var finished := false

func _ready() -> void:
	Scrapbook.use_test_path("user://late_join_test.save")
	app = preload("res://core/ui/AppRoot.tscn").instantiate()
	add_child(app)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		if not finished:
			print("[LATE JOIN] FAIL: timeout")
			get_tree().quit(1))
	if OS.get_cmdline_user_args().has("--enet-host"):
		while LobbyManager.players.is_empty():
			await get_tree().process_frame
		LobbyManager.start_game()
	while app._game == null:
		await get_tree().process_frame
	game = app._game
	game._monster.set_physics_process(false)
	if multiplayer.is_server():
		game._apply_phase(game.Phase.ROUND, {})
		game._phase_timer = 321.0
		game._authoritative_complete(game._objectives[0].def.id)
		var fr: Fragment = game._fragments[0]
		game._player.global_position = fr.global_position + Vector3.UP * 0.2
		game._authoritative_collect_fragment(fr.id(), 1)
		game._authoritative_spawn_item(Item.Kind.KEYS, game._player.global_position)
		game._keys_door_open = true
		game._refresh_exit_doors()
		game._player.freeze = true
		print("[LATE JOIN] host prepared active round")
	else:
		while game.phase != game.Phase.ROUND:
			await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		var inert: bool = game._late_spectator and game._player.freeze and not game._player.visible \
			and game._player.collision_layer == 0 and game._player.state == SleepingBagPlayer.State.COCOONED
		var watching: bool = game._spectate_target() != null
		_report.rpc_id(1, inert and watching, game._done_ids.size(), game._collected_this_round(),
			game._live_item_count(), game._keys_door_open, game._phase_timer)

@rpc("any_peer", "call_remote", "reliable")
func _report(inert: bool, done: int, lore: int, items: int, keys_open: bool, timer: float) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var ok: bool = inert and done == game._done_ids.size() and lore == game._collected_this_round() \
		and items == game._live_item_count() and keys_open and absf(timer - game._phase_timer) < 2.0 \
		and not game._remote_bags.has(pid) and game._lobby_size() == 1
	print("[LATE JOIN] snapshot and spectator: %s" % ok)
	if not ok:
		_finish(false)
		return
	game._host_end_round("ESCAPE")
	game._outro_active = false
	game.replay_round()
	_check_next_night.rpc_id(pid)

@rpc("authority", "call_remote", "reliable")
func _check_next_night() -> void:
	await get_tree().create_timer(0.3).timeout
	var active: bool = not game._late_spectator and not game._player.freeze and game._player.visible \
		and game._player.is_physics_processing() and game._player.collision_mask == 3 \
		and game._player.state != SleepingBagPlayer.State.COCOONED
	_next_report.rpc_id(1, active)

@rpc("any_peer", "call_remote", "reliable")
func _next_report(active: bool) -> void:
	if multiplayer.is_server():
		print("[LATE JOIN] next night active: %s" % active)
		_finish(active)

func _finish(ok: bool) -> void:
	_close.rpc(ok)
	await get_tree().create_timer(0.2).timeout
	_close(ok)

@rpc("authority", "call_remote", "reliable")
func _close(ok: bool) -> void:
	finished = true
	print("[LATE JOIN] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
