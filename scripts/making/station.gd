class_name MakingStation
extends Node3D
## First-person making at the work bench. Ice: take a glass bowl, load an ice block, hold the
## shaver, add toppings from the tubs, pour sauces. Soup: take a white soup bowl (it goes in
## front of the pot), ladle soup in (tap the pot or drag the ladle), add the side (you tiao).
## Then drag the bowl onto the tray (serve) or into the red pail (bin, free). Tap and drag both
## work; mouse arrives as emulated touch, so one code path serves PC and phone.
##
## Spots come from mk_* markers and named objects in assets/models/stall.glb
## (tools/blender/build_stall.py). Picking is ray-vs-sphere against those spots, no physics.

signal finished(item_id: String, result: Dictionary)   ## served; result from RecipeBook.judge
signal cancelled                                       ## back button

const DRAG_START_PX := 5.0
const SHAVE_SECS := 1.6          # holding the shaver this long fills the bowl
const CARRY_H := 0.2             # carried things float this high over the bench
const POUR_TILT := deg_to_rad(115.0)
const MILK_BLOCK := Color8(252, 238, 206)
const LADLE_FILL := 0.34         # one ladle of soup; three fill the bowl
const LADLE_TILT := deg_to_rad(80.0)
const POT_SOUP := "tau_suan_soup"   # the one soup on the burner (more pots come with M10)

var active := false
var item_id := ""
var bowl: Bowl
var ui: MakingUI
var has_bowl := false
var block_kind := "ice"          # ice block in the shaver: "ice" or "milk_ice"
var next_step := {}              # see _step(); refreshed after every move

var _cam: Camera3D
var _bench_y := 0.93
var _spot := {}                  # marker name (without mk_) -> world position
var _sauce := {}                 # sauce id -> MeshInstance3D
var _sauce_home := {}            # sauce id -> Transform3D
var _shaver: Array[Node3D] = []  # shaver + its ice drum (jiggle together)
var _shaver_home: Array[Vector3] = []
var _block: MeshInstance3D
var _milk_mat: StandardMaterial3D
var _ladle: Node3D
var _ladle_home: Transform3D
var _steam: CPUParticles3D
var _snow: CPUParticles3D
var _stream: MeshInstance3D
var _ghost: MeshInstance3D       # scoop of topping being carried
var _shaving := false
var _busy := false               # an animation owns the station (pour, serve, bin)
var _press := {}                 # {pos, hit, dragging, carry}
var _done := false               # served; waiting to hand back to the stall


