extends Node
## Two-process ENet check: use --enet-host / --enet-join.
var app: Node
var game: Node
var finished := false

func _ready() -> void:
	Scrapbook.use_test_path("user://network_inventory_test.save")
	app = preload("res://core/ui/AppRoot.tscn").instantiate()
	add_child(app)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		if not finished:
			print("[INVENTORY NET] FAIL: timeout")
			get_tree().quit(1))
	while app._game == null:
		await get_tree().process_frame
	game = app._game
	while game.phase != game.Phase.ROUND:
		await get_tree().process_frame
	game._monster.set_physics_process(false)
	game._player.set_physics_process(false)
	game._player.freeze = true
	if multiplayer.is_server():
		await get_tree().create_timer(0.8).timeout
		_prepare.rpc(Vector3(0, 0.5, 0))
		_prepare(Vector3(0, 0.5, 0))
		await get_tree().create_timer(0.4).timeout
		game._authoritative_spawn_item(Item.Kind.CAN, Vector3(0, 0.5, 0))
		game._authoritative_spawn_item(Item.Kind.POPPER, Vector3(0, 0.5, 0))
		game._authoritative_spawn_item(Item.Kind.CAN, Vector3(0, 0.5, 0))
		_pickup.rpc()

@rpc("authority", "call_remote", "reliable")
func _prepare(at: Vector3) -> void:
	game._setup_items({})
	if not game._has_objective(ObjectiveDef.Kind.DOG):
		var dog := Objective.new()
		game.add_child(dog)
		dog.setup(ObjectiveDef._dog(), {}, false)
		game._objectives.append(dog)
	game._player.global_position = at
	game._player.linear_velocity = Vector3.ZERO

@rpc("authority", "call_remote", "reliable")
func _pickup() -> void:
	var dog: Objective = _dog_objective()
	dog._dog.global_position += Vector3(2, 0, 0)  # replication must correct this
	for item: Item in game._items:
		game._finish_item_pickup(item)
	await get_tree().create_timer(0.4).timeout
	_report.rpc_id(1, 1, game._inv[0] == Item.Kind.CAN and game._inv[1] == Item.Kind.POPPER
		and game._live_item_count() == 1, dog._dog.global_position)

func _dog_objective() -> Objective:
	for objective: Objective in game._objectives:
		if objective.def.kind == ObjectiveDef.Kind.DOG:
			return objective
	return null

@rpc("authority", "call_remote", "reliable")
func _throw_twice() -> void:
	game._use_slot(0)
	game._use_slot(0)
	await get_tree().create_timer(1.1).timeout
	_report.rpc_id(1, 2, game._inv[0] == -1 and game._inv[1] == Item.Kind.POPPER
		and game._live_item_count() == 2)

@rpc("authority", "call_remote", "reliable")
func _check_capture() -> void:
	await get_tree().create_timer(0.3).timeout
	_report.rpc_id(1, 3, game._inv[0] == -1 and game._inv[1] == -1
		and game._live_item_count() == 3 and game._player.state == SleepingBagPlayer.State.COCOONED)

@rpc("authority", "call_remote", "reliable")
func _go_to_door(at: Vector3) -> void:
	game._player.global_position = at
	await get_tree().create_timer(0.5).timeout
	game._use_slot(game._inv.find(Item.Kind.KEYS))
	await get_tree().create_timer(0.4).timeout
	_report.rpc_id(1, 4, game._keys_door_open and not game._inv_has(Item.Kind.KEYS))

@rpc("any_peer", "call_remote", "reliable")
func _report(stage: int, client_ok: bool, dog_at: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var slots: Array = game._inventory_for(pid)
	var ok := client_ok
	match stage:
		1:
			ok = ok and slots == [Item.Kind.CAN, Item.Kind.POPPER] and game._live_item_count() == 1
			var dog_synced: bool = dog_at.distance_to(_dog_objective()._dog.global_position) < 0.25
			print("[INVENTORY NET] dog position converged: %s" % dog_synced)
			ok = ok and dog_synced
		2:
			ok = ok and slots == [-1, Item.Kind.POPPER] and game._live_item_count() == 2
		3:
			ok = ok and slots == [-1, -1] and game._live_item_count() == 3
		4:
			ok = ok and game._keys_door_open and not slots.has(Item.Kind.KEYS)
	print("[INVENTORY NET] stage %d: %s" % [stage, "PASS" if ok else "FAIL"])
	if not ok or stage == 4:
		_close.rpc(ok)
		await get_tree().create_timer(0.2).timeout
		_close(ok)
	elif stage == 1:
		_throw_twice.rpc_id(pid)
	elif stage == 2:
		game._on_monster_lunged_hit(game._remote_bags[pid])
		_check_capture.rpc_id(pid)
	elif stage == 3:
		game._apply_rescue(pid)
		game._net_rescued.rpc(pid)
		_dog_objective()._dog.global_position = Vector3(8, 0.5, 8)
		var uid: int = game._item_uid_next
		game._authoritative_spawn_item(Item.Kind.JERKY, game._remote_bags[pid].global_position)
		_pass_jerky.rpc_id(pid, uid)

@rpc("authority", "call_remote", "reliable")
func _pass_jerky(uid: int) -> void:
	game._finish_item_pickup(game._item_by_uid(uid))
	await get_tree().create_timer(0.3).timeout
	var held: bool = game._inv_has(Item.Kind.JERKY)
	game._use_slot(game._inv.find(Item.Kind.JERKY))
	await get_tree().create_timer(0.3).timeout
	_jerky_dropped.rpc_id(1, held and not game._inv_has(Item.Kind.JERKY))

@rpc("any_peer", "call_remote", "reliable")
func _jerky_dropped(client_ok: bool) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var snack: Item = null
	for item: Item in game._items:
		if item.kind == Item.Kind.JERKY and not item.taken:
			snack = item
	var ok: bool = client_ok and snack != null and not game._inventory_for(pid).has(Item.Kind.JERKY)
	if ok:
		game._player.global_position = snack.global_position
		game._finish_item_pickup(snack)
		game._player.global_position = _dog_objective()._dog.global_position
		game._use_slot(game._inv.find(Item.Kind.JERKY))
		ok = game._inv_has(Item.Kind.KEYS) and game._done_ids.has("dog") and not game._inv_has(Item.Kind.JERKY)
	print("[INVENTORY NET] teammate jerky pickup and feeding: %s" % ok)
	if not ok:
		_close.rpc(false)
		_close(false)
		return
	game._player.global_position = Vector3(0, 0.5, 0)
	game._use_slot(game._inv.find(Item.Kind.KEYS))
	var dropped_keys: Item = game._items.back()
	_take_keys.rpc_id(pid, dropped_keys.uid, dropped_keys.global_position)

@rpc("authority", "call_remote", "reliable")
func _take_keys(uid: int, at: Vector3) -> void:
	game._player.global_position = at
	await get_tree().create_timer(0.3).timeout
	game._finish_item_pickup(game._item_by_uid(uid))
	await get_tree().create_timer(0.3).timeout
	for exit_def: Dictionary in HouseSuburban.exits():
		if exit_def["name"] == "BACK DOOR":
			_go_to_door(exit_def["at"])

@rpc("authority", "call_remote", "reliable")
func _close(ok: bool) -> void:
	finished = true
	print("[INVENTORY NET] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
