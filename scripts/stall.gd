extends Node3D
## The stall scene: the hawker stall from assets/models/stall.glb (built by
## tools/blender/build_stall.py), sunny day lighting, waiting view with idle motion and the
## customer queue (scripts/customers/*), and the first-person making view (scripts/making/*).
## Tap the front customer (or their bubble) to make their order; serve it and they pay.
## A day is Game.quota() customers; when the last has left, the day summary and shop show
## (scripts/ui/day_panel.gd). Each day is sunny or rainy (Game.weather): rain dims the light,
## falls over the waiting view (scripts/ui/rain_overlay.gd) and plays its loop. The speaker
## button in the HUD mutes all sound.
## It opens on the main menu (scripts/ui/menus.gd). The pause button (top left; Esc or P on a
## keyboard) pauses and offers the settings and the way back to the main menu; losing window or
## tab focus pauses too. A new game's first order runs the tutorial (scripts/ui/tutorial.gd).
## Dev: M = make a random order with no customer. Q = quality high/low (shadows).
## Command line (after --): --shot saves screenshots and quits; --selftest (making view),
## --custtest (customers, end to end), --daytest / --daycheck (day loop, shop, save; see
## scripts/ui/daytest.gd) and --tuttest / --tutcheck (main menu, tutorial, settings; see
## scripts/ui/tuttest.gd) drive the game with fake touches and quit with exit code 0 (pass)
## or 1 (fail). Only normal runs and --tuttest/--tutcheck open on the main menu.

const STALL_GLB := preload("res://assets/models/stall.glb")
const SUN_COLOR := Color(1.0, 0.72, 0.4)   ## golden hour (owner): deep warm yellow, not white
const PAUSE_RECT := Rect2(4, 3, 15, 13)    ## HUD pause button (screen px)
## Vertical FOV per view; positions come from the cam_<view> markers in the glb.
## Keep in sync with CAMERAS in tools/blender/build_stall.py (preview renders).
const VIEW_FOV := {"waiting": 46.0, "making": 50.0}
const LIGHT := {
	"sunny": {"bg": Color(0.98, 0.8, 0.55), "ambient": Color(0.96, 0.84, 0.68), "ambient_energy": 0.32,
		"contrast": 1.12, "saturation": 1.2, "fog": Color(1.0, 0.86, 0.66), "fog_density": 0.0015,
		"sun": SUN_COLOR, "sun_energy": 1.6},
	"rainy": {"bg": Color(0.4, 0.45, 0.52), "ambient": Color(0.66, 0.72, 0.84), "ambient_energy": 0.4,
		"contrast": 1.04, "saturation": 0.88, "fog": Color(0.42, 0.47, 0.54), "fog_density": 0.006,
		"sun": Color(0.78, 0.84, 0.96), "sun_energy": 0.42},
}

var cam: Camera3D
var sun: DirectionalLight3D
var uncle: Node3D
var station: MakingStation
var queue: CustomerQueue
var bubbles: CustomerBubbles
var day_panel: DayPanel
var rain: RainOverlay
var menus: Menus
var tutorial: Tutorial

var _model: Node3D
var _env: Environment
var _portrait := false
var _unfocused := false
var _menu_paused := false            # pause card or its settings open
var _in_title := false               # main menu showing; no day running
var _pause_button: Control
var _day_done_pending := false       # the day ended during a dev order; show it once back
var _serving: Customer               # whose order is being made (null for a dev order)
var _fps_label: Label
var _rotate_overlay: Control
var _making := false
var _t := 0.0
var _uncle_head: Node3D
var _uncle_arms: Array[Node3D] = []
var _fans: Array[Node3D] = []
var _views := {}     # view name -> Transform3D


