class_name CustomerBubbles
extends Control
## Waiting-view overlay: a speech bubble over each queued customer (the front one says their
## order: line, dessert icon and name; the others show just the icon), patience bars, reactions
## over leaving customers, floating "+$2.50" popups, the day and money total, and
## the "DAY N" banner when a day starts.
## Drawn in one _draw pass; never takes touches (the stall asks hit_front()).

const PAPER := Color(0.99, 0.97, 0.9)
const PINK := Color(0.89, 0.25, 0.44)
const INK := Color(0.16, 0.14, 0.16)
const GLASS := Color(0.72, 0.88, 0.92)
const FROST := Color(0.3, 0.62, 0.95)  ## snowflake on a cold order
const DONE := Color(0.18, 0.6, 0.3)    ## tick on a dessert already made (2-dessert order)
const FS := 8                      ## font size (480x270 viewport)
const LINE_H := 10.0
const POPUP_SECS := 1.4
const HIT_PAD := 10.0              ## extra px round the front bubble that still counts as a tap
const BANNER_SECS := 2.2
const BANNER_FS := 24
const SUB_FS := 16

var queue: CustomerQueue
var cam: Camera3D

var _font: Font
var _popups: Array[Dictionary] = []    # {text, color, at (Vector3), age}
var _banner := ""
var _banner_sub := ""
var _banner_age := BANNER_SECS
var _mute_rect := Rect2()


func _init(q: CustomerQueue, camera: Camera3D) -> void:
	queue = q
	cam = camera
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue.paid.connect(_on_paid)


func _ready() -> void:
	_font = get_theme_default_font()


func _process(delta: float) -> void:
	for p in _popups:
		p.age += delta
	_popups = _popups.filter(func(p): return p.age < POPUP_SECS)
	_banner_age += delta
	queue_redraw()


## The front customer if `pos` is on them or their bubble (generous), else null.
func hit_front(pos: Vector2) -> Customer:
	var c := queue.front()
	if c == null or not visible:
		return null
	if _order_rect(c).grow(HIT_PAD).has_point(pos):
		return c
	return c if _body_rect(c).has_point(pos) else null


## Screen rect round a customer's body, a bit wider than they are.
func _body_rect(c: Customer) -> Rect2:
	var top := UiKit.to_ui(cam.unproject_position(c.bubble_anchor()))
	var foot := UiKit.to_ui(cam.unproject_position(c.feet()))
	var half := absf(foot.y - top.y) * 0.22 + 6.0
	return Rect2(Vector2(foot.x - half, top.y), Vector2(half * 2.0, foot.y - top.y))


func _on_paid(c: Customer, price: int) -> void:
	var at := c.bubble_anchor()
	_popups.append({"text": "+" + Game.fmt(price), "color": Color(0.6, 1.0, 0.6), "at": at, "age": 0.0})


# --- drawing -----------------------------------------------------------------------------

func _draw() -> void:
	var front := queue.front()
	for c in queue.line:
		if c.state != Customer.State.WAITING or cam.is_position_behind(c.bubble_anchor()):
			continue
		if c == front:
			_order_bubble(c)
		else:
			_small_bubble(c)
	for c in queue.leaving + queue.line:
		if c.is_saying():
			_say_bubble(c)
	for p in _popups:
		if p.age < 0.0:
			continue
		var s := UiKit.to_ui(cam.unproject_position(p.at)) - Vector2(0, 14 + p.age * 16.0)
		var a := clampf((POPUP_SECS - p.age) / 0.4, 0.0, 1.0)
		_text_outlined(s - Vector2(_w(p.text) / 2.0, 0), p.text, Color(p.color, a))
	_money()
	_draw_banner()


## Front customer: their line, then a row per dessert (icon, a snowflake if cold, name, and a
## tick once made, for a 2-dessert order), then the patience bar.
func _order_bubble(c: Customer) -> void:
	if c.is_saying():
		return
	var r := _order_rect(c)
	_bubble(r, c)
	_text(r.position + Vector2(4, 3), c.order_line, INK)
	var two := c.item2 != ""
	var y := LINE_H
	for o in c.orders():
		var x := 0.0
		if two:
			_tick(r.position + Vector2(4, y + 3), c.made.has(o.item))
			x = 9.0
		_icon(r.position + Vector2(8 + x, y + 8), o.item)
		if o.cold:
			_snowflake(r.position + Vector2(17 + x, y + 8))
		_text(r.position + Vector2(17 + x + (8 if o.cold else 0), y + 3), RecipeBook.order_name(o.item, o.cold), PINK)
		y += LINE_H
	_patience(Rect2(r.position + Vector2(4, r.size.y - 5), Vector2(r.size.x - 8, 2)), c.patience)


