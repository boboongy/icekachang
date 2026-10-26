extends "res://scripts/making/selftest.gd"
## Headless end-to-end test of customers and orders:
##   godot --headless --path . -- --custtest
## Customers walk up, get tapped, their dessert is made with real touch events and served,
## they pay the price (no tips) and leave, the queue moves up. Also: wrong dessert, BACK, patience
## paused while making, patience running out, queue never over 3, a cold bobo chacha, and a
## 2-dessert order (second made first, bin and BACK keep the first, pays both).
## Walking is fast-forwarded with Engine.time_scale; making runs at normal speed.

const FAST := 6.0

var q: CustomerQueue
var orders := 0


func run(s: Node) -> void:
	stall = s
	st = s.station
	q = s.queue
	q.two_share = 0.0                # one dessert each, except in _two_desserts
	await _wait(0.2)
	await _first_customer()
	for i in 3:
		await _serve_front(true)
	await _serve_front(false)
	await _cold_customer()
	_cold_share()
	await _two_desserts()
	_two_rolls()
	_item_lines()
	_exit_paths()
	await _back_keeps_them()
	await _patience_runs_out()
	await _queue_limit()
	Engine.time_scale = 1.0
	print("CUSTTEST: %d orders end to end" % orders)
	print("SELFTEST %s: %d checks, %d failed" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	get_tree().quit(1 if fails else 0)


func _first_customer() -> void:
	print("-- first customer walks up")
	var c := await _wait_front()
	check(c != null, "a customer is at the counter")
	if c == null:
		return
	check(c.item_id in Game.unlocked, "orders from the unlocked menu: %s" % c.item_id)
	check(c.position.distance_to(CustomerQueue.SLOTS[0]) < 0.01, "stands in the front slot")
	var corner := stall.get_viewport().get_visible_rect().size - Vector2(8, 8)
	await tap_at(corner)
	check(not stall._making, "a tap away from the customer does nothing")


## Taps the front customer, checks patience is frozen while making, makes their order
## (or a different dessert if not `right`), serves it, checks the money and the queue.
func _serve_front(right: bool) -> void:
	print("-- serve the front customer (%s)" % ("right dessert" if right else "WRONG dessert"))
	var c := await _wait_front()
	if c == null:
		check(false, "a customer to serve")
		return
	await tap_at(stall.bubbles._order_rect(c).get_center())
	check(stall._making and st.item_id == c.item_id, "tap their bubble: making %s" % st.item_id)
	var waiting := q.line.duplicate()       # (more may walk up meanwhile)
	var before := waiting.map(func(x): return x.patience)
	await _wait(2.0)
	check(waiting.map(func(x): return x.patience) == before, "patience paused while making")
	var item := c.item_id
	if not right:
		item = Game.unlocked.filter(func(x): return x != c.item_id)[0]
	var money := Game.money
	var res := await make(item)
	orders += 1
	check(res.get("correct", not right) == right, "judged %s: %s" % ["right" if right else "wrong", res])
	await _wait(1.0)
	var want := money + RecipeBook.price(c.item_id)
	check(Game.money == want, "paid %s, no tip: money %s (want %s)" % [
		Game.fmt(RecipeBook.price(c.item_id)), Game.fmt(Game.money), Game.fmt(want)])
	check(not c in q.line and c in q.leaving, "left the queue")
	var line_ok := c.said == (CustomerQueue.THANKS[res.stars] if right else CustomerQueue.WRONG_LINE)
	check(line_ok, "says '%s'" % c.said)
	Engine.time_scale = FAST
	var ref: WeakRef = weakref(c)
	var stood := c.position
	var track := {"max_z": stood.z, "min_x": stood.x}
	var gone := func() -> bool:
		if ref.get_ref() == null:
			return true
		track.max_z = maxf(track.max_z, c.position.z)
		track.min_x = minf(track.min_x, c.position.x)
		return false
	await _wait_until(gone, 20.0)
	check(not is_instance_valid(c), "walked off and is gone")
	check(track.max_z <= stood.z + 0.01 and track.min_x >= stood.x - 0.01,
		"walked straight right, never towards the camera (z %.2f -> max %.2f, min x %.2f)" % [stood.z, track.max_z, track.min_x])
	var moved := q.line.is_empty() or q.line[0].position.distance_to(CustomerQueue.SLOTS[0]) < 0.01 \
		or q.line[0].is_walking()
	check(moved, "the next customer moves up")
	Engine.time_scale = 1.0


## Round 9: one who gives up further back leaves left at their own depth, in front of nobody.
func _exit_paths() -> void:
	print("-- exit paths")
	for i in CustomerQueue.SLOTS.size():
		var path := CustomerQueue.exit_path(CustomerQueue.SLOTS[i], i == 0)
		var ok := path.all(func(p): return p.z <= CustomerQueue.SLOTS[i].z + 0.001)
		var away: bool = path[-1].x > 4.0 if i == 0 else path[-1].x < -4.0
		check(ok and away, "slot %d leaves %s, never nearer the camera: %s" % [i, "right" if i == 0 else "left", path])


## M21: every dessert has its own lines, none wider than the longest line already in the game.
func _item_lines() -> void:
	print("-- per-dessert lines")
	var missing := RecipeBook.board().filter(func(id): return CustomerQueue.ITEM_LINES.get(id, []).size() < 2)
	check(missing.is_empty(), "every dessert has 2 own lines (missing: %s)" % [missing])
	var max_w: float = stall.bubbles._w(CustomerQueue.COLD_LINES[1])
	var wide := []
	for id in CustomerQueue.ITEM_LINES:
		for l in CustomerQueue.ITEM_LINES[id]:
			if stall.bubbles._w(l) > max_w:
				wide.append(l)
	check(wide.is_empty(), "no line wider than '%s' (too wide: %s)" % [CustomerQueue.COLD_LINES[1], wide])


## M19: a cold bobo chacha order: snowflake bubble, cold card, made cold = 3 stars, pays.
func _cold_customer() -> void:
	print("-- a cold bobo chacha customer")
	var c := await _wait_front()
	var hot_w: float = stall.bubbles._order_rect(c).size.x
	c.item_id = "bobo_chacha"
	c.order_line = "Ah"  # short, so the name row sets the width
	c.cold = false
	var warm_w: float = stall.bubbles._order_rect(c).size.x
	c.cold = true
	var cold_w: float = stall.bubbles._order_rect(c).size.x
	c.order_line = CustomerQueue.COLD_LINES[0]
	check(cold_w > warm_w, "cold bubble is wider (snowflake): %d vs %d (was %d)" % [cold_w, warm_w, hot_w])
	await tap_at(stall.bubbles._order_rect(c).get_center())
	check(stall._making and st.item_id == "bobo_chacha" and st.cold, "tap: making a cold bobo chacha")
	var money := Game.money
	var res := await make("bobo_chacha")
	orders += 1
	check(res.get("correct", false) and res.stars == 3, "cold bobo chacha 3 stars: %s" % [res])
	await _wait(1.0)
	check(Game.money == money + RecipeBook.price("bobo_chacha"), "paid the bobo chacha price")
	Engine.time_scale = FAST
	var ref: WeakRef = weakref(c)
	await _wait_until(func(): return ref.get_ref() == null, 20.0)
	Engine.time_scale = 1.0


## Cold share of bobo chacha orders, 2000 rolls per weather; never for other desserts.
func _cold_share() -> void:
	print("-- cold share by weather")
	var keep := Game.weather
	for w in ["sunny", "rainy"]:
		Game.weather = w
		var n := 0
		for i in 2000:
			n += int(q.roll_cold("bobo_chacha"))
		var want: float = CustomerQueue.COLD_SHARE[w]
		check(absf(n / 2000.0 - want) < 0.05, "%s: %.1f%% cold (want %d%%)" % [w, n / 20.0, want * 100])
	var other := 0
	for i in 500:
		other += int(q.roll_cold("tau_suan")) + int(q.roll_cold("ice_kachang"))
	check(other == 0, "other desserts never cold")
	Game.weather = keep


## M20: two desserts, made second-first; binning a bowl and BACK keep the first on the tray;
## serving the second pays both, 3 stars each = 3 stars.
func _two_desserts() -> void:
	print("-- a 2-dessert order")
	var c := await _wait_front()
	var one_h: float = stall.bubbles._order_rect(c).size.y
	c.item_id = "ice_kachang"
	c.cold = false
	c.item2 = "mango_milk_ice"
	c.cold2 = false
	c.made = {}
	var two_h: float = stall.bubbles._order_rect(c).size.y
	check(two_h == one_h + CustomerBubbles.LINE_H, "bubble has a row per dessert (%d -> %d px)" % [one_h, two_h])
	await tap_at(stall.bubbles._order_rect(c).get_center())
	check(stall._making and st.item_id == "ice_kachang" and st.orders.size() == 2, "tap: making the first of two")
	check(st.ui._also.visible and st.ui._also_label.text == "THEN: MANGO MILK ICE", "card: '%s'" % st.ui._also_label.text)
	var money := Game.money
	var desserts: int = Game.today.get("desserts", 0)
	var res := await make("mango_milk_ice")
	check(res.is_empty() and stall._making, "the second one made first: no hand-over yet")
	check(c.made.has("mango_milk_ice") and c.made.mango_milk_ice.res.stars == 3, "mango milk ice waits on the tray, 3 stars")
	check(st._tray_bowl.visible and not st.has_bowl and st.item_id == "ice_kachang", "card back to the ice kachang")
	check(st.ui._also_label.text == "ON TRAY: MANGO MILK ICE", "card: '%s'" % st.ui._also_label.text)
	await tap("bowl_stack")
	await hold("shaver", 1.0)
	await drag("bowl", "bin")
	await _wait(0.6)
	check(not st.has_bowl and st._tray_bowl.visible and c.made.has("mango_milk_ice"), "bin: only the new bowl goes")
	st.ui.back_pressed.emit()
	await _wait(0.9)
	check(not stall._making and q.front() == c and c.made.has("mango_milk_ice"), "BACK: they wait, the first is kept")
	await tap_at(stall.bubbles._order_rect(c).get_center())
	check(stall._making and st.item_id == "ice_kachang" and st._tray_bowl.visible, "back in: the first still on the tray")
	res = await make("ice_kachang")
	orders += 1
	check(res.get("correct", false) and res.stars == 3 and res.parts.size() == 2, "both served, 3 stars: %s" % [res.stars])
	await _wait(1.0)
	var want := money + RecipeBook.price("ice_kachang") + RecipeBook.price("mango_milk_ice")
	check(Game.money == want, "pays both: money %s (want %s)" % [Game.fmt(Game.money), Game.fmt(want)])
	check(Game.today.desserts == desserts + 2, "2 desserts counted")
	check(c.said == CustomerQueue.THANKS[3], "says '%s'" % c.said)
	Engine.time_scale = FAST
	var ref: WeakRef = weakref(c)
	await _wait_until(func(): return ref.get_ref() == null, 20.0)
	Engine.time_scale = 1.0


## Who orders two: ~1 in 6 from day 2 once the tutorial is done, two different desserts,
## longer patience; never on day 1 or before the tutorial is done.
func _two_rolls() -> void:
	print("-- 2-dessert odds")
	var keep := [Game.day, Game.tutorial_done]
	q.two_share = CustomerQueue.TWO_SHARE
	Game.day = 3
	Game.tutorial_done = true
	var n := 0
	for i in 3000:
		n += int(q.rolls_two())
	check(absf(n / 3000.0 - 1.0 / 6.0) < 0.03, "day 3: %.1f%% order two (want ~17%%)" % [n / 30.0])
	q.two_share = 1.0
	var queued := q.line.duplicate()     # spawn into an empty line (a full one has no slot left)
	q.line.clear()
	var c := q.spawn()
	check(c.item2 != "" and c.item2 != c.item_id, "spawned: %s + %s" % [c.item_id, c.item2])
	check(is_equal_approx(c.patience_secs, CustomerQueue.PATIENCE_SECS * CustomerQueue.TWO_PATIENCE), "longer patience (%d s)" % c.patience_secs)
	q.line.assign(queued)
	q.spawned -= 1
	c.queue_free()
	Game.day = 1
	var day1 := 0
	for i in 500:
		day1 += int(q.rolls_two())
	Game.day = 3
	Game.tutorial_done = false
	var tut := 0
	for i in 500:
		tut += int(q.rolls_two())
	check(day1 == 0 and tut == 0, "never on day 1 (%d) or before the tutorial is done (%d)" % [day1, tut])
	Game.day = keep[0]
	Game.tutorial_done = keep[1]
	q.two_share = 0.0


func _back_keeps_them() -> void:
	print("-- BACK keeps the customer waiting")
	var c := await _wait_front()
	await tap_at(stall.bubbles._body_rect(c).get_center())
	check(stall._making, "tap the customer's body: making")
	st.ui.back_pressed.emit()
	await _wait(0.8)
	check(not stall._making and q.front() == c, "back: same customer still waiting at the front")


func _patience_runs_out() -> void:
	print("-- patience runs out")
	var c := await _wait_front()
	var money := Game.money
	c.patience = 0.01
	await _wait(1.5)
	check(not c in q.line and c.said == CustomerQueue.GIVE_UP_LINE, "gives up: '%s'" % c.said)
	check(Game.money == money, "no penalty")


func _queue_limit() -> void:
	print("-- queue fills up to 3, never more")
	Engine.time_scale = FAST
	var most := 0
	var t := 0.0
	while t < 150.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		most = maxi(most, q.line.size())
	check(most == CustomerQueue.MAX, "most in line at once: %d" % most)
	Engine.time_scale = 1.0


# --- helpers ---------------------------------------------------------------------------

func _wait_front() -> Customer:
	Engine.time_scale = FAST
	await _wait_until(func(): return q.front() != null, 40.0)
	Engine.time_scale = 1.0
	return q.front()


## Waits (game time) until cond() is true or `secs` pass.
func _wait_until(cond: Callable, secs: float) -> void:
	var t := 0.0
	while not cond.call() and t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()


## Taps a UI position (converted to the screen, which renders larger in the making view).
func tap_at(p: Vector2) -> void:
	p = UiKit.to_screen(p)
	_touch(p, true)
	await get_tree().process_frame
	_touch(p, false)
	await _wait(0.3)