func _ready() -> void:
	_model = STALL_GLB.instantiate()
	add_child(_model)
	RetroMaterials.apply(_model)
	for view in VIEW_FOV:
		var at := (_model.find_child("cam_" + view, true, false) as Node3D).global_position
		var target := (_model.find_child("cam_%s_target" % view, true, false) as Node3D).global_position
		_views[view] = Transform3D.IDENTITY.translated(at).looking_at(target, Vector3.UP)
	var roof := _model.find_child("roof", true, false) as GeometryInstance3D
	if roof:
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # open-sided hall: let the sun in
	uncle = _model.find_child("uncle", true, false)
	_uncle_head = uncle.find_child("uncle_head", true, false)
	for n in ["uncle_arm_l", "uncle_arm_r"]:
		_uncle_arms.append(uncle.find_child(n, true, false))
	for n in ["fan_1", "fan_2"]:
		_fans.append(_model.find_child(n, true, false))

	rain = RainOverlay.new()
	_build_environment()
	cam = Camera3D.new()
	cam.fov = VIEW_FOV.waiting
	cam.global_transform = _views.waiting
	add_child(cam)
	var making_ui := MakingUI.new()
	making_ui.visible = false
	station = MakingStation.new()
	add_child(station)
	station.setup(_model, cam, making_ui)
	station.finished.connect(_on_served)
	station.cancelled.connect(func():
		_serving = null                  # they keep waiting
		_set_view("waiting"))
	queue = CustomerQueue.new()
	add_child(queue)
	queue.setup(_model)
	bubbles = CustomerBubbles.new(queue, cam)
	queue.day_over.connect(_on_day_over)
	day_panel = DayPanel.new()
	day_panel.next_day.connect(_start_day)
	menus = Menus.new()
	menus.play.connect(_on_play)
	menus.resume.connect(_resume)
	menus.main_menu.connect(_to_title)
	menus.started_over.connect(_to_title)
	tutorial = Tutorial.new(self)
	_build_ui(making_ui)
	Game.settings_changed.connect(_apply_settings)
	_apply_settings()
	get_viewport().size_changed.connect(_on_size_changed)
	_on_size_changed()
	var args := OS.get_cmdline_user_args()
	if "--shot" in args:
		_take_shots()
	elif "--selftest" in args or "--custtest" in args:
		queue.spawning = "--custtest" in args     # the making test runs without customers
		var test: Node = (preload("res://scripts/customers/custtest.gd") if "--custtest" in args
			else preload("res://scripts/making/selftest.gd")).new()
		add_child(test)
		test.run(self)                           # endless queue: no day quota
	elif "--daytest" in args or "--daycheck" in args:
		_start_day()
		var test: Node = preload("res://scripts/ui/daytest.gd").new()
		add_child(test)
		test.run(self)
	else:
		_to_title()
		if "--tuttest" in args or "--tutcheck" in args:
			var test: Node = preload("res://scripts/ui/tuttest.gd").new()
			add_child(test)
			test.run(self)


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 1.4
	_env.adjustment_enabled = true
	_env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 22.0
	sun.rotation_degrees = Vector3(-32, -38, 0)  # low golden-hour sun from the front-left, reaches into the stall
	add_child(sun)
	_apply_weather("sunny")


## Light for the day's weather. Sunny: less ambient + strong warm sun = deep shade and bright
## sun patches. Rainy: soft grey daylight, cooler and less saturated, a little haze.
func _apply_weather(w: String) -> void:
	var s: Dictionary = LIGHT[w]
	_env.background_color = s.bg
	_env.ambient_light_color = s.ambient
	_env.ambient_light_energy = s.ambient_energy
	_env.adjustment_contrast = s.contrast
	_env.adjustment_saturation = s.saturation
	_env.fog_light_color = s.fog
	_env.fog_density = s.fog_density
	sun.light_color = s.sun
	sun.light_energy = s.sun_energy
	rain.visible = w == "rainy" and not _making
	Sound.set_rain(w == "rainy")


