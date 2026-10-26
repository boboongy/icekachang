extends "res://scripts/customers/custtest.gd"
## Headless test of the day loop, shop and saving, in two Godot runs on a test save file:
##   godot --headless --path . -- --daytest --savefile user://save_test.json --fresh
##   godot --headless --path . -- --daycheck --savefile user://save_test.json
## Run 1 plays a short day (2 customers) to the summary, checks the numbers and the autosave,
## buys chendol, tau suan and the 5 post-v1 desserts in the shop with real clicks, starts day 2
## and makes every bought dessert; then buys both upgrades and checks they make shaving and
## ladling faster. Run 2 is a restart: money, day, unlocks and upgrades must come back.

const EXPECT := "user://daytest_expect.json"
const DAY_LEN := 2


func run(s: Node) -> void:
	stall = s
	st = s.station
	q = s.queue
	q.two_share = 0.0                # day 2 on could roll 2-dessert orders; custtest covers them
	if "--daycheck" in OS.get_cmdline_user_args():
		await _restart_restores()
	else:
		Game.weather_override = "sunny"   # fixed numbers below; weather has its own checks
		Game.weather = "sunny"
		await _fresh_start()
		await _short_day()
		await _shop()
		await _buy_the_rest()
		await _next_day()
		await _make_bought()
		await _upgrades()
		await _weather_and_mute()
		_write_expect()
	Engine.time_scale = 1.0
	print("SELFTEST %s: %d checks, %d failed" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	get_tree().quit(1 if fails else 0)


func _fresh_start() -> void:
	print("-- fresh save")
	check(Game.save_path == "user://save_test.json", "uses the test save: %s" % Game.save_path)
	check(Game.day == 1 and Game.money == 0, "day 1, $0 (day %d, %s)" % [Game.day, Game.fmt(Game.money)])
	check(Game.unlocked == RecipeBook.makeable(true), "start menu only: %s" % [Game.unlocked])
	check(q.quota == Game.FIRST_QUOTA, "day 1 has %d customers (%d)" % [Game.FIRST_QUOTA, q.quota])
	q.start_day(DAY_LEN)             # a short day for the test


func _short_day() -> void:
	print("-- a %d-customer day" % DAY_LEN)
	var sum := {"price": 0}      # (lambdas capture locals by value)
	var cb := func(_c, price):
		sum.price += price
	q.paid.connect(cb)
	for i in DAY_LEN:
		await _serve_front(true)
	q.paid.disconnect(cb)
	var takings: int = sum.price
	check(q.spawned == DAY_LEN and q.line.is_empty(), "nobody else comes (spawned %d)" % q.spawned)
	Engine.time_scale = FAST
	await _wait_until(func(): return stall.day_panel.visible, 20.0)
	Engine.time_scale = 1.0
	await _wait(0.2)
	check(stall.day_panel.visible, "day summary shows")
	var d := Game.last_day
	check(d.day == 1 and d.served == DAY_LEN and d.gave_up == 0, "summary: day %d, served %d, went home %d" % [
		d.day, d.served, d.gave_up])
	check(d.earned == takings and not d.has("tips"), "summary: earned %s, no tips" % Game.fmt(d.earned))
	check(Game.money == takings, "money %s" % Game.fmt(Game.money))
	check(Game.day == 2, "day moves on to 2")
	var saved := _read_save()
	check(saved.get("day") == 2.0 and saved.get("money") == float(Game.money), "autosaved at day end: %s" % [saved])
	await tap_at(Vector2(240, 35))      # top fifth: would toggle shadows in the waiting view
	check(stall.sun.shadow_enabled, "shadows untouched")
	check(not stall._making and stall.day_panel.visible, "taps behind the summary do nothing")


func _shop() -> void:
	print("-- shop")
	var p: DayPanel = stall.day_panel
	await click(p.shop_button)
	check(p._shop.visible and not p._summary.visible, "SHOP opens the shop page")
	var sells := Game.shop_items()
	var costs := sells.map(func(id): return Game.cost(id))
	var sorted_costs := costs.duplicate()
	sorted_costs.sort()
	check(sells.size() == RecipeBook.makeable().size() - RecipeBook.makeable(true).size() and costs == sorted_costs
		and p.buy_buttons.keys() == sells + ["big_ladle", "fast_shaver"],
		"sells all %d, cheapest first, then the upgrades: %s" % [sells.size(), p.buy_buttons.keys()])
	await get_tree().process_frame
	var screen := p.get_global_rect()
	var off := p.buy_buttons.keys().filter(func(id): return not screen.encloses(p.buy_buttons[id].get_global_rect()))
	check(off.is_empty() and screen.encloses(p.shop_back_button.get_global_rect())
		and screen.encloses(p._shop.get_global_rect()), "the whole shop fits the screen (off: %s)" % [off])
	var b: Button = p.buy_buttons.get("chendol")
	if b == null:
		return
	check(stall.board_lit("ice_kachang") and not stall.board_lit("chendol"), "lightbox: starters lit, chendol dark")
	check(b.disabled and b.text == "BUY $15.00", "too little money: '%s' disabled" % b.text)
	var money := Game.money
	await click(b)
	check(not "chendol" in Game.unlocked and Game.money == money, "can't buy without the money")
	Game.earn(1500)                  # test money
	await click(p.shop_back_button)
	await click(p.shop_button)
	check(not b.disabled, "enough money: BUY enabled")
	await click(b)
	check("chendol" in Game.unlocked and Game.money == money, "bought chendol for $15 (money %s)" % Game.fmt(Game.money))
	check(b.disabled and b.text == "ON MENU", "button says '%s'" % b.text)
	check(stall.board_lit("chendol"), "lightbox: chendol lit once bought")
	check("chendol" in _read_save().get("unlocked", []), "purchase saved")
	var ts: Button = p.buy_buttons.get("tau_suan")
	check(ts.disabled and ts.text == "BUY $25.00", "tau suan: '%s' disabled" % ts.text)
	Game.earn(2500)
	await click(p.shop_back_button)
	await click(p.shop_button)
	await click(ts)
	check("tau_suan" in Game.unlocked and Game.money == money, "bought tau suan for $25")
	await click(p.shop_back_button)
	check(p._summary.visible, "BACK returns to the summary")


const NEW_ITEMS := {"ice_kachang_mango": 3000, "chendol_durian": 4000, "ice_kachang_durian": 4500,
	"bobo_chacha": 6000, "pulut_hitam": 7500}


func _buy_the_rest() -> void:
	print("-- shop: the five post-v1 desserts")
	var p: DayPanel = stall.day_panel
	var money := Game.money
	for id in NEW_ITEMS:
		Game.earn(NEW_ITEMS[id])
		await click(p.shop_button)
		var b: Button = p.buy_buttons[id]
		check(b.text == "BUY " + Game.fmt(NEW_ITEMS[id]) and not b.disabled, "%s: '%s'" % [id, b.text])
		await click(b)
		check(id in Game.unlocked and Game.money == money, "bought %s" % id)
		await click(p.shop_back_button)
	var n := RecipeBook.makeable(true).size() + 2 + NEW_ITEMS.size()
	check(Game.unlocked.size() == n and _read_save().get("unlocked", []).size() == n, "all %d on the menu and saved" % n)


func _next_day() -> void:
	print("-- next day")
	await click(stall.day_panel.next_button)
	check(not stall.day_panel.visible, "NEXT DAY closes the summary")
	check(q.quota == 9 and q.quota == Game.quota(), "day 2 has 9 customers (%d)" % q.quota)
	check(stall.bubbles._banner == "DAY 2" and stall.bubbles._banner_sub == "Sunny day",
		"banner '%s' / '%s'" % [stall.bubbles._banner, stall.bubbles._banner_sub])
	var c := await _wait_front()
	check(c != null, "customers come again")


func _make_bought() -> void:
	for id in ["chendol", "tau_suan"] + NEW_ITEMS.keys():
		print("-- %s can be made" % id)
		await _start(id)
		var res := await make(id)
		check(res.get("correct", false) and res.stars == 3, "%s served correct, 3 stars: %s" % [id, res])


func _upgrades() -> void:
	print("-- upgrades: big ladle, fast shaver")
	await _start("ice_kachang")
	await tap("bowl_stack")
	await hold("shaver", 1.0)
	check(st.bowl.fill > 0.5 and st.bowl.fill < 0.8, "before: 1 s of shaving is not full (%.2f)" % st.bowl.fill)
	st.ui.back_pressed.emit()
	await _wait(1.0)
	var money := Game.money
	var p: DayPanel = stall.day_panel
	Game.last_day = {"day": Game.day, "served": 0, "gave_up": 0, "earned": 0}
	p.show_summary()
	for id in ["big_ladle", "fast_shaver"]:
		Game.earn(Game.UPGRADES[id].cost)
		await click(p.shop_button)
		var b: Button = p.buy_buttons[id]
		check(b.text == "BUY " + Game.fmt(Game.UPGRADES[id].cost) and not b.disabled, "%s: '%s'" % [id, b.text])
		await click(b)
		check(Game.has_upgrade(id) and Game.money == money and b.text == "IN USE", "bought %s: '%s'" % [id, b.text])
		await click(p.shop_back_button)
	check(_read_save().get("upgrades", []) == ["big_ladle", "fast_shaver"], "upgrades saved")
	p.hide_panel()
	await _start("ice_kachang")
	await tap("bowl_stack")
	await hold("shaver", 1.0)
	check(st.bowl.fill == 1.0, "fast shaver: full in 1 s (%.2f)" % st.bowl.fill)
	st.ui.back_pressed.emit()
	await _wait(1.0)
	await _start("tau_suan")
	await tap("soup_stack")
	for i in 2:
		await tap("pot:tau_suan_soup")
		await _wait(1.4)
	check(st.bowl.fill == 1.0, "big ladle: two ladles fill the bowl (%.2f)" % st.bowl.fill)
	st.ui.back_pressed.emit()
	await _wait(1.0)


func _weather_and_mute() -> void:
	print("-- weather")
	Game.weather_override = ""
	check(Game.weather_for(1) == "sunny", "day 1 is sunny")
	var rainy := 0
	for d in range(2, 302):
		rainy += int(Game.weather_for(d) == "rainy")
	check(rainy > 60 and rainy < 120, "about 30%% of days rain: %d of 300" % rainy)
	check(Game.weather_for(17) == Game.weather_for(17), "a day's weather is fixed")
	Game.weather = "sunny"
	var sunny_quota := Game.quota()
	var sunny_soup := _soup_share()
	Game.weather = "rainy"
	check(Game.quota() < sunny_quota, "fewer customers when it rains (%d vs %d)" % [Game.quota(), sunny_quota])
	var rainy_soup := _soup_share()
	check(sunny_soup < 0.35 and rainy_soup > 0.4 and rainy_soup > sunny_soup + 0.15, "soup orders: %.0f%% sunny, %.0f%% rainy" % [sunny_soup * 100, rainy_soup * 100])
	for w in ["sunny", "rainy"]:
		Game.weather = w
		var picks := {}
		var repeats := 0
		var prev := ""
		for i in 3000:
			var id := Game.pick_order()
			picks[id] = picks.get(id, 0) + 1
			repeats += int(id == prev)
			prev = id
		var rarest := Game.unlocked[0]
		for id in Game.unlocked:
			if picks.get(id, 0) < picks.get(rarest, 0):
				rarest = id
		var share: float = picks.get(rarest, 0) / 3000.0
		check(share >= 0.03, "%s: every item ordered, rarest %s %.1f%%" % [w, rarest, share * 100])
		check(repeats == 0, "%s: never the same dessert twice in a row (%d repeats)" % [w, repeats])
	Game.weather = "rainy"
	stall._apply_weather("rainy")
	check(stall.rain.visible and Sound.is_raining() and stall.sun.light_energy < 1.0, "rainy look and sound")
	await _wait(0.2)
	check(stall.rain._drops.size() == RainOverlay.DROPS, "rain falls")
	stall._apply_weather("sunny")
	check(not stall.rain.visible and not Sound.is_raining(), "sunny again: no rain")
	Game.weather_override = "sunny"
	Game.weather = "sunny"
	print("-- mute")
	await _wait(0.1)
	var at: Vector2 = stall.bubbles._mute_rect.get_center()
	await tap_at(at)
	var bus := AudioServer.get_bus_index("Master")
	check(Game.muted and AudioServer.is_bus_mute(bus), "tap the speaker: muted")
	check(_read_save().get("muted") == true, "mute saved")
	await tap_at(at)
	check(not Game.muted and not AudioServer.is_bus_mute(bus), "tap again: sound on")


## Share of soup orders over many picks with every item unlocked.
func _soup_share() -> float:
	var soup := 0
	for i in 1000:
		soup += int(RecipeBook.menu_item(Game.pick_order()).kind == "soup")
	return soup / 1000.0


func _write_expect() -> void:
	var f := FileAccess.open(EXPECT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"money": Game.money, "day": Game.day, "unlocked": Game.unlocked,
		"upgrades": Game.upgrades}))
	f.close()
	print("  wrote %s for --daycheck" % EXPECT)


