class_name ItemVisual
extends RefCounted
## Shared household prop geometry for pickups and thrown objects.

static func build(kind: int) -> Node3D:
	var root := Node3D.new()
	var metal := _material(Color("a6aaa5"), 0.65, 0.4)
	var paper := _material(Color("d6cba8"))
	match kind:
		Item.Kind.JERKY:
			var wrapper := _material(Color("996443"))
			_box(root, Vector3(0.15, 0.025, 0.21), Vector3(0, 0.025, 0), wrapper)
			for z in [-0.095, 0.095]:
				_box(root, Vector3(0.16, 0.014, 0.018), Vector3(0, 0.027, z), paper)
			_box(root, Vector3(0.1, 0.003, 0.10), Vector3(0, 0.039, 0), paper)
			for x in [-0.025, 0.0, 0.025]:
				_box(root, Vector3(0.012, 0.004, 0.06), Vector3(x, 0.042, 0), wrapper)
		Item.Kind.CAN:
			_cylinder(root, 0.091, 0.091, 0.22, Vector3(0, 0.12, 0), metal)
			_cylinder(root, 0.093, 0.093, 0.15, Vector3(0, 0.12, 0), _material(Color("98583e")))
			for y in [0.018, 0.224]:
				_cylinder(root, 0.097, 0.097, 0.012, Vector3(0, y, 0), metal)
			for y in [0.056, 0.184]:
				_cylinder(root, 0.094, 0.094, 0.008, Vector3(0, y, 0), paper)
			# Raised paper paw mark on the wrapper, readable without tiny lettering.
			var palm := _cylinder(root, 0.022, 0.022, 0.003, Vector3(0, 0.105, -0.094), paper)
			palm.rotation.x = PI / 2
			for x in [-0.026, -0.009, 0.009, 0.026]:
				var pad := _cylinder(root, 0.008, 0.008, 0.003, Vector3(x, 0.141 - absf(x) * 0.35, -0.094), paper)
				pad.rotation.x = PI / 2
			var tab := _ring(root, 0.009, 0.015, Vector3(0, 0.232, -0.015), metal)
			tab.scale.z = 1.6
		Item.Kind.KEYS:
			var brass := _material(Color("aa8748"), 0.65, 0.45)
			_ring(root, 0.045, 0.053, Vector3(0, 0.016, 0), metal)
			for i in 2:
				var key := Node3D.new()
				root.add_child(key)
				key.position = Vector3(-0.023 + i * 0.04, 0.012 + i * 0.009, 0.045)
				key.rotation.y = -0.25 + i * 0.7
				_ring(key, 0.012, 0.025, Vector3.ZERO, brass)
				_box(key, Vector3(0.018, 0.009, 0.11), Vector3(0, 0, 0.072), brass)
				for tooth in 3:
					_box(key, Vector3(0.022 + (tooth % 2) * 0.008, 0.009, 0.012),
						Vector3(0.014, 0, 0.08 + tooth * 0.018), brass)
			_box(root, Vector3(0.064, 0.007, 0.09), Vector3(0.07, 0.01, -0.026), _material(Color("708c89")))
		Item.Kind.POPPER:
			var red := _material(Color("ad524b"))
			_cylinder(root, 0.028, 0.074, 0.22, Vector3(0, 0.12, 0), red)
			_cylinder(root, 0.075, 0.075, 0.014, Vector3(0, 0.018, 0), paper)
			_cylinder(root, 0.029, 0.029, 0.014, Vector3(0, 0.23, 0), paper)
			_cylinder(root, 0.053, 0.062, 0.04, Vector3(0, 0.1, 0), paper)
			# Loose pull string curling down one side of the paper shell.
			for i in 12:
				var a := float(i) / 12.0
				var b := float(i + 1) / 12.0
				var start := Vector3(0.025 + sin(a * PI) * 0.065, 0.23 - a * 0.12, 0)
				var end := Vector3(0.025 + sin(b * PI) * 0.065, 0.23 - b * 0.12, 0)
				var string := _cylinder(root, 0.003, 0.003, start.distance_to(end) + 0.001,
					(start + end) * 0.5, paper)
				string.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return root

static func _material(color: Color, metallic: float = 0.0, roughness: float = 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

static func _part(root: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = mat
	root.add_child(part)
	return part

static func _cylinder(root: Node3D, top: float, bottom: float, height: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 20
	return _part(root, mesh, at, mat)

static func _ring(root: Node3D, inner: float, outer: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 8
	return _part(root, mesh, at, mat)

static func _box(root: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_part(root, mesh, at, mat)
