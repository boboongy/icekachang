class_name Bowl
extends Node3D
## The bowl being made: what is in it, and one vertex-coloured mesh for the contents, rebuilt
## whenever something changes. Two vessels: the glass cup (fluffy shaved-ice cone, syrups that
## soak down into it as colour fades, topping clusters, a spoon) and the white soup bowl (flat
## soup surface, toppings floating on it). Look after plan ref 06.
## Local origin = bottom of the bowl's foot. Sizes match tools/blender/build_stall.py.

const RIM_Y := 0.105      # glass: top of the glass, where the mound starts
const MOUND_R := 0.115    # glass: mound base radius (bowl rim is 0.12)
const MOUND_H := 0.18     # glass: height of a full mound (a cone, after ref 06)
const MOUND_POW := 0.75   # cone profile: radius = r * (1 - t)^MOUND_POW at height fraction t
const LUMP := 0.08        # random in/out of the cone's vertices, for the fluffy look
const SOUP_FLOOR_Y := 0.028   # soup bowl: inside bottom, radius SOUP_FLOOR_R
const SOUP_FLOOR_R := 0.05
const SOUP_TOP_Y := 0.082     # soup bowl: rim, inside radius SOUP_TOP_R
const SOUP_TOP_R := 0.094
const SOUP_LEVEL := [0.036, 0.072]   # soup surface height at fill 0 and fill 1
const SEGS := 10         # soup surface
const MOUND_SEGS := 14
const RINGS := 6
const SPOON_ANGLE := -72.0   # degrees from -Z (the uncle's side; +X is screen left): screen right, clear of the toppings
## Where topping clusters go, in order: on top, then round the side facing the uncle (-Z).
## [angle from -Z in degrees, radius as a fraction of the mound radius]
const SLOTS := [[0, 0.0], [0, 0.62], [-58, 0.62], [58, 0.62], [-112, 0.66], [112, 0.66], [180, 0.6]]
## Fruit (jars) in a glass: extra heaps besides its own cluster, [angle, radius fraction] like SLOTS.
const GARNISH_ANGLE := -35.0   # degrees from -Z like SPOON_ANGLE: front right, in view
const FRUIT_SPREAD :=[[-40, 0.5], [40, 0.5], [0, 0.78], [-95, 0.7], [95, 0.7]]
## Soup: the first topping (you tiao) floats at the side nearest the uncle, the rest round it.
const SOUP_SLOTS := [[0, 0.42], [-90, 0.4], [90, 0.4], [180, 0.4], [0, 0.0], [-45, 0.45], [45, 0.45]]
## Shaved ice in a soup bowl (cold bobo chacha): a small heap at the far side, clear of the first
## toppings; [radius, height] at a dab of ice and at ice 1 (a full mound, far too much).
const SOUP_ICE_RHO := 0.35
const SOUP_ICE_R := [0.03, 0.085]
const SOUP_ICE_H := [0.025, 0.11]

var vessel := "glass"     # "glass" or "soup"
var base := ""            # "", or a base ingredient id (ice, milk_ice, tau_suan_soup)
var fill := 0.0           # 0..1, how much ice is shaved / soup is ladled in
var ice := 0.0            # soup bowl only: 0..1, shaved ice on top (cold bobo chacha)
var toppings: Array[String] = []
var sauces: Array[String] = []
var fixes := 0            # toppings taken back out (costs the tidy star)

var _contents: MeshInstance3D
var _glass: Node3D
var _soup: Node3D

static var _mat: StandardMaterial3D


## Lit material for vertex-coloured food meshes (bowl contents, the scoop being carried). A
## small speckle texture, mapped triplanar, gives the shaved ice its grainy snow look.
static func food_material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 1.0
		_mat.metallic_specular = 0.25
		_mat.albedo_texture = _grain_texture()
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat.uv1_triplanar = true
		_mat.uv1_scale = Vector3.ONE * 5.0     # 32 texels per 0.2 m: about 2 px each up close
	return _mat