func setup(model: Node3D, cam: Camera3D, overlay: MakingUI) -> void:
	_cam = cam
	ui = overlay
	process_mode = Node.PROCESS_MODE_PAUSABLE    # the stall keeps running in portrait; we don't
	ui.back_pressed.connect(func():
		if active and not _busy and not _done:
			cancelled.emit())
	for n in model.find_children("mk_*", "", true, false):
		_spot[n.name.substr(3)] = (n as Node3D).global_position
	_bench_y = _spot.bowl_spot.y
	for id in RecipeBook.of_kind("sauce"):
		var s := model.find_child("sauce_" + id, true, false) as MeshInstance3D
		_sauce[id] = s
		_sauce_home[id] = s.global_transform
	for n in ["shaver", "shaver_block"]:
		var s := model.find_child(n, true, false) as Node3D
		_shaver.append(s)
		_shaver_home.append(s.position)
	_block = _shaver[1] as MeshInstance3D
	_milk_mat = StandardMaterial3D.new()
	_milk_mat.albedo_color = MILK_BLOCK
	_milk_mat.roughness = 1.0

	_ladle = model.find_child("ladle", true, false) as Node3D
	_ladle_home = _ladle.global_transform

	bowl = Bowl.new(model.find_child("bowl", true, false) as MeshInstance3D,
		model.find_child("soup_bowl", true, false) as MeshInstance3D)
	add_child(bowl)
	bowl.visible = false

	# a few wisps of steam over the warm pot, only while making
	_steam = CPUParticles3D.new()
	_steam.emitting = false
	_steam.amount = 10
	_steam.lifetime = 1.4
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_steam.emission_sphere_radius = 0.08
	_steam.direction = Vector3.UP
	_steam.spread = 12.0
	_steam.gravity = Vector3.ZERO
	_steam.initial_velocity_min = 0.06
	_steam.initial_velocity_max = 0.12
	_steam.scale_amount_min = 0.6
	_steam.scale_amount_max = 1.2
	var wisp := BoxMesh.new()
	wisp.size = Vector3.ONE * 0.016
	var steam_mat := StandardMaterial3D.new()
	steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_mat.albedo_color = Color(1, 1, 1, 0.3)
	wisp.material = steam_mat
	_steam.mesh = wisp
	_steam.position = _spot.pot + Vector3(0, 0.03, 0)
	add_child(_steam)

	_snow = CPUParticles3D.new()
	_snow.emitting = false
	_snow.amount = 40
	_snow.lifetime = 0.3
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(0.025, 0.004, 0.025)
	_snow.direction = Vector3.DOWN
	_snow.spread = 10.0
	_snow.initial_velocity_min = 0.2
	_snow.initial_velocity_max = 0.4
	_snow.gravity = Vector3(0, -5, 0)
	var flake := BoxMesh.new()
	flake.size = Vector3.ONE * 0.008
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.97, 0.99, 1.0)
	flake.material = white
	_snow.mesh = flake
	_snow.position = _spot.spout
	add_child(_snow)

	_stream = MeshInstance3D.new()
	_stream.mesh = BoxMesh.new()
	_stream.visible = false
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stream.material_override = sm
	add_child(_stream)

	_ghost = MeshInstance3D.new()
	_ghost.visible = false
	add_child(_ghost)


func begin(order_item: String) -> void:
	item_id = order_item
	active = true
	_done = false
	_busy = false
	has_bowl = false
	bowl.clear()
	bowl.visible = false
	_steam.emitting = true
	ui.set_making(true)
	ui.set_order(item_id)
	_refresh()


func end() -> void:
	active = false
	_stop_shave()
	_press = {}
	_ghost.visible = false
	_stream.visible = false
	has_bowl = false
	bowl.visible = false
	for id in _sauce:
		_sauce[id].global_transform = _sauce_home[id]
	_ladle.global_transform = _ladle_home
	_steam.emitting = false
	ui.set_making(false)


## Dev only (screenshots): a bowl half way through an ice kachang, or a finished soup when
## the order is a soup.
func debug_stage() -> void:
	has_bowl = true
	bowl.visible = true
	bowl.fill = 1.0
	if RecipeBook.vessel(item_id) == "soup":
		bowl.set_vessel("soup")
		bowl.global_position = _spot.soup_spot
		bowl.base = RecipeBook.recipe(item_id).base
		bowl.toppings.assign(RecipeBook.recipe(item_id).toppings)
	else:
		bowl.set_vessel("glass")
		bowl.global_position = _spot.bowl_spot
		bowl.base = "ice"
		bowl.toppings.assign(["red_bean", "corn", "attap"])
		bowl.sauces.assign(["rose"])
	bowl.rebuild()
	_refresh()


# --- picking -----------------------------------------------------------------------------

## Everything touchable right now: name -> [world position, radius].
func targets() -> Dictionary:
	var t := {
		"bowl_stack": [_spot.bowl_stack, 0.11],
		"shaver": [_spot.shaver, 0.15],
		"ice:ice": [_spot.ice_plain, 0.06],
		"ice:milk_ice": [_spot.ice_milk, 0.06],
		"bin": [_spot.bin, 0.12],
		"tray": [_spot.tray, 0.18],
		"soup_stack": [_spot.soup_stack, 0.1],
		"pot": [_spot.pot, 0.15],
	}
	for id in RecipeBook.of_kind("topping") + RecipeBook.of_kind("side"):
		t["tub:" + id] = [_spot["tub_" + id], 0.07]
	for id in _sauce:
		var s: MeshInstance3D = _sauce[id]
		t["sauce:" + id] = [s.global_position + Vector3(0, s.get_aabb().end.y * 0.5, 0), 0.065]
	if has_bowl and not _busy:
		var glass := bowl.vessel == "glass"
		t["bowl"] = [bowl.global_position + Vector3(0, 0.1 if glass else 0.06, 0), 0.13 if glass else 0.11]
		for i in bowl.toppings.size():
			t["cluster:%d" % i] = [bowl.cluster_global(i), 0.04]
	return t


