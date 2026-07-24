extends Node
## Proximity voice chat. Autoload (stable RPC path across menu -> lobby -> game).
##
## Capture: the Steam voice API (startVoiceRecording / getVoice) — compression is
## Steam's problem, and the game ships on Steam. Push-to-talk V by default; an
## open-mic toggle lives in settings. Where there's no Steam (solo / the ENet
## loopback harness), `test_tone_mode` sends synthetic raw-PCM packets down the
## SAME RPC path so transport is provable headlessly — real audio just needs ears.
##
## Playback: Main registers an AudioStreamPlayer3D per remote peer, parented to
## that peer's ghost bag — proximity attenuation comes from the 3D mixer for free.
## A cocooned speaker's player is routed to the "InBag" low-pass bus (600 Hz):
## voice through fabric. The local player's own voice is never played back.
##
## The monster does NOT hear voice. Design law: talking is the co-op glue and must
## always feel safe; hops and zippers are the noise economy, not your friends.

signal speaking_changed(pid: int, talking: bool)

const PTT_KEY := KEY_V
const SPEAK_HOLD := 0.4          ## secs an indicator lingers after the last packet
const TONE_INTERVAL := 0.1       ## test mode: synthetic packet cadence
const TONE_HZ := 440.0
const RAW_RATE := 24000          ## sample rate for raw (non-Steam) test packets

# Occlusion: voice through a wall/floor is MUFFLED, never muted — hearing a friend's
# panic through the floorboards is the good version of this. Only the clarity is wrong.
const OCCLUDED_BUS := "VoiceOccluded"
const OCCLUDED_CUTOFF := 1400.0  ## Hz — "through a wall" (InBag's 600Hz is "inside a bag")
const OCCLUDED_DB := -6.0
const OCCLUSION_INTERVAL := 0.15 ## secs between LOS checks (only for peers actually talking)

var enabled: bool = true         ## settings master switch
var open_mic: bool = false       ## false = push-to-talk (V)
var voice_range: float = 20.0    ## AudioStreamPlayer3D max_distance (set by Main)

# Proximity voice loudness. unit_size is the radius (m) at which the voice is at
# full volume before falloff starts — big enough that a room-sized conversation
# stays comfortable, small enough that distance still means something.
const VOICE_UNIT_SIZE := 6.0
const VOICE_VOLUME_DB := 6.0
var test_tone_mode: bool = false ## loopback harness: send tone packets, no mic

# Stats the selftest asserts on (headless can't hear, but it can count).
var stat_rx_packets: int = 0
var stat_frames_pushed: int = 0

var _recording: bool = false
var _sample_rate: int = RAW_RATE
var _rate_queried: bool = false
var _tone_cd: float = 0.0
var _tone_phase: float = 0.0
var _players: Dictionary = {}    ## pid -> AudioStreamPlayer3D
var _playbacks: Dictionary = {}  ## pid -> AudioStreamGeneratorPlayback (may be null headless)
var _speak_t: Dictionary = {}    ## pid -> countdown until "stopped talking"
var _cocooned: Dictionary = {}   ## pid -> bool (zipped in: the tightest muffle)
var _occluded: Dictionary = {}   ## pid -> bool (no line of sight: wall/floor between us)
var _occl_cd: float = 0.0

signal mic_mode_changed(open_mic: bool)

func _ready() -> void:
	_ensure_occluded_bus()
	# Mic prefs persist (Scrapbook autoloads before this one).
	enabled = Scrapbook.voice_enabled
	open_mic = Scrapbook.voice_open_mic

## Push-to-talk <-> open mic. Persists, and announces so HUD/settings stay in sync
## no matter which one flipped it.
func set_open_mic(v: bool) -> void:
	if v == open_mic:
		return
	open_mic = v
	Scrapbook.voice_open_mic = v
	Scrapbook.save_game()
	mic_mode_changed.emit(v)

func toggle_open_mic() -> void:
	set_open_mic(not open_mic)

func set_enabled(v: bool) -> void:
	if v == enabled:
		return
	enabled = v
	Scrapbook.voice_enabled = v
	Scrapbook.save_game()
	mic_mode_changed.emit(open_mic)

