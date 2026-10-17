extends Node
## Headless self-test of the making view:
##   godot --headless --path . -- --selftest
## Drives the station with the same touch events a phone sends (taps, holds, drags) at the
## screen positions of the real props, then checks the bowl and the judged result.
## Prints one line per check and a SELFTEST summary; exits 0 on pass, 1 on any failure.

var stall: Node
var st: MakingStation
var fails := 0
var checks := 0


func run(s: Node) -> void:
	stall = s
	st = s.station
	await _wait(0.2)
	await _ice_kachang()
	await _mango_milk_ice()
	await _wrong_ice_served()
	await _tau_suan()
	await _back_button_and_guards()
	print("SELFTEST %s: %d checks, %d failed" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	get_tree().quit(1 if fails else 0)


func _ice_kachang() -> void:
	print("-- ice kachang, with a wrong topping taken back out")
	await _start("ice_kachang")
	await tap("shaver")
	check(not st.has_bowl and st.bowl.fill == 0.0, "shaver does nothing without a bowl")
	await tap("bowl_stack")
	check(st.has_bowl, "tap the bowls: a bowl is out")
	await tap("tub:red_bean")
	check(st.bowl.toppings.is_empty(), "no toppings before there is ice")
	await hold("shaver", 2.0)
	check(st.bowl.base == "ice" and st.bowl.fill == 1.0, "hold the shaver: full plain ice (fill %.2f)" % st.bowl.fill)
	for t in ["red_bean", "corn", "attap"]:
		await tap("tub:" + t)
	await drag("tub:grass_jelly", "bowl")
	await tap("tub:jelly")
	await tap("tub:jelly")
	check(st.bowl.toppings == (["red_bean", "corn", "attap", "grass_jelly", "jelly"] as Array[String]),
		"tap and drag toppings in, a second tap does not double: %s" % [st.bowl.toppings])
	await tap("tub:mango")
	check("mango" in st.bowl.toppings, "wrong topping goes in")
	await drag("cluster:5", "bin")
	check(not "mango" in st.bowl.toppings and st.bowl.fixes == 1, "drag the mango back out")
	await drag("cluster:0", "bowl")
	check(st.bowl.toppings.size() == 5 and st.bowl.fixes == 1, "lift a topping and drop it back: no change")
	await tap("sauce:rose")
	await _wait(1.3)
	await drag("sauce:evap_milk", "bowl")
	await _wait(1.3)
	check(st.bowl.sauces == (["rose", "evap_milk"] as Array[String]), "tap and drag sauces: %s" % [st.bowl.sauces])
	var all_done := RecipeBook.checklist("ice_kachang", st.bowl.state()).all(func(r): return r.done)
	check(all_done, "order card all ticked")
	var res := await _serve()
	check(res.get("correct", false) and res.stars == 2, "served correct, 2 stars (one take-back): %s" % [res])


func _mango_milk_ice() -> void:
	print("-- mango milk ice, binning a bowl with the wrong ice first")
	await _start("mango_milk_ice")
	await tap("bowl_stack")
	check(st.ui._hint_base.contains("milk ice block"), "hint says load the milk block: '%s'" % st.ui._hint_base)
	await hold("shaver", 0.6)
	check(st.bowl.base == "ice" and st.bowl.fill > 0.25 and st.bowl.fill < 0.6, "short hold: some plain ice (%.2f)" % st.bowl.fill)
	check(st.ui._hint_base.begins_with("Wrong ice"), "hint says wrong ice: '%s'" % st.ui._hint_base)
	await drag("bowl", "bin")
	await _wait(0.5)
	check(not st.has_bowl, "drag the bowl to the pail: binned")
	await tap("ice:milk_ice")
	check(st.block_kind == "milk_ice", "tap the milk block: loaded")
	await tap("bowl_stack")
	await hold("shaver", 2.0)
	await tap("tub:mango")
	await tap("sauce:mango_sauce")
	await _wait(1.3)
	await tap("sauce:condensed_milk")
	await _wait(1.3)
	var res := await _serve()
	check(res.get("correct", false) and res.stars == 3, "served correct, 3 stars: %s" % [res])


func _wrong_ice_served() -> void:
	print("-- serving the wrong thing")
	await _start("ice_kachang")      # milk block still loaded from the last order
	await tap("bowl_stack")
	await hold("shaver", 2.0)
	check(st.bowl.base == "milk_ice", "milk block still in the shaver")
	await tap("ice:ice")
	await hold("shaver", 0.3)
	check(st.bowl.base == "milk_ice", "can't mix ice kinds in one bowl")
	var res := await _serve()
	check(not res.get("correct", true) and res.stars == 0 and "ice" in res.missing,
		"wrong dessert judged wrong: %s" % [res])


func _tau_suan() -> void:
	print("-- tau suan: wrong bowl binned, ladle by tap and by drag, you tiao on the side")
	await _start("tau_suan")
	check(st.ui._hint_base.contains("soup bowls"), "hint says take a soup bowl: '%s'" % st.ui._hint_base)
	await tap("pot")
	await _wait(0.5)
	check(not st.has_bowl, "the pot does nothing without a bowl")
	await tap("bowl_stack")
	check(st.ui._hint_base.begins_with("Wrong bowl"), "glass bowl for a soup: '%s'" % st.ui._hint_base)
	await tap("pot")
	await _wait(1.2)
	check(st.bowl.fill == 0.0, "no soup in a glass bowl")
	await drag("bowl", "bin")
	await _wait(0.5)
	await tap("soup_stack")
	check(st.has_bowl and st.bowl.vessel == "soup", "tap the soup bowls: a soup bowl is out")
	await hold("shaver", 0.6)
	check(st.bowl.fill == 0.0, "the shaver does nothing for a soup bowl")
	await tap("tub:you_tiao")
	check(st.bowl.toppings.is_empty(), "no you tiao before there is soup")
	await tap("pot")
	await _wait(1.2)
	check(st.bowl.base == "tau_suan_soup" and is_equal_approx(st.bowl.fill, 0.34),
		"tap the pot: one ladle (%.2f)" % st.bowl.fill)
	await drag("pot", "bowl")
	await _wait(1.0)
	check(is_equal_approx(st.bowl.fill, 0.68), "drag the ladle to the bowl: two ladles (%.2f)" % st.bowl.fill)
	check(st.ui._hint_base.contains("you tiao"), "hint asks for you tiao: '%s'" % st.ui._hint_base)
	await tap("pot")
	await _wait(1.2)
	await tap("pot")
	await _wait(1.2)
	check(st.bowl.fill == 1.0, "three ladles fill it, a fourth does not overflow (%.2f)" % st.bowl.fill)
	await drag("tub:you_tiao", "bowl")
	check(st.bowl.toppings == (["you_tiao"] as Array[String]), "drag you tiao in: %s" % [st.bowl.toppings])
	check(RecipeBook.checklist("tau_suan", st.bowl.state()).all(func(r): return r.done), "order card all ticked")
	var res := await _serve()
	check(res.get("correct", false) and res.stars == 3, "served correct, 3 stars: %s" % [res])
	print("-- tau suan by make(), then a soup served as an ice kachang")
	await _start("tau_suan")
	res = await make("tau_suan")
	check(res.get("correct", false) and res.stars == 3, "make(tau_suan): %s" % [res])
	await _start("ice_kachang")
	await tap("soup_stack")
	await tap("pot")
	await _wait(1.2)
	res = await _serve()
	check(not res.get("correct", true) and "tau_suan_soup" in res.extra, "soup for an ice order judged wrong: %s" % [res])


func _back_button_and_guards() -> void:
	print("-- back button, serve guard")
	await _start("mango_milk_ice")
	await tap("bowl_stack")
	await drag("bowl", "tray")
	check(st.has_bowl and st.active, "an empty bowl can't be served")
	st.ui.back_pressed.emit()
	await _wait(0.8)
	check(not st.active and not stall._making, "back returns to the waiting view")


# --- helpers ---------------------------------------------------------------------------

## Makes `item` from data/recipes.json the tidy way (taps and a hold) and serves it.
## Returns the judged result, or {} if nothing was served.
func make(item: String) -> Dictionary:
	var r := RecipeBook.recipe(item)
	if RecipeBook.vessel(item) == "soup":
		await tap("soup_stack")
		for i in 3:
			await tap("pot")
			await _wait(1.2)
	else:
		await tap("bowl_stack")
		if st.block_kind != r.base:
			await tap("ice:" + r.base)
		await hold("shaver", 2.0)
	for t in r.toppings:
		await tap("tub:" + t)
	for s in r.sauces:
		await tap("sauce:" + s)
		await _wait(1.3)
	return await _serve()


func _start(item: String) -> void:
	stall.start_order(item)
	await _wait(0.9)                  # camera move


func _serve() -> Dictionary:
	var got := []
	var cb := func(_i, r): got.append(r)
	st.finished.connect(cb)
	await drag("bowl", "tray")
	await _wait(3.0)
	st.finished.disconnect(cb)
	return got[0] if got.size() == 1 else {}


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	get_viewport().push_input(e, true)


func tap(target: String) -> void:
	var p := st.screen_pos(target)
	_touch(p, true)
	await get_tree().process_frame
	_touch(p, false)
	await _wait(0.3)


func hold(target: String, secs: float) -> void:
	var p := st.screen_pos(target)
	_touch(p, true)
	await _wait(secs)
	_touch(p, false)
	await _wait(0.1)


func drag(from: String, to: String) -> void:
	var a := st.screen_pos(from)
	var b := st.screen_pos(to)
	_touch(a, true)
	await get_tree().process_frame
	var last := a
	for i in range(1, 11):
		var p := a.lerp(b, i / 10.0)
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = p
		e.relative = p - last
		last = p
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	_touch(b, false)
	await _wait(0.4)