## Mostly white with fine grey grains and a few bright sparkles (multiplies the vertex colour).
static func _grain_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 32:
		for x in 32:
			var v := rng.randf_range(0.9, 1.0)
			var r := rng.randf()
			if r < 0.12:
				v = rng.randf_range(0.76, 0.84)
			elif r > 0.95:
				v = 1.0
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


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
	return {"vessel": vessel, "base": base, "fill": fill, "ice": ice, "toppings": toppings.duplicate(),
		"sauces": sauces.duplicate(), "fixes": fixes}


## Puts back a state() taken earlier (the first of a 2-dessert order waiting on the tray).
func load_state(s: Dictionary) -> void:
	set_vessel(s.vessel)
	base = s.base
	fill = s.fill
	ice = s.get("ice", 0.0)
	toppings.assign(s.toppings)
	sauces.assign(s.sauces)
	fixes = s.fixes
	rebuild()


func clear() -> void:
	base = ""
	fill = 0.0
	ice = 0.0
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


## Height of the contents' surface at distance rho from the centre: the mound (a cone with a
## soft profile, see MOUND_POW; the lumps are left out) or the flat soup.
func _surface_y(rho: float) -> float:
	if vessel == "soup":
		return _soup_level()
	var q := clampf(rho / _r(), 0.0, 1.0)
	return RIM_Y + _h() * (1.0 - pow(q, 1.0 / MOUND_POW))


func rebuild() -> void:
	if fill <= 0.0 and ice <= 0.0:
		_contents.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if vessel == "soup":
		if fill > 0.0:
			_add_soup(st)
		if ice > 0.0:
			_add_soup_ice(st)
	else:
		_add_mound(st)
		if has_base():
			_add_spoon(st)
	for i in toppings.size():
		add_pieces(st, toppings[i], cluster_local(i), i, self)
		if vessel == "glass" and RecipeBook.ingredient(toppings[i]).kind == "fruit":
			for k in FRUIT_SPREAD.size():       # a fruit ice is all about the fruit: heaps round the front
				var a := deg_to_rad(FRUIT_SPREAD[k][0])
				var rho: float = FRUIT_SPREAD[k][1] * _r()
				add_pieces(st, toppings[i], Vector3(sin(a) * rho, _surface_y(rho), -cos(a) * rho), i * 10 + k + 1, self)
			_add_garnish(st, toppings[i])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, food_material())
	_contents.mesh = mesh


func _add_mound(st: SurfaceTool) -> void:
	var r := _r()
	var h := _h()
	var ice := RecipeBook.color(base)
	# ice packed inside the cup, seen through the glass (inner wall: tools/blender/build_stall.py)
	var inner_c := ice.darkened(0.08)
	var lo := [0.062, 0.05]
	var hi := [0.112, RIM_Y]
	for i in MOUND_SEGS:
		var a0 := TAU * i / MOUND_SEGS
		var a1 := TAU * (i + 1) / MOUND_SEGS
		var c := inner_c.lightened(0.06) if i % 2 else inner_c
		_tri(st, c, _ring_pt(lo, a0), _ring_pt(lo, a1), _ring_pt(hi, a0))
		_tri(st, c, _ring_pt(lo, a1), _ring_pt(hi, a1), _ring_pt(hi, a0))
	# the cone: RINGS rings of MOUND_SEGS vertices, coloured per vertex so the syrups blend
	# smoothly into the ice; the top ring has radius 0 (the tip)
	var pts := []
	var cols := []
	for k in RINGS + 1:
		var t := float(k) / RINGS
		var row := []
		var crow := []
		for i in MOUND_SEGS:
			var a := TAU * i / MOUND_SEGS
			var lump := 0.0 if k == 0 or k == RINGS else _hash(k * 31 + i) * LUMP
			var rho := r * pow(1.0 - t, MOUND_POW) * (1.0 + lump)
			row.append(Vector3(sin(a) * rho, RIM_Y + h * t + lump * 0.02, -cos(a) * rho))
			crow.append(_ice_color(ice, a, t, k * 31 + i))
		pts.append(row)
		cols.append(crow)
	for k in RINGS:
		for i in MOUND_SEGS:
			var j := (i + 1) % MOUND_SEGS
			_tri_c(st, [pts[k][i], pts[k][j], pts[k + 1][i]], [cols[k][i], cols[k][j], cols[k + 1][i]])
			if k < RINGS - 1:
				_tri_c(st, [pts[k][j], pts[k + 1][j], pts[k + 1][i]], [cols[k][j], cols[k + 1][j], cols[k + 1][i]])


