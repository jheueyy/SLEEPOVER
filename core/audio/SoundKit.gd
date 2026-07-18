class_name SoundKit
extends Object
## Procedurally generated placeholder audio — no asset files, everything is
## synthesized once at first use and cached. Real sound design replaces these
## stream-by-stream in the art pass; every consumer just calls get_stream().
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

static var _cache: Dictionary = {}

static func get_stream(kind: String) -> AudioStreamWAV:
	if not _cache.has(kind):
		_cache[kind] = _generate(kind)
	return _cache[kind]

## Fire a transient positional one-shot at `pos`, parented under `host`, and
## free it when done. For objective action sounds (barks, beeps, clatter).
static func play_at(host: Node, pos: Vector3, kind: String, max_dist: float = 20.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(kind)
	p.max_distance = max_dist
	host.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

static func _generate(kind: String) -> AudioStreamWAV:
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
		var f := lerpf(340.0, 170.0, t) * (1.0 + randf_range(-0.06, 0.06))
		phase += f / RATE
		var saw := 2.0 * fmod(phase, 1.0) - 1.0
		out[i] = (saw * 0.5 + randf_range(-0.3, 0.3)) * sin(PI * t) * 0.4
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
				out[start + i] += randf_range(-0.8, 0.8) * exp(-float(i) * 0.12)
	return out

static func _click() -> PackedFloat32Array:
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = randf_range(-0.9, 0.9) * exp(-float(i) * 0.01)
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
				out[idx] += (saw * 0.6 + randf_range(-0.35, 0.35)) * sin(PI * t) * 0.6
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
		var white := randf_range(-1.0, 1.0)
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
		var white := randf_range(-1.0, 1.0)
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
		out[i] = randf_range(-0.9, 0.9) * exp(-float(i) * 0.02)
	var prev := 0.0
	for i in range(int(RATE * 0.06), n):
		var t := float(i) / RATE
		var env := clampf((t - 0.06) / 0.1, 0.0, 1.0) * clampf((1.6 - t) / 0.25, 0.0, 1.0)
		var white := randf_range(-1.0, 1.0)
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
		var start := int(randf_range(0.0, 0.42) * RATE)
		var f := randf_range(900.0, 2200.0)
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