func _order_rect(c: Customer) -> Rect2:
	var w := _w(c.order_line)
	for o in c.orders():
		w = maxf(w, _w(RecipeBook.order_name(o.item, o.cold)) + (21.0 if o.cold else 13.0) + (9.0 if c.item2 != "" else 0.0))
	return _bubble_rect(c, Vector2(w + 8.0, LINE_H * (1.0 + c.orders().size()) + 10.0))


## Waiting further back: just the dessert icon(s) and patience.
func _small_bubble(c: Customer) -> void:
	if c.is_saying():
		return
	var w := 4.0
	for o in c.orders():
		w += 10.0 + (8.0 if o.cold else 0.0)
	var r := _bubble_rect(c, Vector2(w + 4.0, 15))
	_bubble(r, c)
	var x := r.position.x + 9.0
	for o in c.orders():
		_icon(Vector2(x, r.position.y + 5), o.item)
		x += 10.0
		if o.cold:
			_snowflake(Vector2(x - 1.0, r.position.y + 5))
			x += 8.0
	_patience(Rect2(r.position + Vector2(3, r.size.y - 4), Vector2(r.size.x - 6, 2)), c.patience)


## 7x7 box at `top_left`, ticked when `done`.
func _tick(top_left: Vector2, done: bool) -> void:
	draw_rect(Rect2(top_left, Vector2(7, 7)), Color(0.7, 0.66, 0.6), false, 1.0)
	if done:
		draw_polyline(PackedVector2Array([top_left + Vector2(1, 3), top_left + Vector2(3, 6), top_left + Vector2(8, -1)]), DONE, 2.0)


func _say_bubble(c: Customer) -> void:
	var r := _bubble_rect(c, Vector2(_w(c.said) + 8.0, LINE_H + 6.0))
	_bubble(r, c)
	_text(r.position + Vector2(4, 3), c.said, INK)


## Bubble of `sz` centred above the customer's head, kept on screen.
func _bubble_rect(c: Customer, sz: Vector2) -> Rect2:
	var a := UiKit.to_ui(cam.unproject_position(c.bubble_anchor()))
	var p := Vector2(a.x - sz.x / 2.0, a.y - sz.y - 5.0)
	p = p.clamp(Vector2(2, 14), size - sz - Vector2(2, 2))
	return Rect2(p.round(), sz)


func _bubble(r: Rect2, c: Customer) -> void:
	var a := UiKit.to_ui(cam.unproject_position(c.bubble_anchor()))
	var tx := clampf(a.x, r.position.x + 4, r.end.x - 4)
	var tail := PackedVector2Array([Vector2(tx - 3, r.end.y - 1), Vector2(tx + 3, r.end.y - 1), Vector2(tx, r.end.y + 4)])
	draw_rect(r.grow(1), INK)
	draw_colored_polygon(PackedVector2Array([tail[0] + Vector2(-1, 0), tail[1] + Vector2(1, 0), tail[2] + Vector2(0, 1)]), INK)
	draw_rect(r, PAPER)
	draw_colored_polygon(tail, PAPER)


## Little glass bowl with a mound in the dessert's colour, centred at `c`.
func _icon(c: Vector2, item_id: String) -> void:
	draw_circle(c + Vector2(0, 1), 3.5, RecipeBook.item_color(item_id))
	draw_rect(Rect2(c + Vector2(-4.5, 1), Vector2(9, 3)), GLASS)
	draw_rect(Rect2(c + Vector2(-1.5, 4), Vector2(3, 1)), GLASS)


## Small light-blue snowflake (7x7 px) centred at `c`.
func _snowflake(c: Vector2) -> void:
	c = c.round()
	draw_rect(Rect2(c + Vector2(-3, 0), Vector2(7, 1)), FROST)
	draw_rect(Rect2(c + Vector2(0, -3), Vector2(1, 7)), FROST)
	for d in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
		draw_rect(Rect2(c + d, Vector2.ONE), FROST)


func _patience(r: Rect2, v: float) -> void:
	draw_rect(r, Color(0.8, 0.78, 0.74))
	var col := Color(0.3, 0.75, 0.35) if v > 0.5 else (Color(0.95, 0.7, 0.15) if v > 0.25 else Color(0.9, 0.25, 0.2))
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(v, 0.0, 1.0)), r.size.y)), col)


