extends Node3D
## Sleepover game scene: full-house gray-box + camera + HUD + net sync.
## The house itself is built by maps/house_suburban/HouseSuburban.gd from data
## tables; this script owns actors, camera, HUD, and the catch/reset loop.
##
## CAMERA (part of the kill test — spec Part 2.1): low, close, third-person
## chase cam. ~0.9m height, ~2.2m behind, right-shoulder offset, mouse-orbit,
## SpringArm3D for wall collision. Ground-level scale makes the house loom.
## Chase juice: FOV 70 -> 82 + shake when the monster is within 8m.
## Q = quick 180° look-back glance (camera only; movement keeps its heading).
## All geometry is procedural — no assets required.

@export var catch_radius: float = 1.2

@export_group("Camera")
@export var cam_height: float = 0.9        ## pivot height above the bag (m)
@export var cam_distance: float = 2.2      ## spring arm length behind (m)
@export var cam_shoulder: float = 0.35     ## right-shoulder offset (m)
@export var mouse_sensitivity: float = 0.004
@export var cam_pitch_default: float = -6.0  ## degrees; slightly down at the bag
@export var fov_base: float = 70.0
@export var fov_chase: float = 82.0        ## kicks in when monster is close
@export var chase_range: float = 8.0       ## monster within this = FOV kick (no shake)

var _player: SleepingBagPlayer
var _monster: NoiseMonster
var _cam_pivot: Node3D
var _cam_pitch: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _lookback: float = 0.0   ## 0 = forward, 1 = fully turned around (Q held)
var _aim: MeshInstance3D
var _state_label: Label
var _net_label: Label
var _pips: Array[ColorRect] = []
var _caught: bool = false

# ── Networking (Week-1 GodotSteam spike) ───────────────────────────────────
# Each peer simulates its OWN bag; remote bags are interpolated ghosts.
# The HOST is authoritative for the monster: it simulates, clients display.
var _remote_bags: Dictionary = {}     ## peer_id -> Node3D ghost
var _ghost_targets: Dictionary = {}   ## peer_id -> [pos: Vector3, rot: Quaternion]
var _monster_target: Vector3
var _has_monster_target: bool = false
var _net_accum: float = 0.0

const NET_SEND_INTERVAL := 0.05       ## 20 Hz state sync
const GHOST_LERP := 10.0              ## ~100ms interpolation buffer feel

const PIP_ON := Color(1.0, 0.85, 0.25)
const PIP_OFF := Color(0.25, 0.25, 0.28)

func _ready() -> void:
	_build_environment()
	_build_level()
	_spawn_actors()
	_build_camera()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	SteamManager.lobby_ready.connect(_on_lobby_ready)
	SteamManager.lobby_failed.connect(func(reason: String) -> void:
		_net_label.text = "NET: " + reason)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	NoiseBus.noise_emitted.connect(_on_local_noise)
	_update_net_label()

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
	# The full suburban house gray-box — layout data lives with the map.
	# Built under a NavigationRegion3D so the monster's navmesh bakes from it.
	var nav_region := NavigationRegion3D.new()
	add_child(nav_region)
	HouseSuburban.build(nav_region)

	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.35        # doors are 1.1m wide — leaves a walkable gap
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.4      # stair steps rise 0.3; must survive voxel floor
	nm.cell_size = 0.2            # matches navigation/3d defaults in project.godot
	nm.cell_height = 0.2
	nm.geometry_collision_mask = 1  # bake real geometry only, not player stair ramps
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)  # synchronous — one beat at startup

func _spawn_actors() -> void:
	_player = SleepingBagPlayer.new()
	_player.position = HouseSuburban.SPAWNS[0]
	add_child(_player)

	_monster = NoiseMonster.new()
	_monster.position = HouseSuburban.MONSTER_SPAWN
	_monster.player = _player
	_monster.patrol_span = 2.8  # wanders its (scaled-up) room; navmesh handles the rest
	add_child(_monster)

	# Floating aim arrow so you can read your heading (the bag itself tumbles).
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

func _build_camera() -> void:
	# Pivot (yaw) -> pitch node -> spring arm (wall collision) -> camera.
	_cam_pivot = Node3D.new()
	add_child(_cam_pivot)

	_cam_pitch = Node3D.new()
	_cam_pivot.add_child(_cam_pitch)
	_pitch = deg_to_rad(cam_pitch_default)

	_spring = SpringArm3D.new()
	_spring.spring_length = cam_distance
	_spring.position.x = cam_shoulder      # right-shoulder bias
	_spring.margin = 0.15
	_cam_pitch.add_child(_spring)

	_camera = Camera3D.new()
	_camera.fov = fov_base
	_camera.current = true
	_spring.add_child(_camera)

	# The spring ray must not collide with the player's own capsule.
	_spring.add_excluded_object(_player.get_rid())

	_snap_camera()

