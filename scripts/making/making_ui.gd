class_name MakingUI
extends Control
## Making-view overlay: order card with a tick per ingredient, step hint at the bottom, name tag
## over the thing being touched, and the result after serving. Never blocks touches except
## the back button.

signal back_pressed

const PAPER := Color(0.99, 0.97, 0.9)
const PINK := Color(0.89, 0.25, 0.44)
const INK := Color(0.16, 0.14, 0.16)
const DONE := Color(0.18, 0.6, 0.3)

var _card: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _hint: Label
var _tag: Label
var _result: PanelContainer
var _result_title: Label
var _result_stars: Stars
var _result_detail: Label
var _back: Button
var _hint_base := ""
var _hint_until := 0.0
var _tag_until := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# top right under BACK: the left side holds the bowl stack, the top left the dev HUD
	_card = _panel(PAPER, PINK)
	add_child(_card)     # placed in _process (its width depends on the order)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	_card.add_child(v)
	_title = _label(PINK)
	v.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	v.add_child(_rows)

	_hint = _label(Color.WHITE, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -14
	_hint.offset_bottom = -3
	add_child(_hint)

	_tag = _label(Color.WHITE, true)
	_tag.visible = false
	add_child(_tag)

	_back = Button.new()
	_back.text = "< BACK"
	_back.add_theme_font_size_override("font_size", 8)
	_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_back.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_back.offset_left = -44
	_back.offset_top = 4
	_back.offset_right = -4
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func(): back_pressed.emit())
	add_child(_back)

	_result = _panel(PAPER, PINK)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.visible = false
	add_child(_result)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	_result.add_child(rv)
	_result_title = _label(PINK)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 16)
	rv.add_child(_result_title)
	_result_stars = Stars.new()
	_result_stars.custom_minimum_size = Vector2(60, 18)
	_result_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(_result_stars)
	_result_detail = _label(INK)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_result_detail)


func set_order(item_id: String) -> void:
	_title.text = RecipeBook.item_name(item_id).to_upper()
	for c in _rows.get_children():
		_rows.remove_child(c)    # now, so refresh() and the card size see only the new rows
		c.queue_free()
	for row in RecipeBook.checklist(item_id, {"base": "", "fill": 0.0, "toppings": [], "sauces": []}):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 3)
		var tick := Tick.new()
		tick.custom_minimum_size = Vector2(7, 9)
		h.add_child(tick)
		var sw := ColorRect.new()
		sw.color = RecipeBook.color(row.id)
		sw.custom_minimum_size = Vector2(5, 5)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var l := _label(INK)
		l.text = RecipeBook.ingredient_name(row.id)
		h.add_child(l)
		h.set_meta("id", row.id)
		_rows.add_child(h)
	_result.visible = false
	_card.visible = true
	_card.reset_size()


func refresh(item_id: String, bowl: Dictionary) -> void:
	var rows := RecipeBook.checklist(item_id, bowl)
	for i in mini(rows.size(), _rows.get_child_count()):
		var h := _rows.get_child(i)
		var done: bool = rows[i].done
		(h.get_child(0) as Tick).done = done
		(h.get_child(2) as Label).add_theme_color_override("font_color", DONE if done else INK)


## Standing hint for the current step.
func set_hint(text: String) -> void:
	_hint_base = text
	if Time.get_ticks_msec() / 1000.0 >= _hint_until:
		_hint.text = text


## Short-lived hint (a nudge after a wrong move); the step hint comes back after it.
func flash_hint(text: String, secs := 1.8) -> void:
	_hint.text = text
	_hint_until = Time.get_ticks_msec() / 1000.0 + secs


func show_tag(text: String, at: Vector2) -> void:
	_tag.text = text
	_tag.reset_size()
	_tag.position = (at - Vector2(_tag.size.x / 2, 18)).clamp(Vector2(2, 2), size - _tag.size - Vector2(2, 2))
	_tag.visible = true
	_tag_until = Time.get_ticks_msec() / 1000.0 + 1.2


func show_result(res: Dictionary) -> void:
	_result_title.text = ["Oops!", "Thank you!", "Very nice!", "Perfect!"][res.stars] if res.correct else "Not quite..."
	_result_stars.count = res.stars
	var names := func(ids: Array) -> String:
		return ", ".join(PackedStringArray(ids.map(func(id): return RecipeBook.ingredient_name(id))))
	var lines := PackedStringArray()
	if not res.missing.is_empty():
		lines.append("Missing: " + names.call(res.missing))
	if not res.extra.is_empty():
		lines.append("Extra: " + names.call(res.extra))
	if res.correct and res.stars < 3:
		lines.append("Hint: a full bowl and no take-backs = 3 stars")
	_result_detail.text = "\n".join(lines)
	_result.visible = true
	_result.reset_size()
	_card.visible = false
	_hint.text = ""


func set_making(on: bool) -> void:
	visible = on
	_result.visible = false
	_tag.visible = false


func _process(_delta: float) -> void:
	_card.position = Vector2(size.x - _card.size.x - 4, 22)
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _hint_until and _hint.text != _hint_base and not _result.visible:
		_hint.text = _hint_base
	if _tag.visible and now >= _tag_until:
		_tag.visible = false


func _label(col: Color, outline := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_font_override("font", UiKit.OUTLINED)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_content_margin_all(4)
	sb.content_margin_top = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


class Tick extends Control:
	var done := false:
		set(v):
			done = v
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(0, 1, 7, 7)
		draw_rect(r, Color(0.7, 0.66, 0.6), false, 1.0)
		if done:
			draw_polyline(PackedVector2Array([Vector2(1, 4), Vector2(3, 7), Vector2(8, 0)]), DONE, 2.0)


class Stars extends Control:
	var count := 0:
		set(v):
			count = v
			queue_redraw()

	func _draw() -> void:
		for i in 3:
			var c := Vector2(10 + i * 20, 9)
			var pts := PackedVector2Array()
			for k in 10:
				var r := 8.0 if k % 2 == 0 else 3.5
				pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * r)
			draw_colored_polygon(pts, Color(1.0, 0.78, 0.15) if i < count else Color(0.8, 0.78, 0.74))
