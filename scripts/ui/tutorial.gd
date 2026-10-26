class_name Tutorial
extends Control
## Three-step tutorial on the first order of a new game (and again if asked in the settings):
##   1/3 tap the customer, 2/3 make the dessert by following the arrow, 3/3 drag it to the tray.
## A bouncing arrow points at what to touch next (from MakingStation.pointer() in the making
## view); a drag shows a dot sliding to where it goes, a hold shows a filling ring. Nobody's
## patience runs down meanwhile. Then a "well done" note, and Game.tutorial_done is saved.
## Never takes touches.

signal finished

enum Step {OFF, TAKE, MAKE, SERVE, WELL_DONE}

const ORDER := "ice_kachang"           ## the first customer orders the title dessert
const WELL_DONE_SECS := 5.0
const ARROW := Color(1.0, 0.85, 0.25)
const EDGE := Color(0.1, 0.08, 0.12)

var step := Step.OFF
## What the arrow shows, in screen pixels: {at, to (Vector2, drag there; absent = tap), hold}.
var pointer := {}

var _stall: Node
var _box: PanelContainer
var _text: Label
var _t := 0.0
var _served := false
var _done_t := 0.0


func _init(stall: Node) -> void:
	_stall = stall
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.16, 0.88)
	sb.border_color = ARROW
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_box.add_theme_stylebox_override("panel", sb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_text = UiKit.label(Color.WHITE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(200, 0)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_text)


func _ready() -> void:
	_stall.station.finished.connect(func(_i, _r): _served = step != Step.OFF)


func start() -> void:
	step = Step.TAKE
	_served = false
	_stall.queue.frozen = true
	if _stall.queue.line.is_empty():
		_stall.queue.next_order = ORDER
	visible = true


func active() -> bool:
	return step != Step.OFF


## Leave it unfinished (back to the main menu); it runs again on the next order.
func stop() -> void:
	step = Step.OFF
	pointer = {}
	visible = false
	_stall.queue.frozen = false


func _finish() -> void:
	step = Step.OFF
	pointer = {}
	visible = false
	_stall.queue.frozen = false
	Game.set_tutorial_done(true)
	finished.emit()


func _process(delta: float) -> void:
	if step == Step.OFF:
		return
	_t += delta
	var making: bool = _stall._making
	var st: MakingStation = _stall.station
	pointer = {}
	match step:
		Step.TAKE:
			if making:
				step = Step.MAKE
			else:
				var c: Customer = _stall.queue.front()
				if c:
					pointer = {"at": _stall.bubbles._order_rect(c).get_center(), "hold": false}
					_say("1/3   A customer! Tap them to take their order.")
				else:
					_say("1/3   Here comes your first customer...")
		Step.MAKE, Step.SERVE:
			if not making:
				if _served:
					step = Step.WELL_DONE
					_done_t = 0.0
				else:
					step = Step.TAKE             # BACK: they are still waiting
				return
			var p := st.pointer()
			if not p.is_empty():
				step = Step.SERVE if p.target == "bowl" and p.to == "tray" else Step.MAKE
				pointer = {"at": UiKit.to_ui(st.screen_pos(p.target)), "hold": p.hold}
				if p.to != "":
					pointer.to = UiKit.to_ui(st.screen_pos(p.to))
			if step == Step.SERVE:
				_say("3/3   All done! Drag the bowl onto the pink tray to serve it.")
			else:
				_say("2/3   Follow the arrow. The card ticks off each step.")
		Step.WELL_DONE:
			_done_t += delta
			_say("Well done! Serve every customer to finish the day. Your money buys new desserts in the shop.")
			if _done_t >= WELL_DONE_SECS:
				_finish()
				return
	_box.reset_size()
	_box.position = Vector2(roundf((size.x - _box.size.x) / 2.0), 22.0)
	queue_redraw()


func _say(t: String) -> void:
	_text.text = t


func _draw() -> void:
	if pointer.is_empty():
		return
	var at: Vector2 = pointer.at.round()
	if pointer.has("to"):
		var to: Vector2 = pointer.to.round()
		var n := int(at.distance_to(to) / 6.0)
		for i in range(1, n):
			draw_rect(Rect2(at.lerp(to, float(i) / n).round() - Vector2.ONE, Vector2(2, 2)), Color(ARROW, 0.7))
		var k := fmod(_t, 1.4) / 1.1
		if k <= 1.0:
			var dot := at.lerp(to, ease(k, -2.0))
			draw_circle(dot, 4.0, EDGE)
			draw_circle(dot, 3.0, Color.WHITE)
		_ring(to, 7.0, 1.0)
	if pointer.get("hold", false):
		_ring(at, 9.0, fmod(_t, 1.8) / 1.6)
		var f := UiKit.OUTLINED
		var w := f.get_string_size("HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(f, at + Vector2(-w / 2.0, 20), "HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ARROW)
	_arrow(at)


## Arrow coming down onto `tip` (up from below near the top of the screen), bobbing.
func _arrow(tip: Vector2) -> void:
	var up := tip.y < 40.0
	var dir := -1.0 if up else 1.0          # +1: arrow points down
	var bob := roundf(absf(sin(_t * 5.0)) * 4.0)
	var t := tip - Vector2(0, dir * (3.0 + bob))
	var pts := PackedVector2Array([t, t + Vector2(-6, -dir * 7), t + Vector2(-2.5, -dir * 7),
		t + Vector2(-2.5, -dir * 16), t + Vector2(2.5, -dir * 16), t + Vector2(2.5, -dir * 7),
		t + Vector2(6, -dir * 7)])
	var edge := PackedVector2Array()
	for p in pts:
		edge.append(p)
	edge.append(pts[0])
	draw_colored_polygon(pts, ARROW)
	draw_polyline(edge, EDGE, 1.0)


## Circle outline round `c`, drawn `part` (0..1) of the way round.
func _ring(c: Vector2, r: float, part: float) -> void:
	part = clampf(part, 0.0, 1.0)
	draw_arc(c, r + 1.0, 0.0, TAU, 24, EDGE, 1.0)
	if part > 0.0:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * part, 24, ARROW, 2.0)
