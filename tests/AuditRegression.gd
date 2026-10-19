extends Node

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
	print("[AUDIT] %s: %s" % [label, condition])

func _ready() -> void:
	var gait := Node3D.new()
	BagVisual.animate_shuffle(gait, 0.1125, true, 0.125)
	check(absf(gait.rotation.z) > 0.01 and gait.scale.y < 1.0, "shuffle gait shifts weight and compresses")
	var stopped_phase: float = gait.get_meta("gait_phase")
	for i in 60:
		BagVisual.animate_shuffle(gait, 0.0, true, 1.0 / 60.0)
	check(is_equal_approx(float(gait.get_meta("gait_phase")), stopped_phase)
		and gait.scale.is_equal_approx(Vector3.ONE), "stationary gait stops and settles")
	BagVisual.animate_shuffle(gait, 10.0, true, 0.016)
	check(is_equal_approx(float(gait.get_meta("gait_phase")), stopped_phase), "teleports do not advance gait")
	gait.free()
	Scrapbook.use_test_path("user://audit_regression.save")
	Scrapbook._from_dict({"collected": 42, "selected_skin": {},
		"career_rounds": -8, "career_tumbles": [], "voice_open_mic": "false"})
	check(Scrapbook.collected.is_empty() and Scrapbook.selected_skin == 0,
		"malformed collection and skin recover")
	check(Scrapbook.career_rounds == 0 and Scrapbook.career_tumbles == 0
		and not Scrapbook.voice_open_mic, "malformed preferences and totals recover")
	Scrapbook._from_dict({"collected": ["flyer_wren", "flyer_wren", "missing", 1], "selected_skin": 7})
	check(Scrapbook.collected == ["flyer_wren"] and Scrapbook.selected_skin == 0,
		"unknown fragments, duplicates and locked skins rejected")
	Scrapbook.save_game()
	Scrapbook.career_rounds = 7
	Scrapbook.mouse_sensitivity = 0.007
	Scrapbook.master_volume = 0.25
	Scrapbook.save_game()
	Scrapbook.career_rounds = 0
	Scrapbook.mouse_sensitivity = 0.004
	Scrapbook.master_volume = 1.0
	Scrapbook.load_game()
	check(is_equal_approx(Scrapbook.mouse_sensitivity, 0.007)
		and is_equal_approx(Scrapbook.master_volume, 0.25), "audio and mouse preferences persist")
	check(Scrapbook.career_rounds == 7 and Scrapbook.has("flyer_wren"),
		"save replacement survives reload")
	Scrapbook.save_game()
	var damaged := FileAccess.open(Scrapbook.save_path(), FileAccess.WRITE)
	damaged.store_string("{interrupted")
	damaged.close()
	Scrapbook.career_rounds = 0
	Scrapbook.load_game()
	check(Scrapbook.career_rounds == 7 and Scrapbook.has("flyer_wren"), "damaged primary recovers previous save")
	var backup_before := FileAccess.get_file_as_bytes(Scrapbook.save_path() + ".bak")
	Scrapbook.save_game()
	check(FileAccess.get_file_as_bytes(Scrapbook.save_path() + ".bak") == backup_before,
		"damaged primary cannot replace good backup")
	check(Scrapbook._read_local_save(Scrapbook.save_path()) is Dictionary,
		"recovered progress can be saved again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Scrapbook.save_path()))
	Scrapbook.career_rounds = 0
	Scrapbook.load_game()
	check(Scrapbook.career_rounds == 7, "missing primary also recovers backup")
	LobbyManager.enter_lobby("Tester")
	LobbyManager.start_game()
	check(not LobbyManager.started, "unready start rejected")
	LobbyManager.set_ready(true)
	check(LobbyManager.can_start(), "ready solo can start")
	LobbyManager.start_game()
	check(LobbyManager.started and not LobbyManager.can_start(), "solo starts once")
	LobbyManager.leave()
	LobbyManager.players = {1: {"ready": true, "spectator": true}}
	check(not LobbyManager.can_start(), "spectators cannot start a round")
	LobbyManager.leave()
	check(not LobbyManager._connected and not LobbyManager._want_ready, "leave clears pending state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Scrapbook.save_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Scrapbook.save_path() + ".bak"))
	print("[AUDIT] RESULT: %s" % ("PASS" if failures.is_empty() else str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)
