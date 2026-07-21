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

var enabled: bool = true         ## settings master switch
var open_mic: bool = false       ## false = push-to-talk (V)
var voice_range: float = 14.0    ## AudioStreamPlayer3D max_distance (set by Main)
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

func _process(delta: float) -> void:
	_update_capture(delta)
	# Tick down speaking indicators.
	for pid: int in _speak_t.keys():
		_speak_t[pid] -= delta
		if _speak_t[pid] <= 0.0:
			_speak_t.erase(pid)
			speaking_changed.emit(pid, false)

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
	p.max_distance = voice_range
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
	if _speak_t.has(pid):
		_speak_t.erase(pid)
		speaking_changed.emit(pid, false)

func unregister_all() -> void:
	for pid: int in _players.keys().duplicate():
		unregister_player(pid)

## Cocooned speaker -> route through the InBag low-pass (voice through fabric).
func set_muffled(pid: int, muffled: bool) -> void:
	var p: AudioStreamPlayer3D = _players.get(pid)
	if p != null and is_instance_valid(p):
		p.bus = "InBag" if muffled else "Master"

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
