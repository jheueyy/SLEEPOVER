extends Node

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	print("[INVENTORY] %s: %s" % [label, ok])
	if not ok:
		failures.append(label)

func _ready() -> void:
	Scrapbook.use_test_path("user://inventory_regression.save")
	var app := preload("res://core/ui/AppRoot.tscn").instantiate()
	add_child(app)
	SteamManager.is_host = true
	LobbyManager.enter_lobby("Inventory tester")
	app._load_game(true)
	var game: Node = app._game
	game._apply_phase(game.Phase.ROUND, {})
	game._monster.set_physics_process(false)
	var pid := 9878
	var bag: Node3D = game._spawn_remote_bag(pid)
	bag.global_position = game._player.global_position
	var can: Item = game._spawn_item(90001, Item.Kind.CAN, bag.global_position)
	var popper: Item = game._spawn_item(90002, Item.Kind.POPPER, bag.global_position)
	var spare: Item = game._spawn_item(90003, Item.Kind.CAN, bag.global_position)
	game._authoritative_take_item(can.uid, pid)
	game._authoritative_take_item(popper.uid, pid)
	game._authoritative_take_item(spare.uid, pid)
	check(can.taken and popper.taken and not spare.taken, "remote two-slot capacity enforced")
	var slots: Array = game._inventory_for(pid)
	var before: int = game._live_item_count()
	game._authoritative_use_item(pid, 0, Item.Kind.KEYS, Vector3.FORWARD)
	game._authoritative_use_item(pid, 0, Item.Kind.CAN, Vector3.INF)
	game._authoritative_use_item(9999, 0, Item.Kind.CAN, Vector3.FORWARD)
	check(slots[0] == Item.Kind.CAN and game._live_item_count() == before, "forged uses cannot create items")
	bag.set_meta("cocooned", true)
	game._authoritative_use_item(pid, 0, Item.Kind.CAN, Vector3.FORWARD)
	check(slots[0] == Item.Kind.CAN, "captured peer cannot use inventory")
	bag.set_meta("cocooned", false)
	var host_noise: float = game._stat(game._my_id()).get("noise_total", 0.0)
	var peer_noise: float = game._stat(pid).get("noise_total", 0.0)
	game._authoritative_use_item(pid, 0, Item.Kind.CAN, Vector3.FORWARD)
	game._authoritative_use_item(pid, 0, Item.Kind.CAN, Vector3.FORWARD)
	check(game._live_item_count() == before
		and is_equal_approx(game._stat(pid).get("noise_total", 0.0), peer_noise),
		"airborne can is not collectible and makes no impact noise")
	await get_tree().create_timer(1.0).timeout
	check(slots[0] == -1 and game._live_item_count() == before + 1, "duplicate throw consumes one can and creates one landing")
	check(is_equal_approx(game._stat(game._my_id()).get("noise_total", 0.0), host_noise)
		and is_equal_approx(game._stat(pid).get("noise_total", 0.0), peer_noise + game.can_loudness),
		"host-generated throw noise credits only its owner")
	game._authoritative_use_item(pid, 1, Item.Kind.POPPER, Vector3.FORWARD)
	var after_pop: float = game._stat(pid).get("noise_total", 0.0)
	game._authoritative_use_item(pid, 1, Item.Kind.POPPER, Vector3.FORWARD)
	check(slots[1] == -1 and is_equal_approx(game._stat(pid).get("noise_total", 0.0), after_pop),
		"duplicate popper cannot make another bang")
	for exit_def: Dictionary in HouseSuburban.exits():
		if exit_def["name"] == "BACK DOOR":
			bag.global_position = exit_def["at"]
	game._authoritative_keys_turned(pid)
	check(not game._keys_door_open, "remote peer without owned keys cannot unlock")
	game._grant_keys(pid, bag.global_position)
	game._authoritative_use_item(pid, 0, Item.Kind.KEYS, Vector3.FORWARD)
	check(game._keys_door_open and not slots.has(Item.Kind.KEYS), "remote owned keys open lock and are consumed")
	game._keys_door_open = false
	bag.global_position = Vector3(100, 0, 100)
	game._grant_keys(pid, bag.global_position)
	before = game._live_item_count()
	game._authoritative_use_item(pid, 0, Item.Kind.KEYS, Vector3.FORWARD)
	check(not slots.has(Item.Kind.KEYS) and game._live_item_count() == before + 1,
		"setting down keys produces one recoverable item")
	game._grant_keys(pid, bag.global_position)
	before = game._live_item_count()
	game._on_monster_lunged_hit(bag)
	game._on_monster_lunged_hit(bag)
	check(not slots.has(Item.Kind.KEYS) and game._live_item_count() == before + 1,
		"capture spills owned keys once")
	bag.set_meta("cocooned", false)
	game._grant_keys(pid, bag.global_position)
	before = game._live_item_count()
	game._on_peer_disconnected(pid)
	check(not game._remote_inventory.has(pid) and game._live_item_count() == before + 1,
		"disconnect leaves carried keys recoverable and clears ledger")
	var feeder: Node3D = game._spawn_remote_bag(9879)
	feeder.global_position = game._player.global_position
	var full_slots: Array = game._inventory_for(9879)
	full_slots[0] = -1
	full_slots[1] = Item.Kind.POPPER
	if not game._has_objective(ObjectiveDef.Kind.DOG):
		var dog := Objective.new()
		game.add_child(dog)
		dog.setup(ObjectiveDef._dog(), {}, false)
		game._objectives.append(dog)
	game._authoritative_complete("dog", 9879)
	check(not game._done_ids.has("dog"), "dog cannot be completed without carrying jerky")
	feeder.global_position = Vector3(100, 0.5, 100)
	var jerky: Item = game._spawn_item(90010, Item.Kind.JERKY, feeder.global_position)
	game._authoritative_take_item(jerky.uid, 9879)
	check(jerky.taken and full_slots.has(Item.Kind.JERKY), "jerky pickup occupies a real slot")
	game._authoritative_use_item(9879, 0, Item.Kind.JERKY, Vector3.FORWARD)
	var dropped_snack: Item = game._items.back()
	check(not full_slots.has(Item.Kind.JERKY) and dropped_snack.kind == Item.Kind.JERKY,
		"jerky can be set down for a teammate")
	feeder.global_position = dropped_snack.global_position
	game._authoritative_take_item(dropped_snack.uid, 9879)
	for objective: Objective in game._objectives:
		if objective.def.kind == ObjectiveDef.Kind.DOG:
			feeder.global_position = objective._dog.global_position
	before = game._live_item_count()
	var feeder_noise: float = game._stat(9879).get("noise_total", 0.0)
	game._authoritative_use_item(9879, 0, Item.Kind.JERKY, Vector3.FORWARD)
	game._authoritative_complete("dog", 9879)
	check(is_equal_approx(game._stat(9879).get("noise_total", 0.0), feeder_noise + 0.7),
		"accepted feeding credits the feeder once")
	check(game._live_item_count() == before and full_slots == [Item.Kind.KEYS, Item.Kind.POPPER]
		and not game._inv_has(Item.Kind.KEYS), "dog consumes owned jerky and grants keys once in freed slot")
	full_slots[0] = Item.Kind.CAN
	game._authoritative_use_item(9879, 0, Item.Kind.CAN, Vector3.FORWARD)
	game._apply_phase(game.Phase.LOBBY, {})
	check(game._remote_inventory.is_empty(), "round reset clears ownership")
	game._apply_phase(game.Phase.ROUND, {})
	await get_tree().create_timer(1.0).timeout
	check(game._live_item_count() == 0, "previous round's airborne can cannot land in next round")
	var floor_fixture := _solid(Vector3(50, 9.9, 50), Vector3(1, 0.2, 2))
	var wall_fixture := _solid(Vector3(50, 10.5, 49.65), Vector3(1, 1, 0.2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var near_wall: Vector3 = game._drop_position(Vector3(50, 10.5, 50), Vector3(0, 0, -0.6))
	check(near_wall.z > 49.85 and is_equal_approx(near_wall.y, 10.025),
		"drop stays in front of wall and rests on floor")
	var ledge: Vector3 = game._drop_position(Vector3(50, 10.5, 50), Vector3(0.8, 0, 0))
	check(is_equal_approx(ledge.x, 50.0) and is_equal_approx(ledge.y, 10.025),
		"drop beyond ledge falls back to ground beneath bag")
	floor_fixture.queue_free()
	wall_fixture.queue_free()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	print("[INVENTORY] RESULT: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func _solid(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.global_position = at
	return body