## Shaved ice in the soup bowl: a lumpy white cone on the soup (or the empty bowl's floor),
## growing with `ice`. Before or after the soup, it looks the same.
func _add_soup_ice(st: SurfaceTool) -> void:
	var r := lerpf(SOUP_ICE_R[0], SOUP_ICE_R[1], ice)
	var h := lerpf(SOUP_ICE_H[0], SOUP_ICE_H[1], ice)
	var y0 := _soup_level() if fill > 0.0 else SOUP_FLOOR_Y
	var c := Vector3(0, y0, SOUP_ICE_RHO * SOUP_TOP_R * (1.0 - ice))   # +Z = away from the uncle
	var white := RecipeBook.color("ice")
	var rows := 3
	var pts := []
	for k in rows + 1:
		var t := float(k) / rows
		var row := []
		for i in MOUND_SEGS:
			var a := TAU * i / MOUND_SEGS
			var lump := 0.0 if k == 0 or k == rows else _hash(k * 31 + i) * LUMP * 1.5
			var rho := r * pow(1.0 - t, MOUND_POW) * (1.0 + lump)
			row.append(c + Vector3(sin(a) * rho, h * t, -cos(a) * rho))
		pts.append(row)
	for k in rows:
		for i in MOUND_SEGS:
			var j := (i + 1) % MOUND_SEGS
			var col := white.darkened(0.04) if (i + k) % 2 else white
			_tri(st, col, pts[k][i], pts[k][j], pts[k + 1][i])
			if k < rows - 1:
				_tri(st, col, pts[k][j], pts[k + 1][j], pts[k + 1][i])


## A cut calamansi perched on the rim (data/recipes.json "garnish": skin, flesh), front right
## so the camera sees it. Decoration only: it is not a step.
func _add_garnish(st: SurfaceTool, id: String) -> void:
	var info := RecipeBook.ingredient(id)
	if not info.has("garnish"):
		return
	var g: Array = info.garnish
	var a := deg_to_rad(GARNISH_ANGLE)
	var p := Vector3(sin(a) * 0.112, RIM_Y + 0.008, -cos(a) * 0.112)
	_cube(st, p, 0.024, a, Color8(g[0][0], g[0][1], g[0][2]), Vector3(1, 0.8, 1))
	_cube(st, p + Vector3(0, 0.009, 0), 0.02, a, Color8(g[1][0], g[1][1], g[1][2]), Vector3(1, 0.15, 1))


## A long spoon pushed into the side of the ice, handle up and out, with a coloured end (ref 06).
func _add_spoon(st: SurfaceTool) -> void:
	var a := deg_to_rad(SPOON_ANGLE)
	var out := Vector3(sin(a), 0, -cos(a))
	var rho := _r() * 0.45
	var start := out * rho + Vector3(0, _surface_y(rho) - 0.025, 0)
	var dir := (out * 0.7 + Vector3(0, 0.71, 0)).normalized()
	var steel := Color(0.84, 0.86, 0.9)
	_bar(st, start, start + dir * 0.13, 0.009, steel)
	_bar(st, start + dir * 0.13, start + dir * 0.16, 0.011, Color(0.93, 0.3, 0.32))


