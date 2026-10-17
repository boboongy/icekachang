class_name UiKit
## Shared look for the 2D screens: colours, the pixel font (assets/fonts/, painted by
## tools/font/make_font.py; the plain one is the project's default font), paper cards and pink
## buttons. Font size 8 = the font's own pixels; 16 and 24 scale it by whole pixels.

const PAPER := Color(0.99, 0.97, 0.9)
const PINK := Color(0.89, 0.25, 0.44)
const INK := Color(0.16, 0.14, 0.16)
const SOFT := Color(0.45, 0.4, 0.42)
const GREEN := Color(0.18, 0.6, 0.3)
const BTN := Vector2(76, 24)        ## thumb-size at 480x270 on a phone

const FONT := preload("res://assets/fonts/pixel.fnt")
const OUTLINED := preload("res://assets/fonts/pixel_outline.fnt")   ## white text with a dark edge


static func label(col: Color, fs := 8, outlined := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if outlined:
		l.add_theme_font_override("font", OUTLINED)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, on_press: Callable, sz := BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 8)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": PINK, "hover": PINK.lightened(0.1), "pressed": PINK.darkened(0.25),
			"disabled": Color(0.8, 0.78, 0.74)}[state]
		sb.border_color = INK
		sb.border_width_bottom = 2
		sb.set_content_margin_all(3)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.98, 0.96, 0.92))
	b.pressed.connect(func(): Sound.play("click"))
	b.pressed.connect(on_press)
	return b


## Paper card with a pink border, centred on its parent; content goes in the returned card.
static func card(min_w := 220.0) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = PINK
	sb.set_border_width_all(2)
	sb.border_width_top = 5
	sb.set_content_margin_all(8)
	c.add_theme_stylebox_override("panel", sb)
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.custom_minimum_size = Vector2(min_w, 0)
	return c


static func button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	return row


## Full-screen tint that swallows taps meant for the stall behind.
static func dim(alpha := 0.35) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.1, 0.06, 0.1, alpha)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d