## "OPEN MIC" / "PUSH-TO-TALK (V)" / "VOICE OFF" — for HUD + settings labels.
func mic_mode_text() -> String:
	if not enabled:
		return "VOICE OFF"
	return "OPEN MIC" if open_mic else "PUSH-TO-TALK (V)"

func _process(delta: float) -> void:
	_update_capture(delta)
	_update_occlusion(delta)
	# Tick down speaking indicators.
	for pid: int in _speak_t.keys():
		_speak_t[pid] -= delta
		if _speak_t[pid] <= 0.0:
			_speak_t.erase(pid)
			speaking_changed.emit(pid, false)

# ── Occlusion: walls and floors muffle voice ───────────────────────────────

func _ensure_occluded_bus() -> void:
	if AudioServer.get_bus_index(OCCLUDED_BUS) != -1:
		return
	var idx := AudioServer.get_bus_count()
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, OCCLUDED_BUS)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, OCCLUDED_DB)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = OCCLUDED_CUTOFF
	AudioServer.add_bus_effect(idx, lp)

## True when world geometry (mask 1 = slabs + walls) sits between the two points.
## Same raycast pattern the monster uses for sight (Monster._los_to).
func is_occluded_between(from: Vector3, to: Vector3) -> bool:
	var world := get_viewport().world_3d if get_viewport() != null else null
	if world == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not world.direct_space_state.intersect_ray(q).is_empty()

## Re-check line of sight to whoever is actually TALKING (throttled — at most a
## handful of rays a second, and only while someone speaks).
func _update_occlusion(delta: float) -> void:
	_occl_cd -= delta
	if _occl_cd > 0.0:
		return
	_occl_cd = OCCLUSION_INTERVAL
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return  # menu / headless: nothing to listen from
	var ear := cam.global_position
	for pid: int in _players:
		if not _speak_t.has(pid):
			continue
		var p: AudioStreamPlayer3D = _players[pid]
		if not is_instance_valid(p):
			continue
		var blocked := is_occluded_between(ear, p.global_position)
		if blocked != bool(_occluded.get(pid, false)):
			_occluded[pid] = blocked
			_apply_bus(pid)

## Fabric beats walls: a cocooned speaker always gets the tightest muffle.
func _apply_bus(pid: int) -> void:
	var p: AudioStreamPlayer3D = _players.get(pid)
	if p == null or not is_instance_valid(p):
		return
	if bool(_cocooned.get(pid, false)):
		p.bus = "InBag"
	elif bool(_occluded.get(pid, false)):
		p.bus = OCCLUDED_BUS
	else:
		p.bus = "Master"

# ── Capture / send ─────────────────────────────────────────────────────────

func _update_capture(delta: float) -> void:
	var want := enabled and _net_ok() and (open_mic or Input.is_key_pressed(PTT_KEY))
	if SteamManager.steam_ok:
		if want and not _recording:
			if not _rate_queried:
				_rate_queried = true
				var r: int = Steam.getVoiceOptimalSampleRate()
				if r > 0:
					_sample_rate = r
			Steam.startVoiceRecording()
			_recording = true
		elif not want and _recording:
			Steam.stopVoiceRecording()
			_recording = false
		if _recording:
			var avail: Dictionary = Steam.getAvailableVoice()
			if int(avail.get("result", 1)) == Steam.VOICE_RESULT_OK:
				var v: Dictionary = Steam.getVoice()
				var buf: PackedByteArray = v.get("buffer", PackedByteArray())
				var written := int(v.get("written", buf.size()))
				if written > 0:
					_rx_voice.rpc(buf.slice(0, written), false)
	elif test_tone_mode and want:
		# No Steam: prove the transport with a synthetic s16 tone packet.
		_tone_cd -= delta
		if _tone_cd <= 0.0:
			_tone_cd = TONE_INTERVAL
			_rx_voice.rpc(_make_tone(TONE_INTERVAL), true)

func _make_tone(secs: float) -> PackedByteArray:
	var n := int(RAW_RATE * secs)
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		_tone_phase += TONE_HZ / RAW_RATE
		out.encode_s16(i * 2, int(sin(TAU * _tone_phase) * 12000.0))
	return out

