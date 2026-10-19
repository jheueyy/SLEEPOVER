class_name SoundKit
extends Object
## Licensed sample variants with procedural fallbacks for unfinished sound cues.
## Provenance is recorded in assets/audio/README.md and the bundled licenses.
##
##   hum       — the Housesitter's patrol lullaby drone (loop)
##   heartbeat — in-the-bag pulse, volume driven by monster proximity (loop)
##   creak     — floorboard creak for monster footsteps
##   sting     — dissonant chord when a chase begins
##   screech   — lunge windup
##   zipper    — rescue / unzip
##   breath    — heavy scared breathing heard from inside the bag (loop)
##   tape      — answering-machine tape: deck clunk + warbly hiss (lore pickup)
##   click     — rotary phone dial

const RATE := 22050
const EFFECTS_BUS := "Effects"
const VOICE_BUS := "Voice"
const VOICE_INBAG_BUS := "VoiceInBag"
const SHUFFLE_DISTANCE := 0.65
const SHUFFLE_COOLDOWN := 0.32

static func ensure_buses() -> void:
	_ensure_bus(EFFECTS_BUS, "Master")
	_ensure_bus(VOICE_BUS, "Master")
	_ensure_bus("InBag", EFFECTS_BUS, 600.0)
	_ensure_bus(VOICE_INBAG_BUS, VOICE_BUS, 600.0)
	_ensure_bus("VoiceOccluded", VOICE_BUS, 1400.0, -6.0)

static func _ensure_bus(bus_name: String, send: String, cutoff: float = 0.0, gain: float = 0.0) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = AudioServer.get_bus_count()
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_volume_db(index, gain)
		if cutoff > 0.0:
			var lowpass := AudioEffectLowPassFilter.new()
			lowpass.cutoff_hz = cutoff
			AudioServer.add_bus_effect(index, lowpass)
	AudioServer.set_bus_send(index, send)

static func apply_mix(master: float, effects: float, voice: float) -> void:
	ensure_buses()
	_set_bus_volume("Master", master)
	_set_bus_volume(EFFECTS_BUS, effects)
	_set_bus_volume(VOICE_BUS, voice)

static func _set_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	var linear := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))

static var _cache: Dictionary = {}
static var _last_sample: Dictionary = {}
static var _audio_rng := RandomNumberGenerator.new()
static var _rng_ready := false

const SAMPLE_SETS := {
	"bark": ["brandon-morris/dog_barking_mono.wav"],
	"breath": ["mikeask/breathing.wav"],
	"zipper": ["antumdeluge/zipper.ogg"],
	"shuffle": ["kenney-rpg/cloth1.ogg", "kenney-rpg/cloth2.ogg", "kenney-rpg/cloth3.ogg", "kenney-rpg/cloth4.ogg"],
	"thump": ["kenney-impact/impactSoft_heavy_000.ogg", "kenney-impact/impactSoft_heavy_001.ogg", "kenney-impact/impactSoft_heavy_002.ogg"],
	"creak": ["kenney-rpg/creak1.ogg", "kenney-rpg/creak2.ogg", "kenney-rpg/creak3.ogg"],
	"can_land": ["kenney-rpg/metalPot1.ogg", "kenney-rpg/metalPot2.ogg", "kenney-rpg/metalPot3.ogg"],
	"unlock": ["kenney-rpg/metalLatch.ogg"],
	"page": ["kenney-rpg/bookFlip1.ogg", "kenney-rpg/bookFlip2.ogg", "kenney-rpg/bookFlip3.ogg"],
	"clatter": ["kenney-impact/impactMetal_light_000.ogg", "kenney-impact/impactMetal_light_001.ogg", "kenney-impact/impactMetal_light_002.ogg"],
	"ui_click": ["kenney-interface/click_001.ogg", "kenney-interface/click_002.ogg"],
	"ui_focus": ["kenney-interface/select_001.ogg"],
}

static func variation_pitch() -> float:
	_ensure_rng()
	return _audio_rng.randf_range(0.94, 1.06)

static func _ensure_rng() -> void:
	if not _rng_ready:
		_audio_rng.randomize()
		_rng_ready = true

static func get_stream(kind: String) -> AudioStream:
	if SAMPLE_SETS.has(kind):
		_ensure_rng()
		var samples: Array = SAMPLE_SETS[kind]
		var index := _audio_rng.randi_range(0, samples.size() - 1)
		if samples.size() > 1 and _last_sample.get(kind, -1) == index:
			index = (index + 1 + _audio_rng.randi_range(0, samples.size() - 2)) % samples.size()
		_last_sample[kind] = index
		var path: String = "res://assets/audio/" + samples[index]
		if not _cache.has(path) and ResourceLoader.exists(path):
			_cache[path] = load(path)
		if _cache.get(path) is AudioStream:
			return _cache[path]
	if not _cache.has(kind):
		_cache[kind] = _generate(kind)
	return _cache[kind]

