extends RigidBody3D
class_name SleepingBagPlayer
## The sleeping bag — UPRIGHT, potato-sack-race posture. A wobbly standing
## capsule that self-rights via a (deliberately weak) spring so near-tumbles
## are constant and recoveries feel lucky. Face-plants are the comedy engine.
##
## Locomotion (spec Part 2 / 3.2 — the stamina economy IS the panic engine):
##   Shuffle — WASD        : slowed walk ~1.3 m/s, quiet, stamina regens
##   Hop     — Space (tap) : fast forward burst, LOUD landing thump, costs 1 pip
##   Tumble  — automatic   : hop at 0 stamina or land badly = face-plant;
##                           mash WASD ~2.5s to wriggle upright, fully vulnerable
## Stamina: 5 pips, ~1 pip/2s regen while grounded, NO regen mid-air.
## WASD is camera-relative (Main feeds us `control_yaw`); mouse only orbits the cam.
##
## ALL feel constants are @export so you can tune them live in the Inspector
## while the game runs. They are mirrored in FEEL.md — keep the two in sync.

# ── Shuffle ────────────────────────────────────────────────────────────────
@export_group("Shuffle")
@export var shuffle_force: float = 45.0      ## push while a WASD key is held (N)
@export var shuffle_speed: float = 2.0       ## m/s cap — slowed walk, but not boring
@export var brake_damping: float = 8.0       ## how hard the bag stops with no input (holds on stair ramps)

# ── Hop & Stamina ──────────────────────────────────────────────────────────
@export_group("Hop & Stamina")
@export var hop_speed: float = 3.6           ## forward burst speed of one hop (m/s)
@export var hop_up_speed: float = 4.6        ## upward speed — clears stairs with room to spare
@export var stamina_max: float = 5.0         ## hop pips
@export var stamina_regen: float = 0.6       ## pips/sec while grounded (1 pip / ~1.7s)
@export var regen_delay: float = 1.6         ## secs after a hop before regen resumes — mid-chain you earn NOTHING
@export var land_loudness: float = 1.0       ## noise ping on each landing thump (0..1)
@export var land_tumble_speed: float = 6.5   ## land harder than this = face-plant

# ── Wobble & Tumble ────────────────────────────────────────────────────────
@export_group("Wobble & Tumble")
@export var upright_stiffness: float = 40.0  ## weak-ish — near-tumbles, not constant falls
@export var upright_damping: float = 7.0     ## settles the sway between hops
@export var tumble_angle_deg: float = 60.0   ## tilt past this = down you go
@export var hop_wobble_torque: float = 1.2   ## random lean per hop — a wobble, not a coin flip
@export var faceplant_kick: float = 5.0      ## forward flop when hopping on empty
@export var recover_mashes_needed: float = 8.0 ## key mashes to wriggle upright (~2.5s)
@export var recover_mash_kick: float = 3.0   ## righting impulse per mash
@export var tumble_loudness: float = 0.8     ## crash ping when you go down

enum State { NORMAL, TUMBLED, CAUGHT }

const DIR_KEYS := {
	KEY_W: Vector3(0, 0, -1),
	KEY_S: Vector3(0, 0, 1),
	KEY_A: Vector3(-1, 0, 0),
	KEY_D: Vector3(1, 0, 0),
}

var state: State = State.NORMAL
var control_yaw: float = 0.0             ## camera yaw, set by Main — WASD is camera-relative
var facing: Vector3 = Vector3(0, 0, -1)  ## last direction moved; hops burst this way
var stamina: float = 5.0
var grounded: bool = false
var _regen_cooldown: float = 0.0
var recover_progress: float = 0.0
var _hop_queued: bool = false
var _was_grounded: bool = true
var _spawn_grace: float = 0.0  ## suppress landing noise right after (re)spawn

var _ground_rays: Array[RayCast3D] = []
var _visual: Node3D
var _spawn: Transform3D

