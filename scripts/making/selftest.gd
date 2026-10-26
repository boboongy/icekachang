extends Node
## Headless self-test of the making view:
##   godot --headless --path . -- --selftest
## Drives the station with the same touch events a phone sends (taps, holds, drags) at the
## screen positions of the real props, then checks the bowl and the judged result.
## Prints one line per check and a SELFTEST summary; exits 0 on pass, 1 on any failure.

## iOS Safari's Touch.identifier is large and never 0; Godot web passes it on as the index.
const TOUCH_ID := 7183

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
	await _two_wells()
	await _cold_chacha()
	await _fruit_jar()
	await _handling()
	await _card_layout()
	_syrup_spread()
	await _whole_menu()
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
	check(st.bowl.toppings.size() == 5 and st.bowl.fixes == 1 and st.has_bowl, "grab a topping that belongs: nothing lifts out")
	await hold("tub:mango", 0.8)
	check(not "mango" in st.bowl.toppings and st.ui._tag.visible and st.ui._tag.text == "Diced mango",
		"hold a tub: shows '%s', adds nothing" % st.ui._tag.text)
	await hold("sauce:rose", 0.8)
	await _wait(1.0)
	check(st.bowl.sauces.is_empty(), "hold a bottle: pours nothing")
	await tap_ui(st.ui.row_rect("rose").get_center())
	var ptr: Vector2 = st.ui._pointer.at
	check(st.ui._pointer.until > Time.get_ticks_msec() / 1000.0 and ptr.distance_to(UiKit.to_ui(st.screen_pos("sauce:rose"))) < 1.0
		and st.bowl.sauces.is_empty(), "tap the card's rose row: points at the rose bottle, pours nothing")
	await tap("sauce:rose")
	await _wait(1.3)
	await tap("sauce:green_syrup")
	await _wait(1.3)
	await drag("sauce:evap_milk", "bowl")
	await _wait(1.3)
	check(st.bowl.sauces == (["rose", "green_syrup", "evap_milk"] as Array[String]), "tap and drag sauces: %s" % [st.bowl.sauces])
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
	await tap("pot:tau_suan_soup")
	await _wait(0.5)
	check(not st.has_bowl, "the pot does nothing without a bowl")
	await tap("bowl_stack")
	check(st.ui._hint_base.begins_with("Wrong bowl"), "glass bowl for a soup: '%s'" % st.ui._hint_base)
	await tap("pot:tau_suan_soup")
	await _wait(1.2)
	check(st.bowl.fill == 0.0, "no soup in a glass bowl")
	await drag("bowl", "bin")
	await _wait(0.5)
	await tap("soup_stack")
	check(st.has_bowl and st.bowl.vessel == "soup", "tap the soup bowls: a soup bowl is out")
	await hold("shaver", 0.6)
	check(st.bowl.fill == 0.0 and st.bowl.ice == 0.0, "the shaver does nothing for a warm soup bowl")
	await tap("tub:you_tiao")
	check(st.bowl.toppings.is_empty(), "no you tiao before there is soup")
	await tap("pot:tau_suan_soup")
	await _wait(1.2)
	check(st.bowl.base == "tau_suan_soup" and is_equal_approx(st.bowl.fill, 0.34),
		"tap the pot: one ladle (%.2f)" % st.bowl.fill)
	await drag("pot:tau_suan_soup", "bowl")
	await _wait(1.0)
	check(is_equal_approx(st.bowl.fill, 0.68), "drag the ladle to the bowl: two ladles (%.2f)" % st.bowl.fill)
	check(st.ui._hint_base.contains("you tiao"), "hint asks for you tiao: '%s'" % st.ui._hint_base)
	await tap("pot:tau_suan_soup")
	await _wait(1.2)
	await tap("pot:tau_suan_soup")
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
	await tap("pot:tau_suan_soup")
	await _wait(1.2)
	res = await _serve()
	check(not res.get("correct", true) and "tau_suan_soup" in res.extra, "soup for an ice order judged wrong: %s" % [res])


