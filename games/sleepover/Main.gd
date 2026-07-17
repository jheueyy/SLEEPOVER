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

var _player: SleepingBagPlayer
var _monster: NoiseMonster
var _cam_pivot: Node3D
var _cam_pitch: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _lookback: float = 0.0
var _aim: MeshInstance3D

# HUD
var _state_label: Label
var _net_label: Label
var _toast: Label
var _clock_label: Label
var _prompt_label: Label
var _tracker_label: Label
var _debug_label: Label
var _pips: Array[ColorRect] = []
var _cocoon_overlay: Control
var _results_overlay: Control
var _results_label: Label
var _phone_panel: PanelContainer
var _phone_label: Label

# Round state
var phase: Phase = Phase.LOBBY
var _phase_timer: float = 0.0
var _round_elapsed: float = 0.0
var _objectives: Array[Objective] = []   ## the 5 active this round
var _done_ids: Array[String] = []        ## objective ids completed (need 3)
var _escape_armed: bool = false
var _blurred_pid: int = 0                 ## glasses: whose screen is blurred (0 = nobody)
var _rescue_target: Node3D = null
var _rescue_t: float = 0.0
var _rescue_zipped: bool = false
var _debug_visible: bool = false
var _monster_fx_state: int = -1

# Glasses blur (post-process on the one blurred player)
var _blur_overlay: ColorRect

# Audio
var _heartbeat: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _zip_sound: AudioStreamPlayer

# Networking: each peer simulates its OWN bag; remote bags are ghosts.
var _remote_bags: Dictionary = {}     ## peer_id -> Node3D ghost
var _ghost_targets: Dictionary = {}   ## peer_id -> [pos, rot]
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
	# 1. OBJECTIVES + ESCAPE. 5 spawn; completing 3 arms escape + unlocks doors;
	#    walking into TWO different exits both end the round in ESCAPE.
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	var ok_count := _objectives.size() == 5
	var front_locked := _exit_door_locked("front_door")
	# Force 3 objectives done (whichever 5 were drawn).
	for i in 3:
		_authoritative_complete(_objectives[i].def.id)
	var ok_armed := _escape_armed and not _exit_door_locked("front_door")
	# Exit A: front door.
	var exits := HouseSuburban.exits()
	_player.global_position = exits[0]["at"]
	_net_report_escape(1)
	var ok_exit_a := phase == Phase.RESULTS and _results_label.text.contains("ESCAPE")
	# Exit B: garage (fresh armed round).
	_apply_phase(Phase.LOBBY, {})
	_host_start_round()
	_apply_phase(Phase.ROUND, {})
	for i in 3:
		_authoritative_complete(_objectives[i].def.id)
	_player.global_position = exits[1]["at"]
	_net_report_escape(1)
	var ok_exit_b := phase == Phase.RESULTS and _results_label.text.contains("ESCAPE")
	print("[SELFTEST] objectives: 5spawn=%s front-locked=%s 3done-arms=%s exitA=%s exitB=%s" % [
		ok_count, front_locked, ok_armed, ok_exit_a, ok_exit_b])
	pass_all = pass_all and ok_count and front_locked and ok_armed and ok_exit_a and ok_exit_b

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

	print("[SELFTEST] RESULT: %s" % ("ALL PASS" if pass_all else "FAIL"))
	get_tree().quit(0 if pass_all else 1)

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
	help.text = "WASD shuffle   Space hop   E interact   Q look back   F3 debug   Esc cursor"
	help.position = Vector2(16, 12)
	layer.add_child(help)

	_state_label = Label.new()
	_state_label.position = Vector2(16, 40)
	_state_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_state_label)

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
	_prompt_label.position = Vector2(-260, -110)
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
	var cocoon_text := Label.new()
	cocoon_text.text = "COCOONED\n\nYou are zipped in tight.\nA friend must hold E next to you for 5 seconds."
	cocoon_text.set_anchors_preset(Control.PRESET_CENTER)
	cocoon_text.position = Vector2(-260, -60)
	cocoon_text.custom_minimum_size = Vector2(520, 120)
	cocoon_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cocoon_text.add_theme_font_size_override("font_size", 24)
	_cocoon_overlay.add_child(cocoon_text)

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
	_clear_objectives()
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
	var objs: Array = []
	var has_glasses := false
	for d: ObjectiveDef in defs:
		var s := {"id": d.id}
		if d.clue_spots.size() > 0:
			s["clue"] = randi() % d.clue_spots.size()
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
	var data := {"objs": objs, "blurred": blurred}
	_apply_phase(Phase.LIGHTS_OUT, data)
	if _net_connected():
		_net_phase.rpc(Phase.LIGHTS_OUT, data)

