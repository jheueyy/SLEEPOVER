class_name DogVisual
extends RefCounted
## Small floppy-eared house dog, built from a consistent set of soft shapes.

static func build() -> Node3D:
	var root := Node3D.new()
	var coat := _mat(Color("82614a"))
	var cream := _mat(Color("c9b698"))
	var dark := _mat(Color("302822"))
	_oval(root, Vector3(0, 0.35, 0.03), Vector3(0.34, 0.35, 0.63), coat)
	_oval(root, Vector3(0, 0.43, -0.28), Vector3(0.32, 0.32, 0.30), coat)
	_oval(root, Vector3(0, 0.365, -0.43), Vector3(0.235, 0.16, 0.23), cream)
	_oval(root, Vector3(0, 0.41, -0.535), Vector3(0.09, 0.06, 0.045), dark)
	for side in [-1, 1]:
		var ear := _oval(root, Vector3(side * 0.16, 0.38, -0.27), Vector3(0.10, 0.32, 0.18), dark)
		ear.rotation.z = side * 0.17
		_oval(root, Vector3(side * 0.092, 0.477, -0.407), Vector3(0.042, 0.047, 0.023), dark)
		_oval(root, Vector3(side * 0.092 - 0.006, 0.487, -0.419), Vector3(0.009, 0.009, 0.005), cream)
	var collar := _oval(root, Vector3(0, 0.35, -0.205), Vector3(0.345, 0.10, 0.21), _mat(Color("536f69")))
	collar.rotation.x = -0.3
	var legs: Array[Node3D] = []
	for z in [-0.18, 0.25]:
		for side in [-1, 1]:
			var pivot := Node3D.new()
			root.add_child(pivot)
			pivot.position = Vector3(side * 0.115, 0.24, z)
			_oval(pivot, Vector3(0, -0.095, 0), Vector3(0.09, 0.23, 0.105), coat)
			_oval(pivot, Vector3(0, -0.205, -0.018), Vector3(0.11, 0.075, 0.15), cream)
			legs.append(pivot)
	var tail := Node3D.new()
	root.add_child(tail)
	tail.position = Vector3(0, 0.37, 0.30)
	var tail_mesh := _oval(tail, Vector3(0, 0.055, 0.12), Vector3(0.07, 0.08, 0.30), coat)
	tail_mesh.rotation.x = -0.4
	var keys := ItemVisual.build(Item.Kind.KEYS)
	root.add_child(keys)
	keys.position = Vector3(0, 0.345, -0.49)
	keys.rotation.x = PI / 2
	keys.scale = Vector3.ONE * 0.7
	root.set_meta("legs", legs)
	root.set_meta("tail", tail)
	root.set_meta("keys", keys)
	return root

static func animate(root: Node3D, phase: float, moving: bool, fed: bool, delta: float) -> void:
	var legs: Array = root.get_meta("legs", [])
	for i in legs.size():
		var target := sin(phase + (0.0 if i in [0, 3] else PI)) * 0.28 if moving else 0.0
		legs[i].rotation.x = lerpf(legs[i].rotation.x, target, minf(delta * 14.0, 1.0))
	var tail: Node3D = root.get_meta("tail")
	tail.rotation.y = sin(Time.get_ticks_msec() * 0.005) * (0.4 if fed else 0.16)
	(root.get_meta("keys") as Node3D).visible = not fed

static func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	return mat

static func _oval(root: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	part.mesh = sphere
	part.scale = size
	part.position = at
	part.material_override = mat
	root.add_child(part)
	return part
