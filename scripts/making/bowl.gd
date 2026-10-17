class_name Bowl
extends Node3D
## The bowl being made: what is in it, and one vertex-coloured mesh for the contents, rebuilt
## whenever something changes. Two vessels: the glass bowl (ice mound, syrup on the ice, topping
## clusters on the mound) and the white soup bowl (flat soup surface, toppings floating on it).
## Local origin = bottom of the bowl's foot. Sizes match tools/blender/build_stall.py.

const RIM_Y := 0.105      # glass: top of the glass, where the mound starts
const MOUND_R := 0.115    # glass: mound base radius (bowl rim is 0.12)
const MOUND_H := 0.15     # glass: height of a full mound
const SOUP_FLOOR_Y := 0.028   # soup bowl: inside bottom, radius SOUP_FLOOR_R
const SOUP_FLOOR_R := 0.05
const SOUP_TOP_Y := 0.082     # soup bowl: rim, inside radius SOUP_TOP_R
const SOUP_TOP_R := 0.094
const SOUP_LEVEL := [0.036, 0.072]   # soup surface height at fill 0 and fill 1
const SEGS := 10
const RINGS := 4
## Where topping clusters go, in order: on top, then round the side facing the uncle (-Z).
## [angle from -Z in degrees, radius as a fraction of the mound radius]
const SLOTS := [[0, 0.0], [0, 0.62], [-58, 0.62], [58, 0.62], [-112, 0.66], [112, 0.66], [180, 0.6]]
## Soup: the first topping (you tiao) floats at the side nearest the uncle, the rest round it.
const SOUP_SLOTS := [[0, 0.42], [-90, 0.4], [90, 0.4], [180, 0.4], [0, 0.0], [-45, 0.45], [45, 0.45]]

var vessel := "glass"     # "glass" or "soup"
var base := ""            # "", or a base ingredient id (ice, milk_ice, tau_suan_soup)
var fill := 0.0           # 0..1, how much ice is shaved / soup is ladled in
var toppings: Array[String] = []
var sauces: Array[String] = []
var fixes := 0            # toppings taken back out (costs the tidy star)

var _contents: MeshInstance3D
var _glass: Node3D
var _soup: Node3D

static var _mat: StandardMaterial3D


## Lit material for vertex-coloured food meshes (bowl contents, the scoop being carried).
static func food_material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 1.0
		_mat.metallic_specular = 0.25
	return _mat


func _init(glass: MeshInstance3D = null, soup: MeshInstance3D = null) -> void:
	_glass = _adopt(glass)
	_soup = _adopt(soup)
	_contents = MeshInstance3D.new()
	add_child(_contents)
	set_vessel("glass")


func _adopt(mesh: MeshInstance3D) -> Node3D:
	if mesh:
		mesh.get_parent().remove_child(mesh)
		mesh.transform = Transform3D.IDENTITY
		add_child(mesh)
	return mesh


func set_vessel(v: String) -> void:
	vessel = v
	if _glass:
		_glass.visible = v == "glass"
	if _soup:
		_soup.visible = v == "soup"


func state() -> Dictionary:
	return {"vessel": vessel, "base": base, "fill": fill, "toppings": toppings.duplicate(),
		"sauces": sauces.duplicate(), "fixes": fixes}


func clear() -> void:
	base = ""
	fill = 0.0
	toppings.clear()
	sauces.clear()
	fixes = 0
	rebuild()


## Enough ice or soup in it to add toppings and serve.
func has_base() -> bool:
	return fill >= RecipeBook.MIN_ICE


## Local height of the top of the contents (or of the empty bowl), for pouring and carrying.
func top_y() -> float:
	if vessel == "soup":
		return SOUP_TOP_Y
	return RIM_Y + _h()


