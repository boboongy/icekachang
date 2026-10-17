extends Node
## Autoload "Game": the player's progress. Money, unlocked menu items, the day count and today's
## takings; saved to user://save.json after every payment, purchase and day end (plus the mute
## and the settings when they change). Each day is sunny or rainy (weather_for: fixed per day number, so a
## restart replays the same weather); rain means fewer customers who mostly want warm soup.
## Command line (after --): --savefile <user://path> uses another save file; --fresh deletes it
## first; --weather sunny|rainy forces the weather. Test runs (--selftest, --custtest, --shot)
## without --savefile never load or save, so they can't touch the owner's save.
## Settings (sound, music, quality, FPS counter) and whether the tutorial is done live in the
## same save; settings_changed tells the stall to apply them.

signal money_changed(cents: int)
signal settings_changed

const SAVE_VERSION := 1
const FIRST_QUOTA := 8              ## customers on day 1
const MAX_QUOTA := 14
const RAIN_CHANCE := 0.3            ## day 1 is always sunny
const RAIN_QUOTA := 0.7             ## rainy days have this share of the customers
## Order weights by dessert kind (data/menu.json "kind") and weather.
const ORDER_WEIGHT := {"sunny": {"ice": 3.0, "soup": 1.0}, "rainy": {"ice": 1.0, "soup": 5.0}}

var money := 0                      ## cents
var day := 1
var unlocked: Array[String] = []    ## menu item ids customers may order
var today := {}                     ## {served, gave_up, earned}
var save_path := "user://save.json" ## "" = never save
var weather := "sunny"              ## today's weather: "sunny" or "rainy"
var weather_override := ""          ## tests and --weather: force every day's weather
var muted := false
var music := true                   ## music loop on (sound effects follow `muted` only)
var quality := "high"               ## "high" = sun shadows on, "low" = off (for slow phones)
var show_fps := false
var tutorial_done := false          ## the 3-step tutorial runs on the first order until this is set

## Last finished day, for the summary: today's numbers plus {day}.
var last_day := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--savefile")
	if i >= 0 and i + 1 < args.size():
		save_path = args[i + 1]
	elif "--selftest" in args or "--custtest" in args or "--shot" in args:
		save_path = ""
	if "--fresh" in args and save_path != "" and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	var w := args.find("--weather")
	if w >= 0 and w + 1 < args.size():
		weather_override = args[w + 1]
	_reset_today()
	unlocked = RecipeBook.makeable(true)
	load_game()
	weather = weather_for(day)


func earn(cents: int) -> void:
	money += cents
	money_changed.emit(money)


## A customer paid `price` cents (no tips: Singaporeans don't tip, owner).
func record_sale(price: int) -> void:
	today.served += 1
	today.earned += price
	earn(price)
	save_game()


func record_gave_up() -> void:
	today.gave_up += 1


## Customers today (fixed per day, one more each day; fewer when it rains).
func quota() -> int:
	var n := mini(FIRST_QUOTA + day - 1, MAX_QUOTA)
	return roundi(n * RAIN_QUOTA) if weather == "rainy" else n


## Weather of day `d`: the same for a given day number every time. Day 1 is sunny.
func weather_for(d: int) -> String:
	if weather_override != "":
		return weather_override
	if d <= 1:
		return "sunny"
	var rng := RandomNumberGenerator.new()
	rng.seed = d * 7919 + 13
	return "rainy" if rng.randf() < RAIN_CHANCE else "sunny"


## What the next customer orders: an unlocked item, weighted by kind and today's weather.
func pick_order() -> String:
	var weights: Dictionary = ORDER_WEIGHT[weather]
	var total := 0.0
	for id in unlocked:
		total += weights[RecipeBook.menu_item(id).kind]
	var r := randf() * total
	for id in unlocked:
		r -= weights[RecipeBook.menu_item(id).kind]
		if r <= 0.0:
			return id
	return unlocked.back()


## The day's last customer has left: keep its numbers for the summary, move on, autosave.
func end_day() -> void:
	last_day = today.duplicate()
	last_day.day = day
	last_day.weather = weather
	day += 1
	weather = weather_for(day)
	_reset_today()
	save_game()


func set_muted(on: bool) -> void:
	muted = on
	Sound.set_muted(on)
	save_game()
	settings_changed.emit()


func set_music(on: bool) -> void:
	music = on
	Sound.set_music(on)
	save_game()
	settings_changed.emit()


func set_quality(q: String) -> void:
	quality = q
	save_game()
	settings_changed.emit()


func set_show_fps(on: bool) -> void:
	show_fps = on
	save_game()
	settings_changed.emit()


func set_tutorial_done(done: bool) -> void:
	tutorial_done = done
	save_game()


## Start over: day 1, no money, start menu, tutorial again. Settings are kept.
func reset_progress() -> void:
	money = 0
	day = 1
	unlocked = RecipeBook.makeable(true)
	tutorial_done = false
	weather = weather_for(day)
	_reset_today()
	last_day = {}
	save_game()
	money_changed.emit(money)


## A day left half way (back to the main menu): it starts again from its first customer.
## Money already earned stays, as when the tab is closed.
func restart_today() -> void:
	_reset_today()


## Anything to continue (vs a brand-new game)?
func has_progress() -> bool:
	return day > 1 or money > 0 or unlocked.size() > RecipeBook.makeable(true).size()


## Menu items the shop sells: v1 items the making view can build that are not unlocked yet,
## plus the ones already bought (shown as owned). Menu order.
func shop_items() -> Array[String]:
	var out: Array[String] = []
	for id in RecipeBook.makeable():
		var m := RecipeBook.menu_item(id)
		if m.v1 and not m.start_unlocked and m.has("unlock_cost"):
			out.append(id)
	return out


func can_buy(item_id: String) -> bool:
	return not item_id in unlocked and money >= RecipeBook.unlock_cost(item_id)


func buy(item_id: String) -> bool:
	if not can_buy(item_id):
		return false
	unlocked.append(item_id)
	earn(-RecipeBook.unlock_cost(item_id))
	save_game()
	return true


func save_game() -> void:
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "money": money, "day": day,
		"unlocked": unlocked, "muted": muted, "music": music, "quality": quality, "show_fps": show_fps,
		"tutorial_done": tutorial_done}))
	f.close()


func load_game() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not d is Dictionary:
		push_warning("save unreadable, starting fresh")
		return
	money = int(d.get("money", 0))
	day = maxi(1, int(d.get("day", 1)))
	muted = bool(d.get("muted", false))
	music = bool(d.get("music", true))
	quality = "low" if d.get("quality", "high") == "low" else "high"
	show_fps = bool(d.get("show_fps", false))
	tutorial_done = bool(d.get("tutorial_done", day > 1))   # saves from before the tutorial
	var known := RecipeBook.makeable()
	for id in d.get("unlocked", []):
		if id in known and not id in unlocked:     # start items are always there
			unlocked.append(id)
	money_changed.emit(money)


func _reset_today() -> void:
	today = {"served": 0, "gave_up": 0, "earned": 0}


## 250 -> "$2.50"
static func fmt(cents: int) -> String:
	var s := "-" if cents < 0 else ""
	cents = absi(cents)
	return "%s$%d.%02d" % [s, cents / 100, cents % 100]
