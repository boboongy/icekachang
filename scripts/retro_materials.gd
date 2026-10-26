class_name RetroMaterials
## Replaces the placeholder materials exported by tools/blender/build_stall.py with the
## game's pixel-art materials, matched by name. All static geometry shares these few
## materials, which keeps draw calls low on phones.

const ATLAS := preload("res://assets/textures/atlas.png")
const FLOOR := preload("res://assets/textures/floor.png")
const WALLTILE := preload("res://assets/textures/walltile.png")
const PEOPLE := preload("res://assets/textures/people.png")
const MENU := preload("res://assets/textures/menu.png")

static var _cache := {}


static func get_material(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic_specular = 0.15
	match mat_name:
		"atlas":
			m.albedo_texture = ATLAS
		"glow":
			m.albedo_texture = ATLAS
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.disable_receive_shadows = true
		"menu":     # our lightbox: its own texture; Stall darkens the tiles not on the menu yet
			m.albedo_texture = MENU
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.disable_receive_shadows = true
		"people":   # customers: their own painted texture (tools/blender/build_stall.py paint_people)
			m.albedo_texture = PEOPLE
			m.metallic_specular = 0.0   # matte, painted look; specular bleached the faces in the sun
		"floor":
			m.albedo_texture = FLOOR
			m.metallic_specular = 0.3
		"walltile":
			m.albedo_texture = WALLTILE
			m.metallic_specular = 0.2  # higher washed the white tiles out
		"glass":
			m.albedo_color = Color(0.82, 0.95, 1.0, 0.18)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic_specular = 0.6
			m.roughness = 0.2
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"bowlglass":   # dessert glass bowls: tinted, see-through, bright edges
			m.albedo_color = Color(0.62, 0.88, 0.9, 0.55)
			m.emission_enabled = true   # stays clearly teal in the dim making light
			m.emission = Color(0.12, 0.3, 0.32)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic_specular = 0.9
			m.roughness = 0.15
			m.rim_enabled = true
			m.rim = 1.0
			m.rim_tint = 0.3
		_:
			push_warning("RetroMaterials: unknown material '%s'" % mat_name)
			m.albedo_color = Color.MAGENTA
	_cache[mat_name] = m
	return m


## Walks `root` and swaps every surface material for the shared one with the same name.
static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var has_glass := false
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mat_name := src.resource_name if src else "atlas"
			mi.set_surface_override_material(i, get_material(mat_name))
			has_glass = has_glass or mat_name == "glass"
		if has_glass:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
