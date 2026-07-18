extends CharacterBody3D
class_name NoiseMonster
## The Housesitter. SENSES-ONLY AI: it never reads a player position directly —
## its ONLY inputs are NoiseBus pings and line-of-sight checks. State machine:
##   ASLEEP      — round hasn't started (wake_delay); deaf, blind, motionless
##   PATROL      — walks a waypoint lap through the house, humming a lullaby
##   INVESTIGATE — walks to a ping, searches ~investigate_time; a second ping
##                 while investigating escalates straight to CHASE
##   CHASE       — hunts the LAST KNOWN position (updated only by sight/pings);
##                 loses the trail after chase_memory secs of no contact
##   LUNGE       — within lunge_range with line of sight: windup screech, then
##                 a straight burst. Connecting = the victim is COCOONED.
## Movement is navmesh-routed and collision-free; feet snap to the visible
## treads. Main supplies targets, patrol points, and handles cocooning.

signal woke_up
signal state_changed(new_state: int)
signal lunged_hit(target: Node3D)

@export var move_speed: float = 2.6        ## chase speed: > shuffle (2.0), < hop chain (~3.6). FEEL.md
@export var patrol_speed_mult: float = 0.45 ## patrol crawl, relative to move_speed
@export var patrol_floor_dwell: float = 20.0 ## max secs on one floor in PATROL before routing to another
@export var wake_delay: float = 40.0       ## secs asleep at round start
@export var hearing_radius: float = 14.0   ## pings farther than this don't exist
@export var solo_hearing_mult: float = 0.6 ## solo test: hearing x0.6 (−40%) so it doesn't zero in
@export var solo_chase_memory: float = 8.0 ## solo test: give up after 8s instead of 12
@export var investigate_time: float = 8.0  ## secs spent searching a ping site
@export var pings_to_chase: int = 3        ## this many pings within ping_window = chase
@export var ping_window: float = 10.0
@export var chase_memory: float = 12.0     ## secs of no sight/ping before the trail dies
@export var sight_range: float = 8.0       ## darkness-adjusted eyes — short on purpose
@export var sight_fov_deg: float = 120.0   ## vision cone around its heading
@export var sight_min_speed: float = 0.6   ## slower than this = invisible. FREEZE to hide.
@export var turn_rate: float = 2.5         ## heading turn speed, rad/s — juke window
@export var lunge_range: float = 3.0       ## chase + LOS inside this = lunge
@export var lunge_windup: float = 0.4      ## stationary screech before the burst
@export var lunge_speed_mult: float = 2.3  ## burst speed multiplier
@export var lunge_hit_radius: float = 1.1  ## connect distance = cocoon
@export var lunge_cooldown: float = 1.6    ## recovery after a miss
@export var shush_range: float = 4.0       ## chase + within this = it shushes you
@export var shush_cooldown: float = 3.5    ## secs between shushes

enum State { PATROL, INVESTIGATE, CHASE, LUNGE }

const BODY_HEIGHT := 2.4  # tall enough to loom over 0.9m bags; hunches at doors

var patrol_points: Array[Vector3] = []     ## set by Main (HouseSuburban loop)
var get_targets: Callable                  ## set by Main; returns Array of bags

var _state: State = State.PATROL
var _asleep: bool = true
var _wake_timer: float = 0.0
var _patrol_i: int = 0
var _floor_dwell: float = 0.0              ## secs on the current floor while patrolling
var _patrol_floor: int = -1               ## floor we've been dwelling on
var _base_hearing: float = 14.0           ## export defaults captured for the solo modifier
var _base_chase_memory: float = 12.0
var _last_known: Vector3                   ## the only "player position" it has
var _chase_timer: float = 0.0
var _dwell: float = 0.0
var _ping_times: Array[float] = []
var _lunge_t: float = 0.0
var _lunge_dir: Vector3 = Vector3.ZERO
var _lunge_traveled: float = 0.0
var _lunge_cd: float = 0.0
var _last_ping_pos: Vector3 = Vector3.ZERO

# Path following (manual — see _repath; NavigationAgent3D deadlocks descents)
var _path: PackedVector3Array = []
var _path_i: int = 0
var _path_goal: Vector3 = Vector3(INF, INF, INF)
var _prev_wp: Vector3 = Vector3.ZERO
var _on_link: bool = false
var _repath_cd: float = 0.0
var _move_dir: Vector3 = Vector3.ZERO
var _facing: Vector3 = Vector3(0, 0, -1)