## Box from a to b, w wide and flatter than wide, in one colour. Drawn two-sided: the winding
## of its faces depends on the direction.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var z := b - a
	var x := z.cross(Vector3.UP).normalized() * w * 0.5
	var y := x.cross(z).normalized() * w * 0.3
	var v := []
	for k in 8:
		v.append((b if k & 4 else a) + (x if k & 1 else -x) + (y if k & 2 else -y))
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(st, c, v[q[0]], v[q[1]], v[q[2]])
		_tri(st, c, v[q[0]], v[q[2]], v[q[3]])
		_tri(st, c, v[q[0]], v[q[2]], v[q[1]])
		_tri(st, c, v[q[0]], v[q[3]], v[q[2]])


## Ice colour at a cone vertex: angle a, height fraction t (0 = rim, 1 = tip). Each syrup is
## poured on the top and soaks down in uneven streaks, fading out towards from_ring (out of 4,
## the ring count when data/recipes.json was written); later syrups sit on top of earlier ones.
## A syrup with "side" only soaks its half of the mound (rose left, green right, after ref photo).
func _ice_color(ice: Color, a: float, t: float, n: int) -> Color:
	var c := ice
	for s in _syrups():
		var info := RecipeBook.ingredient(s)
		var ph := float(info.slot) * 2.1 + (1.3 if info.kind == "fruit" else 0.0)
		var cov := float(info.coverage) / 100.0
		var low := float(info.from_ring) / 4.0
		var streak := 0.5 + 0.3 * sin(2.0 * a + ph) + 0.2 * sin(5.0 * a - 4.0 * t + ph * 1.7)
		var w := smoothstep(cov + 0.12, cov - 0.12, streak)
		w = maxf(w, smoothstep(0.6, 0.95, t))                  # the top is always soaked
		w *= smoothstep(low - 0.1, low + 0.3, t)               # fades out going down
		if info.has("side"):
			w *= smoothstep(-0.3, 0.3, sin(a) * float(info.side))   # sin(a) > 0 = +X = screen left
		c = c.lerp(RecipeBook.color(s, "syrup"), w * 0.92)
	var j := 1.0 + _hash(n * 7 + 3) * 0.03
	return Color(c.r * j, c.g * j, c.b * j)


## What colours the ice, in the order it went in: fruits bring their own syrup (data/recipes.json
## "syrup"), then the sauces.
func _syrups() -> Array[String]:
	var out: Array[String] = []
	for t in toppings:
		if RecipeBook.ingredient(t).has("syrup"):
			out.append(t)
	out.append_array(sauces)
	return out


## Repeatable pseudo-random number in -1..1.
static func _hash(n: int) -> float:
	return float((n * 2654435761) % 1000) / 500.0 - 1.0


static func _tri_c(st: SurfaceTool, p: Array, c: Array) -> void:
	for k in 3:
		st.set_color(c[k])
		st.add_vertex(p[k])


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
	# premade soups (cheng tng, bean soups): their pieces float all over, more as it fills
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base)
	for p: Dictionary in RecipeBook.ingredient(base).get("pieces", []):
		var cols: Array[Color] = [Color8(p.color[0], p.color[1], p.color[2]), Color8(p.color2[0], p.color2[1], p.color2[2])]
		var stretch := Vector3(1.3, 0.45, 1.1) if p.get("shape", "") == "slab" else Vector3.ONE
		for n in ceili(float(p.count) * fill):
			var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r * 0.8
			var s: float = p.size * rng.randf_range(0.8, 1.2)
			_cube(st, Vector3(off.x, y + s * 0.15, off.y), s, rng.randf() * TAU, cols[n % 2], stretch)


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