## Top right, right to left: the money, "Day N", today's weather, then the sound on/off button
## (the stall asks hit_mute()).
func _money() -> void:
	var x := size.x - 4.0
	for t in [Game.fmt(Game.money), "Day %d" % Game.day]:
		var r := Rect2(Vector2(x - _w(t) - 8.0, 3), Vector2(_w(t) + 8.0, LINE_H + 4.0))
		_box(r)
		_text(r.position + Vector2(4, 2), t, INK)
		x = r.position.x - 4.0
	var w := Rect2(Vector2(x - 15.0, 3), Vector2(15, LINE_H + 4.0))
	_box(w)
	_weather_icon(w.get_center(), Game.weather)
	_mute_rect = Rect2(Vector2(w.position.x - 19.0, 3), Vector2(15, LINE_H + 4.0))
	_box(_mute_rect)
	_speaker_icon(_mute_rect.get_center(), Game.muted)


## Generous hit area round the sound button.
func hit_mute(pos: Vector2) -> bool:
	return visible and _mute_rect.size.x > 0 and _mute_rect.grow(5).has_point(pos)


func _box(r: Rect2) -> void:
	draw_rect(r.grow(1), PINK)
	draw_rect(r, PAPER)


func _weather_icon(c: Vector2, w: String) -> void:
	c = c.round()
	if w == "rainy":
		var cloud := Color(0.55, 0.6, 0.68)
		draw_circle(c + Vector2(-2, -1), 2.5, cloud)
		draw_circle(c + Vector2(1.5, -2), 3.0, cloud)
		draw_rect(Rect2(c + Vector2(-5, -1), Vector2(10, 2.5)), cloud)
		for dx in [-3, 0, 3]:
			draw_rect(Rect2(c + Vector2(dx, 3 + absi(dx) % 2), Vector2(1, 2)), Color(0.25, 0.5, 0.95))
	else:
		var sun := Color(1.0, 0.72, 0.1)
		draw_circle(c, 2.5, sun)
		for k in 8:
			var d := Vector2.from_angle(k * TAU / 8.0)
			draw_rect(Rect2((c + d * 4.5).round(), Vector2.ONE), sun)


func _speaker_icon(c: Vector2, off: bool) -> void:
	c = c.round()
	draw_rect(Rect2(c + Vector2(-5, -1), Vector2(2, 3)), INK)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -1), c + Vector2(0, -4), c + Vector2(0, 5),
		c + Vector2(-3, 2)]), INK)
	if off:
		draw_line(c + Vector2(2, -2), c + Vector2(6, 2), PINK, 1.0)
		draw_line(c + Vector2(2, 2), c + Vector2(6, -2), PINK, 1.0)
	else:
		draw_rect(Rect2(c + Vector2(2, -1), Vector2(1, 3)), INK)
		draw_rect(Rect2(c + Vector2(4, -3), Vector2(1, 7)), INK)


## Big "DAY N" in the middle for a moment when a day starts, with a smaller line under it.
func show_banner(text: String, sub := "") -> void:
	_banner = text
	_banner_sub = sub
	_banner_age = 0.0


func _draw_banner() -> void:
	if _banner_age >= BANNER_SECS:
		return
	var a := clampf(minf(_banner_age / 0.3, (BANNER_SECS - _banner_age) / 0.6), 0.0, 1.0)
	var f := UiKit.OUTLINED
	var w := f.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FS).x
	var base := Vector2(roundf((size.x - w) / 2.0), roundf(size.y * 0.4))
	draw_string(f, base, _banner, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FS, Color(1, 1, 1, a))
	if _banner_sub != "":
		var sw := f.get_string_size(_banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, SUB_FS).x
		var sb := Vector2(roundf((size.x - sw) / 2.0), base.y + SUB_FS + 6)
		draw_string(f, sb, _banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, SUB_FS, Color(1, 0.92, 0.6, a))


func _w(t: String) -> float:
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x


## `top_left` is the top of the text line.
func _text(top_left: Vector2, t: String, col: Color) -> void:
	draw_string(_font, top_left + Vector2(0, _font.get_ascent(FS)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col)


func _text_outlined(top_left: Vector2, t: String, col: Color) -> void:
	draw_string(UiKit.OUTLINED, top_left + Vector2(0, _font.get_ascent(FS)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col)
