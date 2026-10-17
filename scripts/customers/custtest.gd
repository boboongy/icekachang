extends "res://scripts/making/selftest.gd"
## Headless end-to-end test of customers and orders:
##   godot --headless --path . -- --custtest
## Customers walk up, get tapped, their dessert is made with real touch events and served,
## they pay the price (no tips) and leave, the queue moves up. Also: wrong dessert, BACK, patience
## paused while making, patience running out, queue never over 3.
## Walking is fast-forwarded with Engine.time_scale; making runs at normal speed.

const FAST := 6.0

var q: CustomerQueue
var orders := 0


func run(s: Node) -> void:
	stall = s
	st = s.station
	q = s.queue
	await _wait(0.2)
	await _first_customer()
	for i in 3:
		await _serve_front(true)
	await _serve_front(false)
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
	await _wait_until(func(): return ref.get_ref() == null, 20.0)
	check(not is_instance_valid(c), "walked off and is gone")
	var moved := q.line.is_empty() or q.line[0].position.distance_to(CustomerQueue.SLOTS[0]) < 0.01 \
		or q.line[0].is_walking()
	check(moved, "the next customer moves up")
	Engine.time_scale = 1.0


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


func tap_at(p: Vector2) -> void:
	_touch(p, true)
	await get_tree().process_frame
	_touch(p, false)
	await _wait(0.3)
