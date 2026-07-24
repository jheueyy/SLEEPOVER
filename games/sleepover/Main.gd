extends Node3D
## Sleepover game scene: one complete playable round, host-authoritative.
##   LOBBY -> LIGHTS OUT (10s) -> ROUND (10 min) -> RESULTS -> LOBBY
## Endings: ESCAPE (landline + front door), SUNRISE (timer survives),
## LOSS (everyone cocooned). The house builds from maps/house_suburban data;
## this script owns actors, camera, HUD, round flow, interaction, audio, and
## the 20Hz net sync. The monster is senses-only: Main feeds it targets and
## handles the consequences (cocooning) — it never reads positions itself.

enum Phase { LOBBY, LIGHTS_OUT, ROUND, RESULTS }

@export_group("Round")
@export var lights_out_duration: float = 10.0
@export var round_duration: float = 600.0   ## 10 minute night
@export var spawn_stair_clearance: float = 3.0  ## monster won't spawn this close to a staircase
@export var fragment_spawn_min: int = 3      ## lore fragments seeded per round (min)
@export var fragment_spawn_max: int = 4      ## …and max; host rolls a count in [min,max]
@export var outro_duration: float = 6.0      ## sunrise / all-cocooned bookend length (<=10s)

@export_group("Camera")
@export var cam_height: float = 0.9
@export var cam_distance: float = 2.2
@export var cam_shoulder: float = 0.35
@export var mouse_sensitivity: float = 0.004
@export var cam_pitch_default: float = -6.0
@export var fov_base: float = 70.0
@export var fov_chase: float = 82.0
@export var chase_range: float = 8.0

@export_group("Rescue")
@export var rescue_range: float = 1.9
@export var rescue_time: float = 5.0
@export var rescue_zipper_at: float = 3.0   ## the loud zipper ping mid-rescue
@export var zipper_loudness: float = 0.9
@export var unzip_secs: float = 1.2         ## hold-E time to unzip & grab a clue/item
@export var unzip_chase_penalty: float = 1.0 ## +time while the monster is chasing (panic fumble)
@export var unzip_loudness: float = 0.85     ## the loud RRRIP the unzip broadcasts

@export_group("Voice")
@export var voice_range: float = 20.0        ## proximity voice falloff (m); monster never hears voice

var _player: SleepingBagPlayer
var _monster: NoiseMonster
var _cam_pivot: Node3D
var _cam_pitch: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _lookback: float = 0.0
var _cocoon_cam: float = 0.0   ## 0 = normal chase cam, 1 = snapped inside the bag
var _porch_light: OmniLight3D  ## flickers during the 10s intro, then dies
var _porch_dying: bool = false
var _aim: MeshInstance3D

# HUD
var _state_label: Label
var _net_label: Label
var _toast: Label
var _clock_label: Label
var _prompt_label: Label
var _tracker_label: Label
var _debug_label: Label
var _voice_label: Label   ## "🗣 name, name" while peers talk
var _mic_label: Label     ## "MIC: PUSH-TO-TALK (V)" / "OPEN MIC" / "VOICE OFF"
var _pips: Array[ColorRect] = []
var _cocoon_overlay: Control
var _cocoon_text: Label
var _shush_ui: AudioStreamPlayer
var _breathing: AudioStreamPlayer   ## heavy in-bag breathing loop (cocooned)
const INBAG_BUS := "InBag"
var _results_overlay: Control
var _results_label: Label
# Outro bookends (sunrise / all-tucked-in): a short overlay over the results.
var _outro_overlay: ColorRect
var _outro_label: Label
var _outro_active: bool = false
var _outro_t: float = 0.0
var _phone_panel: PanelContainer
var _phone_label: Label

# Round state
var phase: Phase = Phase.LOBBY
var _phase_timer: float = 0.0
var _round_elapsed: float = 0.0
# Host-side per-player round stats for the recap awards. Fed from hooks the host
# ALREADY receives (cocoon/rescue/fragment/escape/noise) — no new RPCs; it rides
# along in the RESULTS payload _host_end_round already sends.
var _round_stats: Dictionary = {}
var _cocoon_counter: int = 0
# Cocooned spectator cam: -1 = your own (fabric-dark) view. Opt-in via TAB so the
# claustrophobic cocoon beat stays the default, but you're never stuck staring at
# fabric for minutes waiting on a rescue that isn't coming.
var _spectating: int = -1
var _objectives: Array[Objective] = []   ## the 5 active this round
var _done_ids: Array[String] = []        ## objective ids completed (need 3)
var _escape_armed: bool = false
# Which objective unlocks which exit. The escape PHASE arms at 3-of-5, but a
# given door only opens once ITS objective is completed. With only two support
# objectives (deadbolt, glasses), any 3 completions guarantee ≥1 door opens, so
# every 5-of-6 draw is winnable. Exit names must match HouseSuburban.EXITS.
const EXIT_OBJECTIVE := {
	"FRONT DOOR": "landline",
	"BACK DOOR": "dog",           # the dog has the keys to the deadbolted back door
	"GARAGE": "garage_code",
	"BASEMENT WINDOW": "breaker", # the breaker powers the basement egress
}
var _blurred_pid: int = 0                 ## glasses: whose screen is blurred (0 = nobody)
var _rescue_target: Node3D = null
var _rescue_t: float = 0.0
var _rescue_zipped: bool = false
var _debug_visible: bool = false
var _monster_fx_state: int = -1
# Unzip channel: grabbing a clue/item means unzipping the bag — a hold-E channel
# that takes time and broadcasts a loud RRRIP. Panic-fumbles (+time) in a chase.
var _unzip_target: Objective = null
var _unzip_frag: Fragment = null   ## a lore fragment being unzipped (vs an objective grab)
var _unzip_t: float = 0.0
var _unzip_dur: float = 0.0
var _unzip_panic: bool = false
const PROMPT_POS := Vector2(-260, -110)
# Lore fragments (this round)
var _fragments: Array[Fragment] = []
var _frag_collected_ids: Array[String] = []   ## host: ids already claimed this round
var _frag_spawned: int = 0                     ## how many were seeded this round
var _frag_panel: Control
var _frag_title: Label
var _frag_body: Label
var _frag_panel_t: float = 0.0
var _tape_ui: AudioStreamPlayer

# Glasses blur (post-process on the one blurred player)
var _blur_overlay: ColorRect

# Audio
var _heartbeat: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _zip_sound: AudioStreamPlayer

# Networking: each peer simulates its OWN bag; remote bags are ghosts.
var _remote_bags: Dictionary = {}     ## peer_id -> Node3D ghost
var _ghost_targets: Dictionary = {}   ## peer_id -> [pos, rot]
var _ghost_eyes: Dictionary = {}      ## peer_id -> BagEyes
var _ghost_mood: Dictionary = {}      ## peer_id -> synced eye mood (int)
var _monster_target: Vector3
var _has_monster_target: bool = false
var _net_accum: float = 0.0
var _clock_accum: float = 0.0

const NET_SEND_INTERVAL := 0.05
const GHOST_LERP := 10.0
const PIP_ON := Color(1.0, 0.85, 0.25)
const PIP_OFF := Color(0.25, 0.25, 0.28)
const FLAG_COCOONED := 1
const FLAG_HIDDEN := 2

func _ready() -> void:
	_build_environment()
	_build_level()
	_spawn_actors()
	_build_camera()
	_build_hud()
	_build_audio()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	multiplayer.peer_connected.connect(func(_pid: int) -> void: _update_net_label())
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	NoiseBus.noise_emitted.connect(_on_local_noise)
	_update_net_label()
	_enter_lobby()

	if OS.get_cmdline_user_args().has("--selftest"):
		call_deferred("_run_selftest")

