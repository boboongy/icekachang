extends "res://scripts/ui/daytest.gd"
## Headless test of the main menu, the tutorial, pause and settings, in two runs on a test save:
##   godot --headless --path . -- --tuttest --savefile user://save_tut.json --fresh
##   godot --headless --path . -- --tutcheck --savefile user://save_tut.json
## Run 1 is a new player: PLAY, then the first order is made touching ONLY where the tutorial
## arrow points (tap, hold or drag as it shows), which must give a correct dessert. Then pause,
## settings, main menu, tutorial again, start over. Run 2 is a restart: settings come back.

var tut: Tutorial
var menus: Menus


func run(s: Node) -> void:
	stall = s
	st = s.station
	q = s.queue
	tut = s.tutorial
	menus = s.menus
	await _wait(0.2)
	if "--tutcheck" in OS.get_cmdline_user_args():
		await _restart_keeps_settings()
	else:
		await _title()
		await _tutorial_by_arrow()
		await _pause_and_settings()
		await _main_menu_and_tutorial_again()
		await _start_over()
	Engine.time_scale = 1.0
	print("SELFTEST %s: %d checks, %d failed" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	get_tree().quit(1 if fails else 0)


func _title() -> void:
	print("-- main menu")
	check(menus.visible and menus.title_page.visible, "opens on the main menu")
	check(menus.play_button.text == "PLAY", "new game: '%s'" % menus.play_button.text)
	check(not stall._pause_button.visible, "no pause button on the title")
	Engine.time_scale = FAST
	await _wait(10.0)
	Engine.time_scale = 1.0
	check(q.line.is_empty(), "nobody comes while the title shows")
	await click(menus.play_button)
	check(not menus.visible and stall.queue.spawning, "PLAY starts the day")
	check(tut.active() and tut.step == Tutorial.Step.TAKE, "tutorial starts on a new game")


func _tutorial_by_arrow() -> void:
	print("-- first order, following only the tutorial arrow")
	var c := await _wait_front()
	if c == null:
		check(false, "first customer")
		return
	var first_id := c.get_instance_id()      # taken now: c is freed once they walk off
	check(c.item_id == Tutorial.ORDER, "first customer orders %s" % c.item_id)
	check(tut._text.text.begins_with("1/3"), "step 1: '%s'" % tut._text.text)
	var before := c.patience
	await _wait(2.0)
	check(c.patience == before, "patience frozen during the tutorial")
	check(not tut.pointer.is_empty(), "arrow points at the customer")
	await tap_at(tut.pointer.at)
	check(stall._making, "tapping where the arrow points opens the making view")
	await _wait(0.9)
	check(tut._text.text.begins_with("2/3"), "step 2: '%s'" % tut._text.text)
	var got := []
	var cb := func(_i, r): got.append(r)
	st.finished.connect(cb)
	var money := Game.money
	var saw_serve := false
	var moves := 0
	while stall._making and moves < 30:
		await _wait_until(func(): return not tut.pointer.is_empty() or not stall._making, 5.0)
		if not stall._making:
			break
		if tut.pointer.is_empty():
			check(false, "arrow lost (hint '%s')" % st.ui._hint_base)
			break
		await get_tree().process_frame
		var p := tut.pointer.duplicate()     # UI positions -> screen for the touches
		p.at = UiKit.to_screen(p.at)
		if p.has("to"):
			p.to = UiKit.to_screen(p.to)
		saw_serve = saw_serve or tut.step == Tutorial.Step.SERVE
		moves += 1
		if p.has("to"):
			await _drag_px(p.at, p.to)
		elif p.hold:
			_touch(p.at, true)
			await _wait(2.0)
			_touch(p.at, false)
			await _wait(0.2)
		else:
			_touch(p.at, true)
			await get_tree().process_frame
			_touch(p.at, false)
			await _wait(0.3)
		if got.size() > 0:
			break
	await _wait(3.0)
	st.finished.disconnect(cb)
	check(saw_serve, "step 3 (serve) shown")
	var res: Dictionary = got[0] if got.size() == 1 else {}
	check(res.get("correct", false) and res.stars == 3, "served correct with 3 stars in %d moves: %s" % [moves, res])
	await _wait(1.0)
	check(Game.money > money, "customer paid (%s)" % Game.fmt(Game.money))
	check(tut.step == Tutorial.Step.WELL_DONE, "well done note")
	await _wait(Tutorial.WELL_DONE_SECS + 0.5)
	check(not tut.active() and Game.tutorial_done and _read_save().get("tutorial_done") == true,
		"tutorial done and saved")
	check(not q.frozen, "patience runs again")
	Engine.time_scale = FAST
	await _wait_until(func(): return q.front() != null and q.front().get_instance_id() != first_id, 40.0)
	Engine.time_scale = 1.0
	check(not tut.active(), "no tutorial for the next customer")


func _pause_and_settings() -> void:
	print("-- pause and settings")
	check(stall._pause_button.visible, "pause button shows")
	await tap_at(stall.PAUSE_RECT.get_center())
	check(get_tree().paused and menus.pause_page.visible, "tap pause: paused, pause card")
	await click(menus.resume_button)
	check(not get_tree().paused and not menus.visible, "RESUME")
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	get_viewport().push_input(e)
	await get_tree().process_frame
	check(get_tree().paused and menus.pause_page.visible, "Esc pauses")
	await click(menus.pause_settings_button)
	check(menus.settings_page.visible, "settings open")
	await click(menus.toggles.quality)
	check(Game.quality == "low" and not stall.sun.shadow_enabled, "quality LOW: no shadows")
	await click(menus.toggles.music)
	check(not Game.music and not Sound.is_music_playing(), "music off")
	await click(menus.toggles.fps)
	check(Game.show_fps and stall._fps_label.visible, "FPS counter on")
	await click(menus.toggles.sound)
	check(Game.muted, "sound off")
	await click(menus.toggles.sound)
	check(not Game.muted, "sound on")
	var saved := _read_save()
	check(saved.get("quality") == "low" and saved.get("music") == false and saved.get("show_fps") == true,
		"settings saved: %s" % [saved])
	await click(menus.settings_back_button)
	check(menus.pause_page.visible, "BACK returns to the pause card")
	await click(menus.resume_button)


func _main_menu_and_tutorial_again() -> void:
	print("-- main menu, tutorial again")
	await tap_at(stall.PAUSE_RECT.get_center())
	await click(menus.main_menu_button)
	check(menus.title_page.visible and not get_tree().paused, "MAIN MENU: title")
	check(menus.play_button.text == "CONTINUE", "progress: '%s'" % menus.play_button.text)
	check(q.line.is_empty() and Game.today.served == 0, "the half day is dropped")
	await click(menus.settings_button)
	check(menus.toggles.tutorial.text == "SHOW AGAIN", "tutorial: '%s'" % menus.toggles.tutorial.text)
	await click(menus.toggles.tutorial)
	check(not Game.tutorial_done, "tutorial asked for again")
	await click(menus.settings_back_button)
	check(menus.title_page.visible, "BACK returns to the title")
	await click(menus.play_button)
	check(tut.active(), "CONTINUE: tutorial runs again")
	await tap_at(stall.PAUSE_RECT.get_center())
	await click(menus.main_menu_button)
	check(not tut.active(), "main menu stops the tutorial")


func _start_over() -> void:
	print("-- start over")
	await click(menus.settings_button)
	var b: Button = menus.toggles.reset
	await click(b)
	check(Game.money > 0 and b.text == "SURE? TAP", "first tap asks: '%s'" % b.text)
	await click(b)
	check(Game.money == 0 and Game.day == 1 and Game.unlocked == RecipeBook.makeable(true) and Game.upgrades.is_empty(), "progress wiped")
	check(menus.title_page.visible and menus.play_button.text == "PLAY", "back to the title, PLAY")
	check(Game.quality == "low" and not Game.music, "settings kept")


func _restart_keeps_settings() -> void:
	print("-- restart keeps the settings")
	check(menus.title_page.visible and menus.play_button.text == "PLAY", "title, new game")
	check(Game.quality == "low" and not stall.sun.shadow_enabled, "quality low after the restart")
	check(not Game.music and not Sound.is_music_playing(), "music off after the restart")
	check(Game.show_fps and stall._fps_label.visible, "FPS counter after the restart")
	await click(menus.play_button)
	check(tut.active(), "tutorial runs (it was started over)")


func _drag_px(a: Vector2, b: Vector2) -> void:
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
