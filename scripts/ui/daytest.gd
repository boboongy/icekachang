extends "res://scripts/customers/custtest.gd"
## Headless test of the day loop, shop and saving, in two Godot runs on a test save file:
##   godot --headless --path . -- --daytest --savefile user://save_test.json --fresh
##   godot --headless --path . -- --daycheck --savefile user://save_test.json
## Run 1 plays a short day (2 customers) to the summary, checks the numbers and the autosave,
## buys chendol in the shop with real clicks, starts day 2 and makes a chendol. Run 2 is a
## restart: money, day and unlocks must come back from the save.

const EXPECT := "user://daytest_expect.json"
const DAY_LEN := 2


func run(s: Node) -> void:
	stall = s
	st = s.station
	q = s.queue
	if "--daycheck" in OS.get_cmdline_user_args():
		await _restart_restores()
	else:
		Game.weather_override = "sunny"   # fixed numbers below; weather has its own checks
		Game.weather = "sunny"
		await _fresh_start()
		await _short_day()
		await _shop()
		await _next_day()
		await _make_chendol()
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
	check(p.buy_buttons.keys() == ["chendol", "tau_suan"], "sells chendol and tau suan: %s" % [p.buy_buttons.keys()])
	var b: Button = p.buy_buttons.get("chendol")
	if b == null:
		return
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


func _next_day() -> void:
	print("-- next day")
	await click(stall.day_panel.next_button)
	check(not stall.day_panel.visible, "NEXT DAY closes the summary")
	check(q.quota == 9 and q.quota == Game.quota(), "day 2 has 9 customers (%d)" % q.quota)
	check(stall.bubbles._banner == "DAY 2" and stall.bubbles._banner_sub == "Sunny day",
		"banner '%s' / '%s'" % [stall.bubbles._banner, stall.bubbles._banner_sub])
	var c := await _wait_front()
	check(c != null, "customers come again")


func _make_chendol() -> void:
	print("-- chendol can be made")
	await _start("chendol")
	var res := await make("chendol")
	check(res.get("correct", false) and res.stars == 3, "chendol served correct, 3 stars: %s" % [res])
	print("-- tau suan can be made")
	await _start("tau_suan")
	res = await make("tau_suan")
	check(res.get("correct", false) and res.stars == 3, "tau suan served correct, 3 stars: %s" % [res])


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
	check(sunny_soup < 0.2 and rainy_soup > 0.45, "soup orders: %.0f%% sunny, %.0f%% rainy" % [sunny_soup * 100, rainy_soup * 100])
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


## Share of soup orders over many picks with every v1 item unlocked.
func _soup_share() -> float:
	var soup := 0
	for i in 1000:
		soup += int(RecipeBook.menu_item(Game.pick_order()).kind == "soup")
	return soup / 1000.0


func _write_expect() -> void:
	var f := FileAccess.open(EXPECT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"money": Game.money, "day": Game.day, "unlocked": Game.unlocked}))
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
	check(q.quota == Game.quota(), "today's quota %d" % q.quota)
	check(Game.weather == Game.weather_for(Game.day) and stall.rain.visible == (Game.weather == "rainy"),
		"same weather as before the restart: %s" % Game.weather)
	check(not Game.muted, "sound on after the restart")
	DirAccess.remove_absolute(EXPECT)


func _read_save() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	return d if d is Dictionary else {}


## Left click in the middle of a control, the way the GUI gets a tap on a phone.
func click(c: Control) -> void:
	await get_tree().process_frame
	var p := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p
		e.global_position = p
		e.pressed = pressed
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	await _wait(0.1)