# Deterministic solo acceptance harness: exercises all three endings and the
# hide/ping logic without a second player or the stochastic live chase.
func _run_selftest() -> void:
	var pass_all := true
	# SANDBOX the player's save for the WHOLE harness, before anything runs. Several
	# groups end rounds, and a round-end banks career stats through Scrapbook — so
	# this has to be the first thing that happens or the tests quietly write to the
	# player's real save (which is exactly the bug 515850d fixed for fragments).
	Scrapbook.use_test_path("user://selftest_scrapbook.save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://selftest_scrapbook.save"))
	Scrapbook.collected = []
	Scrapbook.selected_skin = 0
	Scrapbook.voice_enabled = true
	Scrapbook.voice_open_mic = false
	Scrapbook.career_rounds = 0
	Scrapbook.career_tumbles = 0
	Scrapbook.career_rescues = 0
	Scrapbook.career_fragments = 0
	VoiceManager.open_mic = false

	# 1. OBJECTIVES + ESCAPE. 5 spawn; every door starts locked; completing 3 arms
	#    the phase, and a door only opens once ITS objective is done. We escape
	#    through the door that the completed objective actually unlocked.
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	var ok_count := _objectives.size() == 5
	var all_locked := _exit_door_locked("front_door") and _exit_door_locked("back_door") \
		and _exit_door_locked("garage_door")
	# Exit A: complete a drawn door-objective (+ fill to 3), escape through it.
	var exit_a := _selftest_arm_via_door()
	var ok_armed := _escape_armed and exit_a != "" and _exit_is_open(exit_a)
	var ok_exit_a := _selftest_escape_via(exit_a)
	# Exit B: a fresh armed round through another opened door.
	_apply_phase(Phase.LOBBY, {})
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	var exit_b := _selftest_arm_via_door()
	var ok_exit_b := _selftest_escape_via(exit_b)
	print("[SELFTEST] objectives: 5spawn=%s all-locked=%s 3done-arms(%s)=%s exitA(%s)=%s exitB(%s)=%s" % [
		ok_count, all_locked, exit_a, ok_armed, exit_a, ok_exit_a, exit_b, ok_exit_b])
	pass_all = pass_all and ok_count and all_locked and ok_armed and ok_exit_a and ok_exit_b

	# 2. SUNRISE. Round with the timer already run out and a survivor.
	_apply_phase(Phase.LOBBY, {})
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	_phase_timer = 0.01
	_update_phase(0.02)
	var ok_sunrise := phase == Phase.RESULTS and _results_label.text.contains("SUNRISE")
	print("[SELFTEST] sunrise: timer-out with survivor -> SUNRISE=%s" % ok_sunrise)
	pass_all = pass_all and ok_sunrise

	# 3. LOSS. Everyone cocooned.
	_apply_phase(Phase.LOBBY, {})
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	_cocoon_local()
	_update_phase(0.02)
	var ok_loss := phase == Phase.RESULTS and _results_label.text.contains("TUCKED IN")
	print("[SELFTEST] loss: all cocooned -> LOSS=%s" % ok_loss)
	pass_all = pass_all and ok_loss

	# 4. HIDING. The sight + lunge loops both gate on _flag(t,"hidden"); a hidden
	# player is excluded from detection (only a ping into the room reveals them).
	_apply_phase(Phase.LOBBY, {})
	_apply_phase(Phase.ROUND, {})
	_player.hidden = true
	var hidden_excluded := _monster._flag(_player, "hidden")
	_player.hidden = false
	var visible_again := not _monster._flag(_player, "hidden")
	print("[SELFTEST] hiding: excluded while hidden=%s, detectable after=%s" % [hidden_excluded, visible_again])
	pass_all = pass_all and hidden_excluded and visible_again

	# 5. DIAL INPUT. Both the number row and the numeric keypad must map to
	# digits; everything else must be ignored.
	var row_ok := true
	var kp_ok := true
	for d in 10:
		row_ok = row_ok and _keycode_to_digit(KEY_0 + d) == d
		kp_ok = kp_ok and _keycode_to_digit(KEY_KP_0 + d) == d
	var reject_ok := _keycode_to_digit(KEY_A) == -1 and _keycode_to_digit(KEY_SPACE) == -1
	print("[SELFTEST] dial input: numberrow=%s keypad=%s rejects-others=%s" % [row_ok, kp_ok, reject_ok])
	pass_all = pass_all and row_ok and kp_ok and reject_ok

	# 6. GLASSES. Solo (this harness has no peer): the blur must NOT show — the
	# handicap needs teammates — but the glasses objective still completes.
	_apply_phase(Phase.LOBBY, {})
	_apply_phase(Phase.LIGHTS_OUT, {"objs": [{"id": "glasses", "clue": 0}], "blurred": 1})
	_apply_phase(Phase.ROUND, {})
	var no_blur_solo := not _blur_overlay.visible
	var glasses_completes := false
	_authoritative_complete("glasses")
	glasses_completes = _done_ids.has("glasses") and not _blur_overlay.visible
	print("[SELFTEST] glasses: solo unblurred=%s, still completable=%s" % [no_blur_solo, glasses_completes])
	pass_all = pass_all and no_blur_solo and glasses_completes

	# 7. RANDOMIZATION. Two rounds should not spawn the identical clue layout
	# every time (spot check: object id set or a clue index differs across rolls).
	var layouts := {}
	for _r in 6:
		_apply_phase(Phase.LOBBY, {})
		_host_start_round()
		var sig := ""
		for o: Objective in _objectives:
			sig += "%s%d," % [o.def.id, o.seed.get("clue", -1)]
		layouts[sig] = true
	var ok_varied := layouts.size() >= 2
	print("[SELFTEST] randomization: %d distinct layouts across 6 rolls" % layouts.size())
	pass_all = pass_all and ok_varied

	# 8. TRACKER TWO-STAGE REVEAL. A code objective hides its detail until the
	# clue is read; a no-secret objective shows its detail from the start; the
	# reveal syncs (via _apply_reveal); and no tracker line ever names a location.
	_apply_phase(Phase.LOBBY, {})
	_apply_phase(Phase.LIGHTS_OUT, {"objs": [
		{"id": "landline", "clue": 0, "code": "5521"},
		{"id": "deadbolt"}], "blurred": 0})
	_apply_phase(Phase.ROUND, {})
	var landline: Objective = _objectives[0]
	var deadbolt: Objective = _objectives[1]
	var code_secret := not landline.is_revealed()  # detail hidden until clue read
	var deadbolt_open := deadbolt.is_revealed()    # no secret -> shown from start
	_apply_reveal("landline")
	var revealed_after := landline.is_revealed() and landline.tracker_detail().contains("5 5 2 1")
	# WHERE-check: the built tracker text must not leak any spawn coordinate.
	_update_tracker()
	var no_location := not _tracker_label.text.to_lower().contains("vector") \
		and not _tracker_label.text.contains(str(int(HouseSuburban.CLUE_SPOTS[0].x * HouseSuburban.S)))
	print("[SELFTEST] tracker: code-hidden=%s no-secret-shown=%s reveals=%s no-location=%s" % [
		code_secret, deadbolt_open, revealed_after, no_location])
	pass_all = pass_all and code_secret and deadbolt_open and revealed_after and no_location

	# 9. EYE-STATES. The bag's mood maps deterministically from its state.
	_player.respawn()
	var idle_ok := _player.eye_mood() == BagEyes.Mood.IDLE
	_player.stamina = 0.0
	var droop_ok := _player.eye_mood() == BagEyes.Mood.DROOP
	_player.stamina = _player.stamina_max
	_player.hidden = true
	var shut_ok := _player.eye_mood() == BagEyes.Mood.SHUT
	_player.hidden = false
	_player.cocoon()
	var sleepy_ok := _player.eye_mood() == BagEyes.Mood.SLEEPY
	_player.respawn()
	print("[SELFTEST] eye-states: idle=%s droop=%s shut=%s sleepy=%s" % [
		idle_ok, droop_ok, shut_ok, sleepy_ok])
	pass_all = pass_all and idle_ok and droop_ok and shut_ok and sleepy_ok

	# 10. FLOOR DISTRIBUTION. Over several rolls: the round's clues spread across
	# floors (<=2/floor, span >=2, >=1 upstairs), and the monster spawns clear of
	# the staircases (never camped on a chokepoint).
	var spread_ok := true
	var stair_ok := true
	for _r in 8:
		_apply_phase(Phase.LOBBY, {})
		_host_start_round()  # solo: computes spread + spawn, applies LIGHTS_OUT
		var counts := {HouseSuburban.Floor.BASEMENT: 0, HouseSuburban.Floor.GROUND: 0,
			HouseSuburban.Floor.UPSTAIRS: 0}
		for o: Objective in _objectives:
			if o.def.clue_spots.size() > 0 and o.seed.has("clue"):
				counts[HouseSuburban.floor_of(o.def.clue_spots[o.seed["clue"]].y)] += 1
		var used := 0
		var maxc := 0
		for f: int in counts:
			if counts[f] > 0: used += 1
			maxc = maxi(maxc, counts[f])
		if maxc > 2 or used < 2 or counts[HouseSuburban.Floor.UPSTAIRS] < 1:
			spread_ok = false
		if HouseSuburban.dist_to_nearest_stair(_monster.global_position) < spawn_stair_clearance:
			stair_ok = false
	print("[SELFTEST] floors: clue-spread(<=2, span, upstairs)=%s spawn-clear-of-stairs=%s" % [
		spread_ok, stair_ok])
	pass_all = pass_all and spread_ok and stair_ok

	# 11. LORE FRAGMENTS + SCRAPBOOK. Fragments spawn 3-4 at clue anchors; a claim
	# is once-per-lobby (duplicates ignored); collecting fills the Scrapbook, which
	# unlocks a skin and survives a save/load round-trip.
	Scrapbook.collected = []   # ignore whatever the earlier round-groups collected
	_apply_phase(Phase.LOBBY, {})
	_host_start_round()
	var frag_ok := _fragments.size() >= fragment_spawn_min and _fragments.size() <= fragment_spawn_max
	var first_id := _fragments[0].id() if not _fragments.is_empty() else ""
	_authoritative_collect_fragment(first_id, 1)
	_authoritative_collect_fragment(first_id, 1)  # duplicate — must be ignored
	var claim_ok := _collected_this_round() == 1 and _fragment_by_id(first_id).collected
	# Scrapbook (sandboxed): page 0 starts locked, completing it unlocks its skin,
	# and that survives a reload. Deterministic — we own this scratch file.
	var page0: Array = LoreFragments.PAGES[0]["fragments"]
	var page0_skin := int(LoreFragments.PAGES[0]["unlocks_skin"])
	Scrapbook.collected = []                       # clean slate, ignore the round's grab
	var pre_locked := not Scrapbook.is_skin_unlocked(page0_skin)
	for fid: String in page0:
		Scrapbook.collect(fid)
	var unlock_ok := Scrapbook.page_complete(0) and Scrapbook.is_skin_unlocked(page0_skin)
	Scrapbook.save_game()
	Scrapbook.collected = []
	Scrapbook.load_game()
	var persist_ok := Scrapbook.page_complete(0)   # reloaded from disk
	print("[SELFTEST] lore: spawn3-4=%s claim-once=%s skin-was-locked=%s unlock=%s persist=%s" % [
		frag_ok, claim_ok, pre_locked, unlock_ok, persist_ok])
	pass_all = pass_all and frag_ok and claim_ok and pre_locked and unlock_ok and persist_ok

	# 12. BASEMENT ON-FOOT WALKABILITY. Headless can't render, but it runs physics —
	# raycast the collision surfaces straight down the stair path and confirm a
	# CONTINUOUS descent from the garage floor (~y0) to the basement (~y−3), with no
	# gaps you'd fall through and no cliffs you can't step down. This is the check
	# the last two basement attempts lacked.
	var walk_ok := _probe_basement_walkable()
	pass_all = pass_all and walk_ok

	# 13. FLOOR-COVERAGE AUDIT. The basement bug was an anchor/route over a hole or
	# the void that no test caught. Raycast down at EVERY spawn + objective anchor +
	# clue spot and confirm solid floor at the expected height — so a clue can never
	# spawn where a player can't stand.
	var floor_ok := _audit_anchors_on_floor()
	pass_all = pass_all and floor_ok

	# 14. VOICE PLUMBING (no Steam needed). Synthetic raw PCM through the receive
	# path: packets count, the speaking indicator fires and clears, and
	# register/unregister doesn't leak players. Generator frames only push when the
	# audio driver provides a playback (headless dummy may not) — logged, not asserted.
	var talk_events: Array = []
	var talk_cb := func(pid: int, talking: bool) -> void: talk_events.append([pid, talking])
	VoiceManager.speaking_changed.connect(talk_cb)
	var vholder := Node3D.new()
	add_child(vholder)
	VoiceManager.register_player(999, vholder)
	var pkts0: int = VoiceManager.stat_rx_packets
	VoiceManager._handle_voice(999, VoiceManager._make_tone(0.05), true)
	VoiceManager._handle_voice(999, VoiceManager._make_tone(0.05), true)
	var rx_ok: bool = VoiceManager.stat_rx_packets == pkts0 + 2
	var talk_on: bool = VoiceManager.is_speaking(999) and talk_events.has([999, true])
	VoiceManager._process(1.0)  # expire the speak-hold
	var talk_off: bool = not VoiceManager.is_speaking(999) and talk_events.has([999, false])
	VoiceManager.unregister_player(999)
	var voice_clean: bool = VoiceManager.registered_count() == 0
	VoiceManager.speaking_changed.disconnect(talk_cb)
	vholder.queue_free()
	print("[SELFTEST] voice: rx=%s talk-on=%s talk-off=%s unregister-clean=%s (frames pushed: %d)" % [
		rx_ok, talk_on, talk_off, voice_clean, VoiceManager.stat_frames_pushed])
	pass_all = pass_all and rx_ok and talk_on and talk_off and voice_clean

	# 15. VOICE OCCLUSION. Voice must NOT carry cleanly through geometry — floors are
	# only 3m apart and voice_range is 14, so without this the basement is "3m away"
	# and reads as standing next to you, which kills the dread floor's isolation.
	var ear := HouseSuburban.scaled(Vector3(1.25, 0.9, 2.5))       # hall, ground floor
	var below := HouseSuburban.scaled(Vector3(-1.0, -2.4, -2.0))   # basement rec area
	var same_room := HouseSuburban.scaled(Vector3(-5.0, 0.9, 3.5)) # living room, open floor
	var ear2 := HouseSuburban.scaled(Vector3(-6.5, 0.9, 2.0))      # living room, same space
	var thru_floor := VoiceManager.is_occluded_between(ear, below)
	var open_room := VoiceManager.is_occluded_between(ear2, same_room)
	# Down the open stairwell shaft (just inside the basement door -> partway down the
	# flight): reported, not asserted — the shaft is full of treads, so whether it's a
	# clear shout is an emergent property of the geometry, not a promise.
	var shaft_top := HouseSuburban.scaled(Vector3(-0.25, 0.9, 4.6))
	var shaft_mid := HouseSuburban.scaled(Vector3(-0.25, -0.6, 2.2))  # head height ABOVE tread 5 (y-1.5)
	var shaft_clear := not VoiceManager.is_occluded_between(shaft_top, shaft_mid)
	var occl_ok := thru_floor and not open_room
	print("[SELFTEST] voice-occlusion: through-floor-blocked=%s same-room-clear=%s stairwell-clear=%s -> %s" % [
		thru_floor, not open_room, shaft_clear, occl_ok])
	pass_all = pass_all and occl_ok

	# 16. MIC MODE persists. A mic mode you must re-pick every launch is one you'll
	# come to hate — so it lives in the Scrapbook prefs and survives a reload.
	VoiceManager.toggle_open_mic()                          # false -> true
	var flipped: bool = VoiceManager.open_mic and Scrapbook.voice_open_mic
	Scrapbook.voice_open_mic = false                        # scramble, then reload from disk
	Scrapbook.load_game()
	var mic_persist: bool = Scrapbook.voice_open_mic == true
	print("[SELFTEST] mic-mode: toggles=%s persists-across-reload=%s" % [flipped, mic_persist])
	pass_all = pass_all and flipped and mic_persist

	# 17. AWARDS. Pure function of a stats dict — fully deterministic. Must pick the
	# right winners, break ties on the lowest pid so every machine renders the same
	# card, and OMIT awards nobody earned (never "Clutch Rescue — nobody").
	var s1 := Awards.blank_stats(); s1["tumbles"] = 5; s1["noise_pings"] = 9
	s1["noise_total"] = 6.0; s1["cocooned_order"] = 1
	var s2 := Awards.blank_stats(); s2["tumbles"] = 2; s2["noise_pings"] = 1
	s2["noise_total"] = 0.5; s2["rescues"] = 2; s2["fragments"] = 3; s2["escaped"] = true
	var s3 := Awards.blank_stats(); s3["tumbles"] = 5; s3["noise_pings"] = 4
	s3["noise_total"] = 2.0; s3["cocooned_order"] = 0
	var won := {}
	for a: Dictionary in Awards.compute({11: s1, 12: s2, 13: s3}):
		won[a["title"]] = a["pid"]
	var aw_falls: bool = won.get("MOST FALLS") == 11          # 5 vs 5 tie -> lowest pid
	var aw_loud: bool = won.get("LOUDEST ZIPPER") == 11
	var aw_resc: bool = won.get("CLUTCH RESCUE") == 12
	var aw_lore: bool = won.get("LORE HOUND") == 12
	var aw_quiet: bool = won.get("QUIET AS A MOUSE") == 12    # fewest pings
	var aw_first: bool = won.get("FIRST TUCKED IN") == 13     # order 0, not 1
	# Nobody rescued / collected / got caught -> those awards must not appear at all.
	var bare := Awards.blank_stats(); bare["noise_pings"] = 1; bare["noise_total"] = 0.2
	var bare2 := Awards.blank_stats(); bare2["noise_pings"] = 2; bare2["noise_total"] = 0.3
	var sparse := {}
	for a: Dictionary in Awards.compute({21: bare, 22: bare2}):
		sparse[a["title"]] = true
	var aw_omit: bool = not sparse.has("CLUTCH RESCUE") and not sparse.has("LORE HOUND") \
		and not sparse.has("FIRST TUCKED IN") and not sparse.has("MOST FALLS")
	var aw_fate: bool = Awards.fate_of(s2, "SUNRISE") == "escaped" \
		and Awards.fate_of(s3, "SUNRISE") == "tucked in" \
		and Awards.fate_of(bare, "SUNRISE") == "survived till sunrise"
	var awards_ok := aw_falls and aw_loud and aw_resc and aw_lore and aw_quiet \
		and aw_first and aw_omit and aw_fate
	print("[SELFTEST] awards: tie-by-pid=%s loud=%s rescue=%s lore=%s quiet=%s first=%s omit-unearned=%s fates=%s -> %s" % [
		aw_falls, aw_loud, aw_resc, aw_lore, aw_quiet, aw_first, aw_omit, aw_fate, awards_ok])
	pass_all = pass_all and awards_ok

	# 18. COCOONED SPECTATOR CAM. Opt-in only, and never available to a live player
	# (watching through a teammate's eyes mid-round would be an information exploit).
	_apply_phase(Phase.ROUND, {})
	var ghost := _spawn_remote_bag(4242)
	ghost.set_meta("cocooned", false)
	_player.rescue()                                  # alive: must NOT be able to spectate
	var spec_blocked := not _can_spectate()
	_cocoon_local()                                   # now cocooned
	var spec_allowed := _can_spectate()
	_toggle_spectate()
	var spec_on: bool = _spectating == 4242 and _spectate_target() == ghost
	_toggle_spectate()
	var spec_off: bool = _spectating == -1
	_toggle_spectate()                                # on again, then get rescued
	_player.rescue()
	var spec_auto_off: bool = _spectate_target() == null and _spectating == -1
	VoiceManager.unregister_player(4242)
	ghost.queue_free()
	_remote_bags.erase(4242)
	_ghost_targets.erase(4242)
	_ghost_eyes.erase(4242)
	_ghost_mood.erase(4242)
	var spec_ok := spec_blocked and spec_allowed and spec_on and spec_off and spec_auto_off
	print("[SELFTEST] spectate: blocked-while-alive=%s allowed-when-cocooned=%s on=%s off=%s auto-off-on-rescue=%s -> %s" % [
		spec_blocked, spec_allowed, spec_on, spec_off, spec_auto_off, spec_ok])
	pass_all = pass_all and spec_ok

	# 19. STAIRS ARE WALKABLE (real physics, no hops). THE regression test for the
	# playtest report "had to use all jumps to get up the stairs". A shuffling bag must
	# gain height on every flight while spending ZERO stamina, and must not slide back
	# down when you stop pushing.
	var stairs_ok := await _selftest_stairs()
	pass_all = pass_all and stairs_ok

	# 20. PLAYTEST REGRESSIONS. Five separate bugs from the first live 2-player
	# session, each of which passed every existing test while being broken in play.
	pass_all = _selftest_playtest_fixes() and pass_all
	pass_all = await _selftest_monster_containment() and pass_all

	# Hand the player's real save back, untouched by any of the above.
	Scrapbook.use_test_path("")
	Scrapbook.load_game()
	VoiceManager.open_mic = Scrapbook.voice_open_mic
	VoiceManager.enabled = Scrapbook.voice_enabled

	print("[SELFTEST] RESULT: %s" % ("ALL PASS" if pass_all else "FAIL"))
	get_tree().quit(0 if pass_all else 1)

