class_name DayPanel
extends Control
## End-of-day screen over the waiting view: a calm summary (served, went home, earned,
## total money) with SHOP and NEXT DAY, and the shop page that sells menu items
## (Game.shop_items). Nothing here can fail; money only goes up except when buying.

signal next_day

const PINK := UiKit.PINK
const INK := UiKit.INK
const SOFT := UiKit.SOFT

var _summary: VBoxContainer
var _shop: VBoxContainer
var _title: Label
var _stats: GridContainer
var _shop_rows: VBoxContainer
var _shop_money: Label
var shop_button: Button
var next_button: Button
var shop_back_button: Button
var buy_buttons := {}               ## item id -> Button (tests press them)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # nothing behind takes taps while it shows
	visible = false
	add_child(UiKit.dim())
	var card := UiKit.card()
	add_child(card)
	var pages := VBoxContainer.new()
	card.add_child(pages)

	# summary page
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 6)
	pages.add_child(_summary)
	_title = UiKit.label(PINK, 16)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_child(_title)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 16)
	_stats.add_theme_constant_override("v_separation", 1)
	_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_summary.add_child(_stats)
	var row := UiKit.button_row()
	_summary.add_child(row)
	shop_button = UiKit.button("SHOP", func(): _show_page(true))
	next_button = UiKit.button("NEXT DAY >", func():
		hide_panel()
		next_day.emit())
	row.add_child(shop_button)
	row.add_child(next_button)

	# shop page
	_shop = VBoxContainer.new()
	_shop.add_theme_constant_override("separation", 6)
	pages.add_child(_shop)
	var st := UiKit.label(PINK, 16)
	st.text = "SHOP"
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop.add_child(st)
	_shop_money = UiKit.label(INK)
	_shop_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop.add_child(_shop_money)
	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 4)
	_shop.add_child(_shop_rows)
	var srow := UiKit.button_row()
	_shop.add_child(srow)
	shop_back_button = UiKit.button("< BACK", func(): _show_page(false))
	srow.add_child(shop_back_button)


## Shows the summary of Game.last_day.
func show_summary() -> void:
	var d := Game.last_day
	_title.text = "DAY %d DONE" % d.day
	for c in _stats.get_children():
		c.free()
	_stat("Served", str(d.served))
	_stat("Went home", str(d.gave_up))
	_stat("Earned", Game.fmt(d.earned))
	_stat("Money", Game.fmt(Game.money), PINK)
	_build_shop()
	_show_page(false)
	visible = true


func hide_panel() -> void:
	visible = false


func _show_page(shop: bool) -> void:
	_summary.visible = not shop
	_shop.visible = shop
	if shop:
		_refresh_shop()


func _stat(name: String, value: String, col := INK) -> void:
	var a := UiKit.label(SOFT)
	a.text = name
	_stats.add_child(a)
	var b := UiKit.label(col)
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.add_child(b)


func _build_shop() -> void:
	for c in _shop_rows.get_children():
		c.free()
	buy_buttons.clear()
	for id in Game.shop_items():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = RecipeBook.item_color(id)
		sw.custom_minimum_size = Vector2(8, 8)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := UiKit.label(INK)
		n.text = RecipeBook.item_name(id)
		v.add_child(n)
		var p := UiKit.label(SOFT)
		p.text = "sells for %s a bowl" % Game.fmt(RecipeBook.price(id))
		v.add_child(p)
		h.add_child(v)
		var b := UiKit.button("", _buy.bind(id))
		h.add_child(b)
		buy_buttons[id] = b
		_shop_rows.add_child(h)
	if buy_buttons.is_empty():
		var l := UiKit.label(SOFT)
		l.text = "More desserts coming soon!"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_shop_rows.add_child(l)


func _refresh_shop() -> void:
	_shop_money.text = "You have " + Game.fmt(Game.money)
	for id in buy_buttons:
		var b: Button = buy_buttons[id]
		if id in Game.unlocked:
			b.text = "ON MENU"
			b.disabled = true
		else:
			b.text = "BUY " + Game.fmt(RecipeBook.unlock_cost(id))
			b.disabled = not Game.can_buy(id)


func _buy(id: String) -> void:
	if Game.buy(id):
		_refresh_shop()
		_stats.get_child(_stats.get_child_count() - 1).text = Game.fmt(Game.money)