func _two_wells() -> void:
	print("-- warmer wells: the wrong soup can't be topped up with the right one")
	await _start("pulut_hitam")
	await tap("soup_stack")
	check(st.ui._hint_base.contains("black rice well"), "hint points at the black rice well: '%s'" % st.ui._hint_base)
	await tap("pot:chacha_soup")
	await _wait(1.4)
	check(st.bowl.base == "chacha_soup", "tap the coconut well: coconut soup (%s)" % st.bowl.base)
	check(st.ui._hint_base.begins_with("Wrong soup"), "hint says wrong soup: '%s'" % st.ui._hint_base)
	var fill := st.bowl.fill
	await tap("pot:pulut_soup")
	await _wait(1.4)
	check(st.bowl.base == "chacha_soup" and st.bowl.fill == fill, "no black rice on top of coconut soup")
	await drag("bowl", "bin")
	await _wait(0.5)
	check(not st.has_bowl, "binned")
	# M18: the six wells, a premade soup next to a plain one
	await _start("cheng_tng")
	await tap("soup_stack")
	check(st.ui._hint_base.contains("cheng tng well"), "hint points at the cheng tng well: '%s'" % st.ui._hint_base)
	await tap("pot:red_bean_soup")
	await _wait(1.4)
	check(st.bowl.base == "red_bean_soup" and st.ui._hint_base.begins_with("Wrong soup"), "red bean well: wrong soup (%s)" % st.bowl.base)
	var plain_tris: int = st.bowl._contents.mesh.get_faces().size()
	await drag("bowl", "bin")
	await _wait(0.5)
	await tap("soup_stack")
	await tap("pot:cheng_tng_soup")
	await _wait(1.4)
	check(st.bowl.base == "cheng_tng_soup", "cheng tng well: cheng tng (%s)" % st.bowl.base)
	var tris: int = st.bowl._contents.mesh.get_faces().size()
	check(tris > plain_tris, "cheng tng shows its pieces (%d faces vs %d)" % [tris, plain_tris])
	await drag("bowl", "bin")
	await _wait(0.5)
	check(not st.has_bowl, "binned")


## M19/M25: a cold bobo chacha needs a little shaved ice in the soup bowl (before or after the
## soup); the warm one must have none; a full mound of ice costs a star.
func _cold_chacha() -> void:
	print("-- cold bobo chacha: shaved ice, and the wrong temperature")
	check(not st.targets().has("tub:ice_cubes"), "no ice-cube box any more")
	await _start("bobo_chacha", true)
	check(st.cold and st.ui._title.text == "COLD BOBO CHACHA", "cold order card: '%s'" % st.ui._title.text)
	check(st.ui._rows.get_child_count() == 5, "card lists the shaved ice (%d rows)" % st.ui._rows.get_child_count())
	check(st.ingredient_target("ice") == "shaver", "the card's ice row points at the shaver")
	var res := await make("bobo_chacha")
	check(res.get("correct", false) and res.stars == 3, "cold, ice before the soup: %s" % [res])
	check(st.bowl.ice > 0.0 and st.bowl.ice < RecipeBook.TOO_MUCH_ICE, "a little ice in the bowl (%.2f)" % st.bowl.ice)
	await _start("bobo_chacha", true)
	res = await make("bobo_chacha", true)
	check(res.get("correct", false) and res.stars == 3, "cold, ice after the soup: %s" % [res])
	await _start("bobo_chacha", true)
	await tap("soup_stack")
	for i in 3:
		await tap("pot:chacha_soup")
		await _wait(1.4)
	await hold("shaver", 2.4)
	await _wait(0.4)
	check(st.bowl.ice >= 1.0 and st.bowl.global_position.distance_to(st._spot.soup_spot) < 0.01,
		"hold the shaver long: a full mound (%.2f), the bowl back on its spot" % st.bowl.ice)
	for t in ["sweet_potato", "yam", "sago"]:
		await tap("tub:" + t)
	res = await _serve()
	check(res.get("correct", false) and res.stars == 2, "too much ice: 2 stars %s" % [res])
	await _start("bobo_chacha")
	check(not st.cold and st.ui._rows.get_child_count() == 4, "warm order: no ice on the card")
	res = await make("bobo_chacha")
	check(res.get("correct", false) and res.stars == 3, "warm made warm: %s" % [res])
	await _start("bobo_chacha", true)
	res = await make("bobo_chacha", false, "hot")
	check(not res.get("correct", true) and res.stars < 3 and "ice" in res.missing, "cold order served warm: wrong %s" % [res])
	await _start("bobo_chacha")
	res = await make("bobo_chacha", false, "cold")
	check(res.get("correct", false) and st.bowl.ice == 0.0, "the shaver gives a warm chacha no ice: %s" % [res])
	await _start("tau_suan", true)
	check(not st.cold, "only bobo chacha can be cold")
	st.ui.back_pressed.emit()
	await _wait(0.8)


