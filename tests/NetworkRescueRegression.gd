extends Node
## Run two processes with --enet-host / --enet-join using this scene.
var app: Node
var game: Node
var finished := false

func _ready() -> void:
	Scrapbook.use_test_path("user://network_rescue_test.save")
	app = preload("res://core/ui/AppRoot.tscn").instantiate()
	add_child(app)
	get_tree().create_timer(35.0).timeout.connect(func() -> void:
		if not finished:
			print("[RESCUE NET] FAIL: timeout")
			get_tree().quit(1))
	while app._game == null:
		await get_tree().process_frame
	game = app._game
	while game.phase != game.Phase.ROUND:
		await get_tree().process_frame
	game._monster.set_physics_process(false)
	game._player.set_physics_process(false)
	game._player.freeze = true
	game._player.test_move = Vector3.ZERO
	# The harness's own periodic walking cannot move a frozen test bag.
	if multiplayer.is_server():
		await get_tree().create_timer(1.0).timeout
		_prepare.rpc()
		_prepare()
		await get_tree().create_timer(0.5).timeout
		game._on_monster_lunged_hit(game._player)
		await get_tree().create_timer(0.5).timeout
		_begin_hold.rpc()

@rpc("authority", "call_remote", "reliable")
func _prepare() -> void:
	game._player.global_position = Vector3(0.2 if not multiplayer.is_server() else 0.0, 0.25, 0.0)
	game._player.linear_velocity = Vector3.ZERO

@rpc("authority", "call_remote", "reliable")
func _begin_hold() -> void:
	if not game._remote_bags.has(1) or not game._remote_bags[1].get_meta("cocooned", false):
		_finish.rpc_id(1, false, "capture did not reach teammate")
		return
	# Exercise an interrupted hold, then a complete one through real RPCs.
	game._request_rescue.rpc_id(1, 1)
	await get_tree().create_timer(0.25).timeout
	game._request_rescue.rpc_id(1, -1)
	await get_tree().create_timer(0.8).timeout
	for step in 28:
		game._request_rescue.rpc_id(1, 1)
		await get_tree().create_timer(0.2).timeout
	var restored: bool = not game._remote_bags[1].get_meta("cocooned", true)
	_finish.rpc_id(1, restored, "client saw rescue")

@rpc("any_peer", "call_remote", "reliable")
func _finish(client_ok: bool, detail: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var ok: bool = client_ok and game._player.state != SleepingBagPlayer.State.COCOONED \
		and int(game._stat(pid).get("rescues", 0)) == 1
	print("[RESCUE NET] %s: %s; host restored=%s; credit=%s" % ["PASS" if ok else "FAIL", detail,
		game._player.state != SleepingBagPlayer.State.COCOONED, game._stat(pid).get("rescues", 0)])
	_close.rpc(ok)
	await get_tree().create_timer(0.3).timeout
	_close(ok)

@rpc("authority", "call_remote", "reliable")
func _close(ok: bool) -> void:
	finished = true
	get_tree().quit(0 if ok else 1)