## Local position of topping cluster i (on the mound or floating on the soup).
func cluster_local(i: int) -> Vector3:
	var slots: Array = SOUP_SLOTS if vessel == "soup" else SLOTS
	var s: Array = slots[mini(i, slots.size() - 1)]
	var a := deg_to_rad(s[0])
	var rho: float = s[1] * _r()
	return Vector3(sin(a) * rho, _surface_y(rho), -cos(a) * rho)


func cluster_global(i: int) -> Vector3:
	return to_global(cluster_local(i))


## Little bounce when something lands in the bowl.
func bounce() -> void:
	var tw := create_tween()
	_contents.scale = Vector3(1.08, 0.86, 1.08)
	tw.tween_property(_contents, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A heap of one topping, for the scoop the player carries from a tub.
static func scoop_mesh(id: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_pieces(st, id, Vector3.ZERO, 0, null)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, food_material())
	return mesh


## Radius of the mound, or of the soup surface.
func _r() -> float:
	if vessel == "soup":
		var t := (_soup_level() - SOUP_FLOOR_Y) / (SOUP_TOP_Y - SOUP_FLOOR_Y)
		return lerpf(SOUP_FLOOR_R, SOUP_TOP_R, t)
	return MOUND_R * lerpf(0.75, 1.0, fill)


func _h() -> float:
	return MOUND_H * fill + 0.004


func _soup_level() -> float:
	return lerpf(SOUP_LEVEL[0], SOUP_LEVEL[1], fill)


## Height of the contents' surface at distance rho from the centre: the mound (an ellipsoid
## cap) or the flat soup.
func _surface_y(rho: float) -> float:
	if vessel == "soup":
		return _soup_level()
	var q := clampf(rho / _r(), 0.0, 0.97)
	return RIM_Y + _h() * sqrt(1.0 - q * q)


func rebuild() -> void:
	if fill <= 0.0:
		_contents.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if vessel == "soup":
		_add_soup(st)
	else:
		_add_mound(st)
	for i in toppings.size():
		add_pieces(st, toppings[i], cluster_local(i), i, self)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, food_material())
	_contents.mesh = mesh


func _add_mound(st: SurfaceTool) -> void:
	var r := _r()
	var h := _h()
	var ice := RecipeBook.color(base)
	var rings: Array = []
	for k in RINGS + 1:
		var t := float(k) / RINGS
		rings.append([r * cos(t * PI / 2), RIM_Y + h * sin(t * PI / 2)])
	# ice packed inside the glass, seen through its walls (inner wall: r 0.083 at 0.034 to 0.115 at RIM_Y)
	var inner_c := ice.darkened(0.08)
	var lo := [0.08, 0.036]
	var hi := [0.112, RIM_Y]
	for i in SEGS:
		var a0 := TAU * i / SEGS
		var a1 := TAU * (i + 1) / SEGS
		var c := inner_c.lightened(0.06) if i % 2 else inner_c
		_tri(st, c, _ring_pt(lo, a0), _ring_pt(lo, a1), _ring_pt(hi, a0))
		_tri(st, c, _ring_pt(lo, a1), _ring_pt(hi, a1), _ring_pt(hi, a0))
	var face := 0
	for k in RINGS:
		for i in SEGS:
			var a0 := TAU * i / SEGS
			var a1 := TAU * (i + 1) / SEGS
			var c := _face_color(ice, k, face)
			face += 1
			var p00 := _ring_pt(rings[k], a0)
			var p01 := _ring_pt(rings[k], a1)
			var p10 := _ring_pt(rings[k + 1], a0)
			var p11 := _ring_pt(rings[k + 1], a1)
			_tri(st, c, p00, p01, p10)    # clockwise seen from outside = front face in Godot
			if k < RINGS - 1:
				_tri(st, c, p01, p11, p10)