func _snap_camera() -> void:
	_cam_pivot.global_position = _player.global_position + Vector3.UP * cam_height
	_cam_pivot.rotation.y = _yaw
	_cam_pitch.rotation.x = _pitch

# ── HUD ────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var help := Label.new()
	help.text = "WASD shuffle   Space hop (1 pip — empty = face-plant!)   Q look back   R reset (host)   Esc cursor"
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

	# Stamina pip bar, bottom-center — players must FEEL the count, not read it.
	var pip_row := HBoxContainer.new()
	pip_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pip_row.position = Vector2(-70, -48)  # relative to bottom-center anchor
	pip_row.add_theme_constant_override("separation", 6)
	layer.add_child(pip_row)
	for i in range(int(_player.stamina_max)):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(24, 10)
		pip.color = PIP_ON
		pip_row.add_child(pip)
		_pips.append(pip)

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
			KEY_H:
				SteamManager.host_lobby()
			KEY_J:
				SteamManager.join_lobby()
			KEY_R:
				_reset()
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── Frame loop ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_camera(delta)

	# Movement is camera-relative: tell the player which way "W" points.
	_player.control_yaw = _yaw

	# Aim arrow floats just in front of the player, showing hop direction.
	var fwd: Vector3 = _player.facing
	_aim.global_position = _player.global_position + fwd * 1.3 + Vector3.UP * 0.2
	_aim.look_at(_aim.global_position + fwd, Vector3.UP)
	_aim.rotate_object_local(Vector3.RIGHT, -PI / 2.0)

	# Catch check.
	if not _caught and _player.global_position.distance_to(_monster.global_position) < catch_radius:
		_caught = true
		_player.set_caught()
		print("[NETTEST] local player caught")

	if _caught:
		_state_label.text = "CAUGHT!  Press R to reset"
		_state_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:
		_state_label.text = _player.get_state_text()
		_state_label.remove_theme_color_override("font_color")

	# Stamina pips: lit = a hop you can afford.
	for i in range(_pips.size()):
		_pips[i].color = PIP_ON if _player.stamina >= float(i + 1) else PIP_OFF

	_net_tick(delta)

# ── Networking: state sync (Week-1 GodotSteam spike) ───────────────────────

func _net_connected() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and multiplayer.get_peers().size() > 0

func _net_tick(delta: float) -> void:
	# Smoothly interpolate remote ghosts toward their latest network state.
	var t := clampf(GHOST_LERP * delta, 0.0, 1.0)
	for pid: int in _remote_bags:
		var ghost: Node3D = _remote_bags[pid]
		var target: Array = _ghost_targets.get(pid, [])
		if target.size() == 2:
			ghost.global_position = ghost.global_position.lerp(target[0], t)
			ghost.quaternion = ghost.quaternion.slerp(target[1], t)

	if not _net_connected():
		return

	# Client: display the host's monster.
	if not multiplayer.is_server() and _has_monster_target:
		_monster.global_position = _monster.global_position.lerp(_monster_target, t)

	# Host: aim the monster at whichever bag is nearest (local or remote ghost).
	if multiplayer.is_server():
		_monster.player = _nearest_bag()
		# Host also catches remote players.
		for pid: int in _remote_bags:
			if _monster.global_position.distance_to(_remote_bags[pid].global_position) < catch_radius:
				_net_caught.rpc_id(pid)

	# 20 Hz state broadcast.
	_net_accum += delta
	if _net_accum < NET_SEND_INTERVAL:
		return
	_net_accum = 0.0
	_net_bag_state.rpc(_player.global_position, _player.quaternion)
	if multiplayer.is_server():
		_net_monster_state.rpc(_monster.global_position)

func _nearest_bag() -> Node3D:
	var best: Node3D = _player
	var best_d := _monster.global_position.distance_to(_player.global_position)
	for pid: int in _remote_bags:
		var d := _monster.global_position.distance_to(_remote_bags[pid].global_position)
		if d < best_d:
			best_d = d
			best = _remote_bags[pid]
	return best

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_bag_state(pos: Vector3, rot: Quaternion) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not _remote_bags.has(pid):
		_spawn_remote_bag(pid)
	_ghost_targets[pid] = [pos, rot]

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_monster_state(pos: Vector3) -> void:
	if not _has_monster_target:
		print("[NETTEST] first monster state received from host")
	_monster_target = pos
	_has_monster_target = true

@rpc("any_peer", "call_remote", "reliable")
func _net_noise(pos: Vector3, loudness: float) -> void:
	# A remote player made noise — replay it locally so the host monster hears.
	print("[NETTEST] noise received from peer %d" % multiplayer.get_remote_sender_id())
	NoiseBus.emit_noise(pos, loudness)

@rpc("authority", "call_remote", "reliable")
func _net_caught() -> void:
	if not _caught:
		print("[NETTEST] caught by host monster")
		_caught = true
		_player.set_caught()

func _on_local_noise(pos: Vector3, loudness: float) -> void:
	# Forward our own noise pings to the host so its monster reacts to us.
	if _net_connected() and not multiplayer.is_server():
		_net_noise.rpc_id(1, pos, loudness)