var _spawn: Transform3D
var _body: Node3D
var _watched: Node3D
var _watched_prev: Vector3
var _hum: AudioStreamPlayer3D
var _creak: AudioStreamPlayer3D
var _screech: AudioStreamPlayer3D
var _shush: AudioStreamPlayer3D
var _creak_cd: float = 2.0
var _shush_cd: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	_build_body()
	_build_audio()
	_spawn = global_transform
	_wake_timer = wake_delay
	_base_hearing = hearing_radius
	_base_chase_memory = chase_memory
	NoiseBus.noise_emitted.connect(_on_noise)

func _build_body() -> void:
	# Concept sheet: a tall quilted bell of old bedding with a pale mask face.
	_body = Node3D.new()
	_body.position = Vector3(0, -0.4, 0)
	add_child(_body)

	var cloak_mat := StandardMaterial3D.new()
	cloak_mat.albedo_color = Color(0.23, 0.13, 0.17)
	cloak_mat.roughness = 0.95
	var cloak := MeshInstance3D.new()
	var bell := CylinderMesh.new()
	bell.top_radius = 0.10
	bell.bottom_radius = 0.60
	bell.height = BODY_HEIGHT
	cloak.mesh = bell
	cloak.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	cloak.set_surface_override_material(0, cloak_mat)
	_body.add_child(cloak)

	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.92, 0.87, 0.72)
	face_mat.emission_enabled = true
	face_mat.emission = Color(0.45, 0.42, 0.32)
	var face := MeshInstance3D.new()
	var face_mesh := SphereMesh.new()
	face_mesh.radius = 0.16
	face_mesh.height = 0.38
	face.mesh = face_mesh
	face.position = Vector3(0, BODY_HEIGHT * 0.82, -0.16)
	face.set_surface_override_material(0, face_mat)
	_body.add_child(face)

	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.03, 0.03, 0.04)
	pit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side: float in [-1.0, 1.0]:
		var pit := MeshInstance3D.new()
		var pit_mesh := SphereMesh.new()
		pit_mesh.radius = 0.045
		pit_mesh.height = 0.09
		pit.mesh = pit_mesh
		pit.position = Vector3(side * 0.065, BODY_HEIGHT * 0.84, -0.29)
		pit.set_surface_override_material(0, pit_mat)
		_body.add_child(pit)

func _build_audio() -> void:
	# The lullaby hum: how players track it through walls. Always on while awake.
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = SoundKit.get_stream("hum")
	_hum.max_distance = 18.0
	_hum.volume_db = -6.0
	_hum.position = Vector3(0, 1.6, 0)
	add_child(_hum)

	_creak = AudioStreamPlayer3D.new()
	_creak.stream = SoundKit.get_stream("creak")
	_creak.max_distance = 12.0
	_creak.volume_db = -4.0
	add_child(_creak)

	_screech = AudioStreamPlayer3D.new()
	_screech.stream = SoundKit.get_stream("screech")
	_screech.max_distance = 30.0
	_screech.volume_db = 2.0
	add_child(_screech)

	# The shush — "go to sleep" — when it corners a survivor mid-chase.
	_shush = AudioStreamPlayer3D.new()
	_shush.stream = SoundKit.get_stream("shush")
	_shush.max_distance = 10.0
	_shush.volume_db = 0.0
	add_child(_shush)

# ── Public API ─────────────────────────────────────────────────────────────

func set_wake(seconds: float) -> void:
	wake_delay = seconds
	_wake_timer = seconds
	_asleep = seconds > 0.0
	if _asleep and _hum.playing:
		_hum.stop()

func set_spawn_point(world_pos: Vector3) -> void:
	_spawn.origin = world_pos  # host sets the LIGHTS-OUT spawn; respawn() uses it

## Solo-testing modifier (FEEL.md): a lone tester shouldn't get zeroed in on.
## Applied at round start from the base @export values so it's reversible.
func set_solo(is_solo: bool) -> void:
	hearing_radius = _base_hearing * (solo_hearing_mult if is_solo else 1.0)
	chase_memory = solo_chase_memory if is_solo else _base_chase_memory

func respawn() -> void:
	global_transform = _spawn
	_floor_dwell = 0.0
	_patrol_floor = -1
	_set_state(State.PATROL)
	_asleep = true
	_wake_timer = wake_delay
	_patrol_i = 0
	_chase_timer = 0.0
	_dwell = 0.0
	_ping_times.clear()
	_lunge_cd = 0.0
	_path = PackedVector3Array()
	_path_goal = Vector3(INF, INF, INF)
	_move_dir = Vector3.ZERO
	if _hum.playing:
		_hum.stop()

func get_debug_text() -> String:
	var names := ["PATROL", "INVESTIGATE", "CHASE", "LUNGE"]
	return "monster: %s%s\nlast ping: %v\nchase timer: %.1f  pings(10s): %d" % [
		"ASLEEP " if _asleep else "", names[_state], _last_ping_pos,
		_chase_timer, _ping_times.size()]

# Client-side audio hooks: clients disable the monster's physics but still hear
# it. Main relays these over RPC so the hum and stings play on every machine.
func client_audio_wake() -> void:
	if not _hum.playing:
		_hum.play()

func play_state_fx(s: int) -> void:
	if s == State.LUNGE and not _screech.playing:
		_screech.play()

# ── Senses ─────────────────────────────────────────────────────────────────

func _on_noise(pos: Vector3, loudness: float) -> void:
	if _asleep or loudness <= 0.0:
		return
	if global_position.distance_to(pos) > hearing_radius * clampf(loudness, 0.3, 1.0):
		return
	_last_ping_pos = pos
	var now := Time.get_ticks_msec() / 1000.0
	_ping_times.append(now)
	while _ping_times.size() > 0 and now - _ping_times[0] > ping_window:
		_ping_times.remove_at(0)

	match _state:
		State.CHASE, State.LUNGE:
			_last_known = pos
			_chase_timer = chase_memory
		State.INVESTIGATE:
			# A second noise while it's already suspicious = it KNOWS.
			_enter_chase(pos)
		State.PATROL:
			if _ping_times.size() >= pings_to_chase:
				_enter_chase(pos)
			else:
				_set_state(State.INVESTIGATE)
				_last_known = pos
				_dwell = 0.0

func _check_sight(delta: float) -> void:
	if _state == State.LUNGE:
		return
	for t: Node3D in _targets():
		if _flag(t, "cocooned") or _flag(t, "hidden"):
			continue
		if _can_see(t, delta, true):
			_enter_chase(t.global_position)
			return

func _can_see(t: Node3D, delta: float, need_motion: bool) -> bool:
	var pos := t.global_position
	var to := pos - global_position
	if to.length() > sight_range:
		return false
	if need_motion:
		# Motion-gated: freeze completely and it looks right through you.
		if _watched != t:
			_watched = t
			_watched_prev = pos
			return false
		var speed := (pos - _watched_prev).length() / delta
		_watched_prev = pos
		if speed < sight_min_speed:
			return false
	var flat := Vector3(to.x, 0.0, to.z).normalized()
	if flat.dot(_facing) < cos(deg_to_rad(sight_fov_deg * 0.5)):
		return false
	return _los_to(t)

# Clear line of sight to a target? A wall (physics layer 1 = world geometry)
# between us blocks it. Works for the RigidBody player (ray reaches it) and for
# collider-less remote ghosts (a clear ray hits nothing = LOS).
func _los_to(t: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, t.global_position + Vector3.UP * 0.3, 1)
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == t

func _targets() -> Array:
	if get_targets.is_valid():
		return get_targets.call()
	return []

func _flag(t: Node3D, flag: String) -> bool:
	if t is SleepingBagPlayer:
		var p := t as SleepingBagPlayer
		return p.state == SleepingBagPlayer.State.COCOONED if flag == "cocooned" else p.hidden
	return t.get_meta(flag, false)

func _enter_chase(pos: Vector3) -> void:
	_last_known = pos
	_chase_timer = chase_memory
	if _state != State.CHASE:
		_set_state(State.CHASE)

func _set_state(s: State) -> void:
	if _state != s:
		_state = s
		state_changed.emit(s)

# ── Brain + body ───────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _asleep:
		_wake_timer -= delta
		if _wake_timer <= 0.0:
			_asleep = false
			_hum.play()
			woke_up.emit()
		return

	_lunge_cd = maxf(_lunge_cd - delta, 0.0)
	_check_sight(delta)

	var goal := global_position
	var has_goal := false
	var speed := move_speed

	match _state:
		State.PATROL:
			if not patrol_points.is_empty():
				# Dwell cap: no camping one floor — after patrol_floor_dwell secs
				# on a floor, route to the nearest waypoint on a different one.
				var f := HouseSuburban.floor_of(global_position.y)
				if f == _patrol_floor:
					_floor_dwell += delta
				else:
					_patrol_floor = f
					_floor_dwell = 0.0
				if _floor_dwell > patrol_floor_dwell:
					_jump_to_other_floor(f)
					_floor_dwell = 0.0
				var p := patrol_points[_patrol_i % patrol_points.size()]
				if _flat_distance(p) < 1.2:
					_patrol_i = (_patrol_i + 1) % patrol_points.size()
					p = patrol_points[_patrol_i]
				goal = p
				has_goal = true
				speed = move_speed * patrol_speed_mult

		State.INVESTIGATE:
			if _flat_distance(_last_known) < 0.9 or _path_exhausted(_last_known):
				# Arrived (or can't get closer): stand and search, slowly turning.
				_dwell += delta
				_body.rotation.y += delta * 1.4
				_facing = -Basis(Vector3.UP, _body.rotation.y).z
				if _dwell >= investigate_time:
					_set_state(State.PATROL)
					_patrol_i = _nearest_patrol_index()
			else:
				goal = _last_known
				has_goal = true

		State.CHASE:
			# Lunge check: close + clear line of sight (no motion gate — being
			# frozen at point-blank mid-chase will not save you).
			if _lunge_cd <= 0.0:
				for t: Node3D in _targets():
					if _flag(t, "cocooned") or _flag(t, "hidden"):
						continue
					if global_position.distance_to(t.global_position) <= lunge_range \
							and _can_see(t, delta, false):
						_set_state(State.LUNGE)
						_lunge_t = 0.0
						_lunge_traveled = 0.0
						var d := t.global_position - global_position
						_lunge_dir = Vector3(d.x, 0, d.z).normalized()
						_screech.play()
						break
			if _state == State.CHASE:
				goal = _last_known
				has_goal = true
				_chase_timer -= delta
				if _chase_timer <= 0.0:
					_set_state(State.INVESTIGATE)
					_dwell = 0.0

		State.LUNGE:
			_lunge_t += delta
			if _lunge_t >= lunge_windup:
				var step := move_speed * lunge_speed_mult * delta
				global_position += _lunge_dir * step
				_lunge_traveled += step
				for t: Node3D in _targets():
					if _flag(t, "cocooned") or _flag(t, "hidden"):
						continue
					# Distance AND clear line of sight — no grabbing through walls
					# (the body is collision-free, so distance alone isn't enough).
					if global_position.distance_to(t.global_position) <= lunge_hit_radius \
							and _los_to(t):
						lunged_hit.emit(t)
						_lunge_cd = lunge_cooldown
						_set_state(State.PATROL)
						break
				if _state == State.LUNGE and _lunge_traveled >= lunge_range + 1.2:
					_lunge_cd = lunge_cooldown
					_set_state(State.CHASE)  # missed — recover and re-track

	# Route the goal through the navmesh; walk horizontally, feet planted.
	var on_vertical_seg := false
	if has_goal and _nav_map_ready():
		_repath(goal)
		while _path_i < _path.size() and _flat_distance(_path[_path_i]) < 0.5:
			_prev_wp = _path[_path_i]
			_path_i += 1
			_repath_cd = 3.0
		if _path_i < _path.size():
			var wp := _path[_path_i]
			var to := wp - global_position
			to.y = 0.0
			if to.length() > 0.02:
				var want := to.normalized()
				if _move_dir.length() < 0.01:
					_move_dir = want
				else:
					var angle := _move_dir.signed_angle_to(want, Vector3.UP)
					var turn := clampf(angle, -turn_rate * delta, turn_rate * delta)
					_move_dir = _move_dir.rotated(Vector3.UP, turn).normalized()
				global_position += _move_dir * minf(speed * delta, to.length())
				_facing = _move_dir
			# Floor-changing segment: interpolate height along it (latched on
			# the segment's endpoints so mid-crossing repaths can't yo-yo us).
			if absf(wp.y - _prev_wp.y) > 1.0:
				on_vertical_seg = true
				var seg := _flat_between(_prev_wp, wp)
				if seg > 0.1:
					var prog := clampf(1.0 - _flat_distance(wp) / seg, 0.0, 1.0)
					var want_y := lerpf(_prev_wp.y, wp.y, prog) + 0.1
					global_position.y = lerpf(global_position.y, want_y,
						clampf(10.0 * delta, 0.0, 1.0))
		else:
			_move_dir = Vector3.ZERO
	else:
		_move_dir = Vector3.ZERO
	_on_link = on_vertical_seg
	_repath_cd -= delta

	# Feet on the floor (skipped mid vertical segment).
	var space := get_world_3d().direct_space_state
	if not on_vertical_seg:
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 1.2, global_position + Vector3.DOWN * 3.0, 1)
		var hit := space.intersect_ray(query)
		if hit:
			var floor_y: float = hit["position"].y + 0.4
			global_position.y = lerpf(global_position.y, floor_y, clampf(14.0 * delta, 0.0, 1.0))

	# Face where it's going; hunch under low clearance (doorways).
	if _move_dir.length() > 0.1 and _state != State.INVESTIGATE:
		var yaw := atan2(-_move_dir.x, -_move_dir.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, clampf(8.0 * delta, 0.0, 1.0))
	var up_query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.UP * (BODY_HEIGHT + 0.5), 1)
	var ceil_hit := space.intersect_ray(up_query)
	var clearance := BODY_HEIGHT
	if ceil_hit:
		clearance = ceil_hit["position"].y - (global_position.y - 0.4)
	var squash := clampf((clearance - 0.1) / BODY_HEIGHT, 0.5, 1.0)
	_body.scale.y = lerpf(_body.scale.y, squash, clampf(10.0 * delta, 0.0, 1.0))

	# Floorboard creaks while it moves — the "you hear it before you see it".
	_creak_cd -= delta
	if _creak_cd <= 0.0 and _move_dir.length() > 0.1:
		_creak.play()
		_creak_cd = randf_range(1.6, 3.8) * (0.55 if _state >= State.CHASE else 1.0)

	# Dread ramp: the lullaby hum SWELLS as it closes on the nearest survivor,
	# and it SHUSHES them when it's right on top of them during a chase.
	var nearest := _nearest_target_dist()
	var hum_target := lerpf(-3.0, -12.0, clampf((nearest - 3.0) / 12.0, 0.0, 1.0))
	_hum.volume_db = lerpf(_hum.volume_db, hum_target, clampf(3.0 * delta, 0.0, 1.0))
	_shush_cd -= delta
	if _state == State.CHASE and nearest < shush_range and _shush_cd <= 0.0:
		_shush.play()
		_shush_cd = shush_cooldown