## Screen position of a target (the self-test taps these).
func screen_pos(target: String) -> Vector2:
	return _cam.unproject_position(targets()[target][0])


## Closest target under the screen point, by distance from the ray relative to its radius.
## Topping clusters win over the bowl they sit in.
func pick(pos: Vector2, only: Array = []) -> String:
	var o := _cam.project_ray_origin(pos)
	var d := _cam.project_ray_normal(pos)
	var best := ""
	var best_score := 1.0
	var all := targets()
	for tname: String in all:
		if not only.is_empty() and not (tname in only or tname.get_slice(":", 0) in only):
			continue
		var v: Vector3 = all[tname][0] - o
		var along := v.dot(d)
		if along <= 0.0:
			continue
		var score := (v - d * along).length() / float(all[tname][1])
		if tname.begins_with("cluster:"):
			score *= 0.5
		if score < best_score:
			best_score = score
			best = tname
	return best


func _label(target: String) -> String:
	var id := target.get_slice(":", 1)
	match target.get_slice(":", 0):
		"bowl_stack": return "Glass bowls"
		"soup_stack": return "Soup bowls"
		"pot": return "Tau suan pot: tap to ladle"
		"shaver": return "Ice shaver: press and hold"
		"ice": return RecipeBook.ingredient_name(id) + " block"
		"tub", "sauce": return RecipeBook.ingredient_name(id)
		"cluster": return RecipeBook.ingredient_name(bowl.toppings[int(id)])
		"bin": return "Scrap pail"
		"tray": return "Serving tray"
		"bowl": return "Your bowl"
	return ""


# --- input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or _done:
		return
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0:
		_on_move(event.position)
		get_viewport().set_input_as_handled()


func _on_press(pos: Vector2) -> void:
	if _busy:
		return
	var hit := pick(pos)
	_press = {"pos": pos, "hit": hit, "dragging": false, "carry": ""}
	if hit != "":
		ui.show_tag(_label(hit), pos)
	if hit == "shaver":
		_start_shave()


func _on_move(pos: Vector2) -> void:
	if _press.is_empty() or _shaving:
		return
	if not _press.dragging:
		if pos.distance_to(_press.pos) < DRAG_START_PX:
			return
		_begin_drag(_press.hit)
	if _press.dragging:
		_update_drag(pos)


func _on_release(pos: Vector2) -> void:
	if _press.is_empty():
		return
	if _shaving:
		_stop_shave()
	elif _press.dragging:
		_end_drag(pos)
	elif _press.hit != "":
		_tap(_press.hit)
	_press = {}
	_refresh()


func _tap(hit: String) -> void:
	var id := hit.get_slice(":", 1)
	match hit.get_slice(":", 0):
		"bowl_stack": _take_bowl("glass")
		"soup_stack": _take_bowl("soup")
		"pot": _ladle_soup()
		"ice": _load_block(id)
		"tub": _add_topping(id, _spot["tub_" + id] + Vector3(0, 0.03, 0))
		"sauce": _pour(id)
		"bowl": ui.flash_hint("Drag the bowl onto the pink tray to serve")
		"cluster": ui.flash_hint("Drag it out of the bowl to take it back")
		"bin": ui.flash_hint("Drag a bowl here to throw it away")
		"tray": ui.flash_hint("Drag your bowl here to serve")


# --- dragging ------------------------------------------------------------------------------

