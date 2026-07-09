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
## Movement is navmesh-routed (baked by Main from the house gray-box): it walks
## through doorways, up stairs, and across floors. Along a path it GLIDES —
## velocity follows the path in 3D — which reads uncanny in exactly the right
## way. Touch the player = caught (Main handles the freeze).

@export var move_speed: float = 2.6        ## faster than shuffle, loses to a hop chain
@export var gravity: float = 12.0
@export var hearing_radius: float = 40.0   ## ignore pings farther than this
@export var patrol_span: float = 6.0       ## idle back-and-forth distance
@export var chase_trigger_range: float = 6.0 ## ping this close to it = instant chase
@export var proximity_sense: float = 3.5   ## it just KNOWS you're there this close
@export var chase_memory: float = 6.0      ## secs of silence before it loses you
@export var turn_rate: float = 2.5         ## how fast it can change direction — lower = more committed, easier to juke
@export var track_interval: float = 0.4    ## secs between "where are they now" checks — it aims where you WERE

enum State { PATROL, INVESTIGATE, CHASE }

var player: Node3D                         ## set by Main — chase target

var _state: State = State.PATROL
var _chase_timer: float = 0.0
var _tracked_pos: Vector3          ## stale snapshot of the player it aims at
var _track_cd: float = 0.0
var _target: Vector3
var _has_target: bool = false
var _patrol_origin: Vector3
var _patrol_dir: float = 1.0
var _spawn: Transform3D
var _nav: NavigationAgent3D

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.8)  # fits through the 1.1m doorways
	shape.shape = box
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.8, 0.8, 0.8)
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.0, 0.0)
	mesh.set_surface_override_material(0, mat)
	add_child(mesh)

	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 0.5
	_nav.path_height_offset = 0.45  # paths hug the floor; our center rides above
	_nav.path_max_distance = 5.0
	add_child(_nav)

	_spawn = global_transform
	_patrol_origin = global_position
	NoiseBus.noise_emitted.connect(_on_noise)

func respawn() -> void:
	global_transform = _spawn
	_patrol_origin = global_position
	_has_target = false
	_state = State.PATROL
	_chase_timer = 0.0
	velocity = Vector3.ZERO

func _on_noise(pos: Vector3, loudness: float) -> void:
	if loudness <= 0.0:
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
	var goal := global_position
	var has_goal := false
	var speed := move_speed

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
				if _flat_distance(_target) < 0.8:
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

	# Route the goal through the navmesh (doorways, stairs, floors).
	var desired := Vector3.ZERO
	if has_goal and _nav_map_ready():
		_nav.target_position = goal
		if not _nav.is_navigation_finished():
			var to := _nav.get_next_path_position() - global_position
			if to.length() > 0.05:
				desired = to.normalized() * speed

	# Turn inertia: it can't whip around instantly. Committed momentum is what
	# makes juking past it possible — and what makes near-misses feel earned.
	var t := clampf(turn_rate * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, desired.x, t)
	velocity.z = lerpf(velocity.z, desired.z, t)
	if desired == Vector3.ZERO:
		velocity.y -= gravity * delta  # idle: stay planted on the floor
	else:
		velocity.y = desired.y         # on a path: glide along it (stairs etc.)
	move_and_slide()

func _flat_distance(to: Vector3) -> float:
	var d := to - global_position
	return Vector2(d.x, d.z).length()

func _nav_map_ready() -> bool:
	# The navmesh bakes at startup; queries before the map's first sync fail.
	return NavigationServer3D.map_get_iteration_id(_nav.get_navigation_map()) > 0