func _despawn_test_ghost(pid: int) -> void:
	if not _remote_bags.has(pid):
		return
	VoiceManager.unregister_player(pid)
	_remote_bags[pid].queue_free()
	_remote_bags.erase(pid)
	_ghost_targets.erase(pid)
	_ghost_eyes.erase(pid)
	_ghost_mood.erase(pid)

## Regressions from the first live 2-player playtest. Every one of these shipped
## green through the whole suite while being broken in the players' hands, so
## each gets an assert pinned to the symptom that was actually reported.
func _selftest_playtest_fixes() -> bool:
	# A. "door unlocked too early" — an exit objective completing must not open
	# its physical blocker until all 3 tasks are done.
	_apply_phase(Phase.LOBBY, {})
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	var door_group := ""
	var door_obj := ""
	for e: Dictionary in HouseSuburban.exits():
		var need: String = EXIT_OBJECTIVE.get(e["name"], "")
		if str(e["door"]) != "" and need != "":
			door_group = str(e["door"])
			door_obj = need
			break
	_mark_objective_done(door_obj)
	var shut_before := _exit_door_locked(door_group)
	_escape_armed = true
	_refresh_exit_doors()
	var open_after := not _exit_door_locked(door_group)
	_escape_armed = false
	var door_ok := door_group != "" and shut_before and open_after

	# B. "objectives weren't letting me hold E" — a cocooned teammate inside
	# rescue_range used to hijack E outright. Now the NEAREST candidate wins.
	var probe_o: Objective = null
	var probe_p := Vector3.ZERO
	for o: Objective in _objectives:
		if o.interact_distance(o.def.action_spot) < INF:
			probe_o = o
			probe_p = o.def.action_spot
			break
	var focus_ok := false
	if probe_o != null:
		var od := probe_o.interact_distance(probe_p)
		_player.rescue()
		_player.global_position = probe_p
		var g2 := _spawn_remote_bag(4243)
		g2.set_meta("cocooned", true)
		# Caught friend in reach but FARTHER than the objective -> objective keeps E.
		g2.global_position = probe_p + Vector3(0, 0, minf(od + 0.4, rescue_range - 0.05))
		_update_rescue(0.0)
		var obj_wins: bool = str(_interact_focus()["kind"]) == "objective"
		# Closer than the objective -> the rescue takes it back.
		g2.global_position = probe_p + Vector3(0, 0, maxf(od - 0.3, 0.05))
		_update_rescue(0.0)
		var rescue_wins: bool = str(_interact_focus()["kind"]) == "rescue"
		focus_ok = od + 0.4 < rescue_range and obj_wins and rescue_wins
		_despawn_test_ghost(4243)
		_rescue_target = null

	# C. "was not able to spectate" — with your last teammate ALSO caught, the
	# camera key used to go dead at exactly the worst moment.
	var g3 := _spawn_remote_bag(4244)
	g3.set_meta("cocooned", true)
	_cocoon_local()
	var coc_spec := _can_spectate()
	_toggle_spectate()
	var coc_spec_on: bool = _spectating == 4244 and _spectate_target() == g3
	_stop_spectating()
	_player.rescue()
	_despawn_test_ghost(4244)

	# D. _all_cocooned must not end a round on absent data: a teammate on the
	# roster whose ghost state hasn't arrived is NOT a caught teammate.
	var had_9001: bool = LobbyManager.players.has(9001)
	LobbyManager.players[9001] = {"name": "Ghostless"}
	_cocoon_local()
	var roster_ok := not _all_cocooned()
	if not had_9001:
		LobbyManager.players.erase(9001)
	_player.rescue()

	var ok := door_ok and focus_ok and coc_spec and coc_spec_on and roster_ok
	print("[SELFTEST] playtest-fixes: door-shut-until-armed=%s e-nearest-wins=%s "
		% [door_ok, focus_ok]
		+ "spectate-cocooned-mate=%s(%s) roster-aware-loss=%s -> %s"
		% [coc_spec, coc_spec_on, roster_ok, ok])
	return ok

## "The monster glitched through the wall and ended up on the roof" — which is
## also the likeliest cause of the reported chase-less round. It has no collider
## by design, so containment is code, and this runs REAL physics frames rather
## than calling the clamp directly: the bug would come back just as easily by
## unhooking the call as by breaking the maths.
func _selftest_monster_containment() -> bool:
	var saved := _monster.global_transform
	var saved_wake := _monster.wake_delay
	_monster.set_wake(0.0)   # a sleeping monster doesn't run its physics body

	var roof := HouseSuburban.scaled(Vector3(0.0, 0.0, 0.0))
	roof.y = 12.0                                          # above the gable ridge
	_monster.global_position = roof
	for _i in 6:
		await get_tree().physics_frame
	var off_roof := HouseSuburban.is_inside(_monster.global_position)
	var roof_y := _monster.global_position.y

	_monster.global_position = Vector3(60.0, 0.4, 60.0)    # out in the neighbourhood
	for _i in 6:
		await get_tree().physics_frame
	var warped_back := HouseSuburban.is_inside(_monster.global_position)

	_monster.set_wake(saved_wake)
	_monster.global_transform = saved
	var ok := off_roof and warped_back
	print("[SELFTEST] monster-containment: off-roof=%s (y %.2f -> %.2f) back-in-footprint=%s -> %s"
		% [off_roof, 12.0, roof_y, warped_back, ok])
	return ok

## Audit: every gameplay anchor sits on solid floor at its expected height (no
## holes, no void). Returns false + prints the offenders if any anchor is unsupported.
func _audit_anchors_on_floor() -> bool:
	var space := get_world_3d().direct_space_state
	var bad: Array[String] = []
	var n := 0
	# Objective action + clue anchors (plan coords; y is the floor they sit on).
	var singles := {
		"phone": HouseSuburban.PHONE_SPOT, "breaker_box": HouseSuburban.BREAKER_BOX_SPOT,
		"garage_keypad": HouseSuburban.GARAGE_KEYPAD_SPOT, "deadbolt": HouseSuburban.DEADBOLT_SPOT,
		"dog_snack": HouseSuburban.DOG_SNACK_SPOT,
	}
	for label: String in singles:
		n += 1
		if not _floor_under(space, singles[label], singles[label].y):
			bad.append(label)
	var pools := {
		"clue": HouseSuburban.CLUE_SPOTS, "garage_clue": HouseSuburban.GARAGE_CLUE_SPOTS,
		"breaker_diag": HouseSuburban.BREAKER_DIAGRAM_SPOTS, "glasses": HouseSuburban.GLASSES_SPOTS,
	}
	for pool_name: String in pools:
		var pool: Array = pools[pool_name]
		for i in pool.size():
			n += 1
			if not _floor_under(space, pool[i], pool[i].y):
				bad.append("%s[%d]" % [pool_name, i])
	# Player spawns are already world coords, standing on the ground floor (y0).
	for i in HouseSuburban.SPAWNS.size():
		n += 1
		var sp: Vector3 = HouseSuburban.SPAWNS[i]
		if not _floor_under_world(space, sp, 0.0):
			bad.append("spawn[%d]" % i)
	var ok := bad.is_empty()
	print("[SELFTEST] anchors-on-floor: %d checked, bad=%s -> %s" % [n, str(bad), ok])
	return ok

func _floor_under(space: PhysicsDirectSpaceState3D, plan_pt: Vector3, floor_y: float) -> bool:
	return _floor_under_world(space, HouseSuburban.scaled(plan_pt), floor_y)

func _floor_under_world(space: PhysicsDirectSpaceState3D, w: Vector3, floor_y: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(w.x, floor_y + 1.2, w.z), Vector3(w.x, floor_y - 1.6, w.z))
	q.collision_mask = 0xFFFFFFFF
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and absf((hit["position"] as Vector3).y - floor_y) < 0.7

## Raycast down the basement stair path and verify a continuous walkable descent:
## every sample hits a surface (no fall-through gap) and consecutive surfaces never
## drop more than one comfortable step (no un-walkable cliff), ending at basement depth.
func _probe_basement_walkable() -> bool:
	var space := get_world_3d().direct_space_state
	var s := HouseSuburban.S
	var xw := -0.25 * s   # plan x of the shaft (basement flight under the up-stairs)
	var prev_y := 0.5
	var gaps := 0
	var cliffs := 0
	var deepest := 0.0
	# Walk the descending run in travel order: it starts at the DOOR (plan z~5) and
	# descends northward to z~0, so sample z from high to low.
	# The flights are STACKED (up-stairs sit 3m directly above), so each ray must
	# start BELOW the upper flight or it just hits that instead. Expected basement
	# height at plan z: tread i = 2*(5-z)-0.5, y = -0.3*i.
	for i in range(0, 11):
		var zp := lerpf(4.9, 0.1, float(i) / 10.0)
		var want_y := -0.3 * (2.0 * (5.0 - zp) - 0.5)
		var from := Vector3(xw, want_y + 1.2, zp * s)
		var to := Vector3(xw, want_y - 1.5, zp * s)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 0xFFFFFFFF   # treads (layer 1) + player ramp (layer 2)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			gaps += 1
			continue
		var y: float = hit.position.y
		if prev_y - y > 0.55:   # a single step is 0.3; >0.55 = an un-steppable cliff
			cliffs += 1
		prev_y = y
		deepest = minf(deepest, y)
	# The bottom landing sits under the ground-floor south lip; probe it from just
	# below that lip so the ground slab doesn't shadow it.
	var land := HouseSuburban.scaled(Vector3(-0.25, -2.7, -0.2))
	var lq := PhysicsRayQueryParameters3D.create(land + Vector3(0, 0.8, 0), land - Vector3(0, 1.0, 0))
	lq.collision_mask = 0xFFFFFFFF
	var land_hit := not space.intersect_ray(lq).is_empty()
	var ok := gaps == 0 and cliffs == 0 and deepest < -2.3 and land_hit
	print("[SELFTEST] basement-walk: gaps=%d cliffs=%d deepest=%.2f landing=%s -> %s" % [
		gaps, cliffs, deepest, land_hit, ok])
	# The UP-flight shares this shaft and the ground floor beneath it is now a hole,
	# so re-verify it still climbs continuously (tread i = 2z-0.5, y = 0.3*(2z+0.5)).
	var up_gaps := 0
	var up_cliffs := 0
	var up_prev := 0.0
	var highest := 0.0
	for i in range(0, 11):
		var zp := lerpf(0.1, 4.9, float(i) / 10.0)
		var want_y := 0.3 * (2.0 * zp + 0.5)
		var q2 := PhysicsRayQueryParameters3D.create(
			Vector3(xw, want_y + 1.2, zp * s), Vector3(xw, want_y - 1.4, zp * s))
		q2.collision_mask = 0xFFFFFFFF
		var h2 := space.intersect_ray(q2)
		if h2.is_empty():
			up_gaps += 1
			continue
		var y2: float = h2.position.y
		if absf(up_prev - y2) > 0.55:
			up_cliffs += 1
		up_prev = y2
		highest = maxf(highest, y2)
	var up_ok := up_gaps == 0 and up_cliffs == 0 and highest > 2.5
	print("[SELFTEST] upstairs-walk: gaps=%d cliffs=%d highest=%.2f -> %s" % [
		up_gaps, up_cliffs, highest, up_ok])
	return ok and up_ok

## Walk the bag UP every staircase using only shuffle (never a hop) and assert it
## actually climbs, stays slower than flat ground, and holds position when you stop.
func _selftest_stairs() -> bool:
	var s := HouseSuburban.S
	var all_ok := true
	var report: Array[String] = []
	for st: Dictionary in HouseSuburban.STAIRS:
		var start := Vector3(st["start"].x * s, st["base"], st["start"].y * s)
		var d := Vector3(st["dir"].x, 0.0, st["dir"].y)
		var run := float(st["run"]) * s
		var steps := int(st["steps"])
		var rise := float(st["rise"])
		# Always test the CLIMB, so for a descending flight start at its bottom.
		var bottom := start
		var up_dir := d
		if rise < 0.0:
			bottom = start + d * (run * steps)
			bottom.y = float(st["base"]) + rise * steps
			up_dir = -d
		# Drop in ON the flight, a step or so up, at the tread height for that point —
		# placing it *before* the flight can start it on the far side of a doorway wall,
		# and a flat offset buries it inside a tread.
		var along_t := 1.0
		# Drop well clear of the ramp: a down-flight's ramp is lifted an extra half-rise,
		# so a small offset spawns the capsule UNDERNEATH it, wedged on a tread.
		var drop_y: float = bottom.y + (along_t / run) * absf(rise) + 1.2
		_player.freeze = false
		_player.state = SleepingBagPlayer.State.NORMAL
		_player.linear_velocity = Vector3.ZERO
		_player.angular_velocity = Vector3.ZERO
		_player.global_position = Vector3(
			bottom.x + up_dir.x * along_t, drop_y, bottom.z + up_dir.z * along_t)
		_player.stamina = _player.stamina_max
		_player.test_move = Vector3.ZERO
		for _i in 20:
			await get_tree().physics_frame
		var y0: float = _player.global_position.y
		# Shuffle uphill for ~4s.
		_player.test_move = up_dir
		for _i in 240:
			await get_tree().physics_frame
		var y1: float = _player.global_position.y
		# Let go — it must hold, not creep back down.
		_player.test_move = Vector3.ZERO
		for _i in 60:
			await get_tree().physics_frame
		var y2: float = _player.global_position.y
		var climbed := y1 - y0
		var slipped := y1 - y2
		var hopped: bool = _player.stamina < _player.stamina_max - 0.01
		var ok := climbed > 0.9 and slipped < 0.25 and not hopped
		all_ok = all_ok and ok
		report.append("%s climbed=%.2f slipback=%.2f hops=%s%s" % [
			st.get("to", "?"), climbed, slipped, "YES" if hopped else "no",
			"" if ok else "  <-- FAIL"])
	_player.test_move = Vector3.ZERO
	print("[SELFTEST] stairs-walkable (no hops): %s -> %s" % [
		" | ".join(report), all_ok])
	return all_ok

## Selftest helper: complete one drawn door-objective, then fill to 3 total, and
## return the exit that opened (a door-objective is always in a 5-of-6 draw).
func _selftest_arm_via_door() -> String:
	var opened := ""
	for o: Objective in _objectives:
		if _exit_for_objective(o.def.id) != "":
			_authoritative_complete(o.def.id)
			opened = _exit_for_objective(o.def.id)
			break
	for o: Objective in _objectives:
		if _done_ids.size() >= 3:
			break
		if not _done_ids.has(o.def.id):
			_authoritative_complete(o.def.id)
	return opened