func _fruit_jar() -> void:
	print("-- fruit jars: fruit and its syrup in one go")
	await _start("ice_soursop")
	var clash := []
	for target in st.targets():
		var got := st.pick(st.screen_pos(target))
		if got != target:
			clash.append("%s->%s" % [target, got])
	check(clash.is_empty(), "every prop's own spot picks that prop %s" % [clash])
	await tap("bowl_stack")
	await hold("shaver", 2.0)
	check(st.ui._hint_base.contains("jar"), "hint points at the jar: '%s'" % st.ui._hint_base)
	var plain: Color = st.bowl._ice_color(RecipeBook.color("ice"), 0.0, 1.0, 0)
	await tap("tub:soursop")
	await _wait(0.1)
	check(st.bowl.toppings == (["soursop"] as Array[String]) and st.bowl.sauces.is_empty(), "one tap: soursop in, no bottle")
	check(st._drops.emitting, "syrup splashes")
	check(st.bowl._ice_color(RecipeBook.color("ice"), 0.0, 1.0, 0) != plain, "the syrup soaks into the ice")
	var res := await _serve()
	check(res.get("correct", false), "ice soursop correct: %s" % [res])


## M23: a soup bowl full of toppings is dragged to the tray by grabbing a topping.
func _handling() -> void:
	print("-- bobo chacha: grab a topping to drag the bowl, a wrong one still lifts out")
	await _start("bobo_chacha")
	await tap("soup_stack")
	for i in 3:
		await tap("pot:chacha_soup")
		await _wait(1.4)
	for t in ["sweet_potato", "yam", "sago", "corn"]:
		await tap("tub:" + t)
	await drag("cluster:3", "bin")
	check(st.bowl.toppings == (["sweet_potato", "yam", "sago"] as Array[String]) and st.has_bowl,
		"the wrong corn drags out, the bowl stays: %s" % [st.bowl.toppings])
	for i in 3:
		check(st.pick(st.screen_pos("cluster:%d" % i)) == "cluster:%d" % i, "cluster %d is what a press there grabs" % i)
	var got := []
	var cb := func(_i, r): got.append(r)
	st.finished.connect(cb)
	await drag("cluster:1", "tray")
	await _wait(3.0)
	st.finished.disconnect(cb)
	check(got.size() == 1 and got[0].correct and got[0].stars == 2, "grab the yam: the whole bowl is served %s" % [got])


## M23: the order card sits below BACK and every line fits inside it, for every dessert,
## both temperatures and 2-dessert cards (also after a result was shown over the card).
func _card_layout() -> void:
	print("-- order card layout")
	await _start("ice_kachang")
	var ui := st.ui
	var bad := []
	var cases := []
	for item in RecipeBook.makeable():
		cases.append([item, false, {}])
	cases.append(["bobo_chacha", true, {}])
	for also in [{"item": "ice_sea_coconut", "cold": false, "done": true}, {"item": "bobo_chacha", "cold": true, "done": true},
			{"item": "ice_jelly_cocktail", "cold": false, "done": false}]:
		for item in ["ice_sea_coconut", "bobo_chacha", "ice_kachang_durian", "sweet_potato_soup"]:
			if item != also.item:
				cases.append([item, item == "bobo_chacha", also])
	for c in cases:
		ui.show_result({"correct": true, "stars": 3, "missing": [], "extra": []})
		ui.set_order(c[0], c[1], c[2])
		ui.hide_result()
		for f in 3:
			await get_tree().process_frame
		var card: Rect2 = ui._card.get_global_rect()
		var inner := card.grow(-1)
		if card.position.y < ui._back.get_global_rect().end.y or card.position.x < 0 or card.end.y > ui.size.y:
			bad.append("%s: card %s vs back %s" % [c[0], card, ui._back.get_global_rect()])
		for l in ui._card.find_children("*", "Label", true, false):
			var lab := l as Label
			var w := lab.get_theme_font("font").get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var r := lab.get_global_rect()
			if not inner.encloses(r) or w > r.size.x + 0.5:
				bad.append("%s: '%s' %s (text %d) outside %s" % [c[0], lab.text, r, w, inner])
	check(bad.is_empty(), "%d cards: below BACK, every line inside %s" % [cases.size(), bad])
	st.ui.back_pressed.emit()
	await _wait(0.8)


