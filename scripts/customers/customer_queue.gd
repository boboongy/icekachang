class_name CustomerQueue
extends Node3D
## Customers come in from the left, queue along the display case (up to 3, front first), and
## leave to the right. The front customer is served; the others wait their turn. Patience runs
## down only while nobody is being served (paused = the uncle is making). Running out is free:
## the customer just leaves. A day has a fixed number of customers (`quota`); once they have all
## come and gone, `day_over` fires.
##
## Positions are Blender (x, y) -> Godot (x, 0, -y); see tools/blender/build_stall.py.

signal paid(c: Customer, price: int)
signal day_over

const MAX := 3
## Front first. Along the display, going left, so the uncle (right of the display) stays visible.
const SLOTS: Array[Vector3] = [Vector3(-0.5, 0, 0.5), Vector3(-1.3, 0, 0.8), Vector3(-2.0, 0, 1.1)]
const ENTRY := Vector3(-5.5, 0, 2.0)
const EXIT := Vector3(5.5, 0, 2.5)
const FIRST_SPAWN := 2.0
const SPAWN_SECS := Vector2(8.0, 18.0)
const PATIENCE_SECS := 60.0
const REACTION_SECS := 1.6                        ## stand and react before walking off

const RAIN_SPAWN := 1.3                           ## rainy days: customers come this much slower
const COLD_SHARE := {"sunny": 0.5, "rainy": 0.3}  ## share of bobo chacha orders that are cold
const COLD_LINES: Array[String] = ["Bobo chacha, cold one ah!", "Uncle, bobo chacha cold one please!"]
const TWO_SHARE := 1.0 / 6.0                      ## customers who order two desserts (not day 1, not the tutorial)
const TWO_PATIENCE := 1.6                         ## they wait this much longer
const TWO_LINES: Array[String] = ["Uncle, two ah! This and this.", "Boss, I take two, can?",
	"Two please, one for my friend!"]
const TWO_COLD_LINE := "Two ah! The chacha cold one."
const ORDER_LINES: Array[String] = [
	"Uncle, one ah!", "Boss, one please!", "Uncle, I want this one", "Hello uncle! One ah",
	"Uncle, one, thank you!",
]
const ITEM_SHARE := 0.5                           ## single orders that use their dessert's own line
const ITEM_LINES := {                             ## per dessert (owner: "great" = own Singlish lines)
	"ice_kachang": ["Uncle, ABC one ah!", "Ice kachang, the classic one!"],
	"ice_kachang_mango": ["Mango ice kachang, shiok!", "Uncle, the mango one ah"],
	"ice_kachang_durian": ["Durian one! Smell so power", "Wah, durian ice kachang!"],
	"mango_milk_ice": ["Mango milk ice, my favourite!", "Uncle, mango milk one ah"],
	"chendol": ["Chendol, more gula melaka lah!", "Uncle, chendol one, can?"],
	"chendol_durian": ["Durian chendol, best combo!", "Chendol, durian one ah!"],
	"ice_lychee": ["Ice lychee, so refreshing!", "Uncle, lychee one please"],
	"ice_longan": ["Ice longan, sweet sweet!", "Longan one ah, uncle"],
	"ice_sea_coconut": ["Sea coconut, very cooling!", "Uncle, ice sea coconut ah"],
	"ice_soursop": ["Soursop one! Sour sour nice", "Uncle, ice soursop please"],
	"red_ruby_ice": ["Red ruby please, so pretty!", "Uncle, red ruby one ah"],
	"ice_jelly_cocktail": ["Fruit cocktail, colourful!", "Uncle, jelly cocktail ah!"],
	"tau_suan": ["Tau suan please, uncle!", "Tau suan, with you tiao ah"],
	"green_bean_soup": ["Green bean soup, cooling!", "Uncle, green bean one ah"],
	"red_bean_soup": ["Red bean soup please!", "Uncle, red bean one, can?"],
	"sweet_potato_soup": ["Sweet potato one, warm warm", "Ginger soup please, uncle!"],
	"cheng_tng": ["Cheng tng, like my ah ma's!", "Uncle, cheng tng one please"],
	"bobo_chacha": ["Bobo chacha, hot one ah!", "Uncle, bobo chacha please!"],
	"pulut_hitam": ["Pulut hitam, the black one!", "Uncle, pulut hitam ah"],
}
const SUNNY_LINES: Array[String] =["So hot today... one!", "Wah, sun so strong. One ah!"]
const RAINY_LINES: Array[String] = ["Raining so heavy... one ah", "Wet already. Uncle, one!"]
const THANKS: Array[String] = ["", "Ok, thanks uncle", "Nice, thank you uncle!", "Wah, shiok!"]
const WRONG_LINE := "Eh, not what I order... never mind lah"
const GIVE_UP_LINE := "Aiyo, too long. Next time!"

