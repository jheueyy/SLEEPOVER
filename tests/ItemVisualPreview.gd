extends Node3D

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202831")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7c3cf")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.3
	add_child(light)
	for kind in [Item.Kind.CAN, Item.Kind.KEYS, Item.Kind.POPPER]:
		var prop := ItemVisual.build(kind)
		add_child(prop)
		prop.position.x = (float(kind) - 1.0) * 0.42
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.45
	camera.position = Vector3(0, 0.95, -1.4)
	camera.look_at(Vector3(0, 0.08, 0))
	camera.current = true
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://tests/item-visual-preview.png")
	get_tree().quit(result)