# ── Receive / playback ─────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "unreliable")
func _rx_voice(data: PackedByteArray, raw: bool) -> void:
	# Sender identity comes from the transport, never from packet contents.
	_handle_voice(multiplayer.get_remote_sender_id(), data, raw)

## Also called directly by the selftest (bypassing the network) with a fake pid.
func _handle_voice(pid: int, data: PackedByteArray, raw: bool) -> void:
	if not enabled or data.is_empty():
		return
	stat_rx_packets += 1
	if test_tone_mode and stat_rx_packets % 20 == 1:
		print("[NETTEST] voice rx from %d (%d pkts, %d frames)" % [
			pid, stat_rx_packets, stat_frames_pushed])
	var pcm: PackedByteArray
	if raw:
		pcm = data
	else:
		var d: Dictionary = Steam.decompressVoice(data, _sample_rate)
		if int(d.get("result", 1)) != Steam.VOICE_RESULT_OK:
			return
		pcm = d.get("uncompressed", PackedByteArray())
	# Speaking indicator (fires even if this peer has no bound body yet).
	if not _speak_t.has(pid):
		speaking_changed.emit(pid, true)
	_speak_t[pid] = SPEAK_HOLD
	# Push frames into the peer's positional generator.
	var pb: AudioStreamGeneratorPlayback = _playbacks.get(pid)
	if pb == null:
		return
	var frames := PackedVector2Array()
	var count := mini(pcm.size() >> 1, pb.get_frames_available())
	frames.resize(count)
	for i in count:
		var s := pcm.decode_s16(i * 2) / 32768.0
		frames[i] = Vector2(s, s)
	if count > 0:
		pb.push_buffer(frames)
		stat_frames_pushed += count

# ── Binding voices to bodies (Main calls these) ────────────────────────────

## Attach a positional voice emitter for `pid` under `parent` (their ghost bag).
func register_player(pid: int, parent: Node3D) -> void:
	unregister_player(pid)
	var p := AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(_sample_rate if SteamManager.steam_ok else RAW_RATE)
	gen.buffer_length = 0.2
	p.stream = gen
	# Setting only max_distance left everything else on Godot's defaults, where
	# unit_size 10 + inverse-distance falloff makes a voice near-silent long
	# before max_distance — playtest read as "we had to be right on top of each
	# other". Speech needs a flat-ish core out to conversational range and then a
	# quick drop, so: bigger unit_size, a lift on the bus level, and INVERSE_SQUARE
	# swapped for plain INVERSE so the tail doesn't collapse.
	p.max_distance = voice_range
	p.unit_size = VOICE_UNIT_SIZE
	p.volume_db = VOICE_VOLUME_DB
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.position = Vector3(0, 0.7, 0)  # mouth height on a 0.9m bag
	parent.add_child(p)
	p.play()
	_players[pid] = p
	_playbacks[pid] = p.get_stream_playback()  # null under the dummy audio driver

func unregister_player(pid: int) -> void:
	if _players.has(pid):
		var p: AudioStreamPlayer3D = _players[pid]
		if is_instance_valid(p):
			p.queue_free()
		_players.erase(pid)
		_playbacks.erase(pid)
	_cocooned.erase(pid)
	_occluded.erase(pid)
	if _speak_t.has(pid):
		_speak_t.erase(pid)
		speaking_changed.emit(pid, false)

func unregister_all() -> void:
	for pid: int in _players.keys().duplicate():
		unregister_player(pid)

## Cocooned speaker -> route through the InBag low-pass (voice through fabric).
## Resolved against occlusion by _apply_bus, so the two can't fight each other.
func set_muffled(pid: int, muffled: bool) -> void:
	_cocooned[pid] = muffled
	_apply_bus(pid)

func is_speaking(pid: int) -> bool:
	return _speak_t.has(pid)

func speaking_pids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _speak_t:
		out.append(pid)
	out.sort()
	return out

func registered_count() -> int:
	return _players.size()

# ── Helpers ────────────────────────────────────────────────────────────────

func _net_ok() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and multiplayer.get_peers().size() > 0