func _on_lobby_ready(lobby_id: int, is_host: bool) -> void:
	if not is_host:
		# The host simulates the monster; we only display its synced position.
		_monster.set_physics_process(false)
		# Move off the host's spawn slot so bags don't start inside each other.
		var slot := 1 + (multiplayer.get_unique_id() % (HouseSuburban.SPAWNS.size() - 1))
		_player.global_position = HouseSuburban.SPAWNS[slot]
		_player.set_spawn(_player.global_transform)
	if lobby_id == -1 and not is_host:
		# ENet loopback test mode: ping every few seconds like a hopping player
		# so noise-forwarding, the cross-house hunt, and the catch RPC all run.
		var ping_timer := Timer.new()
		ping_timer.wait_time = 3.0
		ping_timer.autostart = true
		ping_timer.timeout.connect(func() -> void:
			NoiseBus.emit_noise(_player.global_position, 1.0)
			print("[NETTEST] client emitted noise ping"))
		add_child(ping_timer)
	elif lobby_id == -1 and is_host:
		_monster.debug_nav = true
		# ...and the host orders a round reset late in the test window.
		get_tree().create_timer(20.0).timeout.connect(_reset)
		# Diagnostic heartbeat: where is the monster and what is it thinking?
		var diag := Timer.new()
		diag.wait_time = 2.0
		diag.autostart = true
		diag.timeout.connect(func() -> void:
			print("[NETTEST] monster at %v state=%d" % [_monster.global_position, _monster._state])
			if not has_meta("path_printed"):
				set_meta("path_printed", true)
				var map := get_world_3d().navigation_map
				var path := NavigationServer3D.map_get_path(
					map, Vector3(0, 0.5, -3.5), Vector3(-5, 0.5, 1), true)
				print("[NETTEST] dining->living path: %s" % str(path)))
		add_child(diag)
	_update_net_label()

func _on_peer_connected(_pid: int) -> void:
	_update_net_label()

func _on_peer_disconnected(pid: int) -> void:
	if _remote_bags.has(pid):
		_remote_bags[pid].queue_free()
		_remote_bags.erase(pid)
		_ghost_targets.erase(pid)
	_update_net_label()

func _spawn_remote_bag(pid: int) -> Node3D:
	# A ghost: same silhouette, different color, no physics — pure display.
	var ghost := Node3D.new()
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.3
	mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15)  # orange vs your cyan
	mesh.set_surface_override_material(0, mat)
	ghost.add_child(mesh)
	add_child(ghost)
	ghost.global_position = _player.global_position
	_remote_bags[pid] = ghost
	print("[NETTEST] ghost bag spawned for peer %d" % pid)
	return ghost

func _update_net_label() -> void:
	if not SteamManager.steam_ok:
		_net_label.text = "NET: Steam offline — solo mode"
	elif SteamManager.lobby_id == 0:
		_net_label.text = "NET: solo (%s)   H = host lobby   J = join lobby" % SteamManager.persona()
	else:
		var role := "HOST" if SteamManager.is_host else "CLIENT"
		_net_label.text = "NET: %s in lobby %d — %d player(s) connected" % [
			role, SteamManager.lobby_id, multiplayer.get_peers().size() + 1]

func _update_camera(delta: float) -> void:
	# Q look-back: swings the camera (not your movement heading) 180°.
	var lookback_target := 1.0 if Input.is_key_pressed(KEY_Q) else 0.0
	_lookback = move_toward(_lookback, lookback_target, delta * 6.0)

	# Follow the bag; smooth only the position, keep orbit 1:1 with the mouse.
	var target := _player.global_position + Vector3.UP * cam_height
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(
		target, clampf(12.0 * delta, 0.0, 1.0))
	_cam_pivot.rotation.y = _yaw + _lookback * PI
	_cam_pitch.rotation.x = _pitch

	# Chase juice: FOV ramps in from chase_range — the dread you feel early.
	var dist := _player.global_position.distance_to(_monster.global_position)
	var panic := clampf(1.0 - dist / chase_range, 0.0, 1.0)
	_camera.fov = lerpf(_camera.fov, lerpf(fov_base, fov_chase, panic), 8.0 * delta)

	# Shake removed for now — playtest verdict: seizure-inducing, not scary.
	# The FOV kick above carries the proximity dread on its own.

func _reset() -> void:
	# In a lobby the round is host-authoritative: only the host's R resets,
	# and it resets EVERYONE. Clients' R does nothing while connected.
	if _net_connected():
		if multiplayer.is_server():
			_net_reset.rpc()
			_do_reset()
	else:
		_do_reset()

func _do_reset() -> void:
	_caught = false
	_player.respawn()
	_monster.respawn()

@rpc("authority", "call_remote", "reliable")
func _net_reset() -> void:
	print("[NETTEST] reset ordered by host")
	_do_reset()

