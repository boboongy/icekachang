class_name Menus
extends Control
## The main menu (title over the stall, PLAY or CONTINUE, SETTINGS), the pause card (RESUME,
## SETTINGS, MAIN MENU) and the settings card (sound, music, quality, FPS counter, tutorial
## again, start over). Runs while the tree is paused. Settings are applied by Game and saved.

signal play
signal resume
signal main_menu
signal started_over

const PINK := UiKit.PINK
const INK := UiKit.INK
const SOFT := UiKit.SOFT
const TOGGLE := Vector2(64, 20)

var title_page: Control
var pause_page: Control
var settings_page: Control
var play_button: Button
var settings_button: Button
var resume_button: Button
var pause_settings_button: Button
var main_menu_button: Button
var settings_back_button: Button
var toggles := {}                   ## setting name -> Button (tests press them)

var _continue_line: Label
var _settings_from: Control         # page to go back to
var _tutorial_note: Label
var _confirm_reset := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.3))

	# title: big name over the stall, buttons under it
	title_page = VBoxContainer.new()
	title_page.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title_page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_page.grow_vertical = Control.GROW_DIRECTION_BOTH
	title_page.add_theme_constant_override("separation", 6)
	add_child(title_page)
	var name_l := UiKit.label(Color.WHITE, 24, true)
	name_l.text = "ICE KACHANG"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_page.add_child(name_l)
	var sub := UiKit.label(Color(1, 0.92, 0.6), 8, true)
	sub.text = "A hawker dessert stall"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_page.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	title_page.add_child(gap)
	play_button = UiKit.button("PLAY", func(): play.emit(), Vector2(100, 26))
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_page.add_child(play_button)
	_continue_line = UiKit.label(Color.WHITE, 8, true)
	_continue_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_page.add_child(_continue_line)
	settings_button = UiKit.button("SETTINGS", func(): _open_settings(title_page), Vector2(100, 22))
	settings_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_page.add_child(settings_button)

	# pause card
	pause_page = UiKit.card(150)
	add_child(pause_page)
	var pv := _column(pause_page, "PAUSED")
	resume_button = UiKit.button("RESUME", func(): resume.emit(), Vector2(100, 24))
	pause_settings_button = UiKit.button("SETTINGS", func(): _open_settings(pause_page), Vector2(100, 22))
	main_menu_button = UiKit.button("MAIN MENU", func(): main_menu.emit(), Vector2(100, 22))
	for b in [resume_button, pause_settings_button, main_menu_button]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pv.add_child(b)

	# settings card
	settings_page = UiKit.card(230)
	add_child(settings_page)
	var sv := _column(settings_page, "SETTINGS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(grid)
	_setting(grid, "sound", "Sound", func(): Game.set_muted(not Game.muted))
	_setting(grid, "music", "Music", func(): Game.set_music(not Game.music))
	_setting(grid, "quality", "Quality", func(): Game.set_quality("low" if Game.quality == "high" else "high"))
	_setting(grid, "fps", "FPS counter", func(): Game.set_show_fps(not Game.show_fps))
	_setting(grid, "tutorial", "Tutorial", func(): Game.set_tutorial_done(false))
	_setting(grid, "reset", "Start over", _start_over)
	_tutorial_note = UiKit.label(SOFT)
	_tutorial_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_tutorial_note)
	settings_back_button = UiKit.button("< BACK", func(): _show(_settings_from), Vector2(76, 22))
	settings_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(settings_back_button)


func show_title() -> void:
	var cont := Game.has_progress()
	play_button.text = "CONTINUE" if cont else "PLAY"
	_continue_line.text = "Day %d   %s" % [Game.day, Game.fmt(Game.money)] if cont else ""
	_continue_line.visible = cont
	_show(title_page)


func show_pause() -> void:
	_show(pause_page)


func hide_menus() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _show(page: Control) -> void:
	for p in [title_page, pause_page, settings_page]:
		p.visible = p == page
	visible = true
	_confirm_reset = false
	_refresh()


func _open_settings(from: Control) -> void:
	_settings_from = from
	_show(settings_page)


func _column(card: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)
	var t := UiKit.label(PINK, 16)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


func _setting(grid: GridContainer, key: String, text: String, on_press: Callable) -> void:
	var l := UiKit.label(INK)
	l.text = text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	var b := UiKit.button("", func():
		on_press.call()
		_refresh(), TOGGLE)
	grid.add_child(b)
	toggles[key] = b


func _refresh() -> void:
	toggles.sound.text = "OFF" if Game.muted else "ON"
	toggles.music.text = "ON" if Game.music else "OFF"
	toggles.quality.text = Game.quality.to_upper()
	toggles.fps.text = "ON" if Game.show_fps else "OFF"
	toggles.tutorial.text = "SHOW AGAIN" if Game.tutorial_done else "NEXT ORDER"
	toggles.tutorial.disabled = not Game.tutorial_done
	toggles.reset.text = "SURE? TAP" if _confirm_reset else "START OVER"
	toggles.reset.disabled = not Game.has_progress() and not _confirm_reset
	_tutorial_note.text = "Low quality: no shadows, for slow phones" if Game.quality == "low" else ""
	_tutorial_note.visible = _tutorial_note.text != ""


## Two taps: the first asks, the second wipes the day, money and desserts (settings stay).
func _start_over() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		return
	_confirm_reset = false
	Game.reset_progress()
	started_over.emit()