func _build_ui(making_ui: MakingUI) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(rain)
	layer.add_child(bubbles)
	layer.add_child(making_ui)
	layer.add_child(tutorial)
	layer.add_child(day_panel)
	_pause_button = Control.new()
	_pause_button.mouse_filter = Control.MOUSE_FILTER_IGNORE   # hit-tested in _input
	_pause_button.position = PAUSE_RECT.position
	_pause_button.size = PAUSE_RECT.size
	_pause_button.draw.connect(func():
		var r := Rect2(Vector2.ZERO, PAUSE_RECT.size)
		_pause_button.draw_rect(r.grow(1), UiKit.PINK)
		_pause_button.draw_rect(r, UiKit.PAPER)
		_pause_button.draw_rect(Rect2(5, 3, 2, 7), UiKit.INK)
		_pause_button.draw_rect(Rect2(9, 3, 2, 7), UiKit.INK))
	layer.add_child(_pause_button)
	_fps_label = UiKit.label(Color.WHITE, 8, true)
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_fps_label.offset_left = 3
	_fps_label.offset_top = -12
	layer.add_child(_fps_label)
	layer.add_child(menus)

	# Browsers cannot lock orientation, so ask portrait players to turn the phone.
	_rotate_overlay = ColorRect.new()
	(_rotate_overlay as ColorRect).color = Color(0.93, 0.32, 0.5)
	_rotate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var msg := Label.new()
	msg.text = "ICE KACHANG\n\nPlease turn your phone\nsideways to play"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_font_override("font", UiKit.OUTLINED)
	_rotate_overlay.add_child(msg)
	layer.add_child(_rotate_overlay)


func _on_size_changed() -> void:
	var size := get_viewport().get_visible_rect().size
	_portrait = size.x < size.y
	_rotate_overlay.visible = _portrait
	_update_pause()


func _update_pause() -> void:
	get_tree().paused = _portrait or _unfocused or _menu_paused


## Pause while the window or browser tab is in the background, and open the pause card so the
## player comes back to it (not in dev/test runs, which often run unfocused).
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if not OS.get_cmdline_user_args().is_empty() or not is_inside_tree():
		return
	_unfocused = what == NOTIFICATION_APPLICATION_FOCUS_OUT
	if _unfocused and _can_pause():
		pause()
	_update_pause()


## Settings from Game (menus change them): quality = sun shadows, FPS counter.
func _apply_settings() -> void:
	sun.shadow_enabled = Game.quality == "high"
	_fps_label.visible = Game.show_fps


## The main menu over the idle stall. Leaving a day half way drops it: it starts again from its
## first customer (money already earned stays).
func _to_title() -> void:
	_menu_paused = false
	_update_pause()
	if _making:
		_serving = null
		_set_view("waiting")
	cam.global_transform = _views.waiting
	cam.fov = VIEW_FOV.waiting
	_day_done_pending = false
	tutorial.stop()
	queue.clear()
	queue.spawning = false
	Game.restart_today()
	day_panel.hide_panel()
	bubbles.visible = false
	_in_title = true
	menus.show_title()


func _on_play() -> void:
	menus.hide_menus()
	_in_title = false
	queue.spawning = true
	_start_day()


func _can_pause() -> bool:
	return not _in_title and not menus.is_open() and not day_panel.visible


func pause() -> void:
	_menu_paused = true
	_update_pause()
	menus.show_pause()


func _resume() -> void:
	menus.hide_menus()
	_menu_paused = false
	_update_pause()
	_maybe_tutorial()


## Runs the tutorial if it is not done yet (new game, or asked for again in the settings).
func _maybe_tutorial() -> void:
	if not Game.tutorial_done and not tutorial.active() and not _in_title:
		tutorial.start()


## Opens day Game.day: its customers start walking up.
func _start_day() -> void:
	_apply_weather(Game.weather)
	queue.start_day(Game.quota())
	bubbles.visible = not _making
	bubbles.show_banner("DAY %d" % Game.day, "Rainy day" if Game.weather == "rainy" else "Sunny day")
	Sound.play("day")
	_maybe_tutorial()


## Summary of the day just finished. The HUD hides meanwhile (it already counts the next day;
## the summary shows the money).
func _show_summary() -> void:
	bubbles.visible = false
	day_panel.show_summary()


## The last customer of the day has gone: autosave and show the summary (once back in the
## waiting view if a dev order is being made).
func _on_day_over() -> void:
	Game.end_day()
	if _making:
		_day_done_pending = true
	else:
		_show_summary()