func _apply_phase(p: Phase, data: Dictionary) -> void:
	phase = p
	match p:
		Phase.LOBBY:
			_enter_lobby()
		Phase.LIGHTS_OUT:
			_phase_timer = lights_out_duration
			_setup_objectives(data)
			_player.respawn()
			_monster.respawn()
			_monster.set_wake(lights_out_duration)
			_cocoon_overlay.visible = false
			_show_toast("LIGHTS OUT.", 3.0)
			print("[NETTEST] phase=LIGHTS_OUT objs=%d blurred=%d" % [
				(data.get("objs", []) as Array).size(), data.get("blurred", 0)])
		Phase.ROUND:
			_phase_timer = round_duration
			_round_elapsed = 0.0
			print("[NETTEST] phase=ROUND")
		Phase.RESULTS:
			_show_results(data)
			print("[NETTEST] phase=RESULTS outcome=%s" % data.get("outcome"))

@rpc("authority", "call_remote", "reliable")
func _net_phase(p: int, data: Dictionary) -> void:
	_apply_phase(p as Phase, data)

func _host_end_round(outcome: String) -> void:
	if phase != Phase.ROUND:
		return
	var stats := {"outcome": outcome, "time": _round_elapsed, "tumbles": _collect_tumbles()}
	_apply_phase(Phase.RESULTS, stats)
	if _net_connected():
		_net_phase.rpc(Phase.RESULTS, stats)

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
	var text: String = headline + "\n\nnight lasted %d:%02d\n\n" % [
		int(data.get("time", 0.0)) / 60, int(data.get("time", 0.0)) % 60]
	var tumbles: Dictionary = data.get("tumbles", {})
	for pid: int in tumbles:
		text += "player %d — %d tumbles\n" % [pid, tumbles[pid]]
	text += "\nhost presses ENTER to return to the lobby"
	_results_label.text = text
	_results_overlay.visible = true
	_cocoon_overlay.visible = false
	_phone_panel.visible = false

# ── Objectives (data-driven; complete any 3 to arm escape) ─────────────────

func _setup_objectives(data: Dictionary) -> void:
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
	_show_toast("Task done (%d/3).  %s" % [mini(_done_ids.size(), 3), id], 3.0)
	print("[NETTEST] objective done: %s (%d)" % [id, _done_ids.size()])

func _arm_escape() -> void:
	_escape_armed = true
	_set_exits_locked(false)
	_show_toast("3 TASKS DONE. The exits are open — GET OUT.", 6.0)
	print("[NETTEST] escape armed")

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
	# Which unlocked exit (if any) the local player is standing in.
	if not _escape_armed:
		return ""
	var p := _player.global_position
	for e: Dictionary in HouseSuburban.exits():
		var at: Vector3 = e["at"]
		var half: Vector2 = e["half"]
		if absf(p.x - at.x) < half.x and absf(p.z - at.z) < half.y and absf(p.y - at.y) < 2.5:
			return e["name"]
	return ""

@rpc("any_peer", "call_remote", "reliable")
func _net_report_escape(pid: int) -> void:
	if _is_authority() and phase == Phase.ROUND and _escape_armed:
		print("[NETTEST] escape by peer %d" % pid)
		_host_end_round("ESCAPE")

# ── Cocoon & rescue ────────────────────────────────────────────────────────

func _on_monster_lunged_hit(target: Node3D) -> void:
	# Host only (the monster simulates on the host).
	if target == _player:
		_cocoon_local()
	else:
		for pid: int in _remote_bags:
			if _remote_bags[pid] == target:
				target.set_meta("cocooned", true)
				_net_cocoon.rpc_id(pid)
				break

@rpc("authority", "call_remote", "reliable")
func _net_cocoon() -> void:
	_cocoon_local()

func _cocoon_local() -> void:
	if _player.state == SleepingBagPlayer.State.COCOONED:
		return
	_player.cocoon()
	_cocoon_overlay.visible = true
	print("[NETTEST] cocooned (me)")

@rpc("any_peer", "call_remote", "reliable")
func _net_rescued(victim_pid: int) -> void:
	_apply_rescue(victim_pid)

func _apply_rescue(victim_pid: int) -> void:
	var my_id := _my_id()
	if victim_pid == my_id:
		_player.rescue()
		_cocoon_overlay.visible = false
		print("[NETTEST] rescued (me)")
	elif _remote_bags.has(victim_pid):
		_remote_bags[victim_pid].set_meta("cocooned", false)

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
			if _net_connected():
				_net_rescued.rpc(candidate_pid)
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

func _try_interact_press() -> void:
	if phase != Phase.ROUND or _player.state == SleepingBagPlayer.State.COCOONED:
		return
	if _rescue_target != null:
		return  # rescue is the hold-E path
	var p := _player.global_position
	for o: Objective in _objectives:
		if o.try_interact(p):
			return