var line: Array[Customer] = []     ## queued (walking up or waiting), front first
var leaving: Array[Customer] = []
var paused := false                ## patience stops while the uncle is making an order
var frozen := false                ## patience stops during the tutorial too
var next_order := ""               ## the next customer orders this (tutorial); then random again
var templates := {}                ## type id -> template Node3D (out of the tree)
var spawning := true
var quota := -1                    ## customers this day; -1 = endless (tests)
var spawned := 0                   ## customers spawned this day
var two_share := TWO_SHARE         ## tests set 0 (or 1) to control 2-dessert orders

var _spawn_in := FIRST_SPAWN
var _day_open := false


## Takes the cust_<type> templates out of the stall model.
func setup(model: Node3D) -> void:
	for n in model.find_children("cust_*", "", true, false):
		if n is MeshInstance3D:
			continue
		templates[n.name.substr(5)] = n
	for n in templates.values():
		n.get_parent().remove_child(n)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in templates.values():
			n.free()                     # out of the tree, so nothing else frees them


## Opens a day with `n` customers; the first walks up after FIRST_SPAWN seconds.
func start_day(n: int) -> void:
	quota = n
	spawned = 0
	_spawn_in = FIRST_SPAWN
	_day_open = true


func day_quota_spawned() -> bool:
	return quota >= 0 and spawned >= quota


func _process(delta: float) -> void:
	if spawning and not day_quota_spawned():
		_spawn_in -= delta
		if _spawn_in <= 0.0:
			_spawn_in = randf_range(SPAWN_SECS.x, SPAWN_SECS.y) * (RAIN_SPAWN if Game.weather == "rainy" else 1.0)
			if line.size() < MAX:
				spawn()
	if _day_open and day_quota_spawned() and line.is_empty() and leaving.is_empty():
		_day_open = false
		day_over.emit()
	if paused or frozen:
		return
	for c in line.duplicate():
		if c.state == Customer.State.WAITING:
			c.patience -= delta / c.patience_secs
			if c.patience <= 0.0:
				c.patience = 0.0
				c.say(GIVE_UP_LINE)
				Game.record_gave_up()
				_leave(c, REACTION_SECS)


## Adds a customer at the back of the queue. Random type (not one already queued) and order.
## temp: "cold" or "hot" for a bobo chacha; "" = random by COLD_SHARE (the tutorial order never).
## item2: a second dessert; "" = rolled by two_share from day 2 once the tutorial is done.
func spawn(type := "", item := "", temp := "", item2 := "") -> Customer:
	if type == "":
		var free := templates.keys().filter(func(t): return line.all(func(c): return c.type_id != t))
		type = (free if not free.is_empty() else templates.keys()).pick_random()
	var c := Customer.new(templates[type], type)
	var told := false
	if item == "" and next_order != "":
		item = next_order
		next_order = ""
		told = true
	c.item_id = item if item != "" else Game.pick_order()
	c.cold = temp == "cold" or (temp == "" and not told and roll_cold(c.item_id))
	if item2 == "" and not told and item == "" and rolls_two():
		item2 = Game.pick_order()      # never the last pick, so never the same as the first
	if item2 != "" and item2 != c.item_id:
		c.item2 = item2
		c.cold2 = roll_cold(item2)
	c.patience_secs = PATIENCE_SECS * (TWO_PATIENCE if c.item2 != "" else 1.0)
	c.order_line = (ORDER_LINES + (RAINY_LINES if Game.weather == "rainy" else SUNNY_LINES)).pick_random()
	if c.item2 != "":
		c.order_line = TWO_COLD_LINE if c.cold or c.cold2 else TWO_LINES.pick_random()
	elif c.cold:
		c.order_line = COLD_LINES.pick_random()
	elif ITEM_LINES.has(c.item_id) and randf() < ITEM_SHARE:
		c.order_line = ITEM_LINES[c.item_id].pick_random()
	add_child(c)
	c.position = ENTRY
	c.rotation.y = PI / 2
	c.arrived.connect(_on_arrived)
	line.append(c)
	spawned += 1
	_to_slot(c, line.size() - 1)
	return c