## Flat soup surface: an outer ring of faces and a centre fan, two tones of the soup colour.
## Sauces (coconut milk on later soups) cover some faces like they do on the ice.
func _add_soup(st: SurfaceTool) -> void:
	var r := _r()
	var y := _soup_level()
	var c1 := RecipeBook.color(base)
	var c2 := RecipeBook.color(base, "color2")
	var inner := [r * 0.55, y]
	var outer := [r, y]
	var face := 0
	for i in SEGS:
		var a0 := TAU * i / SEGS
		var a1 := TAU * (i + 1) / SEGS
		var ci := _face_color(c1 if i % 3 else c2, 1, face)
		var co := _face_color(c2 if i % 4 == 1 else c1, 0, face + SEGS)
		face += 1
		_tri(st, ci, _ring_pt(inner, a0), _ring_pt(inner, a1), Vector3(0, y, 0))
		_tri(st, co, _ring_pt(outer, a0), _ring_pt(outer, a1), _ring_pt(inner, a0))
		_tri(st, co, _ring_pt(outer, a1), _ring_pt(inner, a1), _ring_pt(inner, a0))


## Syrups run down from the top: each covers some faces from its starting ring upwards.
## Later sauces sit on top of earlier ones. Small per-face jitter gives the low-res texture feel.
func _face_color(ice: Color, ring: int, face: int) -> Color:
	var c := ice
	for s in sauces:
		var info := RecipeBook.ingredient(s)
		var hsh := (face * 73 + int(info.slot) * 151 + 17) % 100
		if ring >= int(info.from_ring) and hsh < int(info.coverage):
			c = RecipeBook.color(s)
	var j := 1.0 + (((face * 37) % 9) - 4) * 0.012
	return Color(c.r * j, c.g * j, c.b * j)


func _ring_pt(ring: Array, a: float) -> Vector3:
	return Vector3(sin(a) * ring[0], ring[1], -cos(a) * ring[0])


static func _tri(st: SurfaceTool, c: Color, a: Vector3, b: Vector3, d: Vector3) -> void:
	st.set_color(c)
	st.add_vertex(a)
	st.set_color(c)
	st.add_vertex(b)
	st.set_color(c)
	st.add_vertex(d)


## Adds one cluster of topping pieces around `centre`: little cubes, or long sticks for
## shape "stick" (you tiao). `bowl` gives the surface so pieces sit on it; null = flat heap
## (the scoop the player carries).
static func add_pieces(st: SurfaceTool, id: String, centre: Vector3, seed_: int, bowl: Bowl) -> void:
	var info := RecipeBook.ingredient(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + seed_ * 977
	var size: float = info.size
	var stick: bool = info.get("shape", "") == "stick"
	var spread := 0.022 if stick else 0.032
	var c1 := RecipeBook.color(id)
	var c2 := RecipeBook.color(id, "color2")
	for n in int(info.count):
		var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spread
		var p := centre + Vector3(off.x, 0, off.y)
		var s := size * rng.randf_range(0.8, 1.2)
		if bowl:
			p.y = bowl._surface_y(Vector2(p.x, p.z).length()) + s * 0.3
		else:
			p.y += s * 0.5 + (spread - off.length()) * 0.4
		# sticks lie roughly side by side (across the bowl), cubes any way round
		var yaw := rng.randf_range(-0.35, 0.35) + PI / 2 if stick else rng.randf() * TAU
		var stretch := Vector3(0.8, 0.75, 3.6) if stick else Vector3.ONE
		_cube(st, p, s, yaw, c1 if n % 2 == 0 else c2, stretch)


static func _cube(st: SurfaceTool, p: Vector3, s: float, yaw: float, c: Color, stretch := Vector3.ONE) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(stretch * s * 0.5)
	var v := []
	for k in 8:
		v.append(p + b * Vector3(1 if k & 1 else -1, 1 if k & 2 else -1, 1 if k & 4 else -1))
	# faces as quads of corner indices, clockwise seen from outside (Godot's front face)
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		var shade := 1.0 if q[0] == 2 else 0.85
		var cc := Color(c.r * shade, c.g * shade, c.b * shade)
		_tri(st, cc, v[q[0]], v[q[1]], v[q[2]])
		_tri(st, cc, v[q[0]], v[q[2]], v[q[3]])