## M23: mango sauce and gula melaka colour as much of the mound as the ice kachang's syrups.
## M25: rose soaks only the screen-left half, green syrup only the right; the two together
## count as the ice kachang's syrup.
func _syrup_spread() -> void:
	var b: Bowl = st.bowl
	b.set_vessel("glass")
	b.base = "ice"
	b.fill = 1.0
	b.toppings.clear()
	var ice := RecipeBook.color("ice")
	var share := {}
	var wrong_side := {}
	for s in ["rose", "green_syrup", "mango_sauce", "gula_melaka"]:
		b.sauces.assign([s])
		var n := 0
		var off := 0
		for k in 7:
			for i in 14:
				var a := TAU * i / 14
				var c: Color = b._ice_color(ice, a, k / 6.0, 0)
				var syrup := RecipeBook.color(s)
				# counts as coloured once it is more than half way from the ice to the syrup
				if Vector3(c.r - ice.r, c.g - ice.g, c.b - ice.b).length() > 0.5 * Vector3(syrup.r - ice.r, syrup.g - ice.g, syrup.b - ice.b).length():
					n += 1
					if sin(a) * float(RecipeBook.ingredient(s).get("side", 0)) < -0.01:
						off += 1
		share[s] = n
		wrong_side[s] = off
	b.clear()
	check(share.rose > 25 and share.green_syrup > 25 and wrong_side.rose == 0 and wrong_side.green_syrup == 0,
		"rose colours the left half, green the right: %s, wrong side %s" % [share, wrong_side])
	var both: int = share.rose + share.green_syrup
	check(absi(share.mango_sauce - both) <= both * 0.15 and absi(share.gula_melaka - both) <= both * 0.15,
		"mango + gula melaka cover the mound like rose + green (of 98 points): %s" % [share])


## Every dessert on the menu, once by taps and once by drags, each 3 stars.
func _whole_menu() -> void:
	for item in RecipeBook.makeable():
		print("-- %s by tap, then by drag" % item)
		await _start(item)
		var res := await make(item)
		check(res.get("correct", false) and res.stars == 3, "make(%s) by tap: %s" % [item, res])
		await _start(item)
		res = await make(item, true)
		check(res.get("correct", false) and res.stars == 3, "make(%s) by drag: %s" % [item, res])


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

## Makes `item` from data/recipes.json the tidy way (taps and a hold, or drags) and serves it.
## temp "cold"/"hot" makes that version whatever was ordered; "" = as ordered.
## Returns the judged result, or {} if nothing was served.
func make(item: String, by_drag := false, temp := "") -> Dictionary:
	var r := RecipeBook.recipe(item, st.cold if temp == "" else temp == "cold")
	if RecipeBook.vessel(item) == "soup":
		await tap("soup_stack")
		if r.has("ice") and not by_drag:     # cold: a little ice before the soup (by tap) or after it (by drag)
			await hold("shaver", 0.3)
			await _wait(0.3)
		for i in 3:
			if by_drag:
				await drag("pot:" + r.base, "bowl")
			else:
				await tap("pot:" + r.base)
			await _wait(1.4)
		if r.has("ice") and by_drag:
			await hold("shaver", 0.3)
			await _wait(0.3)
	else:
		await tap("bowl_stack")
		if st.block_kind != r.base:
			await tap("ice:" + r.base)
		await hold("shaver", 2.0)
	for t in r.toppings:
		if by_drag:
			await drag("tub:" + t, "bowl")
		else:
			await tap("tub:" + t)
	for s in r.sauces:
		if by_drag:
			await drag("sauce:" + s, "bowl")
		else:
			await tap("sauce:" + s)
		await _wait(1.3)
	return await _serve()


func _start(item: String, cold := false) -> void:
	stall.start_order(item, null, cold)
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
	e.index = TOUCH_ID
	e.position = pos
	e.pressed = pressed
	get_viewport().push_input(e, true)


func tap(target: String) -> void:
	var p := st.screen_pos(target)
	_touch(p, true)
	await get_tree().process_frame
	_touch(p, false)
	await _wait(0.3)


## Tap at a UI position (the order card).
func tap_ui(at: Vector2) -> void:
	var p := UiKit.to_screen(at)
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
		e.index = TOUCH_ID
		e.position = p
		e.relative = p - last
		last = p
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	_touch(b, false)
	await _wait(0.4)