func _process(delta: float) -> void:
	_t += delta
	for fan in _fans:
		fan.rotate_y(delta * 5.0)
	# Uncle idles: slow breathing, little head look-around, arms sway.
	uncle.position.y = sin(_t * 1.6) * 0.008
	_uncle_head.rotation.y = sin(_t * 0.37) * 0.25 + sin(_t * 1.3) * 0.04
	_uncle_head.rotation.x = sin(_t * 0.8) * 0.04
	_uncle_arms[0].rotation.x = sin(_t * 1.1) * 0.06
	_uncle_arms[1].rotation.x = sin(_t * 1.1 + 1.0) * 0.06
	_pause_button.visible = _can_pause()
	if _fps_label.visible:
		_fps_label.text = "FPS %d  tris %d  calls %d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]


## The pause button goes first, before the making station picks the touch.
func _input(event: InputEvent) -> void:
	if not _can_pause():
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P)
	var tap: bool = event is InputEventScreenTouch and event.pressed and PAUSE_RECT.grow(5).has_point(event.position)
	if key or tap:
		Sound.play("click")
		pause()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _in_title or menus.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			Game.set_quality("low" if Game.quality == "high" else "high")
		elif event.keycode == KEY_M and not _making and not day_panel.visible:
			start_order()
	elif event is InputEventScreenTouch and event.pressed and not _making and not day_panel.visible:
		var c := bubbles.hit_front(event.position)
		if bubbles.hit_mute(event.position):
			Game.set_muted(not Game.muted)
			Sound.play("click")
		elif c:
			start_order(c.item_id, c)


## Go to the making view for `item_id` (random from the unlocked menu if empty), made for
## customer `c` (null = dev order, nobody pays).
func start_order(item_id := "", c: Customer = null) -> void:
	if item_id == "":
		item_id = Game.unlocked.pick_random()
	_serving = c
	_set_view("making")
	station.begin(item_id)


func _on_served(_item: String, res: Dictionary) -> void:
	var c := _serving
	_serving = null
	_set_view("waiting")
	if c:
		queue.serve(c, res, 0.5)   # pay once the camera is nearly back, so the reaction is seen


func _set_view(view: String) -> void:
	_making = view == "making"
	if not _making:
		station.end()
		if _day_done_pending:
			_day_done_pending = false
			_show_summary()
	queue.paused = _making
	bubbles.visible = not _making and not day_panel.visible
	rain.visible = Game.weather == "rainy" and not _making
	uncle.visible = not _making
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "global_transform", _views[view], 0.7)
	tw.tween_property(cam, "fov", VIEW_FOV[view], 0.7)


## Dev only: save a screenshot of each view to build/ and quit. The waiting shot has a full
## queue; the making shot is staged half way through an ice kachang so the bowl, toppings and
## syrup show, the soup shot with a finished tau suan; then the day summary and the shop with
## made-up numbers (shots never save). Menus and tutorial steps 1 and 2 come first.
func _take_shots() -> void:
	queue.spawning = false
	queue.debug_fill()
	for view in ["title", "settings", "pause", "waiting", "rainy", "tut_wait", "tut_make",
			"making", "bowl_zoom", "soup", "summary", "shop"]:
		if view == "title":
			menus.show_title()
		elif view == "settings":
			menus._open_settings(menus.title_page)
		elif view == "pause":
			menus.show_pause()
		elif view == "waiting":
			menus.hide_menus()
		elif view == "rainy":
			Game.weather = "rainy"
			_apply_weather("rainy")
			bubbles.show_banner("DAY 2", "Rainy day")
		elif view == "tut_wait":
			Game.weather = "sunny"
			_apply_weather("sunny")
			tutorial.start()
		elif view == "tut_make":
			start_order("ice_kachang")
		elif view == "making":
			tutorial.stop()
			station.debug_stage()
		elif view == "bowl_zoom":    # close look at the glass bowls (stack + the one being made)
			cam.fov = 22.0
			cam.look_at(station.bowl.global_position.lerp(station._spot.bowl_stack, 0.5) + Vector3(0, 0.06, 0))
		elif view == "soup":
			_set_view("making")
			station.begin("tau_suan")
			station.debug_stage()
		elif view == "summary":
			_set_view("waiting")
			Game.last_day = {"day": 3, "served": 9, "gave_up": 1, "earned": 2280}
			Game.money = 2550
			_show_summary()
		elif view == "shop":
			day_panel._show_page(true)
		for i in 60:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://build/shot_%s.png" % view))
		print("PERF view=%s fps=%d tris=%d calls=%d" % [view, Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()