func _begin_drag(hit: String) -> void:
	var kind := hit.get_slice(":", 0)
	var id := hit.get_slice(":", 1)
	match kind:
		"bowl_stack", "soup_stack":
			_take_bowl("glass" if kind == "bowl_stack" else "soup")   # a flick works like a tap
			return
		"pot":
			if not _ladle_ok():
				_press.hit = ""   # said why once; ignore the rest of this drag
				return
		"tub":
			_show_ghost(id)
		"cluster":
			# lift the topping out; dropping it back in the bowl undoes this for free
			id = bowl.toppings[int(id)]
			bowl.toppings.erase(id)
			bowl.rebuild()
			_show_ghost(id)
		"sauce", "bowl":
			pass
		_:
			return
	_press.dragging = true
	_press.carry = kind + ":" + id


func _drop_targets() -> Array:
	match _press.carry.get_slice(":", 0):
		"tub", "cluster", "sauce", "pot":
			return ["bowl"] if has_bowl else []
		"bowl":
			return ["tray", "bin"]
	return []


func _update_drag(pos: Vector2) -> void:
	var over := pick(pos, _drop_targets())
	var p: Vector3
	if over == "bowl":
		p = bowl.global_position + Vector3(0, bowl.top_y() + 0.06, 0)
	elif over != "":
		p = targets()[over][0] + Vector3(0, 0.08, 0)
	else:
		var hit = Plane(Vector3.UP, _bench_y + CARRY_H).intersects_ray(
			_cam.project_ray_origin(pos), _cam.project_ray_normal(pos))
		if hit == null:
			return
		p = hit
	var kind: String = _press.carry.get_slice(":", 0)
	var id: String = _press.carry.get_slice(":", 1)
	match kind:
		"tub", "cluster":
			_ghost.global_position = p
		"sauce":
			_sauce[id].global_position = p - Vector3(0, 0.05, 0)
		"pot":
			_ladle.global_position = p - Vector3(0, 0.02, 0)
		"bowl":
			bowl.global_position = p - Vector3(0, 0.06, 0)


func _end_drag(pos: Vector2) -> void:
	var over := pick(pos, _drop_targets())
	var kind: String = _press.carry.get_slice(":", 0)
	var id: String = _press.carry.get_slice(":", 1)
	match kind:
		"tub":
			if over != "bowl" or not _add_topping(id, _ghost.global_position):
				_ghost_home(id)
		"cluster":
			if over == "bowl":
				_add_topping(id, _ghost.global_position, true)
			else:
				bowl.fixes += 1
				_ghost_home(id)
				ui.flash_hint("Put the %s back" % RecipeBook.ingredient_name(id).to_lower())
		"sauce":
			if over == "bowl":
				_pour(id)
			else:
				_sauce_back(id)
		"pot":
			if over == "bowl":
				_ladle_soup()
			else:
				_ladle_back()
		"bowl":
			if over == "tray":
				_serve()
			elif over == "bin":
				_bin()
			else:
				_move_bowl(_bowl_home(), 0.2)


func _show_ghost(id: String) -> void:
	_ghost.mesh = Bowl.scoop_mesh(id)
	_ghost.visible = true
	_ghost.scale = Vector3.ONE


func _ghost_home(id: String) -> void:
	var tw := create_tween()
	tw.tween_property(_ghost, "global_position", _spot["tub_" + id] + Vector3(0, 0.02, 0), 0.18)
	tw.tween_property(_ghost, "scale", Vector3.ONE * 0.1, 0.08)
	tw.tween_callback(func(): _ghost.visible = false)


# --- actions -------------------------------------------------------------------------------

## vessel "glass" goes under the shaver, "soup" in front of the pot.
func _take_bowl(vessel: String) -> void:
	if has_bowl:
		ui.flash_hint("One bowl at a time")
		return
	has_bowl = true
	bowl.set_vessel(vessel)
	bowl.clear()
	bowl.visible = true
	bowl.global_position = _spot.bowl_stack if vessel == "glass" else _spot.soup_stack
	_move_bowl(_bowl_home(), 0.3)
	Sound.play("click", 0.8)


