extends Node3D

var failures: Array[String] = []
var noise_events: int = 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
	print("[AUDIO] %s: %s" % [label, condition])

func _ready() -> void:
	check(VoiceManager._make_tone(VoiceManager.TONE_INTERVAL).size() <= 1200,
		"synthetic voice payload fits transport budget")
	SoundKit.apply_mix(1.0, 0.0, 1.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))
		and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "effects mute preserves voice")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("InBag")) == "Effects"
		and AudioServer.get_bus_send(AudioServer.get_bus_index("VoiceInBag")) == "Voice"
		and AudioServer.get_bus_send(AudioServer.get_bus_index("VoiceOccluded")) == "Voice", "muffled audio stays in correct mix group")
	var bus_count := AudioServer.get_bus_count()
	SoundKit.ensure_buses()
	check(AudioServer.get_bus_count() == bus_count, "mix setup does not duplicate buses")
	VoiceManager.register_player(9876, self)
	check(VoiceManager._players[9876].bus == "Voice", "clear speech uses voice volume")
	VoiceManager._occluded[9876] = true
	VoiceManager._apply_bus(9876)
	check(VoiceManager._players[9876].bus == "VoiceOccluded", "occluded speech uses filtered voice route")
	VoiceManager.set_muffled(9876, true)
	check(VoiceManager._players[9876].bus == "VoiceInBag", "cocoon speech uses filtered voice route")
	VoiceManager.unregister_player(9876)
	SoundKit.apply_mix(1.0, 1.0, 0.0)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))
		and AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "voice mute preserves effects")
	SoundKit.apply_mix(Scrapbook.master_volume, Scrapbook.effects_volume, Scrapbook.voice_volume)
	var loaded := 0
	for kind: String in SoundKit.SAMPLE_SETS:
		for relative_path: String in SoundKit.SAMPLE_SETS[kind]:
			var stream := load("res://assets/audio/" + relative_path) as AudioStream
			check((stream is AudioStreamOggVorbis or stream is AudioStreamWAV) and stream.get_length() > 0.0,
				"sample loads: " + relative_path)
			loaded += 1
		var previous := ""
		var repeats := false
		for i in 20:
			var stream := SoundKit.get_stream(kind)
			if SoundKit.SAMPLE_SETS[kind].size() > 1 and stream.resource_path == previous:
				repeats = true
			previous = stream.resource_path
		check(not repeats, "no immediate repeat: " + kind)
	seed(12345)
	var expected := randi()
	seed(12345)
	SoundKit.get_stream("shuffle")
	SoundKit.variation_pitch()
	check(randi() == expected, "sample choices preserve gameplay RNG")
	check(SoundKit.get_stream("zipper") is AudioStreamOggVorbis, "zipper uses recorded fabric zipper")
	check(SoundKit.get_stream("bark").get_length() < 3.7, "recorded bark fits four-second cadence with pitch variation")
	check(SoundKit.get_stream("heartbeat") is AudioStreamWAV, "unfinished cue retains fallback")
	seed(7632)
	var expected_after_fallback := randi()
	seed(7632)
	SoundKit._generate("shush")
	SoundKit._generate("clatter")
	check(randi() == expected_after_fallback, "procedural sound generation preserves gameplay RNG")
	var player := SleepingBagPlayer.new()
	add_child(player)
	player.set_physics_process(false)
	player.grounded = true
	player.linear_velocity = Vector3(1.45, 0, 0)
	NoiseBus.noise_emitted.connect(_noise)
	player._update_shuffle_audio(0.5)
	var voices := player.get_children().filter(func(child: Node) -> bool: return child is AudioStreamPlayer3D).size()
	check(voices == 1 and noise_events == 0, "shuffle plays without alerting monster")
	player.set_controls_enabled(false)
	player._update_shuffle_audio(0.5)
	check(player.get_children().filter(func(child: Node) -> bool: return child is AudioStreamPlayer3D).size() == voices,
		"menu-blocked movement does not play steps")
	NoiseBus.noise_emitted.disconnect(_noise)
	await get_tree().create_timer(0.7).timeout
	check(player.get_children().filter(func(child: Node) -> bool: return child is AudioStreamPlayer3D).is_empty(),
		"cloth envelope releases finished audio")
	player.queue_free()
	await get_tree().process_frame
	print("[AUDIO] %d samples; RESULT: %s" % [loaded, "PASS" if failures.is_empty() else str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _noise(_pos: Vector3, _loudness: float) -> void:
	noise_events += 1