func _ready() -> void:
	# Build our own body procedurally so there's no fragile .tscn to hand-author.
	mass = 2.0
	continuous_cd = true
	can_sleep = false
	collision_mask = 0b11  # world (1) + invisible stair ramps (2)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 0.9  # concept-sheet scale: the bag is ~0.9m tall
	shape.shape = capsule  # upright — a person standing in a bag
	add_child(shape)

	set_skin(BagVisual.skin_for_peer(multiplayer.get_unique_id()))

	# Five ground rays (center + 4 offsets): a single center ray misses when
	# the bag bridges two stair treads, which blocked hopping on staircases.
	for off: Vector2 in [Vector2.ZERO, Vector2(0.25, 0), Vector2(-0.25, 0),
			Vector2(0, 0.25), Vector2(0, -0.25)]:
		var ray := RayCast3D.new()
		ray.position = Vector3(off.x, 0.0, off.y)
		ray.target_position = Vector3(0.0, -1.0, 0.0)
		ray.enabled = true
		add_child(ray)
		_ground_rays.append(ray)

	stamina = stamina_max
	_spawn_grace = 1.0
	_spawn = global_transform

# ── Public API used by Main ────────────────────────────────────────────────

func get_state_text() -> String:
	match state:
		State.CAUGHT: return "CAUGHT"
		State.TUMBLED: return "TUMBLED — mash W/A/S/D to get up!"
		_: return ""

func set_caught() -> void:
	state = State.CAUGHT
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func set_spawn(xform: Transform3D) -> void:
	_spawn = xform  # e.g. a network client relocated to its own spawn slot

func set_skin(skin: int) -> void:
	if _visual != null:
		_visual.queue_free()
	_visual = BagVisual.build(0.9, skin)
	_visual.position = Vector3(0, -0.45, 0)  # bag base at the capsule's bottom
	add_child(_visual)

func respawn() -> void:
	state = State.NORMAL
	stamina = stamina_max
	recover_progress = 0.0
	_regen_cooldown = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	_hop_queued = false
	_spawn_grace = 1.0
	facing = Vector3(0, 0, -1)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _spawn

# ── Input ──────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode == KEY_SPACE and state == State.NORMAL:
		_hop_queued = true  # consumed next physics step
	elif event.keycode in DIR_KEYS and state == State.TUMBLED:
		# Mash to wriggle upright — each press is one wriggle.
		recover_progress += 1.0
		apply_torque_impulse(_upright_axis() * recover_mash_kick)

# ── Physics ────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	grounded = false
	for ray: RayCast3D in _ground_rays:
		if ray.is_colliding():
			grounded = true
			break

	# Turn the googly eyes toward the movement heading (local yaw compensates
	# for whatever the physics body's own yaw is doing).
	if _visual != null and facing.length() > 0.1:
		var body_yaw := global_transform.basis.get_euler().y
		var want_yaw := atan2(-facing.x, -facing.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, want_yaw - body_yaw,
			clampf(10.0 * delta, 0.0, 1.0))

	match state:
		State.CAUGHT:
			return
		State.TUMBLED:
			_process_recovery(delta)
		State.NORMAL:
			_process_normal(delta)

	# Landing: every touchdown is a LOUD thump the monster hears — except the
	# initial settle after (re)spawning, or the whole lobby summons it at t=0.
	_spawn_grace = maxf(_spawn_grace - delta, 0.0)
	if grounded and not _was_grounded and state != State.CAUGHT:
		if _spawn_grace <= 0.0:
			NoiseBus.emit_noise(global_position, land_loudness)
		if _horizontal_speed() > land_tumble_speed and state == State.NORMAL:
			_tumble()
	_was_grounded = grounded