## Fire a transient positional one-shot at `pos`, parented under `host`, and
## free it when done. For objective action sounds (barks, beeps, clatter).
static func play_at(host: Node, pos: Vector3, kind: String, max_dist: float = 20.0, volume: float = 0.0, pitch: float = 1.0) -> void:
	ensure_buses()
	var p := AudioStreamPlayer3D.new()
	p.bus = EFFECTS_BUS
	p.stream = get_stream(kind)
	p.max_distance = max_dist
	p.volume_db = volume
	p.pitch_scale = pitch
	host.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	if kind == "shuffle":
		# Round off the onset and tail so fabric reads as a drag, not a heel strike.
		var duration := minf(p.stream.get_length() / pitch, 0.55)
		var fade := minf(0.06, duration * 0.25)
		p.volume_db = volume - 30.0
		var envelope := p.create_tween()
		envelope.tween_property(p, "volume_db", volume, fade)
		envelope.tween_interval(maxf(0.0, duration - fade * 2.0))
		envelope.tween_property(p, "volume_db", volume - 30.0, fade)
		envelope.tween_callback(p.queue_free)

static func _generate(kind: String) -> AudioStreamWAV:
	_ensure_rng()
	match kind:
		"hum": return _to_wav(_hum(), true)
		"heartbeat": return _to_wav(_heartbeat(), true)
		"creak": return _to_wav(_creak(), false)
		"sting": return _to_wav(_sting(), false)
		"screech": return _to_wav(_screech(), false)
		"zipper": return _to_wav(_zipper(), false)
		"beep": return _to_wav(_beep(), false)
		"bark": return _to_wav(_bark(), false)
		"clatter": return _to_wav(_clatter(), false)
		"shush": return _to_wav(_shush(), false)
		"breath": return _to_wav(_breath(), true)
		"tape": return _to_wav(_tape(), false)
		"thump": return _to_wav(_thump(), false)
		"pop": return _to_wav(_pop(), false)
		"shuffle": return _to_wav(_zipper(), false)
		_: return _to_wav(_click(), false)

# ── Generators (all return mono float samples in [-1, 1]) ─────────────────

static func _hum() -> PackedFloat32Array:
	# A slow, almost-melodic two-note drone: something humming a lullaby.
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 82.0 if fmod(t, 4.0) < 2.0 else 98.0
		var lfo := 0.75 + 0.25 * sin(TAU * 0.7 * t)
		out[i] = (sin(TAU * f * t) * 0.55 + sin(TAU * f * 2.0 * t) * 0.18) * lfo * 0.5
	return out

static func _heartbeat() -> PackedFloat32Array:
	var n := int(RATE * 0.95)
	var out := PackedFloat32Array()
	out.resize(n)
	for beat_at: float in [0.0, 0.32]:
		var start := int(beat_at * RATE)
		for i in range(int(RATE * 0.16)):
			var t := float(i) / RATE
			var idx := start + i
			if idx < n:
				out[idx] += sin(TAU * 52.0 * t) * exp(-t * 26.0) * 0.9
	return out

static func _creak() -> PackedFloat32Array:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(340.0, 170.0, t) * (1.0 + _audio_rng.randf_range(-0.06, 0.06))
		phase += f / RATE
		var saw := 2.0 * fmod(phase, 1.0) - 1.0
		out[i] = (saw * 0.5 + _audio_rng.randf_range(-0.3, 0.3)) * sin(PI * t) * 0.4
	return out

static func _sting() -> PackedFloat32Array:
	var n := int(RATE * 1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 2.2)
		out[i] = (sin(TAU * 392.0 * t) + sin(TAU * 415.3 * t) + sin(TAU * 196.0 * t)) * env * 0.28
	return out

static func _screech() -> PackedFloat32Array:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(1300.0, 260.0, t) / RATE
		var saw := 2.0 * fmod(phase, 1.0) - 1.0
		out[i] = saw * sin(PI * minf(t * 3.0, 1.0)) * 0.55
	return out

static func _zipper() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in 28:
		var start := int((float(c) / 28.0) * 0.42 * RATE)
		for i in 40:
			if start + i < n:
				out[start + i] += _audio_rng.randf_range(-0.8, 0.8) * exp(-float(i) * 0.12)
	return out

