class_name BagVisual
extends Object
## Procedural sleeping-bag character matching the concept sheet 1:1 in
## silhouette, palette, and proportion (~0.9m tall): puffy stacked quilt
## segments, a front zipper with pull tab, and two big googly eyes.
## One builder, eight skins — the launch cosmetic list is a data table.

const SKINS: Array = [
	{"name": "CLASSIC RED", "base": Color(0.82, 0.12, 0.12)},
	{"name": "NIGHT SKY", "base": Color(0.16, 0.28, 0.78)},
	{"name": "SUNSHINE", "base": Color(0.95, 0.72, 0.08)},
	{"name": "FOREST", "base": Color(0.30, 0.62, 0.18)},
	{"name": "DREAMER", "base": Color(0.46, 0.18, 0.66)},
	{"name": "SWEETHEART", "base": Color(0.93, 0.38, 0.58)},
	{"name": "CLOUDY", "base": Color(0.25, 0.75, 0.85)},
	{"name": "RETRO", "base": Color(0.90, 0.46, 0.10)},
]

## Skin for a network peer — same everywhere so everyone sees the same bag.
static func skin_for_peer(peer_id: int) -> int:
	return 0 if peer_id == 1 else peer_id % SKINS.size()

## Builds the bag, base at y=0, front facing -Z. `height` ~0.9 per concept.
static func build(height: float = 0.9, skin: int = 0) -> Node3D:
	var root := Node3D.new()
	var base_col: Color = SKINS[skin % SKINS.size()]["base"]

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = base_col
	body_mat.roughness = 0.85

	# Puffy quilt segments: stacked squashed spheres. The creases where they
	# overlap read as the horizontal seams in the concept art.
	var seg_heights: Array = [0.14, 0.34, 0.54, 0.74, 0.90]  # centers, as fraction of height
	var seg_radii: Array = [0.26, 0.29, 0.28, 0.25, 0.19]    # widest below middle
	for i in range(seg_heights.size()):
		var seg := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = seg_radii[i] * height
		sphere.height = seg_radii[i] * height * 1.35  # squashed puff
		seg.mesh = sphere
		seg.position = Vector3(0, seg_heights[i] * height, 0)
		seg.set_surface_override_material(0, body_mat)
		root.add_child(seg)

	# Zipper: a thin bright strip up the front + a little pull tab at the top.
	var zip_mat := StandardMaterial3D.new()
	zip_mat.albedo_color = Color(0.92, 0.92, 0.88)
	zip_mat.roughness = 0.4
	var zipper := MeshInstance3D.new()
	var zip_box := BoxMesh.new()
	zip_box.size = Vector3(0.030 * height, 0.66 * height, 0.02)
	zipper.mesh = zip_box
	zipper.position = Vector3(0, 0.42 * height, -0.265 * height)
	zipper.set_surface_override_material(0, zip_mat)
	root.add_child(zipper)

	var pull := MeshInstance3D.new()
	var pull_box := BoxMesh.new()
	pull_box.size = Vector3(0.05 * height, 0.07 * height, 0.02)
	pull.mesh = pull_box
	pull.position = Vector3(0, 0.78 * height, -0.24 * height)
	pull.set_surface_override_material(0, zip_mat)
	root.add_child(pull)

	# Googly eyes: the whole personality. Big whites, black pupils, unshaded
	# so they read from any distance in any lighting.
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.98, 0.98, 0.96)
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.05, 0.06)
	pupil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.095 * height
		eye_mesh.height = 0.19 * height
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.085 * height, 0.74 * height, -0.175 * height)
		eye.set_surface_override_material(0, white_mat)
		root.add_child(eye)

		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.045 * height
		pupil_mesh.height = 0.09 * height
		pupil.mesh = pupil_mesh
		pupil.position = Vector3(side * 0.085 * height, 0.745 * height, -0.255 * height)
		pupil.set_surface_override_material(0, pupil_mat)
		root.add_child(pupil)

	return root
