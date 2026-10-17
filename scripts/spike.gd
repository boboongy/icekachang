extends Node3D
## M1 performance spike: blockout stall built from primitives, low-res render,
## on-screen perf readout, tap to switch waiting/making camera, quality toggle.

const SUN_COLOR := Color(1.0, 0.94, 0.82)

var _cam: Camera3D
var _sun: DirectionalLight3D
var _label: Label
var _making := false
var _high_quality := true

var _wait_xform := Transform3D()
var _make_xform := Transform3D()


func _ready() -> void:
	_build_environment()
	_build_stall()
	_build_camera()
	_build_hud()
	if "--shot" in OS.get_cmdline_user_args():
		_take_shots()


## Dev only: save a screenshot of each view to build/ and quit.
func _take_shots() -> void:
	for view in ["waiting", "making"]:
		for i in 40:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://build/shot_%s.png" % view))
		_toggle_view()
	print("PERF fps=%d tris=%d calls=%d" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()


func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_label.text = "FPS %d  tris %d  calls %d\nshadows %s  view %s\ntap top: quality   tap below: switch view" % [
		fps, tris, calls, "on" if _high_quality else "off", "making" if _making else "waiting"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if event.position.y < get_viewport().get_visible_rect().size.y * 0.25:
			_toggle_quality()
		else:
			_toggle_view()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		_toggle_quality()


func _toggle_view() -> void:
	_making = not _making
	var target := _make_xform if _making else _wait_xform
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cam, "global_transform", target, 0.6)


func _toggle_quality() -> void:
	_high_quality = not _high_quality
	_sun.shadow_enabled = _high_quality


# --- builders ---------------------------------------------------------------

func _mat(color: Color, tex: Texture2D = null, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if tex:
		m.albedo_texture = tex
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _checker(a: Color, b: Color, n := 8) -> ImageTexture:
	var img := Image.create(n * 2, n * 2, false, Image.FORMAT_RGB8)
	for y in n * 2:
		for x in n * 2:
			img.set_pixel(x, y, a if ((x / n + y / n) % 2 == 0) else b)
	return ImageTexture.create_from_image(img)


func _menu_texture() -> ImageTexture:
	# 9 x 3 grid of "photo" tiles, like the lightbox menu reference.
	var cols := [Color(0.95, 0.3, 0.35), Color(0.3, 0.8, 0.4), Color(1.0, 0.75, 0.2),
		Color(0.95, 0.55, 0.75), Color(0.55, 0.35, 0.25), Color(1.0, 0.9, 0.6)]
	var img := Image.create(90, 30, false, Image.FORMAT_RGB8)
	img.fill(Color(0.15, 0.3, 0.75))
	for i in 27:
		var cx := (i % 9) * 10
		var cy := (i / 9) * 10
		img.fill_rect(Rect2i(cx + 1, cy + 1, 8, 7), Color(0.98, 0.98, 0.95))
		img.fill_rect(Rect2i(cx + 3, cy + 2, 4, 4), cols[i % cols.size()])
	return ImageTexture.create_from_image(img)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.82, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.9, 0.95)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.light_color = SUN_COLOR
	_sun.light_energy = 0.75
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 25.0
	_sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(_sun)


func _build_stall() -> void:
	var tile := _mat(Color.WHITE, _checker(Color(0.62, 0.64, 0.66), Color(0.5, 0.52, 0.55)))
	tile.uv1_scale = Vector3(12, 12, 1)
	_box(Vector3(30, 0.1, 30), Vector3(0, -0.05, 0), tile)

	var wall := _mat(Color(0.92, 0.9, 0.86))
	var steel := _mat(Color(0.75, 0.77, 0.8))
	var glass := _mat(Color(0.75, 0.9, 1.0, 0.35))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Stall unit: back wall, side walls, signboard.
	_box(Vector3(4.0, 3.0, 0.1), Vector3(0, 1.5, -1.6), wall)
	_box(Vector3(0.15, 3.0, 3.2), Vector3(-2.0, 1.5, 0), wall)
	_box(Vector3(0.15, 3.0, 3.2), Vector3(2.0, 1.5, 0), wall)
	_box(Vector3(4.2, 0.5, 0.2), Vector3(0, 3.05, 1.55), _mat(Color(0.95, 0.4, 0.55)))

	# Lightbox menu above the counter.
	_box(Vector3(3.4, 0.9, 0.08), Vector3(0, 2.35, 1.5), _mat(Color.WHITE, _menu_texture(), true))

	# Glass display counter with steel base.
	_box(Vector3(2.4, 0.8, 0.8), Vector3(-0.4, 0.4, 0.9), steel)
	_box(Vector3(2.4, 0.5, 0.8), Vector3(-0.4, 1.05, 0.9), glass)
	_box(Vector3(2.5, 0.05, 0.85), Vector3(-0.4, 1.32, 0.9), steel)

	# Prep bench behind (where making happens).
	_box(Vector3(3.6, 0.9, 0.7), Vector3(0, 0.45, -1.1), steel)

	# Ice shaver (rounded cylinders, ref 04).
	var cream := _mat(Color(0.95, 0.92, 0.82))
	_cyl(0.18, 0.22, 0.08, Vector3(-0.6, 0.94, -1.1), cream)
	_box(Vector3(0.08, 0.6, 0.08), Vector3(-0.6, 1.2, -1.3), cream)
	_cyl(0.2, 0.2, 0.25, Vector3(-0.6, 1.45, -1.1), _mat(Color(0.55, 0.8, 0.95)))
	_cyl(0.03, 0.03, 0.3, Vector3(-0.6, 1.7, -1.1), cream, 6)

	# Bowls with shaved ice + topping tubs.
	var bowl_glass := _mat(Color(0.75, 0.9, 0.85))
	var ice_cols := [Color(1, 0.6, 0.7), Color(0.6, 0.9, 0.5), Color(1, 0.9, 0.5)]
	for i in 3:
		var x := 0.1 + i * 0.35
		_cyl(0.12, 0.07, 0.1, Vector3(x, 0.95, -1.0), bowl_glass, 8)
		_cyl(0.0, 0.11, 0.18, Vector3(x, 1.09, -1.0), _mat(ice_cols[i]), 8)
	for i in 6:
		_cyl(0.08, 0.08, 0.1, Vector3(-0.2 + i * 0.22, 0.95, -1.35), _mat(Color.from_hsv(i / 6.0, 0.6, 0.85)), 8)

	# Soup pot.
	_cyl(0.25, 0.22, 0.3, Vector3(1.4, 1.05, -1.1), steel, 12)

	# Uncle blockout: white singlet, apron, specs.
	var uncle := Node3D.new()
	uncle.position = Vector3(0.6, 0, -0.3)
	add_child(uncle)
	_box(Vector3(0.45, 0.8, 0.25), Vector3(0, 0.4, 0), _mat(Color(0.25, 0.25, 0.3)), uncle)
	_box(Vector3(0.5, 0.6, 0.28), Vector3(0, 1.1, 0), _mat(Color(0.97, 0.97, 0.97)), uncle)
	_box(Vector3(0.42, 0.55, 0.05), Vector3(0, 1.0, 0.16), _mat(Color(0.3, 0.45, 0.7)), uncle)
	_box(Vector3(0.28, 0.32, 0.28), Vector3(0, 1.6, 0), _mat(Color(0.85, 0.65, 0.5)), uncle)
	_box(Vector3(0.24, 0.05, 0.02), Vector3(0, 1.64, 0.15), _mat(Color(0.1, 0.1, 0.1)), uncle)

	# Small folding table beside the stall.
	_box(Vector3(0.9, 0.05, 0.6), Vector3(2.7, 0.75, 1.2), _mat(Color(0.9, 0.9, 0.82)))

	# Neighbour stalls, slightly in frame.
	for side in [-1, 1]:
		var x: float = side * 6.2
		_box(Vector3(4.0, 3.0, 0.1), Vector3(x, 1.5, -1.6), wall)
		_box(Vector3(4.2, 0.5, 0.2), Vector3(x, 3.05, 1.55), _mat(Color(0.95, 0.75, 0.3) if side < 0 else Color(0.4, 0.75, 0.5)))
		_box(Vector3(3.0, 1.0, 0.8), Vector3(x, 0.5, 0.9), steel)

	# Hawker centre ceiling, columns and tables in front.
	var roof := _box(Vector3(30, 0.2, 14), Vector3(0, 3.6, 2), _mat(Color(0.88, 0.88, 0.85)))
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # open-sided hawker roof: let sun in
	for x in [-4.1, 4.1]:
		_box(Vector3(0.4, 3.6, 0.4), Vector3(x, 1.8, 1.8), _mat(Color(0.8, 0.5, 0.35)))
	for i in 4:
		var tx: float = [-5.0, -2.6, 2.6, 5.0][i]
		_cyl(0.6, 0.6, 0.05, Vector3(tx, 0.75, 3.6), _mat(Color(0.92, 0.92, 0.88)), 12)
		_cyl(0.06, 0.06, 0.75, Vector3(tx, 0.375, 3.6), steel, 6)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60
	add_child(_cam)
	_wait_xform = Transform3D.IDENTITY.translated(Vector3(0.3, 1.8, 6.0)).looking_at(Vector3(0, 1.3, 0), Vector3.UP)
	_make_xform = Transform3D.IDENTITY.translated(Vector3(0.2, 1.75, -0.2)).looking_at(Vector3(0.2, 0.9, -1.15), Vector3.UP)
	_cam.global_transform = _wait_xform


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(4, 2)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	layer.add_child(_label)
