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
const ORDER_LINES: Array[String] = [
	"Uncle, one ah!", "Boss, one please!", "Uncle, I want this one", "Hello uncle! One ah",
	"Uncle, one, thank you!",
]
const SUNNY_LINES: Array[String] = ["So hot today... one!", "Wah, sun so strong. One ah!"]
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
			c.patience -= delta / PATIENCE_SECS
			if c.patience <= 0.0:
				c.patience = 0.0
				c.say(GIVE_UP_LINE)
				Game.record_gave_up()
				_leave(c, REACTION_SECS)


## Adds a customer at the back of the queue. Random type (not one already queued) and order.
func spawn(type := "", item := "") -> Customer:
	if type == "":
		var free := templates.keys().filter(func(t): return line.all(func(c): return c.type_id != t))
		type = (free if not free.is_empty() else templates.keys()).pick_random()
	var c := Customer.new(templates[type], type)
	if item == "" and next_order != "":
		item = next_order
		next_order = ""
	c.item_id = item if item != "" else Game.pick_order()
	c.order_line = (ORDER_LINES + (RAINY_LINES if Game.weather == "rainy" else SUNNY_LINES)).pick_random()
	add_child(c)
	c.position = ENTRY
	c.rotation.y = PI / 2
	c.arrived.connect(_on_arrived)
	line.append(c)
	spawned += 1
	_to_slot(c, line.size() - 1)
	return c


## The customer who can be served now: first in line, standing at the counter.
func front() -> Customer:
	if line.is_empty():
		return null
	var c := line[0]
	return c if c.state == Customer.State.WAITING and not c.is_walking() else null


## Served `c` with `item` judged as `res` (RecipeBook.judge). They pay the price of what they
## ordered (no tips), react by stars, and leave. `delay`: pay after this long
## (the camera is still moving back); they can't be tapped again meanwhile.
func serve(c: Customer, res: Dictionary, delay := 0.0) -> void:
	c.state = Customer.State.LEAVING
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
		if not is_instance_valid(c):
			return                       # left for the main menu meanwhile
	var price := RecipeBook.price(c.item_id)
	Game.record_sale(price)
	Sound.play("coin")
	c.say(THANKS[res.stars] if res.correct else WRONG_LINE)
	paid.emit(c, price)
	_leave(c, REACTION_SECS)


func _leave(c: Customer, wait: float) -> void:
	line.erase(c)
	leaving.append(c)
	c.state = Customer.State.LEAVING
	_advance()
	get_tree().create_timer(wait, false).timeout.connect(func():
		if is_instance_valid(c):
			# step out towards the camera first so nobody walks through the queue
			c.walk_to([Vector3(c.position.x + 0.4, 0, 2.1), EXIT]))


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