## Selftest helper: teleport to `exit_name`'s zone and trigger the escape check.
func _selftest_escape_via(exit_name: String) -> bool:
	for e: Dictionary in HouseSuburban.exits():
		if e["name"] == exit_name:
			_player.global_position = e["at"]
			break
	_net_report_escape(1)
	return phase == Phase.RESULTS and _results_label.text.contains("ESCAPE")

# ── World ──────────────────────────────────────────────────────────────────

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.35, 0.45)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	# Porch light just outside the front door — flickers through the 10s intro,
	# then dies as LIGHTS OUT begins (the round's opening beat).
	_porch_light = OmniLight3D.new()
	_porch_light.position = Vector3(0.5 * HouseSuburban.S, 2.2, 6.0 * HouseSuburban.S + 0.6)
	_porch_light.omni_range = 6.0
	_porch_light.light_color = Color(1.0, 0.86, 0.6)
	_porch_light.light_energy = 0.0
	add_child(_porch_light)

func _build_level() -> void:
	var nav_region := NavigationRegion3D.new()
	add_child(nav_region)
	HouseSuburban.build(nav_region)

	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.35
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.4
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)

	for area: Node in get_tree().get_nodes_in_group("hide_spot"):
		var a := area as Area3D
		a.body_entered.connect(_on_hide_entered)
		a.body_exited.connect(_on_hide_exited)

func _spawn_actors() -> void:
	_player = SleepingBagPlayer.new()
	_player.position = HouseSuburban.SPAWNS[0]
	add_child(_player)

	_monster = NoiseMonster.new()
	_monster.position = HouseSuburban.MONSTER_SPAWN
	_monster.patrol_points = HouseSuburban.patrol_points()
	_monster.get_targets = _monster_targets
	_monster.woke_up.connect(_on_monster_woke)
	_monster.state_changed.connect(_on_monster_state_changed)
	_monster.lunged_hit.connect(_on_monster_lunged_hit)
	add_child(_monster)

	_aim = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.18
	cone.height = 0.6
	_aim.mesh = cone
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim.set_surface_override_material(0, m)
	add_child(_aim)

func _monster_targets() -> Array:
	var out: Array = [_player]
	for pid: int in _remote_bags:
		out.append(_remote_bags[pid])
	return out

func _build_camera() -> void:
	_cam_pivot = Node3D.new()
	add_child(_cam_pivot)
	_cam_pitch = Node3D.new()
	_cam_pivot.add_child(_cam_pitch)
	_pitch = deg_to_rad(cam_pitch_default)
	_spring = SpringArm3D.new()
	_spring.spring_length = cam_distance
	_spring.position.x = cam_shoulder
	_spring.margin = 0.15
	_cam_pitch.add_child(_spring)
	_camera = Camera3D.new()
	_camera.fov = fov_base
	_camera.current = true
	_spring.add_child(_camera)
	_spring.add_excluded_object(_player.get_rid())
	_cam_pivot.global_position = _player.global_position + Vector3.UP * cam_height