## Does the next customer order two desserts? Never on day 1 or before the tutorial is done.
func rolls_two() -> bool:
	return Game.day > 1 and Game.tutorial_done and Game.unlocked.size() > 1 and randf() < two_share


## Is this order the cold version? Only bobo chacha, COLD_SHARE of the time by today's weather.
func roll_cold(item: String) -> bool:
	return RecipeBook.has_cold(item) and randf() < COLD_SHARE.get(Game.weather, 0.5)


## The customer who can be served now: first in line, standing at the counter.
func front() -> Customer:
	if line.is_empty():
		return null
	var c := line[0]
	return c if c.state == Customer.State.WAITING and not c.is_walking() else null


## Served `c` with `item` judged as `res` (RecipeBook.judge; for two desserts the stars are
## their average). They pay the price of what they ordered (both, no tips), react by stars, and leave. `delay`: pay after this long
## (the camera is still moving back); they can't be tapped again meanwhile.
func serve(c: Customer, res: Dictionary, delay := 0.0) -> void:
	c.state = Customer.State.LEAVING
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
		if not is_instance_valid(c):
			return                       # left for the main menu meanwhile
	var price := 0
	for o in c.orders():
		price += RecipeBook.price(o.item)
	Game.record_sale(price, c.orders().size())
	Sound.play("coin")
	c.say(THANKS[res.stars] if res.correct else WRONG_LINE)
	paid.emit(c, price)
	_leave(c, REACTION_SECS)


## The leaver stands and reacts for `wait`, then walks off; the rest move up only then, so
## nobody steps into a spot that is still taken.
func _leave(c: Customer, wait: float) -> void:
	var front := not line.is_empty() and line[0] == c
	line.erase(c)
	leaving.append(c)
	c.state = Customer.State.LEAVING
	get_tree().create_timer(wait, false).timeout.connect(func():
		if is_instance_valid(c):
			c.walk_to(exit_path(c.position, front))
		_advance())


## Round 9: never towards the camera (+Z) and never across the queue. The front customer goes
## straight right along the counter; one further back (gave up) goes back left the way they came.
static func exit_path(from: Vector3, front: bool) -> Array[Vector3]:
	return [Vector3(EXIT.x if front else ENTRY.x, 0, from.z)]


func _advance() -> void:
	for i in line.size():
		if not line[i].position.is_equal_approx(SLOTS[i]):
			_to_slot(line[i], i)


func _on_arrived(c: Customer) -> void:
	match c.state:
		Customer.State.WALK_IN:
			c.state = Customer.State.WAITING
		Customer.State.LEAVING:
			leaving.erase(c)
			c.queue_free()


## Everyone goes, the day closes without day_over (back to the main menu).
func clear() -> void:
	for c in line + leaving:
		c.queue_free()
	line.clear()
	leaving.clear()
	_day_open = false
	quota = -1
	spawned = 0
	next_order = ""
	frozen = false


## Dev (screenshots): a full queue standing at the counter right away.
func debug_fill() -> void:
	while line.size() < MAX:
		var c := spawn()
		c.position = SLOTS[line.size() - 1]
		c.rotation.y = c.stand_yaw
		c.walk_to([c.position])


## Front customer faces the stall; the ones behind turn towards the front (faces to the camera).
func _to_slot(c: Customer, i: int) -> void:
	c.stand_yaw = Customer.FACE_STALL if i == 0 else Customer.FACE_FRONT
	c.walk_to([SLOTS[i]])