# ── Frame loop ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_camera(delta)
	_player.control_yaw = _yaw

	var fwd: Vector3 = _player.facing
	_aim.global_position = _player.global_position + fwd * 1.3 + Vector3.UP * 0.2
	_aim.look_at(_aim.global_position + fwd, Vector3.UP)
	_aim.rotate_object_local(Vector3.RIGHT, -PI / 2.0)

	_state_label.text = _player.get_state_text()
	for i in range(_pips.size()):
		_pips[i].color = PIP_ON if _player.stamina >= float(i + 1) else PIP_OFF

	_prompt_label.text = ""
	if phase == Phase.ROUND:
		_update_rescue(delta)
		_update_objectives(delta)
		_update_prompts()
		_update_tracker()
	else:
		_tracker_label.text = ""
		# Escape: through any unlocked exit, out into the night.
		if _escape_armed and _player_at_exit() != "" \
				and _player.state != SleepingBagPlayer.State.COCOONED:
			if _is_authority():
				_net_report_escape(_my_id())
			else:
				_net_report_escape.rpc_id(1, _my_id())

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
	if _rescue_target != null:
		if not Input.is_key_pressed(KEY_E):
			_prompt_label.text = "HOLD E TO RESCUE"
		return
	var p := _player.global_position
	for o: Objective in _objectives:
		var pr := o.prompt(p)
		if pr != "":
			_prompt_label.text = pr
			return

func _update_tracker() -> void:
	# WHAT + WHETHER, never WHERE. Name only until a clue is found; then the
	# action detail. State: [x] done, [~] in progress, [ ] not started.
	var text := "ESCAPE  %d / 3 tasks\n" % mini(_done_ids.size(), 3)
	for o: Objective in _objectives:
		var box := " "
		match o.tracker_state():
			Objective.Tracker.DONE: box = "x"
			Objective.Tracker.IN_PROGRESS: box = "~"
		var line := "[%s] %s" % [box, o.def.display_name]
		if o.is_revealed() and o.tracker_state() != Objective.Tracker.DONE:
			line += "  —  " + o.tracker_detail()
		text += line + "\n"
	_tracker_label.text = text

func _update_phase(delta: float) -> void:
	var is_authority := _is_authority()
	match phase:
		Phase.LIGHTS_OUT:
			_phase_timer -= delta
			_clock_label.text = "dark in %d..." % int(ceil(maxf(_phase_timer, 0.0)))
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

func _update_camera(delta: float) -> void:
	var lookback_target := 1.0 if Input.is_key_pressed(KEY_Q) else 0.0
	_lookback = move_toward(_lookback, lookback_target, delta * 6.0)
	var target := _player.global_position + Vector3.UP * cam_height
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(
		target, clampf(12.0 * delta, 0.0, 1.0))
	_cam_pivot.rotation.y = _yaw + _lookback * PI
	_cam_pitch.rotation.x = _pitch
	var dist := _player.global_position.distance_to(_monster.global_position)
	var panic := clampf(1.0 - dist / chase_range, 0.0, 1.0)
	_camera.fov = lerpf(_camera.fov, lerpf(fov_base, fov_chase, panic), 8.0 * delta)

# ── Networking ─────────────────────────────────────────────────────────────

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
	_net_bag_state.rpc(_player.global_position, _player.quaternion, flags, _player.tumbles)
	if multiplayer.is_server():
		_net_monster_state.rpc(_monster.global_position)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_bag_state(pos: Vector3, rot: Quaternion, flags: int, tumbles: int) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not _remote_bags.has(pid):
		_spawn_remote_bag(pid)
	_ghost_targets[pid] = [pos, rot]
	var ghost: Node3D = _remote_bags[pid]
	ghost.set_meta("cocooned", flags & FLAG_COCOONED != 0)
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
	print("[NETTEST] noise received from peer %d" % multiplayer.get_remote_sender_id())
	NoiseBus.emit_noise(pos, loudness)

func _on_local_noise(pos: Vector3, loudness: float) -> void:
	if _net_connected() and not multiplayer.is_server():
		_net_noise.rpc_id(1, pos, loudness)

## Called by AppRoot once the lobby's START loads this scene on every peer.
## The multiplayer peer already exists; here we take our network role and,
## on the host, kick off the round once all clients report they're loaded.
func begin(is_host: bool, is_test: bool, is_spectator: bool = false) -> void:
	if not is_host:
		_monster.set_physics_process(false)
		var slot := 1 + (multiplayer.get_unique_id() % (HouseSuburban.SPAWNS.size() - 1))
		_player.global_position = HouseSuburban.SPAWNS[slot]
		_player.set_spawn(_player.global_transform)
		_player.set_skin(BagVisual.skin_for_peer(multiplayer.get_unique_id()))
	if is_spectator:
		_become_spectator()

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
	var from := Vector3(9.1, 0.5, 0.0)  # garage, ground floor
	var targets := {
		"rec_room": HouseSuburban.scaled(Vector3(6.0, -2.7, -3.5)),
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
	if _remote_bags.has(pid):
		_remote_bags[pid].queue_free()
		_remote_bags.erase(pid)
		_ghost_targets.erase(pid)
	_update_net_label()

func _spawn_remote_bag(pid: int) -> Node3D:
	var ghost := Node3D.new()
	var bag := BagVisual.build(0.9, BagVisual.skin_for_peer(pid))
	bag.position = Vector3(0, -0.45, 0)
	ghost.add_child(bag)
	add_child(ghost)
	ghost.global_position = _player.global_position
	_remote_bags[pid] = ghost
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