# ── HUD ────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var help := Label.new()
	help.text = "WASD shuffle   Space hop   E interact   Q look back   V talk   M mic mode   F3 debug   Esc cursor"
	help.position = Vector2(16, 12)
	layer.add_child(help)

	# Always show which mic mode you're in — a hot mic you didn't know about is the
	# single worst voice-chat surprise.
	_mic_label = Label.new()
	_mic_label.position = Vector2(16, 72)
	_mic_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
	layer.add_child(_mic_label)
	var refresh_mic := func(_v: bool = false) -> void:
		_mic_label.text = "MIC: %s" % VoiceManager.mic_mode_text()
	refresh_mic.call()
	VoiceManager.mic_mode_changed.connect(refresh_mic)

	_state_label = Label.new()
	_state_label.position = Vector2(16, 40)
	_state_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_state_label)

	# Who's talking (driven by VoiceManager.speaking_changed).
	_voice_label = Label.new()
	_voice_label.position = Vector2(16, 96)
	_voice_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	layer.add_child(_voice_label)
	VoiceManager.speaking_changed.connect(func(_pid: int, _talking: bool) -> void:
		var pids := VoiceManager.speaking_pids()
		var names: Array[String] = []
		for p: int in pids:
			names.append(str(LobbyManager.players.get(p, {}).get("name", "player %d" % p)))
		_voice_label.text = ("🗣 " + ", ".join(names)) if not names.is_empty() else "")

	_net_label = Label.new()
	_net_label.position = Vector2(16, 72)
	_net_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	layer.add_child(_net_label)

	_clock_label = Label.new()
	_clock_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_clock_label.position = Vector2(-60, 14)
	_clock_label.custom_minimum_size = Vector2(120, 30)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(_clock_label)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 120)
	_toast.custom_minimum_size = Vector2(600, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 28)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_toast.visible = false
	layer.add_child(_toast)

	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = PROMPT_POS
	_prompt_label.custom_minimum_size = Vector2(520, 30)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	layer.add_child(_prompt_label)

	# Objective tracker, top-right: WHAT + WHETHER, never WHERE. Names show first;
	# the action detail appears only after a player finds that objective's clue.
	_tracker_label = Label.new()
	_tracker_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tracker_label.position = Vector2(-330, 40)
	_tracker_label.custom_minimum_size = Vector2(314, 160)
	_tracker_label.add_theme_font_size_override("font_size", 17)
	layer.add_child(_tracker_label)

	_debug_label = Label.new()
	_debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_label.position = Vector2(-330, 220)
	_debug_label.custom_minimum_size = Vector2(314, 100)
	_debug_label.visible = false
	_debug_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	layer.add_child(_debug_label)

	# Glasses blur: a full-screen post-process box blur, on only for the one
	# player who lost their glasses (The Glasses objective). Clears on pickup.
	_blur_overlay = ColorRect.new()
	_blur_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_overlay.visible = false
	var blur_shader := Shader.new()
	blur_shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	// Softer blur — a squint, not a whiteout. Friends still describe the room.
	vec2 px = 1.6 / vec2(textureSize(screen_tex, 0));
	vec4 c = vec4(0.0);
	for (int x = -1; x <= 1; x++)
		for (int y = -1; y <= 1; y++)
			c += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px);
	COLOR = c / 9.0;
}
"""
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = blur_shader
	_blur_overlay.material = blur_mat
	layer.add_child(_blur_overlay)

	var pip_row := HBoxContainer.new()
	pip_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pip_row.position = Vector2(-70, -48)
	pip_row.add_theme_constant_override("separation", 6)
	layer.add_child(pip_row)
	for i in range(int(_player.stamina_max)):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(24, 10)
		pip.color = PIP_ON
		pip_row.add_child(pip)
		_pips.append(pip)

	# Cocooned: near-black fabric dark + instructions. Placeholder first-person.
	_cocoon_overlay = ColorRect.new()
	(_cocoon_overlay as ColorRect).color = Color(0.03, 0.015, 0.03, 0.94)
	_cocoon_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cocoon_overlay.visible = false
	layer.add_child(_cocoon_overlay)
	_cocoon_text = Label.new()
	_cocoon_text.text = "COCOONED"  # rewritten live by _update_cocoon_text()
	_cocoon_text.set_anchors_preset(Control.PRESET_CENTER)
	_cocoon_text.position = Vector2(-260, -110)
	_cocoon_text.custom_minimum_size = Vector2(520, 220)
	_cocoon_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cocoon_text.add_theme_font_size_override("font_size", 24)
	_cocoon_overlay.add_child(_cocoon_text)

	# In-bag audio bus: a low-pass filter muffles everything routed here so it
	# reads as "heard through fabric". The heavy breathing loop lives on it, and
	# proximity voice should route here too once VOIP exists (Task 2 low-pass).
	_ensure_inbag_bus()
	_shush_ui = AudioStreamPlayer.new()
	_shush_ui.stream = SoundKit.get_stream("shush")
	_shush_ui.bus = INBAG_BUS
	add_child(_shush_ui)
	_breathing = AudioStreamPlayer.new()
	_breathing.stream = SoundKit.get_stream("breath")
	_breathing.bus = INBAG_BUS
	_breathing.volume_db = -3.0
	add_child(_breathing)

	# Lore-fragment reader: a bottom panel that shows a collected fragment's title
	# + body for a few seconds. Tapes "play" a procedural tape sound (no voice).
	_frag_panel = PanelContainer.new()
	_frag_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_frag_panel.position = Vector2(-320, -240)
	_frag_panel.custom_minimum_size = Vector2(640, 180)
	_frag_panel.visible = false
	layer.add_child(_frag_panel)
	var frag_box := VBoxContainer.new()
	frag_box.add_theme_constant_override("separation", 6)
	_frag_panel.add_child(frag_box)
	_frag_title = Label.new()
	_frag_title.add_theme_font_size_override("font_size", 22)
	_frag_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	frag_box.add_child(_frag_title)
	_frag_body = Label.new()
	_frag_body.custom_minimum_size = Vector2(620, 0)
	_frag_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_frag_body.add_theme_font_size_override("font_size", 18)
	frag_box.add_child(_frag_body)
	_tape_ui = AudioStreamPlayer.new()
	_tape_ui.stream = SoundKit.get_stream("tape")
	add_child(_tape_ui)

	# Results screen.
	_results_overlay = ColorRect.new()
	(_results_overlay as ColorRect).color = Color(0.02, 0.02, 0.05, 0.9)
	_results_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results_overlay.visible = false
	layer.add_child(_results_overlay)
	_results_label = Label.new()
	_results_label.set_anchors_preset(Control.PRESET_CENTER)
	_results_label.position = Vector2(-300, -140)
	_results_label.custom_minimum_size = Vector2(600, 280)
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.add_theme_font_size_override("font_size", 26)
	_results_overlay.add_child(_results_label)

	# Outro bookend overlay: sits ON TOP of the results for a few seconds (sunrise
	# glow or a quiet fade) then lifts to reveal the results. The results text is
	# set underneath immediately, so nothing about the outcome is delayed logically.
	_outro_overlay = ColorRect.new()
	_outro_overlay.color = Color(0, 0, 0, 0)
	_outro_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outro_overlay.visible = false
	layer.add_child(_outro_overlay)
	_outro_label = Label.new()
	_outro_label.set_anchors_preset(Control.PRESET_CENTER)
	_outro_label.position = Vector2(-300, -40)
	_outro_label.custom_minimum_size = Vector2(600, 80)
	_outro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outro_label.add_theme_font_size_override("font_size", 30)
	_outro_overlay.add_child(_outro_label)

	# Rotary phone panel.
	_phone_panel = PanelContainer.new()
	_phone_panel.set_anchors_preset(Control.PRESET_CENTER)
	_phone_panel.position = Vector2(-190, 40)
	_phone_panel.custom_minimum_size = Vector2(380, 110)
	_phone_panel.visible = false
	layer.add_child(_phone_panel)
	_phone_label = Label.new()
	_phone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_label.add_theme_font_size_override("font_size", 22)
	_phone_panel.add_child(_phone_label)

func _build_audio() -> void:
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = SoundKit.get_stream("heartbeat")
	_heartbeat.volume_db = -60.0
	_heartbeat.autoplay = true
	add_child(_heartbeat)
	_sting = AudioStreamPlayer.new()
	_sting.stream = SoundKit.get_stream("sting")
	_sting.volume_db = -4.0
	add_child(_sting)
	_zip_sound = AudioStreamPlayer.new()
	_zip_sound.stream = SoundKit.get_stream("zipper")
	add_child(_zip_sound)

# ── Round flow (host authoritative) ────────────────────────────────────────

func _enter_lobby() -> void:
	phase = Phase.LOBBY
	_results_overlay.visible = false
	_cocoon_overlay.visible = false
	_phone_panel.visible = false
	_blur_overlay.visible = false
	_reset_cocoon_ui()
	_clear_objectives()
	_clear_fragments()
	_set_exits_locked(true)
	_player.respawn()
	_monster.respawn()
	_monster.set_wake(1e9)  # sleeps until lights out
	for pid: int in _remote_bags:
		_remote_bags[pid].set_meta("cocooned", false)
	_clock_label.text = "LOBBY"
	_state_label.text = ""
	if _is_authority():
		_show_toast("LOBBY — host presses ENTER to start the night", 6.0)

func _host_start_round() -> void:
	# Host rolls the round layout: 5 of 6 objectives, each with a randomized
	# clue spot + code, and (if The Glasses is drawn) a random blurred player.
	var defs := ObjectiveDef.all()
	defs.shuffle()
	defs = defs.slice(0, 5)
	# Spread each objective's clue across floors (the traversal driver): <=2 per
	# floor, and at least one upstairs + one basement when the draw allows.
	var clue_idx := _spread_clue_indices(defs)
	var objs: Array = []
	var has_glasses := false
	var anchors: Array[Vector3] = [HouseSuburban.SPAWNS[0]]  # player start (living room)
	for d: ObjectiveDef in defs:
		var s := {"id": d.id}
		if d.clue_spots.size() > 0:
			s["clue"] = clue_idx[d.id]
			anchors.append(d.clue_spots[clue_idx[d.id]])
		if d.action_spot != Vector3.ZERO:
			anchors.append(d.action_spot)
		if d.code_len > 0:
			var lo := 1 if d.kind == ObjectiveDef.Kind.BREAKER else 0
			var hi := 3 if d.kind == ObjectiveDef.Kind.BREAKER else 9
			var code := ""
			for i in d.code_len:
				code += str(randi_range(lo, hi))
			s["code"] = code
		if d.kind == ObjectiveDef.Kind.GLASSES:
			has_glasses = true
		objs.append(s)
	var blurred := 0
	if has_glasses:
		var players: Array[int] = [1]
		if _net_connected():
			players = [_my_id()]
			for pid in multiplayer.get_peers():
				players.append(pid)
		blurred = players[randi() % players.size()]
	# Monster starts far from the players AND the round's clues/actions, never
	# camped on a staircase — so every round the "action floor" is monster-free.
	var spawn := _pick_monster_spawn(anchors)
	# Lore fragments share the clue-spawn anchors, so lore-hunting = objective risk.
	var frags := _pick_fragments(anchors)
	var data := {"objs": objs, "blurred": blurred, "monster_spawn": spawn, "frags": frags}
	_apply_phase(Phase.LIGHTS_OUT, data)
	if _net_connected():
		_net_phase.rpc(Phase.LIGHTS_OUT, data)

## Assign each drawn objective's clue index so the round's clues spread across
## floors: fixed-floor objectives first (Glasses=upstairs, Dog=ground), then the
## flexible ones (Landline/Garage/Breaker) fill under-covered floors, <=2/floor.
func _spread_clue_indices(defs: Array) -> Dictionary:
	var counts := {HouseSuburban.Floor.BASEMENT: 0, HouseSuburban.Floor.GROUND: 0,
		HouseSuburban.Floor.UPSTAIRS: 0}
	var out := {}
	# Build each def's floor -> [clue indices] map; classify flexible vs fixed.
	var by_floor := {}     # id -> {floor -> [idx]}
	var flexible: Array = []
	var fixed: Array = []
	for d: ObjectiveDef in defs:
		if d.clue_spots.is_empty():
			continue
		var fmap := {}
		for i in d.clue_spots.size():
			var f := HouseSuburban.floor_of(d.clue_spots[i].y)
			fmap.get_or_add(f, []).append(i)
		by_floor[d.id] = fmap
		if fmap.size() > 1:
			flexible.append(d.id)
		else:
			fixed.append(d.id)
	# Fixed objectives take their only floor.
	for id: String in fixed:
		var f: int = by_floor[id].keys()[0]
		out[id] = _rand_from(by_floor[id][f])
		counts[f] += 1
	# Flexible objectives fill the least-covered floor they can reach (<=2 cap),
	# prioritising floors still at zero so basement + upstairs get coverage.
	for id: String in flexible:
		var choices: Array = by_floor[id].keys()
		choices.sort_custom(func(a: int, b: int) -> bool:
			if (counts[a] == 0) != (counts[b] == 0):
				return counts[a] == 0        # empty floors first
			return counts[a] < counts[b])    # then least-covered
		var chosen: int = choices[0]
		for c: int in choices:
			if counts[c] < 2:
				chosen = c
				break
		out[id] = _rand_from(by_floor[id][chosen])
		counts[chosen] += 1
	return out

func _rand_from(indices: Array) -> int:
	return indices[randi() % indices.size()]

## Host: roll this round's lore fragments — a random 3-4 from the 20-fragment pool,
## each at a distinct clue-spawn anchor that isn't already holding an objective clue.
func _pick_fragments(used: Array[Vector3]) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var want := rng.randi_range(fragment_spawn_min, fragment_spawn_max)
	var frag_ids := LoreFragments.pick(want, rng)
	var spots := HouseSuburban.fragment_anchors()
	for i in range(spots.size() - 1, 0, -1):   # shuffle spots with the same rng
		var j := rng.randi_range(0, i)
		var tmp := spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var out: Array = []
	var si := 0
	for id: String in frag_ids:
		while si < spots.size() and _anchor_taken(spots[si], used):
			si += 1
		if si >= spots.size():
			break
		out.append({"id": id, "at": spots[si]})
		si += 1
	return out

func _anchor_taken(p: Vector3, used: Array[Vector3]) -> bool:
	for u: Vector3 in used:
		if p.distance_to(u) < 1.0:
			return true
	return false

## Pick the spawn candidate farthest (min-distance) from all round anchors,
## excluding any within spawn_stair_clearance of a staircase.
func _pick_monster_spawn(anchors: Array[Vector3]) -> Vector3:
	var best := HouseSuburban.MONSTER_SPAWN + Vector3.ZERO  # fallback
	var best_score := -1.0
	for cand: Vector3 in HouseSuburban.monster_spawn_candidates():
		if HouseSuburban.dist_to_nearest_stair(cand) < spawn_stair_clearance:
			continue
		var nearest := INF
		for a: Vector3 in anchors:
			nearest = minf(nearest, cand.distance_to(a))
		if nearest > best_score:
			best_score = nearest
			best = cand
	return best

func _apply_phase(p: Phase, data: Dictionary) -> void:
	phase = p
	match p:
		Phase.LOBBY:
			_enter_lobby()
		Phase.LIGHTS_OUT:
			_phase_timer = lights_out_duration
			_setup_objectives(data)
			_setup_fragments(data)
			_player.respawn()
			# Same on host + client (same data): the monster's LIGHTS-OUT spawn.
			if data.has("monster_spawn"):
				_monster.set_spawn_point(data["monster_spawn"])
				_monster_target = data["monster_spawn"]
				_has_monster_target = true
			_monster.respawn()
			_monster.set_solo(_lobby_size() == 1)  # solo-testing balance modifier
			_monster.set_wake(lights_out_duration)
			_cocoon_overlay.visible = false
			_reset_cocoon_ui()
			_porch_dying = true
			if _porch_light:
				_porch_light.light_energy = 1.6  # on, about to start failing
			_outro_active = false
			_outro_overlay.visible = false
			Scrapbook.mark_intro_seen()  # the porch-light intro bookend just played
			_show_toast("LIGHTS OUT.", 3.0)
			print("[NETTEST] phase=LIGHTS_OUT objs=%d blurred=%d spawn_floor=%d" % [
				(data.get("objs", []) as Array).size(), data.get("blurred", 0),
				HouseSuburban.floor_of(_monster.global_position.y)])
		Phase.ROUND:
			_phase_timer = round_duration
			_round_elapsed = 0.0
			_porch_dying = false
			if _porch_light:
				_porch_light.light_energy = 0.0  # the porch light finally dies — dark now
			print("[NETTEST] phase=ROUND")
		Phase.RESULTS:
			if _breathing and _breathing.playing:
				_breathing.stop()
			_show_results(data)
			print("[NETTEST] phase=RESULTS outcome=%s" % data.get("outcome"))

@rpc("authority", "call_remote", "reliable")
func _net_phase(p: int, data: Dictionary) -> void:
	_apply_phase(p as Phase, data)

func _host_end_round(outcome: String) -> void:
	if phase != Phase.ROUND:
		return
	var stats := {"outcome": outcome, "time": _round_elapsed, "tumbles": _collect_tumbles(),
		"stats": _finalize_stats(), "names": _roster_names()}
	_apply_phase(Phase.RESULTS, stats)
	if _net_connected():
		_net_phase.rpc(Phase.RESULTS, stats)

# ── Round stats (host) ─────────────────────────────────────────────────────

## Bank MY row into career totals, exactly once per round.
var _career_banked: bool = false

func _bank_career_stats(stats: Dictionary) -> void:
	if _career_banked:
		return
	_career_banked = true
	var mine: Dictionary = stats.get(_my_id(), {})
	if mine.is_empty():
		return
	Scrapbook.add_career(int(mine.get("tumbles", 0)), int(mine.get("rescues", 0)),
		int(mine.get("fragments", 0)))

## Real names for the recap — peer IDs are not screenshot-bait.
func _roster_names() -> Dictionary:
	var out := {}
	for pid: int in _round_stats:
		out[pid] = str(LobbyManager.players.get(pid, {}).get("name", "Player %d" % pid))
	return out

func _stat(pid: int) -> Dictionary:
	if not _round_stats.has(pid):
		_round_stats[pid] = Awards.blank_stats()
	return _round_stats[pid]

func _bump(pid: int, key: String, amount: float = 1.0) -> void:
	if not _is_authority():
		return
	var s := _stat(pid)
	s[key] = s.get(key, 0) + (amount if key == "noise_total" else int(amount))

## Merge live tumble counts (they ride the bag-state RPC) into the stat block.
func _finalize_stats() -> Dictionary:
	for pid: int in _collect_tumbles():
		_stat(pid)["tumbles"] = _collect_tumbles()[pid]
	return _round_stats

func _collect_tumbles() -> Dictionary:
	var out := {}
	out[_my_id()] = _player.tumbles
	for pid: int in _remote_bags:
		out[pid] = _remote_bags[pid].get_meta("tumbles", 0)
	return out

func _show_results(data: Dictionary) -> void:
	var outcome: String = data.get("outcome", "?")
	var headline: String = {
		"ESCAPE": "ESCAPE! You got out of the house.",
		"SUNRISE": "SUNRISE. It had to leave. You made it.",
		"LOSS": "ALL TUCKED IN. The house is quiet now.",
	}.get(outcome, outcome)
	# The recap is the shareable artifact that ends the session, so: real names,
	# what happened to each person, and only awards somebody actually earned.
	var stats: Dictionary = data.get("stats", {})
	var names: Dictionary = data.get("names", {})
	var text: String = headline + "\n     the night lasted %d:%02d\n\n" % [
		int(data.get("time", 0.0)) / 60, int(data.get("time", 0.0)) % 60]
	for pid: int in stats:
		text += "   %s — %s\n" % [
			names.get(pid, "Player %d" % pid),
			Awards.fate_of(stats[pid], outcome)]
	var earned: Array = Awards.compute(stats)
	if not earned.is_empty():
		text += "\n─────────  AWARDS  ─────────\n"
		for a: Dictionary in earned:
			text += "   %s — %s\n      %s\n" % [
				a["title"], names.get(a["pid"], "Player %d" % a["pid"]), a["blurb"]]
	_bank_career_stats(stats)
	text += "\nhost presses ENTER to run it back"
	_results_label.text = text
	_results_overlay.visible = true
	_cocoon_overlay.visible = false
	_phone_panel.visible = false
	_frag_panel.visible = false
	_start_outro(outcome)

## Play the closing bookend over the results: SUNRISE (light floods in, the
## Housesitter withdraws) or ALL-TUCKED-IN (the house goes quiet, lullaby fades).
## ESCAPE has no outro. ≤ outro_duration; skippable once you've seen it before.
func _start_outro(outcome: String) -> void:
	_monster.withdraw()  # it always leaves at the end of the night
	if outcome == "SUNRISE":
		_outro_overlay.color = Color(1.0, 0.93, 0.72, 0.0)  # warm dawn, fades in
		_outro_label.text = "the sun comes up.\nshe has to go home now."
		_outro_label.add_theme_color_override("font_color", Color(0.25, 0.2, 0.1))
	elif outcome == "LOSS":
		_outro_overlay.color = Color(0.02, 0.02, 0.04, 0.0)  # quiet dark
		_outro_label.text = "the house goes quiet.\nsweet dreams."
		_outro_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	else:
		_outro_active = false
		_outro_overlay.visible = false
		return
	_outro_active = true
	_outro_t = outro_duration
	_outro_overlay.visible = true

func _update_outro(delta: float) -> void:
	if not _outro_active:
		return
	_outro_t -= delta
	# Ease the overlay to ~85% opacity over the first second, hold, then it lifts.
	var a := clampf((outro_duration - _outro_t) / 1.0, 0.0, 1.0) * 0.85
	_outro_overlay.color.a = a
	# Skippable after the first time you've watched one all the way through.
	var can_skip := Scrapbook.seen_outro and (Input.is_key_pressed(KEY_SPACE) \
		or Input.is_key_pressed(KEY_ENTER))
	if _outro_t <= 0.0 or can_skip:
		_outro_active = false
		_outro_overlay.visible = false
		Scrapbook.mark_outro_seen()

# ── Objectives (data-driven; complete any 3 to arm escape) ─────────────────

func _setup_objectives(data: Dictionary) -> void:
	_round_stats.clear()      # fresh scorecard every round
	_cocoon_counter = 0
	_career_banked = false
	_spectating = -1
	_unzip_target = null  # old objectives are about to be freed
	_clear_objectives()
	_done_ids.clear()
	_escape_armed = false
	_set_exits_locked(true)
	var by_id := {}
	for d: ObjectiveDef in ObjectiveDef.all():
		by_id[d.id] = d
	_blurred_pid = int(data.get("blurred", 0))
	var blurred_me := _blurred_pid != 0 and _blurred_pid == _my_id()
	for entry: Dictionary in data.get("objs", []):
		var def: ObjectiveDef = by_id[entry["id"]]
		var o := Objective.new()
		add_child(o)
		var is_glasses := def.kind == ObjectiveDef.Kind.GLASSES
		o.setup(def, entry, blurred_me and is_glasses)
		o.completed.connect(_on_objective_completed)
		o.revealed.connect(_on_objective_revealed)
		o.action_noise.connect(func(pos: Vector3, loud: float) -> void: NoiseBus.emit_noise(pos, loud))
		o.toast.connect(func(t: String) -> void: _show_toast(t, 5.0))
		_objectives.append(o)
	# Blur the assigned player's screen until they find their glasses — but ONLY
	# with 2+ players (the handicap needs teammates to describe the room). Solo,
	# the glasses objective still spawns and is completable, just without blur.
	var player_count := 1 + (multiplayer.get_peers().size() if _net_connected() else 0)
	_blur_overlay.visible = blurred_me and _has_objective(ObjectiveDef.Kind.GLASSES) \
		and player_count >= 2

func _clear_objectives() -> void:
	for o: Objective in _objectives:
		o.queue_free()
	_objectives.clear()

# ── Lore fragments (collectible narrative props) ───────────────────────────

func _setup_fragments(data: Dictionary) -> void:
	_unzip_frag = null
	_clear_fragments()
	_frag_collected_ids.clear()
	for entry: Dictionary in data.get("frags", []):
		var fdata := LoreFragments.by_id(str(entry.get("id", "")))
		if fdata.is_empty():
			continue
		var fr := Fragment.new()
		add_child(fr)
		fr.setup(fdata, entry.get("at", Vector3.ZERO))
		_fragments.append(fr)
	_frag_spawned = _fragments.size()
	print("[NETTEST] fragments spawned=%d" % _frag_spawned)

func _clear_fragments() -> void:
	for fr: Fragment in _fragments:
		fr.queue_free()
	_fragments.clear()
	_frag_spawned = 0
	if _frag_panel:
		_frag_panel.visible = false

func _fragment_by_id(id: String) -> Fragment:
	for fr: Fragment in _fragments:
		if fr.id() == id:
			return fr
	return null

func _collected_this_round() -> int:
	var n := 0
	for fr: Fragment in _fragments:
		if fr.collected:
			n += 1
	return n

## Local player finished the unzip on a fragment: show its contents right away
## (optimistic), then ask the host to commit the once-per-lobby claim.
func _finish_fragment_pickup(fr: Fragment) -> void:
	if fr == null or fr.collected:
		return
	_show_fragment(fr)
	if _is_authority():
		_authoritative_collect_fragment(fr.id(), _my_id())
	else:
		_net_request_collect.rpc_id(1, fr.id())

@rpc("any_peer", "call_remote", "reliable")
func _net_request_collect(id: String) -> void:
	if _is_authority():
		_authoritative_collect_fragment(id, multiplayer.get_remote_sender_id())

func _authoritative_collect_fragment(id: String, by_pid: int) -> void:
	if id == "" or _frag_collected_ids.has(id):
		return  # first grab in the lobby wins; ignore the rest
	_frag_collected_ids.append(id)
	_bump(by_pid, "fragments")
	_apply_fragment_collected(id, by_pid)
	if _net_connected():
		_net_fragment_collected.rpc(id, by_pid)

@rpc("authority", "call_remote", "reliable")
func _net_fragment_collected(id: String, by_pid: int) -> void:
	_apply_fragment_collected(id, by_pid)

## Everyone: remove the prop, credit the whole party's Scrapbook (shared discovery),
## and — for players who weren't the one who grabbed it — a light "someone found" note.
func _apply_fragment_collected(id: String, by_pid: int) -> void:
	var fr := _fragment_by_id(id)
	if fr != null:
		fr.mark_collected()
	Scrapbook.collect(id)
	if by_pid != _my_id():
		var fdata := LoreFragments.by_id(id)
		_show_toast("A fragment was found: %s" % fdata.get("title", "?"), 3.0)
	print("[NETTEST] fragment collected: %s by=%d (%d/%d)" % [
		id, by_pid, _collected_this_round(), _frag_spawned])

func _show_fragment(fr: Fragment) -> void:
	# The reader overlay: title + body, held briefly. Tapes "play" (procedural
	# tape audio); the rest get a soft page rustle. No voice, ever.
	_frag_title.text = fr.title()
	_frag_body.text = fr.body()
	_frag_panel.visible = true
	_frag_panel_t = 7.0
	if fr.frag_type() == "tape":
		_tape_ui.play()
	else:
		SoundKit.play_at(self, _player.global_position, "zipper")

func _has_objective(kind: int) -> bool:
	for o: Objective in _objectives:
		if o.def.kind == kind:
			return true
	return false

func _on_objective_revealed(id: String) -> void:
	# A player read a clue — reveal the action detail on every HUD (host-owned).
	if _is_authority():
		_net_reveal.rpc(id)
		_apply_reveal(id)
	else:
		_report_reveal.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _report_reveal(id: String) -> void:
	if _is_authority():
		_net_reveal.rpc(id)
		_apply_reveal(id)

@rpc("authority", "call_remote", "reliable")
func _net_reveal(id: String) -> void:
	_apply_reveal(id)

func _apply_reveal(id: String) -> void:
	for o: Objective in _objectives:
		if o.def.id == id:
			o.set_revealed()

func _on_objective_completed(id: String) -> void:
	if _is_authority():
		_authoritative_complete(id)
	else:
		_report_objective.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _report_objective(id: String) -> void:
	if _is_authority():
		_authoritative_complete(id)

func _authoritative_complete(id: String) -> void:
	if _done_ids.has(id):
		return
	_mark_objective_done(id)
	var armed := _done_ids.size() >= 3
	if armed and not _escape_armed:
		_arm_escape()
	_net_objective_done.rpc(id, _escape_armed)

@rpc("authority", "call_remote", "reliable")
func _net_objective_done(id: String, armed: bool) -> void:
	_mark_objective_done(id)
	if armed and not _escape_armed:
		_arm_escape()

func _mark_objective_done(id: String) -> void:
	if not _done_ids.has(id):
		_done_ids.append(id)
	for o: Objective in _objectives:
		if o.def.id == id:
			o.force_done()
			if o.blurred_is_me:
				_blur_overlay.visible = false  # got the glasses
	_refresh_exit_doors()  # this objective may have opened a specific door
	var opened := _exit_for_objective(id)
	# WHAT + WHETHER, never WHERE: don't name the door — a door-objective just says
	# it opened an exit; the player finds the now-open door in the world.
	if opened != "":
		# Don't promise an open door before 3/3 — the blocker stays shut until armed.
		if _escape_armed:
			_show_toast("Task done (%d/3) — a door just unlocked!" % mini(_done_ids.size(), 3), 4.0)
		else:
			_show_toast("Task done (%d/3) — that's a way out, once all 3 are done."
				% mini(_done_ids.size(), 3), 4.0)
	else:
		_show_toast("Task done (%d/3)." % mini(_done_ids.size(), 3), 3.0)
	print("[NETTEST] objective done: %s (%d) opened=%s" % [id, _done_ids.size(), opened])

func _arm_escape() -> void:
	_escape_armed = true
	_refresh_exit_doors()
	_show_toast("3 TASKS DONE. The exits are open — GET OUT.", 6.0)
	print("[NETTEST] escape armed open=%s" % ", ".join(_open_exit_names()))

## The exit name a given objective unlocks ("" if it's a support objective).
func _exit_for_objective(id: String) -> String:
	for name: String in EXIT_OBJECTIVE:
		if EXIT_OBJECTIVE[name] == id:
			return name
	return ""

## An exit is open when its required objective is completed.
func _exit_is_open(exit_name: String) -> bool:
	var need: String = EXIT_OBJECTIVE.get(exit_name, "")
	return need != "" and _done_ids.has(need)

func _open_exit_names() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in HouseSuburban.exits():
		if _exit_is_open(e["name"]):
			out.append(e["name"])
	return out

## Show/hide each physical door blocker to match its exit's open state. A door
## needs BOTH its own objective done AND the escape armed (3/3) — completing one
## task must never crack a physical way out early.
func _refresh_exit_doors() -> void:
	for e: Dictionary in HouseSuburban.exits():
		if e["door"] == "":
			continue
		var open := _escape_armed and _exit_is_open(e["name"])
		for node: Node in get_tree().get_nodes_in_group(e["door"]):
			var d := node as StaticBody3D
			d.visible = not open
			(d.get_child(0) as CollisionShape3D).disabled = open

## Reset helper: force every physical door blocker to a state (used on lobby /
## round setup to hard-lock before any objective is done).
func _set_exits_locked(locked: bool) -> void:
	for e: Dictionary in HouseSuburban.exits():
		if e["door"] == "":
			continue
		for node: Node in get_tree().get_nodes_in_group(e["door"]):
			var d := node as StaticBody3D
			d.visible = locked
			(d.get_child(0) as CollisionShape3D).disabled = not locked

func _exit_door_locked(group: String) -> bool:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes.size() > 0 and (nodes[0] as StaticBody3D).visible

func _player_at_exit() -> String:
	# Which OPEN exit (if any) the local player is standing in. Requires the
	# escape phase to be armed AND that specific door's objective to be done.
	if not _escape_armed:
		return ""
	var p := _player.global_position
	for e: Dictionary in HouseSuburban.exits():
		if not _exit_is_open(e["name"]):
			continue
		var at: Vector3 = e["at"]
		var half: Vector2 = e["half"]
		if absf(p.x - at.x) < half.x and absf(p.z - at.z) < half.y and absf(p.y - at.y) < 2.5:
			return e["name"]
	return ""

@rpc("any_peer", "call_remote", "reliable")
func _net_report_escape(pid: int) -> void:
	if _is_authority() and phase == Phase.ROUND and _escape_armed:
		print("[NETTEST] escape by peer %d" % pid)
		_stat(pid)["escaped"] = true
		_host_end_round("ESCAPE")

# ── Cocoon & rescue ────────────────────────────────────────────────────────

func _on_monster_lunged_hit(target: Node3D) -> void:
	# Host only (the monster simulates on the host).
	if target == _player:
		_mark_cocooned_stat(_my_id())
		_cocoon_local()
	else:
		for pid: int in _remote_bags:
			if _remote_bags[pid] == target:
				target.set_meta("cocooned", true)
				_mark_cocooned_stat(pid)
				_net_cocoon.rpc_id(pid)
				break

## Ordinal, not a count — FIRST TUCKED IN needs to know who the Housesitter got first.
func _mark_cocooned_stat(pid: int) -> void:
	if not _is_authority():
		return
	var s := _stat(pid)
	if int(s.get("cocooned_order", -1)) < 0:
		s["cocooned_order"] = _cocoon_counter
		_cocoon_counter += 1

@rpc("authority", "call_remote", "reliable")
func _net_cocoon() -> void:
	_cocoon_local()

func _cocoon_local() -> void:
	if _player.state == SleepingBagPlayer.State.COCOONED:
		return
	# The chase CAMERA is killed instantly (no AnimationPlayer) — _update_camera
	# snaps _cocoon_cam to 1 while COCOONED. The fabric-dark overlay then FADES in
	# (the "tucking in" beat: the screen settles to dark, lullaby audible through
	# the bag) rather than popping. WASD is locked by the COCOONED state; the
	# wiggling body stays visible to others for the rescue window.
	_player.cocoon()
	_unzip_target = null  # a caught player can't be mid-unzip
	_unzip_frag = null
	_cocoon_cam = 1.0
	_cocoon_overlay.visible = true
	(_cocoon_overlay as ColorRect).color.a = 0.35  # fades up to full in _process
	_cocoon_text.visible = true
	_shush_ui.play()
	if not _breathing.playing:
		_breathing.play()
	print("[NETTEST] cocooned (me)")

@rpc("any_peer", "call_remote", "reliable")
func _net_rescued(victim_pid: int) -> void:
	_apply_rescue(victim_pid)

func _apply_rescue(victim_pid: int) -> void:
	var my_id := _my_id()
	if victim_pid == my_id:
		_player.rescue()
		_cocoon_overlay.visible = false
		_reset_cocoon_ui()
		print("[NETTEST] rescued (me)")
	elif _remote_bags.has(victim_pid):
		_remote_bags[victim_pid].set_meta("cocooned", false)

## Rescues are performed locally by the rescuer, so the host is told who did it.
@rpc("any_peer", "call_remote", "reliable")
func _report_rescue(pid: int) -> void:
	_credit_rescue(pid)

func _credit_rescue(pid: int) -> void:
	if _is_authority():
		_bump(pid, "rescues")

func _update_rescue(delta: float) -> void:
	# Find a cocooned bag in reach (you can't rescue yourself).
	var candidate: Node3D = null
	var candidate_pid := -1
	if _player.state != SleepingBagPlayer.State.COCOONED:
		for pid: int in _remote_bags:
			var ghost: Node3D = _remote_bags[pid]
			if ghost.get_meta("cocooned", false) \
					and _player.global_position.distance_to(ghost.global_position) < rescue_range:
				candidate = ghost
				candidate_pid = pid
				break
	if candidate == null:
		_rescue_target = null
		_rescue_t = 0.0
		return

	_rescue_target = candidate
	# E is shared with objectives and lore. Only hold-to-rescue when the cocooned
	# bag is the nearest thing E could act on, so a friend caught next to a keypad
	# doesn't lock you out of the keypad (or vice versa).
	if str(_interact_focus()["kind"]) != "rescue":
		_rescue_t = 0.0
		return

	if Input.is_key_pressed(KEY_E):
		if _rescue_t == 0.0:
			_rescue_zipped = false
		_rescue_t += delta
		_prompt_label.text = "UNZIPPING... %d%%" % int(_rescue_t / rescue_time * 100.0)
		if not _rescue_zipped and _rescue_t >= rescue_zipper_at:
			_rescue_zipped = true
			_zip_sound.play()
			NoiseBus.emit_noise(_player.global_position, zipper_loudness)  # LOUD
		if _rescue_t >= rescue_time:
			_rescue_t = 0.0
			_apply_rescue(candidate_pid)
			_credit_rescue(_my_id())        # I did the unzipping
			if _net_connected():
				_net_rescued.rpc(candidate_pid)
				_report_rescue.rpc_id(1, _my_id())
	else:
		_rescue_t = 0.0
		_prompt_label.text = "HOLD E TO RESCUE"

# ── Hiding ─────────────────────────────────────────────────────────────────

func _on_hide_entered(body: Node3D) -> void:
	if body == _player:
		_player.hidden = true

func _on_hide_exited(body: Node3D) -> void:
	if body == _player:
		_player.hidden = false
		# Slipping out of a hiding spot makes a small rustle.
		NoiseBus.emit_noise(_player.global_position, 0.3)

# ── Monster events / audio ─────────────────────────────────────────────────

func _on_monster_woke() -> void:
	_show_toast("...something in the attic just woke up.")
	if _net_connected() and multiplayer.is_server():
		_net_monster_woke.rpc()

@rpc("authority", "call_remote", "reliable")
func _net_monster_woke() -> void:
	_show_toast("...something in the attic just woke up.")
	_monster.client_audio_wake()

func _on_monster_state_changed(s: int) -> void:
	_apply_monster_fx(s)
	if _net_connected() and multiplayer.is_server():
		_net_monster_fx.rpc(s)

@rpc("authority", "call_remote", "reliable")
func _net_monster_fx(s: int) -> void:
	_apply_monster_fx(s)
	_monster.play_state_fx(s)

func _apply_monster_fx(s: int) -> void:
	_monster_fx_state = s
	if s == NoiseMonster.State.CHASE:
		_sting.play()

func _show_toast(text: String, secs: float = 4.0) -> void:
	_toast.text = text
	_toast.visible = true
	get_tree().create_timer(secs).timeout.connect(func() -> void:
		if _toast.text == text:
			_toast.visible = false)

# ── Input ──────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(-55.0), deg_to_rad(25.0))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
					if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
					else Input.MOUSE_MODE_CAPTURED)
			KEY_F3:
				_debug_visible = not _debug_visible
				_debug_label.visible = _debug_visible
			KEY_ENTER:
				if _is_authority():
					if phase == Phase.LOBBY:
						_host_start_round()
					elif phase == Phase.RESULTS:
						_apply_phase(Phase.LOBBY, {})
						if _net_connected():
							_net_phase.rpc(Phase.LOBBY, {})
			KEY_R:
				if (_is_authority()) and phase != Phase.LOBBY:
					_apply_phase(Phase.LOBBY, {})
					if _net_connected():
						_net_phase.rpc(Phase.LOBBY, {})
			KEY_E:
				_try_interact_press()
			KEY_M:
				# Flip push-to-talk <-> open mic mid-round (persists).
				VoiceManager.toggle_open_mic()
				_show_toast("MIC: %s" % VoiceManager.mic_mode_text(), 2.0)
			KEY_F:
				# NOT Tab: Tab is ui_focus_next, so Godot's GUI focus system eats
				# it in the viewport and it never reaches _unhandled_input. That
				# left cocooned players pressing a key that did literally nothing.
				_toggle_spectate()
			KEY_BRACKETLEFT:
				_cycle_spectate(-1)
			KEY_BRACKETRIGHT:
				_cycle_spectate(1)
			_:
				var digit := _keycode_to_digit(event.keycode)
				if digit != -1:
					var entry := _active_entry()
					if entry != null:
						entry.on_key(digit)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Number-row (KEY_0..KEY_9) AND numeric keypad (KEY_KP_0..KEY_KP_9) both dial.
func _keycode_to_digit(kc: int) -> int:
	if kc >= KEY_0 and kc <= KEY_9:
		return kc - KEY_0
	if kc >= KEY_KP_0 and kc <= KEY_KP_9:
		return kc - KEY_KP_0
	return -1

func _active_entry() -> Objective:
	for o: Objective in _objectives:
		if o.panel_open():
			return o
	return null

## What one E press/hold acts on right now: whichever candidate is NEAREST.
## Before this, a cocooned teammate anywhere within rescue_range hijacked E and
## silently disabled every objective in reach — you could stand on a keypad next
## to a caught friend and neither would respond.
func _interact_focus() -> Dictionary:
	var p := _player.global_position
	var out := {"kind": "none", "obj": null, "frag": null, "dist": INF}
	if _rescue_target != null:
		out = {"kind": "rescue", "obj": null, "frag": null,
			"dist": p.distance_to(_rescue_target.global_position)}
	for o: Objective in _objectives:
		var d := o.interact_distance(p)
		if d < float(out["dist"]):
			out = {"kind": "objective", "obj": o, "frag": null, "dist": d}
	for fr: Fragment in _fragments:
		if fr.near(p):
			var d := p.distance_to(fr.position)
			if d < float(out["dist"]):
				out = {"kind": "fragment", "obj": null, "frag": fr, "dist": d}
	return out

func _try_interact_press() -> void:
	if phase != Phase.ROUND or _player.state == SleepingBagPlayer.State.COCOONED:
		print("[PLAYTEST] E ignored: phase=%d cocooned=%s"
			% [phase, _player.state == SleepingBagPlayer.State.COCOONED])
		return
	if _unzip_target != null or _unzip_frag != null:
		return  # already unzipping
	var p := _player.global_position
	var focus := _interact_focus()
	match str(focus["kind"]):
		"rescue":
			# Hold-E channel owned by _update_rescue; the press just starts it.
			print("[PLAYTEST] E -> rescue (%.2fm)" % float(focus["dist"]))
		"fragment":
			_begin_unzip(null, focus["frag"] as Fragment)
		"objective":
			var o := focus["obj"] as Objective
			# Grabbing a clue/item means unzipping the bag: a slow, loud hold-E
			# channel. Panels and hand-offs fire instantly on the press.
			if o.grab_available(p):
				_begin_unzip(o, null)
			elif not o.try_interact(p):
				print("[PLAYTEST] E -> %s in reach but nothing to do" % o.def.id)
		_:
			print("[PLAYTEST] E -> nothing in reach at %v" % p)

func _begin_unzip(o: Objective, fr: Fragment) -> void:
	_unzip_target = o
	_unzip_frag = fr
	_unzip_t = 0.0
	_unzip_panic = _monster_fx_state >= NoiseMonster.State.CHASE
	_unzip_dur = unzip_secs + (unzip_chase_penalty if _unzip_panic else 0.0)
	# The zip breaking the seal is LOUD — a ping every hunter in earshot gets.
	NoiseBus.emit_noise(_player.global_position, unzip_loudness)
	SoundKit.play_at(self, _player.global_position, "zipper")

func _update_unzip(delta: float) -> void:
	if _unzip_target == null and _unzip_frag == null:
		return
	var p := _player.global_position
	# Cancel on release, cocoon, or moving off the target; the grab is not committed
	# until the channel completes (so a fumbled unzip still costs the time + noise).
	var still_valid := Input.is_key_pressed(KEY_E) \
		and _player.state != SleepingBagPlayer.State.COCOONED \
		and ((_unzip_target != null and _unzip_target.grab_available(p)) \
			or (_unzip_frag != null and _unzip_frag.near(p)))
	if not still_valid:
		_unzip_target = null
		_unzip_frag = null
		return
	_unzip_t += delta
	if _unzip_t >= _unzip_dur:
		if _unzip_target != null:
			_unzip_target.try_interact(p)  # zipped open — grab it now
		elif _unzip_frag != null:
			_finish_fragment_pickup(_unzip_frag)
		_unzip_target = null
		_unzip_frag = null

# ── Frame loop ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_camera(delta)
	_player.control_yaw = _yaw

	# Fragment reader auto-dismiss.
	if _frag_panel and _frag_panel.visible:
		_frag_panel_t -= delta
		if _frag_panel_t <= 0.0:
			_frag_panel.visible = false

	# Cocoon "tucking in": the fabric-dark overlay settles to full over ~0.4s.
	if _cocoon_overlay.visible and _player.state == SleepingBagPlayer.State.COCOONED:
		var cc := (_cocoon_overlay as ColorRect).color
		cc.a = move_toward(cc.a, 0.94, delta * 1.5)
		(_cocoon_overlay as ColorRect).color = cc
		_update_cocoon_text()

	_update_outro(delta)

	var fwd: Vector3 = _player.facing
	_aim.global_position = _player.global_position + fwd * 1.3 + Vector3.UP * 0.2
	_aim.look_at(_aim.global_position + fwd, Vector3.UP)
	_aim.rotate_object_local(Vector3.RIGHT, -PI / 2.0)

	_state_label.text = _player.get_state_text()
	for i in range(_pips.size()):
		_pips[i].color = PIP_ON if _player.stamina >= float(i + 1) else PIP_OFF

	_update_eyes(delta)

	_prompt_label.text = ""
	if phase == Phase.ROUND:
		_update_rescue(delta)
		_update_unzip(delta)
		_update_objectives(delta)
		_update_prompts()
		_update_tracker()
		# Escape: walk into an OPEN exit (its objective done) once armed → out.
		if _escape_armed and _player_at_exit() != "" \
				and _player.state != SleepingBagPlayer.State.COCOONED:
			if _is_authority():
				_net_report_escape(_my_id())
			else:
				_net_report_escape.rpc_id(1, _my_id())
	else:
		_tracker_label.text = ""

	_update_phase(delta)
	_update_audio(delta)
	_update_debug()
	_net_tick(delta)

func _update_objectives(delta: float) -> void:
	var p := _player.global_position
	for o: Objective in _objectives:
		var near_count := _bodies_near(o.def.action_spot, Objective.NEAR)
		o.update(delta, p, near_count)
	# The one open entry panel (phone / keypad / fuse box) drives the panel UI.
	var entry := _active_entry()
	if entry != null:
		_phone_panel.visible = true
		_phone_label.text = entry.panel_text()
	else:
		_phone_panel.visible = false

func _bodies_near(pos: Vector3, r: float) -> int:
	var n := 0
	if _player.global_position.distance_to(pos) < r:
		n += 1
	for pid: int in _remote_bags:
		if _remote_bags[pid].global_position.distance_to(pos) < r:
			n += 1
	return n

func _update_prompts() -> void:
	# Unzip channel takes priority: show progress, and shake the text (NOT the
	# camera) while panic-fumbling in a chase to sell the shaky hands.
	if _unzip_target != null or _unzip_frag != null:
		var pct := int(clampf(_unzip_t / _unzip_dur, 0.0, 1.0) * 100.0)
		var verb := "UNZIPPING" if _unzip_target != null else "REACHING OUT"
		if _unzip_panic:
			_prompt_label.text = "%s… %d%%   — hands shaking!" % [verb, pct]
			_prompt_label.position = PROMPT_POS + Vector2(randf_range(-4, 4), randf_range(-3, 3))
		else:
			_prompt_label.text = "%s… %d%%" % [verb, pct]
			_prompt_label.position = PROMPT_POS
		return
	_prompt_label.position = PROMPT_POS
	var p := _player.global_position
	# The prompt must name whatever E is ACTUALLY bound to this frame, or players
	# hold a key that's quietly going somewhere else.
	var focus := _interact_focus()
	match str(focus["kind"]):
		"rescue":
			if not Input.is_key_pressed(KEY_E):
				_prompt_label.text = "HOLD E TO RESCUE"
			return
		"fragment":
			_prompt_label.text = "✦ %s  (hold E: unzip)" \
				% (focus["frag"] as Fragment).frag_type().to_upper()
			return
		"objective":
			var fo := focus["obj"] as Objective
			var fpr := fo.prompt(p)
			if fpr != "":
				# Hint that grabs cost an unzip, so the loud channel isn't a surprise.
				_prompt_label.text = fpr + ("  (hold E: unzip)" if fo.grab_available(p) else "")
				return
	# Nothing pressable won: fall through for hold-only actions (the deadbolt),
	# which never consume the press and so never enter the focus arbitration.
	for o: Objective in _objectives:
		var pr := o.prompt(p)
		if pr != "":
			_prompt_label.text = pr
			return

func _update_tracker() -> void:
	# WHAT + WHETHER, never WHERE. Name + state only; the action detail (what to
	# DO, e.g. the dialed number — never a location) reveals after a clue is found.
	var text := "ESCAPE  %d / 3 tasks\n" % mini(_done_ids.size(), 3)
	for o: Objective in _objectives:
		var box := " "
		match o.tracker_state():
			Objective.Tracker.DONE: box = "x"
			Objective.Tracker.IN_PROGRESS: box = "~"
		var line := "[%s] %s" % [box, o.def.display_name]
		if o.is_revealed() and o.tracker_state() != Objective.Tracker.DONE:
			var detail := o.tracker_detail()
			if detail != "":
				line += "  —  " + detail
		text += line + "\n"
	if _escape_armed:
		text += "\nTHE EXITS ARE OPEN — GET OUT."
	if _frag_spawned > 0:
		text += "\n\n✦ LORE  %d / %d found" % [_collected_this_round(), _frag_spawned]
	_tracker_label.text = text

func _update_phase(delta: float) -> void:
	var is_authority := _is_authority()
	match phase:
		Phase.LIGHTS_OUT:
			_phase_timer -= delta
			_clock_label.text = "dark in %d..." % int(ceil(maxf(_phase_timer, 0.0)))
			if _porch_light and _porch_dying:
				# Failing porch light: base glow dimming toward the end of the intro,
				# with erratic flicker dropouts that get worse as LIGHTS OUT nears.
				var frac := clampf(_phase_timer / lights_out_duration, 0.0, 1.0)  # 1→0
				var base := lerpf(0.4, 1.6, frac)
				var flick := 1.0 if randf() > (0.5 - 0.35 * (1.0 - frac)) else randf_range(0.0, 0.3)
				_porch_light.light_energy = base * flick
			if is_authority and _phase_timer <= 0.0:
				_apply_phase(Phase.ROUND, {})
				if _net_connected():
					_net_phase.rpc(Phase.ROUND, {})
		Phase.ROUND:
			_round_elapsed += delta
			if is_authority:
				_phase_timer -= delta
				_clock_label.text = _fmt_clock(_phase_timer)
				_clock_accum += delta
				if _clock_accum > 0.5 and _net_connected():
					_clock_accum = 0.0
					_net_clock.rpc(_phase_timer)
				if _phase_timer <= 0.0:
					_host_end_round("SUNRISE")
				elif _all_cocooned():
					_host_end_round("LOSS")
		Phase.LOBBY:
			_clock_label.text = "LOBBY"

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_clock(remaining: float) -> void:
	_phase_timer = remaining
	_clock_label.text = _fmt_clock(remaining)

func _fmt_clock(t: float) -> String:
	t = maxf(t, 0.0)
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

func _all_cocooned() -> bool:
	if _player.state != SleepingBagPlayer.State.COCOONED:
		return false
	# Roster-aware. Judging this on _remote_bags alone means a join race or a gap
	# in ghost state reads as "everyone is caught" and ends the round on absent
	# data — so require a ghost to exist for every other player in the lobby.
	var expected := 0
	for pid: int in LobbyManager.players:
		if pid != _my_id():
			expected += 1
	if _remote_bags.size() < expected:
		return false
	for pid: int in _remote_bags:
		if not _remote_bags[pid].get_meta("cocooned", false):
			return false
	return true

func _update_audio(_delta: float) -> void:
	# Heartbeat scales with monster proximity — your body knows before you do.
	var dist := _player.global_position.distance_to(_monster.global_position)
	if phase == Phase.ROUND and dist < 13.0:
		_heartbeat.volume_db = lerpf(-8.0, -34.0, clampf((dist - 2.0) / 11.0, 0.0, 1.0))
	else:
		_heartbeat.volume_db = -60.0

func _update_debug() -> void:
	if not _debug_visible:
		return
	if _is_authority():
		_debug_label.text = _monster.get_debug_text()
	else:
		var names := ["PATROL", "INVESTIGATE", "CHASE", "LUNGE"]
		var s: String = names[_monster_fx_state] if _monster_fx_state >= 0 else "?"
		_debug_label.text = "monster (synced): %s\npos %v" % [s, _monster.global_position]

func _update_eyes(delta: float) -> void:
	# Local bag: its own mood, upgraded to ALERT when the monster is close.
	var mp := _monster.global_position
	var m := _player.eye_mood()
	if _alert_over(m) and _player.global_position.distance_to(mp) < chase_range:
		m = BagEyes.Mood.ALERT
	_player.drive_eyes(m, delta)
	# Remote ghosts: the synced mood, likewise upgraded near the monster — this
	# is the "watch your friend's eyes go WIDE" clip.
	for pid: int in _ghost_eyes:
		var gm: int = _ghost_mood.get(pid, BagEyes.Mood.IDLE)
		if _alert_over(gm) and _remote_bags[pid].global_position.distance_to(mp) < chase_range:
			gm = BagEyes.Mood.ALERT
		_ghost_eyes[pid].apply(gm, delta)

func _alert_over(mood: int) -> bool:
	# ALERT (scared-wide) overrides the calm moods, not the committed ones.
	return mood == BagEyes.Mood.IDLE or mood == BagEyes.Mood.DROOP

func _ensure_inbag_bus() -> void:
	# A muffled bus for everything you hear while zipped in: heavy breathing now,
	# proximity voice later. A low-pass filter kills the highs so it sounds like
	# it's coming through fabric.
	if AudioServer.get_bus_index(INBAG_BUS) != -1:
		return
	var idx := AudioServer.get_bus_count()
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, INBAG_BUS)
	AudioServer.set_bus_send(idx, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 600.0  # muffled: only the low breathy body of the sound survives
	AudioServer.add_bus_effect(idx, lp)

## Being caught used to mean staring at fabric-dark with zero information until
## someone happened to rescue you. It reads as "the round ended for me". Tell the
## cocooned player what's still true: who is up, that rescue is real, and that
## they can watch. Rebuilt every frame because the roster changes under them.
func _update_cocoon_text() -> void:
	if _spectating != -1:
		return  # watching a friend — overlay is hidden anyway
	var up: Array[String] = []
	for pid: int in _remote_bags:
		if not bool(_remote_bags[pid].get_meta("cocooned", false)):
			up.append(str(LobbyManager.players.get(pid, {}).get("name", "Player %d" % pid)))
	up.sort()
	var t := "COCOONED\n\nYou are zipped in tight.\n"
	if up.is_empty():
		t += "Nobody is left standing.\n"
	else:
		t += "%s must hold E next to you for %d seconds.\n" % [
			" and ".join(up), int(rescue_time)]
	t += "\n(hold Q to look back  ·  F to watch a friend)"
	_cocoon_text.text = t

func _reset_cocoon_ui() -> void:
	# Rescue / lobby reset: drop the overlay, stop the in-bag breathing, snap the
	# chase cam back out of the bag.
	_cocoon_text.visible = true
	(_cocoon_overlay as ColorRect).color.a = 0.94
	_cocoon_cam = 0.0
	if _breathing and _breathing.playing:
		_breathing.stop()

# ── Cocooned spectator cam ─────────────────────────────────────────────────

## Only while cocooned — a live player watching through someone else's eyes would
## be an information exploit; a cocooned one is out of the round anyway.
func _can_spectate() -> bool:
	return _player.state == SleepingBagPlayer.State.COCOONED and not _spectatable().is_empty()

## ANY teammate, including a cocooned one. Restricting this to survivors meant that
## the moment your last teammate was also caught the key went dead — the worst
## possible time to take someone's camera away. Watching a cocooned friend's bag
## from outside still shows you the room, the monster, and any rescue coming.
func _spectatable() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _remote_bags:
		out.append(pid)
	out.sort()
	return out

func _toggle_spectate() -> void:
	if _spectating != -1:
		_stop_spectating()
		return
	# Say why nothing happened rather than silently swallowing the key.
	if _player.state != SleepingBagPlayer.State.COCOONED:
		return
	if _spectatable().is_empty():
		_show_toast("nobody left to watch.", 2.0)
		return
	_spectating = _spectatable()[0]
	_show_toast("SPECTATING %s   ([ ] to cycle, F to return)" % _spectate_name(), 3.0)

func _cycle_spectate(dir: int) -> void:
	if _spectating == -1:
		return
	var list := _spectatable()
	if list.is_empty():
		_stop_spectating()
		return
	var i := list.find(_spectating)
	_spectating = list[(maxi(i, 0) + dir + list.size()) % list.size()]
	_show_toast("SPECTATING %s" % _spectate_name(), 2.0)

func _stop_spectating() -> void:
	if _spectating == -1:
		return
	_spectating = -1
	_show_toast("back in the bag.", 2.0)

func _spectate_name() -> String:
	return str(LobbyManager.players.get(_spectating, {}).get("name", "Player %d" % _spectating))

## The bag you're watching, or null to watch yourself.
func _spectate_target() -> Node3D:
	if _spectating == -1:
		return null
	# Vanished / gone home / you got rescued: fall back to your own view. A target
	# getting cocooned no longer kicks you out — you keep watching their bag.
	if not _remote_bags.has(_spectating) \
			or _player.state != SleepingBagPlayer.State.COCOONED:
		_stop_spectating()
		return null
	return _remote_bags[_spectating]

func _update_camera(delta: float) -> void:
	var cocooned := _player.state == SleepingBagPlayer.State.COCOONED
	# Look-back over the shoulder (hold Q). In the bag it's INSTANT (snap 180°,
	# release snaps straight back); out of the bag it eases for a smoother glance.
	var lookback_target := 1.0 if Input.is_key_pressed(KEY_Q) else 0.0
	if cocooned:
		_lookback = lookback_target
	else:
		_lookback = move_toward(_lookback, lookback_target, delta * 6.0)
	# Cocoon snap: the chase cam is killed INSTANTLY (no ease) and the camera is
	# pulled inside the bag so the fabric-dark overlay fills the screen. Snapped in
	# _cocoon_local; here we just hold it and ease back OUT on rescue.
	# Spectating a teammate (cocooned + TAB): normal chase cam on THEIR bag, and the
	# fabric-dark overlay lifts so you can actually watch.
	var watch := _spectate_target()
	if watch != null:
		_cocoon_cam = 0.0
		_cocoon_overlay.visible = false
	elif cocooned:
		_cocoon_cam = 1.0
		_cocoon_overlay.visible = true
	else:
		_cocoon_cam = move_toward(_cocoon_cam, 0.0, delta * 4.0)
	_spring.spring_length = lerpf(cam_distance, 0.12, _cocoon_cam)
	var h := lerpf(cam_height, 0.35, _cocoon_cam)
	var follow: Vector3 = watch.global_position if watch != null else _player.global_position
	var target := follow + Vector3.UP * h
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(
		target, clampf(12.0 * delta, 0.0, 1.0))
	_cam_pivot.rotation.y = _yaw + _lookback * PI
	_cam_pitch.rotation.x = _pitch
	var dist := _player.global_position.distance_to(_monster.global_position)
	var panic := clampf(1.0 - dist / chase_range, 0.0, 1.0)
	_camera.fov = lerpf(_camera.fov, lerpf(fov_base, fov_chase, panic), 8.0 * delta)

# ── Networking ─────────────────────────────────────────────────────────────

func _lobby_size() -> int:
	return (1 + multiplayer.get_peers().size()) if _net_connected() else 1

func _net_connected() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and multiplayer.get_peers().size() > 0

# Safe wrappers: `multiplayer.is_server()` / `get_unique_id()` error when the
# peer is inactive (solo, or during teardown). Route every call through these.
func _peer_live() -> bool:
	# A peer object can linger after its ENet connection drops (teardown);
	# is_server()/get_unique_id() error unless the connection is truly up.
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func _is_authority() -> bool:
	return not _net_connected() or (_peer_live() and multiplayer.is_server())

func _my_id() -> int:
	return multiplayer.get_unique_id() if _peer_live() else 1

func _net_tick(delta: float) -> void:
	var t := clampf(GHOST_LERP * delta, 0.0, 1.0)
	for pid: int in _remote_bags:
		var ghost: Node3D = _remote_bags[pid]
		var target: Array = _ghost_targets.get(pid, [])
		if target.size() == 2:
			ghost.global_position = ghost.global_position.lerp(target[0], t)
			ghost.quaternion = ghost.quaternion.slerp(target[1], t)

	if not _net_connected():
		return

	if not multiplayer.is_server() and _has_monster_target:
		_monster.global_position = _monster.global_position.lerp(_monster_target, t)

	_net_accum += delta
	if _net_accum < NET_SEND_INTERVAL:
		return
	_net_accum = 0.0
	var flags := 0
	if _player.state == SleepingBagPlayer.State.COCOONED:
		flags |= FLAG_COCOONED
	if _player.hidden:
		flags |= FLAG_HIDDEN
	_net_bag_state.rpc(_player.global_position, _player.quaternion, flags, _player.tumbles, _player.eye_mood())
	if multiplayer.is_server():
		_net_monster_state.rpc(_monster.global_position)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_bag_state(pos: Vector3, rot: Quaternion, flags: int, tumbles: int, mood: int) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not _remote_bags.has(pid):
		_spawn_remote_bag(pid)
	_ghost_targets[pid] = [pos, rot]
	_ghost_mood[pid] = mood
	var ghost: Node3D = _remote_bags[pid]
	var now_cocooned := flags & FLAG_COCOONED != 0
	if now_cocooned != bool(ghost.get_meta("cocooned", false)):
		VoiceManager.set_muffled(pid, now_cocooned)  # voice through fabric
	ghost.set_meta("cocooned", now_cocooned)
	ghost.set_meta("hidden", flags & FLAG_HIDDEN != 0)
	ghost.set_meta("tumbles", tumbles)

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_monster_state(pos: Vector3) -> void:
	if not _has_monster_target:
		print("[NETTEST] first monster state received from host")
	_monster_target = pos
	_has_monster_target = true

@rpc("any_peer", "call_remote", "reliable")
func _net_noise(pos: Vector3, loudness: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	print("[NETTEST] noise received from peer %d" % from)
	_credit_noise(from, loudness)
	NoiseBus.emit_noise(pos, loudness)

func _on_local_noise(pos: Vector3, loudness: float) -> void:
	_credit_noise(_my_id(), loudness)   # host counts its own racket too
	if _net_connected() and not multiplayer.is_server():
		_net_noise.rpc_id(1, pos, loudness)

## Only count noise DURING the round — lobby thumps and respawn settles aren't
## anyone's fault, and they'd hand out a bogus "Loudest Zipper".
func _credit_noise(pid: int, loudness: float) -> void:
	if not _is_authority() or phase != Phase.ROUND:
		return
	_bump(pid, "noise_total", loudness)
	_bump(pid, "noise_pings")

## Called by AppRoot once the lobby's START loads this scene on every peer.
## The multiplayer peer already exists; here we take our network role and,
## on the host, kick off the round once all clients report they're loaded.
func begin(is_host: bool, is_test: bool, is_spectator: bool = false) -> void:
	if not is_host:
		_monster.set_physics_process(false)
		var slot := 1 + (multiplayer.get_unique_id() % (HouseSuburban.SPAWNS.size() - 1))
		_player.global_position = HouseSuburban.SPAWNS[slot]
		_player.set_spawn(_player.global_transform)
	# The local player wears the skin they picked in the Scrapbook (cosmetic unlock).
	_player.set_skin(Scrapbook.selected_skin)
	if is_spectator:
		_become_spectator()

	# Loopback harness has no Steam and no mic: both sides stream synthetic tone
	# packets down the real voice RPC path so transport is provable headlessly.
	if is_test:
		VoiceManager.test_tone_mode = true
		VoiceManager.open_mic = true

	if is_test and not is_host:
		_start_bot_harness()
	elif is_test and is_host:
		lights_out_duration = 1.5
		var diag := Timer.new()
		diag.wait_time = 2.0
		diag.autostart = true
		diag.timeout.connect(func() -> void:
			print("[NETTEST] monster at %v %s" % [_monster.global_position,
				_monster.get_debug_text().replace("\n", " | ")]))
		add_child(diag)
		get_tree().create_timer(2.5).timeout.connect(_probe_basement_nav)

	# Round start is host-authoritative AND waits for every client's game scene
	# to load, so the LIGHTS_OUT phase RPC can't arrive before their Main exists.
	if is_host:
		_await_clients_then_start()
	elif _net_connected():
		_ack_loaded.rpc_id(1)
	_update_net_label()

# Test-mode nav probe: prove the enlarged basement rec room and the utility
# alcove (Breaker anchor) are both navmesh-reachable from the ground floor.
func _probe_basement_nav() -> void:
	var map := get_world_3d().navigation_map
	var from := HouseSuburban.scaled(Vector3(1.25, 0.5, 2.5))  # hall lane, ground floor
	var targets := {
		"rec_room": HouseSuburban.scaled(Vector3(-1.0, -2.7, -2.0)),
		"utility_breaker": HouseSuburban.scaled(HouseSuburban.BREAKER_BOX_SPOT + Vector3(0.6, 0, 0)),
	}
	for label: String in targets:
		var pts: PackedVector3Array = NavigationServer3D.map_get_path(map, from, targets[label], true)
		var end := pts[pts.size() - 1] if pts.size() > 0 else Vector3.INF
		var reached := end.distance_to(targets[label]) < 1.5
		print("[NETTEST] basement %s pts=%d reached=%s" % [label, pts.size(), reached])

var _acked_peers: Array[int] = []

func _await_clients_then_start() -> void:
	_acked_peers = [_my_id()]
	# Fallback: start anyway after 5s in case an ack is lost.
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if phase == Phase.LOBBY:
			_host_start_round())
	if not _net_connected() or multiplayer.get_peers().is_empty():
		_host_start_round()

@rpc("any_peer", "call_remote", "reliable")
func _ack_loaded() -> void:
	if not _is_authority():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _acked_peers.has(pid):
		_acked_peers.append(pid)
	# Everyone (host + all connected peers) is in — begin the night.
	if _acked_peers.size() >= multiplayer.get_peers().size() + 1 and phase == Phase.LOBBY:
		_host_start_round()

func _become_spectator() -> void:
	# Joined after START: watch, don't play. Bag is hidden and inert.
	_player.set_physics_process(false)
	_player.visible = false
	_show_toast("SPECTATING — you joined mid-round.", 6.0)

func _start_bot_harness() -> void:
	# ENet loopback test: ping + wander like a player (silent while cocooned).
	var ping_timer := Timer.new()
	ping_timer.wait_time = 3.0
	ping_timer.autostart = true
	ping_timer.timeout.connect(func() -> void:
		if _player.state != SleepingBagPlayer.State.COCOONED:
			NoiseBus.emit_noise(_player.global_position, 1.0)
			print("[NETTEST] client emitted noise ping"))
	add_child(ping_timer)
	var wander := Timer.new()
	wander.wait_time = 0.15
	wander.autostart = true
	wander.timeout.connect(func() -> void:
		if _player.state != SleepingBagPlayer.State.COCOONED:
			var wt := Time.get_ticks_msec() / 1000.0
			_player.apply_central_impulse(Vector3(sin(wt * 0.6), 0.0, cos(wt * 0.6)) * 0.8))
	add_child(wander)

func _on_peer_disconnected(pid: int) -> void:
	VoiceManager.unregister_player(pid)
	if _remote_bags.has(pid):
		_remote_bags[pid].queue_free()
		_remote_bags.erase(pid)
		_ghost_targets.erase(pid)
		_ghost_eyes.erase(pid)
		_ghost_mood.erase(pid)
	_update_net_label()

func _spawn_remote_bag(pid: int) -> Node3D:
	var ghost := Node3D.new()
	# Use the peer's chosen skin from the roster (they reported it); fall back to
	# the deterministic per-peer skin if the roster doesn't carry one.
	var skin := int(LobbyManager.players.get(pid, {}).get("skin", BagVisual.skin_for_peer(pid)))
	var built := BagVisual.build_with_eyes(0.9, skin)
	var bag: Node3D = built[0]
	bag.position = Vector3(0, -0.45, 0)
	ghost.add_child(bag)
	add_child(ghost)
	ghost.global_position = _player.global_position
	_remote_bags[pid] = ghost
	_ghost_eyes[pid] = built[1]   # BagEyes for this ghost
	_ghost_mood[pid] = BagEyes.Mood.IDLE
	# Their voice comes out of their bag — proximity attenuation via the 3D mixer.
	VoiceManager.voice_range = voice_range
	VoiceManager.register_player(pid, ghost)
	print("[NETTEST] ghost bag spawned for peer %d" % pid)
	return ghost

func _update_net_label() -> void:
	if not SteamManager.steam_ok and SteamManager.lobby_id == 0:
		_net_label.text = "NET: solo"
	elif SteamManager.lobby_id == 0:
		_net_label.text = "NET: solo (%s)" % SteamManager.persona()
	else:
		var role := "HOST" if SteamManager.is_host else "CLIENT"
		_net_label.text = "NET: %s  code %s  — %d player(s)" % [
			role, SteamManager.join_code, multiplayer.get_peers().size() + 1]