## Adds one cluster of topping pieces around `centre`: little cubes, long sticks for
## shape "stick" (you tiao), flat discs for "slab", curved slices for "curve" (sea coconut) or
## wiggly "strand"s (pandan jelly). Pieces take turns between
## color and color2 (or cycle "colors"); with "seed", every third piece is a small dark seed. `bowl` gives the surface so pieces sit on it; null = flat heap
## (the scoop the player carries).
static func add_pieces(st: SurfaceTool, id: String, centre: Vector3, seed_: int, bowl: Bowl) -> void:
	var info := RecipeBook.ingredient(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + seed_ * 977
	var size: float = info.size
	var stick: bool = info.get("shape", "") == "stick"
	var spread := 0.022 if stick else 0.032
	var cols: Array[Color] = [RecipeBook.color(id), RecipeBook.color(id, "color2")]
	if info.has("colors"):
		cols.clear()
		for c in info.colors:
			cols.append(Color8(int(c[0]), int(c[1]), int(c[2])))
	var shape: String = info.get("shape", "")
	for n in int(info.count):
		var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spread
		var p := centre + Vector3(off.x, 0, off.y)
		var s := size * rng.randf_range(0.8, 1.2)
		var c: Color = cols[n % cols.size()]
		if info.has("seed") and n % 3 == 2:
			s *= 0.4
			c = RecipeBook.color(id, "seed")
		if bowl:
			p.y = bowl._surface_y(Vector2(p.x, p.z).length()) + s * 0.3
		else:
			p.y += s * 0.5 + (spread - off.length()) * 0.4
		# sticks lie roughly side by side (across the bowl), cubes any way round
		var yaw := rng.randf_range(-0.35, 0.35) + PI / 2 if stick else rng.randf() * TAU
		var stretch := Vector3(0.8, 0.75, 3.6) if stick else Vector3.ONE
		if shape == "slab":
			stretch = Vector3(1.3, 0.45, 1.1)
		if shape == "curve":
			_curve(st, p, s, yaw, c)
		elif shape == "strand":
			_strand(st, p, s, yaw, c)
		else:
			_cube(st, p, s, yaw, c, stretch)


## A big curved slice (sea coconut): three thin slabs bent into a shallow cup, open side up.
static func _curve(st: SurfaceTool, p: Vector3, s: float, yaw: float, c: Color) -> void:
	var turn := Basis(Vector3.UP, yaw)
	for i in 3:
		var th := (i - 1) * 0.55
		var side := turn * Vector3(sin(th) * s * 0.55, (1.0 - cos(th)) * s * 0.55, 0)
		var b := turn * Basis(Vector3.BACK, th) * Basis.from_scale(Vector3(0.6, 0.18, 1.2) * s * 0.5)
		_box(st, p + side, b, c.lightened(0.08) if i == 1 else c)


## A short wiggly strand (pandan jelly in chendol): three thin pieces zigzagging end to end.
static func _strand(st: SurfaceTool, p: Vector3, s: float, yaw: float, c: Color) -> void:
	var at := p
	for i in 3:
		var turn := Basis(Vector3.UP, yaw + (0.6 if i % 2 else -0.6))
		var step := turn * Vector3(0, 0, s)
		_box(st, at + step * 0.5, turn * Basis.from_scale(Vector3(0.55, 0.55, 2.2) * s * 0.5), c)
		at += step


static func _cube(st: SurfaceTool, p: Vector3, s: float, yaw: float, c: Color, stretch := Vector3.ONE) -> void:
	_box(st, p, Basis(Vector3.UP, yaw) * Basis.from_scale(stretch * s * 0.5), c)


## Box centred on p, its half-extents and turn given by b; the top face lit, the rest shaded.
static func _box(st: SurfaceTool, p: Vector3, b: Basis, c: Color) -> void:
	var v := []
	for k in 8:
		v.append(p + b * Vector3(1 if k & 1 else -1, 1 if k & 2 else -1, 1 if k & 4 else -1))
	# faces as quads of corner indices, clockwise seen from outside (Godot's front face)
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		var shade := 1.0 if q[0] == 2 else 0.85
		var cc := Color(c.r * shade, c.g * shade, c.b * shade)
		_tri(st, cc, v[q[0]], v[q[1]], v[q[2]])
		_tri(st, cc, v[q[0]], v[q[2]], v[q[3]])
