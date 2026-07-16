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
##   click     — rotary phone dial

const RATE := 22050

static var _cache: Dictionary = {}

static func get_stream(kind: String) -> AudioStreamWAV:
	if not _cache.has(kind):
		_cache[kind] = _generate(kind)
	return _cache[kind]

static func _generate(kind: String) -> AudioStreamWAV:
	match kind:
		"hum": return _to_wav(_hum(), true)
		"heartbeat": return _to_wav(_heartbeat(), true)
		"creak": return _to_wav(_creak(), false)
		"sting": return _to_wav(_sting(), false)
		"screech": return _to_wav(_screech(), false)
		"zipper": return _to_wav(_zipper(), false)
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