func _restart_restores() -> void:
	print("-- restart restores the save")
	if not FileAccess.file_exists(EXPECT):
		check(false, "run --daytest first (%s missing)" % EXPECT)
		return
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECT))
	check(Game.money == int(want.money), "money %s (want %s)" % [Game.fmt(Game.money), Game.fmt(int(want.money))])
	check(Game.day == int(want.day), "day %d (want %d)" % [Game.day, int(want.day)])
	check(str(Game.unlocked) == str(want.unlocked), "unlocked %s" % [Game.unlocked])
	check(str(Game.upgrades) == str(want.upgrades) and Game.upgrades.size() == 2, "upgrades %s" % [Game.upgrades])
	check(q.quota == Game.quota(), "today's quota %d" % q.quota)
	check(Game.weather == Game.weather_for(Game.day) and stall.rain.visible == (Game.weather == "rainy"),
		"same weather as before the restart: %s" % Game.weather)
	check(not Game.muted, "sound on after the restart")
	DirAccess.remove_absolute(EXPECT)
	# M18: a save from before green bean soup gets it free and keeps what was bought
	var old_save := "user://save_old_test.json"
	var f := FileAccess.open(old_save, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "money": 1234, "day": 5, "unlocked": ["ice_kachang", "mango_milk_ice", "chendol", "tau_suan"]}))
	f.close()
	var keep := Game.save_path
	Game.unlocked.assign(RecipeBook.makeable(true))
	Game.save_path = old_save
	Game.load_game()
	Game.save_path = keep
	check("green_bean_soup" in Game.unlocked and "chendol" in Game.unlocked and "tau_suan" in Game.unlocked and Game.money == 1234,
		"old save: green bean soup added, purchases kept %s" % [Game.unlocked])
	DirAccess.remove_absolute(old_save)


func _read_save() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	return d if d is Dictionary else {}


## Left click in the middle of a control, the way the GUI gets a tap on a phone.
func click(c: Control) -> void:
	await get_tree().process_frame
	var p := UiKit.to_screen(c.get_global_rect().get_center())
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p
		e.global_position = p
		e.pressed = pressed
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	await _wait(0.1)
