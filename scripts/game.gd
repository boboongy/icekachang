extends Node
## Autoload "Game": the player's progress. Money, unlocked menu items, bought upgrades, the day count and today's
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
## Order weights by dessert kind (data/menu.json "kind") and weather: a gentle pull, so every item still gets ordered.
const ORDER_WEIGHT := {"sunny": {"ice": 1.5, "soup": 1.0}, "rainy": {"ice": 1.0, "soup": 2.0}}
## Shop equipment: only makes things faster (scripts/making/station.gd reads them). Cost in cents.
const UPGRADES := {
	"big_ladle": {"name": "Big ladle", "cost": 4000, "line": "2 ladles fill a bowl"},
	"fast_shaver": {"name": "Fast shaver", "cost": 5000, "line": "shaves in 0.9 s"},
}

var money := 0                      ## cents
var day := 1
var unlocked: Array[String] = []    ## menu item ids customers may order
var upgrades: Array[String] = []    ## UPGRADES ids bought
var today := {}                     ## {served (customers), gave_up, earned, desserts}
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
var _last_order := ""                ## the last pick_order() result


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
	_playtest_money()


## Playtest shortcut (owner): opening the web game with ?money=500 tops the savings up to $500.
## Only on the local test server (localhost or a LAN address), never on the live site.
func _playtest_money() -> void:
	if not OS.has_feature("web"):
		return
	var local := str(JavaScriptBridge.eval(
		"/^(localhost|127\\.|10\\.|192\\.168\\.)/.test(location.hostname) ? '1' : ''")) == "1"
	if not local:
		return
	var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('money') || ''"))
	if q.is_valid_int() and q.to_int() * 100 > money:
		money = q.to_int() * 100
		save_game()


func earn(cents: int) -> void:
	money += cents
	money_changed.emit(money)


## A customer paid `price` cents for `desserts` desserts (no tips: Singaporeans don't tip, owner).
func record_sale(price: int, desserts := 1) -> void:
	today.served += 1
	today.desserts = today.get("desserts", 0) + desserts
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
## Never the same item twice in a row (owner), unless only one item is unlocked.
func pick_order() -> String:
	var weights: Dictionary = ORDER_WEIGHT[weather]
	var pool := unlocked.duplicate()
	if pool.size() > 1:
		pool.erase(_last_order)
	var total := 0.0
	for id in pool:
		total += weights[RecipeBook.menu_item(id).kind]
	var r := randf() * total
	var pick: String = pool.back()
	for id in pool:
		r -= weights[RecipeBook.menu_item(id).kind]
		if r <= 0.0:
			pick = id
			break
	_last_order = pick
	return pick


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
	upgrades.clear()
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
	return day > 1 or money > 0 or unlocked.size() > RecipeBook.makeable(true).size() or not upgrades.is_empty()


## Menu items the shop sells: items the making view can build that do not start unlocked
## (the ones already bought show as owned). Cheapest first.
func shop_items() -> Array[String]:
	var out: Array[String] = []
	for id in RecipeBook.makeable():
		var m := RecipeBook.menu_item(id)
		if not m.start_unlocked and m.has("unlock_cost"):
			out.append(id)
	out.sort_custom(func(a, b): return RecipeBook.unlock_cost(a) < RecipeBook.unlock_cost(b))
	return out


## Shop price of a menu item or an upgrade (cents).
func cost(id: String) -> int:
	return int(UPGRADES[id].cost) if UPGRADES.has(id) else RecipeBook.unlock_cost(id)


## Already bought (on the menu, or the upgrade is in use)?
func owns(id: String) -> bool:
	return id in upgrades or id in unlocked


func has_upgrade(id: String) -> bool:
	return id in upgrades


func can_buy(id: String) -> bool:
	return not owns(id) and money >= cost(id)


## Buys a menu item or an upgrade.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var price := cost(id)
	if UPGRADES.has(id):
		upgrades.append(id)
	else:
		unlocked.append(id)
	earn(-price)
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
		"unlocked": unlocked, "upgrades": upgrades, "muted": muted, "music": music, "quality": quality, "show_fps": show_fps,
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
	upgrades.clear()
	for id in d.get("upgrades", []):
		if UPGRADES.has(id) and not id in upgrades:
			upgrades.append(id)
	money_changed.emit(money)


func _reset_today() -> void:
	today = {"served": 0, "gave_up": 0, "earned": 0, "desserts": 0}


## 250 -> "$2.50"
static func fmt(cents: int) -> String:
	var s := "-" if cents < 0 else ""
	cents = absi(cents)
	return "%s$%d.%02d" % [s, cents / 100, cents % 100]
