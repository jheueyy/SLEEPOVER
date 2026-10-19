extends Control
## Lightweight title-screen composition. Final painted assets can replace this
## without changing menu navigation or shipping a separate rendering dependency.

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var scale_xy := size / Vector2(1152, 648)
	draw_set_transform(Vector2.ZERO, 0.0, scale_xy)
	draw_rect(Rect2(0, 0, 1152, 648), Color("171f29"))
	# Bedroom wall and low skirting, leaving the invitation column quiet.
	draw_rect(Rect2(478, 0, 674, 490), Color("202c37"))
	for x in range(492, 1152, 38):
		draw_line(Vector2(x, 0), Vector2(x, 490), Color("26323a"), 1)
	draw_rect(Rect2(478, 486, 674, 10), Color("394047"))
	draw_rect(Rect2(478, 496, 674, 152), Color("151c24"))
	# A single moonlit window, with an ordinary house beyond it.
	draw_rect(Rect2(704, 80, 258, 282), Color("0d141f"))
	draw_rect(Rect2(720, 96, 226, 250), Color("536478"))
	draw_circle(Vector2(892, 144), 29, Color("e3dac1"))
	draw_colored_polygon(PackedVector2Array([Vector2(720, 300), Vector2(768, 251), Vector2(850, 285), Vector2(946, 243), Vector2(946, 346), Vector2(720, 346)]), Color("283443"))
	draw_rect(Rect2(828, 96, 10, 250), Color("171f29"))
	draw_rect(Rect2(720, 212, 226, 10), Color("171f29"))
	draw_rect(Rect2(693, 354, 280, 12), Color("867965"))
	# Curtains use a restrained repeated fold, no animated flicker behind text.
	for x in [680, 956]:
		draw_rect(Rect2(x, 69, 35, 304), Color("6b4140"))
		draw_line(Vector2(x + 11, 72), Vector2(x + 11, 371), Color("824e47"), 4)
	# Sleeping bags on the rug echo the characters' quilted silhouette.
	draw_colored_polygon(PackedVector2Array([Vector2(590, 542), Vector2(1010, 512), Vector2(1142, 647), Vector2(532, 647)]), Color("484b48"))
	_bag(Vector2(651, 483), Color("99554c"), -0.12)
	_bag(Vector2(871, 485), Color("687c7a"), 0.16)
	draw_set_transform(Vector2.ZERO)

func _bag(origin: Vector2, color: Color, angle: float) -> void:
	draw_set_transform(origin * size / Vector2(1152, 648), angle, size / Vector2(1152, 648))
	var body := StyleBoxFlat.new()
	body.bg_color = color
	body.set_corner_radius_all(28)
	draw_style_box(body, Rect2(0, 0, 126, 160))
	draw_ellipse_shape(Vector2(63, 29), Vector2(43, 20), Color("1c242b"))
	for y in [66, 93, 120, 144]:
		draw_line(Vector2(12, y), Vector2(113, y), color.darkened(0.18), 2)
	draw_line(Vector2(108, 46), Vector2(108, 137), Color("c6b38e"), 2)
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1152, 648))

func draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, color)
