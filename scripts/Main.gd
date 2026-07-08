extends Node3D
## Gray-box level + camera + HUD for the Week 1 kill test.
## Builds a straight hallway with a staircase up to a landing (hopping downstairs
## on low stamina = uncontrolled tumble chain = the money clip), spawns the
## sleeping-bag player and the red-cube noise monster, and handles catch/reset.
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
var _pips: Array[ColorRect] = []
var _caught: bool = false

const PIP_ON := Color(1.0, 0.85, 0.25)
const PIP_OFF := Color(0.25, 0.25, 0.28)

func _ready() -> void:
	_build_environment()
	_build_level()
	_spawn_actors()
	_build_camera()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	# Ground-floor hallway: 6 wide, 24 long.
	_add_box(Vector3(0, -0.5, 0), Vector3(6, 1, 24), Color(0.30, 0.30, 0.34))
	# Side walls — tall, so the low camera makes them loom.
	_add_box(Vector3(-3, 1.5, 0), Vector3(0.4, 4, 24), Color(0.22, 0.22, 0.26))
	_add_box(Vector3(3, 1.5, 0), Vector3(0.4, 4, 24), Color(0.22, 0.22, 0.26))
	# Back wall behind the spawn.
	_add_box(Vector3(0, 1.5, 12), Vector3(6, 4, 0.4), Color(0.22, 0.22, 0.26))

	# Staircase climbing away from spawn (toward -Z), 9 steps up to a landing.
	var steps := 9
	var rise := 0.32
	var run := 0.9
	for i in range(steps):
		var y := rise * (i + 1)
		var z := -12.0 - run * i
		_add_box(Vector3(0, y - rise * 0.5, z), Vector3(6, rise, run),
			Color(0.34, 0.28, 0.24) if i % 2 == 0 else Color(0.40, 0.33, 0.28))
	# Landing platform at the top.
	var top_y := rise * steps
	var top_z := -12.0 - run * steps - 2.0
	_add_box(Vector3(0, top_y - 0.25, top_z), Vector3(6, 0.5, 4), Color(0.28, 0.30, 0.34))

func _spawn_actors() -> void:
	_player = SleepingBagPlayer.new()
	_player.position = Vector3(0, 1.0, 9.0)
	add_child(_player)

	_monster = NoiseMonster.new()
	_monster.position = Vector3(0, 1.0, -6.0)
	_monster.player = _player
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
	help.text = "WASD shuffle   Space hop (1 pip — empty = face-plant!)   Q look back   R reset   Esc cursor"
	help.position = Vector2(16, 12)
	layer.add_child(help)

	_state_label = Label.new()
	_state_label.position = Vector2(16, 40)
	_state_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_state_label)

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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── Frame loop ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R):
		_reset()

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

	if _caught:
		_state_label.text = "CAUGHT!  Press R to reset"
		_state_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:
		_state_label.text = _player.get_state_text()
		_state_label.remove_theme_color_override("font_color")

	# Stamina pips: lit = a hop you can afford.
	for i in range(_pips.size()):
		_pips[i].color = PIP_ON if _player.stamina >= float(i + 1) else PIP_OFF

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
	_caught = false
	_player.respawn()
	_monster.respawn()

# ── Geometry helper ────────────────────────────────────────────────────────

func _add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)

	add_child(body)