func _bowl_home() -> Vector3:
	return _spot.bowl_spot if bowl.vessel == "glass" else _spot.soup_spot


## What to say when the bowl is still empty.
func _empty_hint() -> String:
	return "Shave some ice first" if bowl.vessel == "glass" else "Ladle some soup in first"


func _move_bowl(to: Vector3, secs: float) -> Tween:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(bowl, "global_position", to, secs)
	return tw


func _load_block(kind: String) -> void:
	if block_kind == kind:
		ui.flash_hint("The %s block is already in the shaver" % RecipeBook.ingredient_name(kind).to_lower())
		return
	block_kind = kind
	_block.material_override = _milk_mat if kind == "milk_ice" else null
	_block.scale = Vector3(1.1, 0.8, 1.1)
	create_tween().tween_property(_block, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	Sound.play("bin", 1.6)
	ui.flash_hint("%s block loaded" % RecipeBook.ingredient_name(kind))


func _start_shave() -> void:
	if not has_bowl:
		ui.flash_hint("Put a bowl under the shaver first")
	elif bowl.vessel != "glass":
		ui.flash_hint("Ice goes in a glass bowl. Bin the soup bowl first.")
	elif bowl.base != "" and bowl.base != block_kind:
		ui.flash_hint("This bowl has %s. Bin it to change the ice." % RecipeBook.ingredient_name(bowl.base).to_lower())
	elif bowl.fill >= 1.0:
		ui.flash_hint("That's a full mountain already!")
	else:
		bowl.base = block_kind
		_shaving = true
		_snow.emitting = true
		Sound.shave(true)


func _stop_shave() -> void:
	if not _shaving:
		return
	_shaving = false
	_snow.emitting = false
	Sound.shave(false)
	for i in _shaver.size():
		_shaver[i].position = _shaver_home[i]
	_refresh()


func _process(delta: float) -> void:
	if not _shaving:
		return
	bowl.fill = minf(bowl.fill + delta / SHAVE_SECS, 1.0)
	bowl.rebuild()
	var jig := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.003
	for i in _shaver.size():
		_shaver[i].position = _shaver_home[i] + jig
	if bowl.fill >= 1.0:
		_stop_shave()
		bowl.bounce()
		ui.flash_hint("Nice full mountain!")


## Adds a topping, flying the scoop from `from` into the bowl. False if it can't go in.
func _add_topping(id: String, from: Vector3, put_back := false) -> bool:
	var why := ""
	if not has_bowl:
		why = "Take a bowl first"
	elif not bowl.has_base():
		why = _empty_hint()
	elif id in bowl.toppings:
		why = "It already has %s" % RecipeBook.ingredient_name(id).to_lower()
	elif bowl.toppings.size() >= Bowl.SLOTS.size():
		why = "The bowl is full"
	if why != "":
		ui.flash_hint(why)
		if put_back:
			_ghost_home(id)
		return false
	bowl.toppings.append(id)
	if not _ghost.visible:
		_show_ghost(id)
		_ghost.global_position = from
	var to := bowl.cluster_global(bowl.toppings.size() - 1)
	bowl.toppings.pop_back()   # shown once the scoop lands
	_busy = true               # one scoop in the air at a time
	var tw := create_tween()
	tw.tween_property(_ghost, "global_position", to, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_ghost.visible = false
		bowl.toppings.append(id)
		bowl.rebuild()
		bowl.bounce()
		Sound.play("scoop")
		_busy = false
		_refresh())
	return true


func _pour(id: String) -> void:
	var why := ""
	if not has_bowl:
		why = "Take a bowl first"
	elif not bowl.has_base():
		why = _empty_hint()
	elif id in bowl.sauces:
		why = "It already has %s" % RecipeBook.ingredient_name(id).to_lower()
	if why != "":
		ui.flash_hint(why)
		_sauce_back(id)
		return
	_busy = true
	var s: MeshInstance3D = _sauce[id]
	var h := s.get_aabb().end.y
	var top := bowl.global_position + Vector3(0, bowl.top_y(), 0)
	var mouth := top + Vector3(0, 0.12, 0)
	var tilt := Basis(Vector3.BACK, -POUR_TILT)            # top leans towards +X (the bowl side)
	var pour_xf := Transform3D(tilt, mouth - tilt * Vector3(0, h, 0))
	var c := RecipeBook.color(id)
	(_stream.material_override as StandardMaterial3D).albedo_color = c
	(_stream.mesh as BoxMesh).size = Vector3(0.012, mouth.y - top.y, 0.012)
	_stream.global_position = (mouth + top) / 2
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(s, "global_transform", pour_xf, 0.3)
	tw.tween_callback(func():
		_stream.visible = true
		Sound.play("pour")
		bowl.sauces.append(id)
		bowl.rebuild()
		_refresh())
	tw.tween_interval(0.5)
	tw.tween_callback(func(): _stream.visible = false)
	tw.tween_property(s, "global_transform", _sauce_home[id], 0.3)
	tw.tween_callback(func(): _busy = false)


func _sauce_back(id: String) -> void:
	create_tween().tween_property(_sauce[id], "global_transform", _sauce_home[id], 0.2)


## Can a ladle of soup go in now? Says why not.
func _ladle_ok() -> bool:
	var why := ""
	if not has_bowl:
		why = "Take a white soup bowl first"
	elif bowl.vessel != "soup":
		why = "Soup goes in a white soup bowl"
	elif bowl.fill >= 1.0:
		why = "The bowl is full!"
	if why != "":
		ui.flash_hint(why)
	return why == ""


## One ladle of soup from the pot into the soup bowl. Works from the resting ladle (tap the
## pot) or from wherever the player dragged it.
func _ladle_soup() -> void:
	if not _ladle_ok():
		_ladle_back()
		return
	_busy = true
	var top := bowl.global_position + Vector3(0, Bowl.SOUP_TOP_Y + 0.07, 0)
	var over := Transform3D(_ladle_home.basis, top + Vector3(0.03, 0, 0))
	var tip := Transform3D(Basis(Vector3.BACK, -LADLE_TILT) * _ladle_home.basis, top)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _ladle.global_transform.is_equal_approx(_ladle_home):
		tw.tween_property(_ladle, "global_position", _ladle_home.origin + Vector3(0, -0.04, 0), 0.12)
		tw.tween_property(_ladle, "global_position", _ladle_home.origin + Vector3(0, 0.1, 0), 0.14)
	tw.tween_property(_ladle, "global_transform", over, 0.22)
	tw.tween_property(_ladle, "global_transform", tip, 0.16)
	tw.tween_callback(func():
		bowl.base = POT_SOUP
		var surf := bowl.global_position + Vector3(0, bowl._surface_y(0.0), 0)
		(_stream.material_override as StandardMaterial3D).albedo_color = RecipeBook.color(POT_SOUP)
		(_stream.mesh as BoxMesh).size = Vector3(0.02, maxf(top.y - surf.y, 0.01), 0.02)
		_stream.global_position = (top + surf) / 2
		_stream.visible = true
		Sound.play("ladle"))
	var set_fill := func(f: float) -> void:
		bowl.fill = f
		bowl.rebuild()
	tw.tween_method(set_fill, bowl.fill, minf(bowl.fill + LADLE_FILL, 1.0), 0.32)
	tw.tween_callback(func():
		_stream.visible = false
		bowl.bounce()
		if bowl.fill >= 1.0:
			ui.flash_hint("Nice full bowl!")
		_refresh())
	tw.tween_property(_ladle, "global_transform", _ladle_home, 0.3)
	tw.tween_callback(func():
		_busy = false
		_refresh())


func _ladle_back() -> void:
	create_tween().tween_property(_ladle, "global_transform", _ladle_home, 0.2)


func _serve() -> void:
	if not bowl.has_base():
		ui.flash_hint(_empty_hint())
		_move_bowl(_bowl_home(), 0.2)
		return
	_busy = true
	_done = true
	var res := RecipeBook.judge(item_id, bowl.state())
	var tw := _move_bowl(_spot.tray, 0.25)
	tw.tween_callback(func():
		Sound.play("serve")
		ui.show_result(res))
	tw.tween_interval(2.2)
	tw.tween_callback(func():
		_busy = false
		finished.emit(item_id, res))


func _bin() -> void:
	_busy = true
	var tw := _move_bowl(_spot.bin + Vector3(0, 0.05, 0), 0.2)
	tw.tween_property(bowl, "scale", Vector3.ONE * 0.2, 0.15)
	tw.tween_callback(func():
		Sound.play("bin")
		has_bowl = false
		bowl.visible = false
		bowl.scale = Vector3.ONE
		bowl.clear()
		_busy = false
		ui.flash_hint("Binned. Take a fresh bowl.")
		_refresh())


# --- step hint -----------------------------------------------------------------------------

func _refresh() -> void:
	if not active or _done:
		return
	var st := bowl.state()
	ui.refresh(item_id, st)
	next_step = _next_step(st)
	ui.set_hint(next_step.hint)


## What to touch now, and how (the hint at the bottom and the tutorial pointer).
## Empty while an animation runs or once served.
func pointer() -> Dictionary:
	if not active or _done or _busy or next_step.is_empty() or not targets().has(next_step.target):
		return {}
	return next_step


## {hint, target, to (drag onto this target, or ""), hold (press and hold)}
func _step(hint: String, target: String, to := "", hold := false) -> Dictionary:
	return {"hint": hint, "target": target, "to": to, "hold": hold}


func _next_step(st: Dictionary) -> Dictionary:
	var r := RecipeBook.recipe(item_id)
	var nm := func(id: String) -> String: return RecipeBook.ingredient_name(id).to_lower()
	var soup := RecipeBook.vessel(item_id) == "soup"
	if not has_bowl:
		if soup:
			return _step("Tap the white soup bowls to take one", "soup_stack")
		return _step("Tap the glass bowls to take one", "bowl_stack")
	if bowl.vessel != RecipeBook.vessel(item_id):
		return _step("Wrong bowl! Drag it to the red pail", "bowl", "bin")
	if not bowl.has_base():
		if soup:
			return _step("Tap the pot (or drag the ladle) to add soup", "pot")
		if st.base == "" and block_kind != r.base:
			return _step("Tap the %s block to load the shaver" % nm.call(r.base), "ice:" + r.base)
		return _step("Press and hold the shaver to shave ice", "shaver", "", true)
	if st.base != r.base:
		return _step("Wrong ice! Drag the bowl to the red pail", "bowl", "bin")
	for t in r.toppings:
		if not t in st.toppings:
			var from := "the plate" if RecipeBook.ingredient(t).kind == "side" else "its tub"
			return _step("Add %s: tap or drag %s" % [nm.call(t), from], "tub:" + t)
	for i in st.toppings.size():
		var t: String = st.toppings[i]
		if not t in r.toppings:
			return _step("Drag the %s back out of the bowl" % nm.call(t), "cluster:%d" % i, "bin")
	for s in r.sauces:
		if not s in st.sauces:
			return _step("Pour the %s: tap or drag it" % nm.call(s), "sauce:" + s)
	for s in st.sauces:
		if not s in r.sauces:
			return _step("Oops, extra %s. Bin it (red pail) or serve" % nm.call(s), "bowl", "bin")
	if st.fill < RecipeBook.FULL_ICE:
		if soup:
			return _step("Ladle in more soup, or serve", "pot")
		return _step("Hold the shaver for more ice, or serve", "shaver", "", true)
	return _step("Drag the bowl onto the pink tray to serve", "bowl", "tray")