static func _click() -> PackedFloat32Array:
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = _audio_rng.randf_range(-0.9, 0.9) * exp(-float(i) * 0.01)
	return out

static func _thump() -> PackedFloat32Array:
	# A full can of dog food hitting carpet: a heavy dead thud, all body and no
	# snap. (`clatter` is the loose metallic fuse rattle — wrong for a sealed tin.)
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 70.0 * (1.0 - t * 0.6) * t) * exp(-t * 18.0) * 0.85
	return out

static func _pop() -> PackedFloat32Array:
	# Party popper: an instant crack of noise, fast decay, tiny confetti fizz.
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var crack := _audio_rng.randf_range(-1.0, 1.0) * exp(-t * 30.0)
		var fizz := _audio_rng.randf_range(-0.2, 0.2) * exp(-t * 5.0)
		out[i] = clampf(crack + fizz, -1.0, 1.0) * 0.9
	return out

static func _beep() -> PackedFloat32Array:
	# Keypad beep — a hard square tone, loud and cheap.
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (1.0 if sin(TAU * 880.0 * t) > 0.0 else -1.0) * 0.45 * sin(PI * (float(i) / n))
	return out

static func _bark() -> PackedFloat32Array:
	# Dog bark — two rough noisy bursts with a downward pitch.
	var n := int(RATE * 0.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for burst_at: float in [0.0, 0.2]:
		var start := int(burst_at * RATE)
		for i in range(int(RATE * 0.14)):
			var t := float(i) / (RATE * 0.14)
			var idx := start + i
			if idx < n:
				phase += lerpf(420.0, 180.0, t) / RATE
				var saw := 2.0 * fmod(phase, 1.0) - 1.0
				out[idx] += (saw * 0.6 + _audio_rng.randf_range(-0.35, 0.35)) * sin(PI * t) * 0.6
	return out

static func _shush() -> PackedFloat32Array:
	# "shhhh" — band-ish filtered noise that swells then fades. The Housesitter
	# telling you to go to sleep. Creepy-cute, not a scream.
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		var env := sin(PI * t)              # swell in, fade out
		var white := _audio_rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.35)     # crude low-pass → airy "shh", not hiss
		out[i] = (white - prev) * env * 0.5  # high-passed noise = breathy consonant
	return out

static func _breath() -> PackedFloat32Array:
	# Heavy, scared breathing heard from inside the bag: a slow in-out cycle of
	# band-passed noise (~4s loop). Two breaths per loop — inhale swell, exhale
	# fall — with a crude low-pass so it's airy, not hissy.
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var cyc := fmod(t, 2.0) / 2.0            # 0..1 per 2s breath
		# Inhale (rising) for the first 45%, exhale (falling) after — never silent.
		var env := (cyc / 0.45) if cyc < 0.45 else (1.0 - (cyc - 0.45) / 0.55)
		env = 0.15 + 0.85 * clampf(env, 0.0, 1.0)
		var white := _audio_rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.18)          # low-pass → breathy, not sharp
		out[i] = prev * env * 0.4
	return out

static func _tape() -> PackedFloat32Array:
	# Answering-machine tape: a mechanical *click*, then a bed of warbly tape hiss
	# with slow wow-and-flutter. No voice — the "message" is the transcript on screen.
	var n := int(RATE * 1.6)
	var out := PackedFloat32Array()
	out.resize(n)
	# Opening deck clunk.
	for i in range(int(RATE * 0.05)):
		out[i] = _audio_rng.randf_range(-0.9, 0.9) * exp(-float(i) * 0.02)
	var prev := 0.0
	for i in range(int(RATE * 0.06), n):
		var t := float(i) / RATE
		var env := clampf((t - 0.06) / 0.1, 0.0, 1.0) * clampf((1.6 - t) / 0.25, 0.0, 1.0)
		var white := _audio_rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.25)              # band-limited hiss
		var flutter := 0.5 + 0.5 * sin(TAU * 4.0 * t)  # wow/flutter warble
		out[i] = prev * env * 0.22 * (0.7 + 0.3 * flutter)
	return out

static func _clatter() -> PackedFloat32Array:
	# Fuse-box clatter — a burst of metallic clicks.
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in 9:
		var start := int(_audio_rng.randf_range(0.0, 0.42) * RATE)
		var f := _audio_rng.randf_range(900.0, 2200.0)
		for i in range(int(RATE * 0.05)):
			if start + i < n:
				out[start + i] += sin(TAU * f * float(i) / RATE) * exp(-float(i) * 0.02) * 0.5
	return out

static func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav
