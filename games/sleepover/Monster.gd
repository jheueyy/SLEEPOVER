extends CharacterBody3D
class_name NoiseMonster
## Placeholder "Housesitter": a red cube with the real Patrol -> Investigate ->
## Chase state machine (spec 3.4). It hears noise pings (hop thumps, tumbles):
##   PATROL      — slow wander around its haunt
##   INVESTIGATE — path to the last ping's location; arrive quietly = give up
##   CHASE       — locked onto the PLAYER, tracks their live position. Entered
##                 when a ping happens close to it, or it gets near enough while
##                 investigating. Going silent does NOT break a chase — it only
##                 gives up after `chase_memory` secs without any contact.
## Movement is navmesh-routed (baked by Main from the house gray-box) and the
## body has NO world collision — the path decides where it goes, so doorways,
## stairs, and floor changes can never physically block it. It walks the path
## horizontally with its feet snapped to the surface underfoot, so it visibly
## climbs stairs tread by tread instead of floating.
## Touch the player = caught (Main's distance check handles the freeze).

signal woke_up  ## fired once when the wake_delay grace period ends

@export var move_speed: float = 2.6        ## faster than shuffle, loses to a hop chain
@export var wake_delay: float = 40.0       ## secs asleep at round start — the exploration grace
@export var hearing_radius: float = 14.0   ## room-scale ears, not house-scale (was 40)
@export var patrol_span: float = 6.0       ## idle back-and-forth distance
@export var chase_trigger_range: float = 6.0 ## ping this close to it = instant chase
@export var proximity_sense: float = 3.5   ## it just KNOWS you're there this close
@export var chase_memory: float = 10.0     ## secs of no contact before it loses you
@export var sight_range: float = 7.0       ## it SEES moving players this far ahead
@export var sight_fov_deg: float = 120.0   ## vision cone around its heading
@export var sight_min_speed: float = 0.6   ## slower than this = invisible. FREEZE to hide.
@export var turn_rate: float = 2.5         ## heading turn speed in rad/s (~143°/s) — lower = more committed, easier to juke
@export var track_interval: float = 0.4    ## secs between "where are they now" checks — it aims where you WERE

enum State { PATROL, INVESTIGATE, CHASE }

var player: Node3D                         ## set by Main — chase target

var _asleep: bool = true
var _wake_timer: float = 0.0
var _state: State = State.PATROL
var _chase_timer: float = 0.0
var _tracked_pos: Vector3          ## stale snapshot of the player it aims at
var _track_cd: float = 0.0
var _target: Vector3
var _has_target: bool = false
var _patrol_origin: Vector3
var _patrol_dir: float = 1.0
var debug_nav: bool = false        ## loopback test mode: dump path state
var _spawn: Transform3D
var _move_dir: Vector3 = Vector3.ZERO  ## smoothed heading along the nav path
# Manual path following (NavigationAgent3D advances waypoints by 3D distance,
# which deadlocks on descents — a waypoint 3m below is "never reached" when
# you're standing right above it. We advance by HORIZONTAL distance instead;
# the floor-snap owns the vertical.)
var _path: PackedVector3Array = []
var _path_i: int = 0
var _path_goal: Vector3 = Vector3(INF, INF, INF)
var _prev_wp: Vector3 = Vector3.ZERO  ## segment start, for vertical interpolation
var _on_link: bool = false            ## mid floor-change: hold the path steady
var _repath_cd: float = 0.0
var _watched: Node3D               ## whose motion we measured last frame
var _watched_prev: Vector3
var _debug_tick: int = 0

const BODY_HEIGHT := 2.4  # tall enough to loom over 0.9m bags; hunches at doors

var _body: Node3D

func _ready() -> void:
	# No collision shape and no layers: the world can't stop it, only the
	# navmesh path decides where it goes. Catching is a distance check in Main.
	collision_layer = 0
	collision_mask = 0
	_build_body()

func _build_body() -> void:
	# The Housesitter, concept-sheet edition: a tall quilted bell of old
	# bedding with a pale mask face. Origin sits 0.4 above the floor (the
	# floor-snap keeps it there); the body hangs from that point.
	_body = Node3D.new()
	_body.position = Vector3(0, -0.4, 0)  # body base = floor
	add_child(_body)

	var cloak_mat := StandardMaterial3D.new()
	cloak_mat.albedo_color = Color(0.23, 0.13, 0.17)  # dark patchwork quilt
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

	# The pale mask — the only bright thing on it. It reads in the dark.
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

	# Hollow eye pits.
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

	_spawn = global_transform
	_patrol_origin = global_position
	_wake_timer = wake_delay
	NoiseBus.noise_emitted.connect(_on_noise)

func set_wake(seconds: float) -> void:
	wake_delay = seconds
	_wake_timer = seconds
	_asleep = seconds > 0.0

func respawn() -> void:
	global_transform = _spawn
	_patrol_origin = global_position
	_has_target = false
	_state = State.PATROL
	_chase_timer = 0.0
	_move_dir = Vector3.ZERO
	_asleep = true
	_wake_timer = wake_delay

func _on_noise(pos: Vector3, loudness: float) -> void:
	if _asleep or loudness <= 0.0:
		return
	if global_position.distance_to(pos) > hearing_radius:
		return
	_target = pos
	_has_target = true
	if _state == State.CHASE:
		_chase_timer = chase_memory  # any contact keeps the chase alive
	elif global_position.distance_to(pos) <= chase_trigger_range:
		_state = State.CHASE        # that was CLOSE — it's on you now
		_chase_timer = chase_memory
		_tracked_pos = pos
		_track_cd = track_interval
	else:
		_state = State.INVESTIGATE  # distant noise: go take a look

func _physics_process(delta: float) -> void:
	# Asleep at round start: deaf, blind, motionless. The exploration window.
	if _asleep:
		_wake_timer -= delta
		if _wake_timer <= 0.0:
			_asleep = false
			woke_up.emit()
		return

	var goal := global_position
	var has_goal := false
	var speed := move_speed

	# Sight: a MOVING player in front of it, close, with clear line of sight,
	# is spotted — enters or refreshes the chase. Freeze and you're invisible.
	if player != null and _can_see_player(delta):
		_state = State.CHASE
		_chase_timer = chase_memory
		_tracked_pos = player.global_position
		_track_cd = track_interval

	match _state:
		State.PATROL:
			# Slow wander between two points around the haunt.
			var p := _patrol_origin + Vector3(_patrol_dir * patrol_span, 0.0, 0.0)
			if _flat_distance(p) < 0.8:
				_patrol_dir *= -1.0
				p = _patrol_origin + Vector3(_patrol_dir * patrol_span, 0.0, 0.0)
			goal = p
			has_goal = true
			speed = move_speed * 0.4

		State.INVESTIGATE:
			# Getting near the player mid-investigation = it notices you.
			if player != null and global_position.distance_to(player.global_position) <= proximity_sense:
				_state = State.CHASE
				_chase_timer = chase_memory
				_tracked_pos = player.global_position
				_track_cd = track_interval
			elif _has_target:
				# Arrived — or the path is exhausted (target unreachable):
				# either way, stop investigating instead of freezing forever.
				if _flat_distance(_target) < 0.8 or _path_exhausted(_target):
					_has_target = false
					_state = State.PATROL  # nothing here — false alarm
				else:
					goal = _target
					has_goal = true
			else:
				_state = State.PATROL

		State.CHASE:
			# Locked on — but it aims at a STALE snapshot of where you were
			# (refreshed every track_interval), so a hard sidestep can beat it.
			if player != null:
				if global_position.distance_to(player.global_position) <= proximity_sense:
					_chase_timer = chase_memory
				_track_cd -= delta
				if _track_cd <= 0.0:
					_tracked_pos = player.global_position
					_track_cd = track_interval
				goal = _tracked_pos
				has_goal = true
			_chase_timer -= delta
			if _chase_timer <= 0.0:
				_state = State.INVESTIGATE  # lost you — check last known noise

	# Route the goal through the navmesh; walk it horizontally, feet planted.
	# Turn inertia: the heading blends toward the path direction, so it can't
	# whip around instantly — juking past it stays possible and earned.
	var on_vertical_seg := false
	if has_goal and _nav_map_ready():
		_repath(goal)
		# Advance waypoints by HORIZONTAL distance (see _path comment above).
		# Each advance is progress — push the stuck-recovery heartbeat back.
		while _path_i < _path.size() and _flat_distance(_path[_path_i]) < 0.5:
			_prev_wp = _path[_path_i]
			_path_i += 1
			_repath_cd = 3.0
		if debug_nav:
			_debug_tick += 1
			if _debug_tick % 120 == 0:
				print("[NETTEST] path state=%d pos=%v wp=%d/%d goal=%v" % [
					_state, global_position, _path_i, _path.size(), goal])
		if _path_i < _path.size():
			var wp := _path[_path_i]
			var to := wp - global_position
			to.y = 0.0  # horizontal walk; the feet find the floor below
			if to.length() > 0.02:
				var want := to.normalized()
				if _move_dir.length() < 0.01:
					_move_dir = want
				else:
					# Rotate the heading toward the path at turn_rate rad/s.
					# (NOT lerp+normalize — that can never turn a full 180°.)
					var angle := _move_dir.signed_angle_to(want, Vector3.UP)
					var step := clampf(angle, -turn_rate * delta, turn_rate * delta)
					_move_dir = _move_dir.rotated(Vector3.UP, step).normalized()
				global_position += _move_dir * minf(speed * delta, to.length())
			# Floor-changing segment (a stairwell link or a whole ramp in one
			# span): interpolate height along the segment instead of snapping —
			# the snap ray can't see the destination floor from up/down here.
			# LATCHED on the segment's endpoints, not the current height gap:
			# a moving chase target must never repath us mid-crossing (start
			# snapping is ambiguous in midair and yo-yos us back up).
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

	# Feet on the floor: snap to the surface underfoot each frame. On stairs
	# this rides the treads step by step — it WALKS up and down, no floating.
	# (mask 1: snaps to real geometry, never the invisible player stair ramps.
	# Skipped mid vertical segment — the interpolation above owns the height.)
	var space := get_world_3d().direct_space_state
	if not on_vertical_seg:
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 1.2, global_position + Vector3.DOWN * 3.0, 1)
		var hit := space.intersect_ray(query)
		if hit:
			var floor_y: float = hit["position"].y + 0.4
			global_position.y = lerpf(global_position.y, floor_y, clampf(14.0 * delta, 0.0, 1.0))

	# Face where it's going, and HUNCH under low clearance — a 2.4m thing
	# folding itself through a 2m doorway is exactly the nightmare we want.
	if _move_dir.length() > 0.1:
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

func _can_see_player(delta: float) -> bool:
	# Measure the target's speed from position deltas (works for the local
	# RigidBody bag AND the interpolated network ghosts alike).
	var pos := player.global_position
	if _watched != player:
		_watched = player
		_watched_prev = pos
		return false
	var target_speed := (pos - _watched_prev).length() / delta
	_watched_prev = pos
	if target_speed < sight_min_speed:
		return false  # holding still = invisible

	var to := pos - global_position
	if to.length() > sight_range:
		return false
	if _move_dir.length() < 0.1:
		return false  # standing idle, staring at nothing
	var flat := Vector3(to.x, 0.0, to.z).normalized()
	if flat.dot(_move_dir) < cos(deg_to_rad(sight_fov_deg * 0.5)):
		return false  # outside the vision cone

	# Line of sight: walls block it. Ray ends at the player, so hitting the
	# player's own body (or nothing at all, for ghosts) means a clear view.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, pos + Vector3.UP * 0.3, 1)  # mask 1: ignore stair ramps
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == player

func _repath(goal: Vector3) -> void:
	# A path in progress is left alone: recompute only when the goal genuinely
	# moved or the stuck-recovery heartbeat expires — and NEVER mid link
	# crossing, where a fresh path can snap our hovering position back to the
	# departure floor and yank us into an oscillation.
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

func _flat_distance(to: Vector3) -> float:
	var d := to - global_position
	return Vector2(d.x, d.z).length()

func _flat_between(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

func _nav_map_ready() -> bool:
	# The navmesh bakes at startup; queries before the map's first sync fail.
	return NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0