func _process_normal(delta: float) -> void:
	# Weak upright spring: the bag is ALWAYS almost falling over.
	_apply_upright_spring(1.0)
	if _tilt_angle() > deg_to_rad(tumble_angle_deg):
		_tumble()
		return

	# Stamina regens only on the ground, and only after a pause since the last
	# hop — a chain runs on a strictly fixed tank: 5 pips, then the floor.
	_regen_cooldown = maxf(_regen_cooldown - delta, 0.0)
	if grounded and _regen_cooldown <= 0.0:
		stamina = minf(stamina + stamina_regen * delta, stamina_max)

	# Shuffle: quiet slowed walk in whatever direction keys are held.
	var dir := _input_dir()
	if dir != Vector3.ZERO:
		facing = dir
		if _horizontal_speed() < shuffle_speed:
			apply_central_force(dir * shuffle_force)
	elif grounded:
		# No input: brake to a stop so the bag doesn't creep down stair ramps.
		var t := clampf(brake_damping * delta, 0.0, 1.0)
		linear_velocity.x = lerpf(linear_velocity.x, 0.0, t)
		linear_velocity.z = lerpf(linear_velocity.z, 0.0, t)

	# Hop: tap Space. Full pip = burst. Empty tank = face-plant. That's the game.
	# (velocity gate: the longer rays still see ground early in a hop's ascent)
	if _hop_queued:
		_hop_queued = false
		if grounded and linear_velocity.y < 1.5:
			if stamina >= 1.0:
				_launch_hop(dir if dir != Vector3.ZERO else facing)
			else:
				_faceplant()

func _process_recovery(_delta: float) -> void:
	# Mashing ramps the upright spring back on; upright enough = free.
	var t := clampf(recover_progress / recover_mashes_needed, 0.0, 1.0)
	_apply_upright_spring(t)
	if _tilt_angle() < deg_to_rad(20.0) and t >= 1.0:
		state = State.NORMAL
		linear_damp = 0.0
		angular_damp = 0.0

# ── Verb helpers ───────────────────────────────────────────────────────────

func _input_dir() -> Vector3:
	var dir := Vector3.ZERO
	for key: int in DIR_KEYS:
		if Input.is_key_pressed(key):
			dir += DIR_KEYS[key]
	if dir.length() < 0.01:
		return Vector3.ZERO
	# Rotate by the camera yaw so W is always "away from the camera".
	return dir.normalized().rotated(Vector3.UP, control_yaw)

func _launch_hop(dir: Vector3) -> void:
	stamina -= 1.0
	_regen_cooldown = regen_delay
	facing = dir
	var burst := dir * hop_speed + Vector3.UP * hop_up_speed
	apply_central_impulse(burst * mass)
	# A random little lean per hop — every hop is a small gamble.
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * hop_wobble_torque)

func _faceplant() -> void:
	# Hopped on an empty tank: lunge forward and eat the floor.
	apply_central_impulse(facing * 2.0 * mass)
	apply_torque_impulse(Vector3.UP.cross(facing) * faceplant_kick)
	_tumble()

func _tumble() -> void:
	state = State.TUMBLED
	recover_progress = 0.0
	# Fall over, don't fly: bleed momentum and turn on heavy damping so the
	# bag flops in place instead of ragdolling across the map.
	linear_velocity *= 0.35
	angular_velocity = angular_velocity.limit_length(4.0)
	linear_damp = 2.0
	angular_damp = 3.0
	NoiseBus.emit_noise(global_position, tumble_loudness)

# ── Math helpers ───────────────────────────────────────────────────────────

func _horizontal_speed() -> float:
	return Vector2(linear_velocity.x, linear_velocity.z).length()

func _tilt_angle() -> float:
	return global_transform.basis.y.angle_to(Vector3.UP)

func _upright_axis() -> Vector3:
	var axis := global_transform.basis.y.cross(Vector3.UP)
	return axis.normalized() if axis.length() > 0.001 else Vector3.ZERO

func _apply_upright_spring(scale: float) -> void:
	var axis := _upright_axis()
	if axis != Vector3.ZERO:
		apply_torque(axis * _tilt_angle() * upright_stiffness * scale)
	apply_torque(-angular_velocity * upright_damping * scale)