func _nearest_target_dist() -> float:
	var best := INF
	for t: Node3D in _targets():
		if _flag(t, "cocooned"):
			continue
		best = minf(best, global_position.distance_to(t.global_position))
	return best

# ── Path helpers ───────────────────────────────────────────────────────────

func _repath(goal: Vector3) -> void:
	var need := _path.is_empty() \
		or (not _on_link and (goal.distance_to(_path_goal) > 0.5 or _repath_cd <= 0.0))
	if need:
		_path = NavigationServer3D.map_get_path(
			get_world_3d().navigation_map, global_position, goal, true)
		_path_goal = goal
		_path_i = 0
		_prev_wp = global_position
		_repath_cd = 3.0

func _path_exhausted(goal: Vector3) -> bool:
	return goal.distance_to(_path_goal) < 0.6 and _path_i >= _path.size()

func _nearest_patrol_index() -> int:
	var best := 0
	var best_d := INF
	for i in patrol_points.size():
		var d := _flat_distance(patrol_points[i])
		if d < best_d:
			best_d = d
			best = i
	return best

## Route to the nearest patrol waypoint NOT on `cur_floor` — the dwell-cap escape.
func _jump_to_other_floor(cur_floor: int) -> void:
	var best := -1
	var best_d := INF
	for i in patrol_points.size():
		if HouseSuburban.floor_of(patrol_points[i].y) == cur_floor:
			continue
		var d := _flat_distance(patrol_points[i])
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_patrol_i = best

func _flat_distance(to: Vector3) -> float:
	var d := to - global_position
	return Vector2(d.x, d.z).length()

func _flat_between(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

func _nav_map_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0
