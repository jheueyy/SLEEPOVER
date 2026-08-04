class_name BagVisual
extends Object
## Procedural sleeping-bag character matching the concept sheet 1:1 in
## silhouette, palette, and proportion: puffy stacked quilt segments, a front
## zipper with pull tab, and two big googly eyes.
## One builder, eight skins — the launch cosmetic list is a data table.

## THE canonical bag height, and the one number that sets the game's sense of
## scale. Everything that must physically MATCH the bag derives from it — the
## collision capsule, the ground rays, the mouth height a voice comes out of.
## A mismatch between any of those and the visual is a bug, not a tuning choice.
##
## Rooms are 3m floor-to-floor and the Housesitter is 2.4m, so at 0.45 she stands
## 5.3x your height and a single storey is nearly 7 bag-heights: you are a small
## thing loose in a full-sized house. Camera and reach values are scaled to match
## but kept as their own numbers, because those are FEEL and want independent
## tuning. House geometry is deliberately NOT scaled — see FEEL.md.
const BAG_HEIGHT := 0.45

## Where the googly eyes sit, as a fraction of height above the bag's FEET.
## The first-person camera reads this so "first person" is genuinely behind the
## eyes. Keep it and the eye meshes below in sync — they are the same number.
const EYE_FRACTION := 0.74

## Meshes at or above eye level are tagged with this. The LOCAL player moves them
## to their own render layer so a first-person camera can cull them and leave the
## body — you look down and see the bag you're zipped into. Remote ghosts never
## act on the tag, which is what keeps teammates' googly eyes on screen.
const HEAD_PART_META := "head_part"

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

## Builds the bag and returns just the visual root (eyes idle).
static func build(height: float = BAG_HEIGHT, skin: int = 0) -> Node3D:
	return build_with_eyes(height, skin)[0]

## Builds the bag AND returns [root, BagEyes] so a caller can drive eye-states.
## Every segment is a fraction of `height`, so the whole character scales from
## the one number.
static func build_with_eyes(height: float = BAG_HEIGHT, skin: int = 0) -> Array:
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
		# Segments at or above EYE_FRACTION are "head": the first-person camera
		# sits INSIDE segment 3, so leaving it drawn fills the screen with the
		# inside of your own bag. Everything below stays — that's the body you
		# look down and see.
		if seg_heights[i] >= EYE_FRACTION - 0.01:
			seg.set_meta(HEAD_PART_META, true)
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
	pull.set_meta(HEAD_PART_META, true)  # above the eye and in front — would hang in view
	root.add_child(pull)

	# Googly eyes: the whole personality. Big whites, black pupils, unshaded
	# so they read from any distance in any lighting.
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.98, 0.98, 0.96)
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.05, 0.06)
	pupil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Eyelids: a body-coloured cap that slides down over each eye (BagEyes drives
	# the y). Unshaded so it reads flat over the unshaded white.
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = base_col.darkened(0.15)
	lid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var pupils: Array[Node3D] = []
	var lids: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.095 * height
		eye_mesh.height = 0.19 * height
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.085 * height, EYE_FRACTION * height, -0.175 * height)
		eye.set_surface_override_material(0, white_mat)
		eye.set_meta(HEAD_PART_META, true)   # you can't see your own eyeballs
		root.add_child(eye)

		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.045 * height
		pupil_mesh.height = 0.09 * height
		pupil.mesh = pupil_mesh
		pupil.position = Vector3(side * 0.085 * height, 0.745 * height, -0.255 * height)
		pupil.set_surface_override_material(0, pupil_mat)
		pupil.set_meta(HEAD_PART_META, true)
		root.add_child(pupil)
		pupils.append(pupil)

		var lid := MeshInstance3D.new()
		var lid_mesh := SphereMesh.new()
		lid_mesh.radius = 0.11 * height
		lid_mesh.height = 0.22 * height
		lid.mesh = lid_mesh
		# Rest position: raised above the eye (open). BagEyes lowers it to close.
		lid.position = Vector3(side * 0.085 * height, 0.74 * height + 0.19 * height, -0.185 * height)
		lid.set_surface_override_material(0, lid_mat)
		lid.set_meta(HEAD_PART_META, true)
		root.add_child(lid)
		lids.append(lid)

	var eyes := BagEyes.new()
	eyes.setup(pupils, lids, height)
	return [root, eyes]
