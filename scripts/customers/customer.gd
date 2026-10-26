class_name Customer
extends Node3D
## One customer: a copy of a cust_<type> template from assets/models/stall.glb (built by
## tools/blender/build_stall.py) that walks along points, swings its legs, bobs, turns to face
## where it goes, and idles while it waits. The queue (customer_queue.gd) decides where it goes,
## its order and its patience; the bubbles (customer_bubbles.gd) draw what it says.

signal arrived(c: Customer)        ## reached the last point of its path

enum State { WALK_IN, WAITING, LEAVING }

const SPEED := 1.1                 ## m/s
const STRIDE := 6.5                ## leg swing radians per metre walked
const TURN := 9.0
const FACE_STALL := PI             ## yaw that faces the stall (-Z); the models face +Z
const FACE_FRONT := 0.9            ## further back: turned to the front of the queue, face to the camera

var type_id := ""
var item_id := ""                  ## what they ordered
var cold := false                  ## the cold bobo chacha (ice cubes in it)
var item2 := ""                    ## a second, different dessert ("" = one dessert)
var cold2 := false                 ## the second one is the cold bobo chacha
var made := {}                     ## 2-dessert order: item id -> {res, bowl} of the one waiting on the tray
var patience_secs := 60.0          ## seconds from full patience to giving up (set by the queue)
var state := State.WALK_IN
var patience := 1.0                ## 1 = just arrived, 0 = gives up
var order_line := ""               ## the Singlish line in the order bubble
var said := ""                     ## a reaction shown over their head
var said_left := 0.0               ## seconds the reaction stays up
var stand_yaw := FACE_STALL        ## which way to face when standing (set by the queue)

var _model: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _path: Array[Vector3] = []
var _phase := 0.0
var _t := 0.0
var _yaw_goal := FACE_STALL


func _init(template: Node3D, type: String) -> void:
	type_id = type
	_model = template.duplicate()
	_model.transform = Transform3D.IDENTITY
	add_child(_model)
	var prefix := "cust_%s_" % type
	_head = _model.find_child(prefix + "head", true, false)
	for n in ["leg_l", "leg_r"]:
		_legs.append(_model.find_child(prefix + n, true, false))
	_t = randf() * 10.0


## Their order, first dessert first: [{item, cold}], two entries for a 2-dessert order.
func orders() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"item": item_id, "cold": cold}]
	if item2 != "":
		out.append({"item": item2, "cold": cold2})
	return out


func walk_to(points: Array[Vector3]) -> void:
	_path = points.duplicate()


func is_walking() -> bool:
	return not _path.is_empty()


func say(text: String, secs := 2.5) -> void:
	said = text
	said_left = secs


func is_saying() -> bool:
	return said != "" and said_left > 0.0


## World point just above the head, where the bubble's tail points.
func bubble_anchor() -> Vector3:
	return _head.global_position + Vector3(0, 0.36, 0)


## Feet, on the floor.
func feet() -> Vector3:
	return global_position


func _process(delta: float) -> void:
	_t += delta
	said_left -= delta
	if not _path.is_empty():
		_walk(delta)
	else:
		_idle(delta)
	rotation.y = lerp_angle(rotation.y, _yaw_goal, 1.0 - exp(-TURN * delta))


func _walk(delta: float) -> void:
	var to := _path[0]
	var d := to - position
	d.y = 0.0
	var step := SPEED * delta
	if d.length() <= step:
		position = Vector3(to.x, 0.0, to.z)
		_path.pop_front()
		if _path.is_empty():
			if state != State.LEAVING:
				_yaw_goal = stand_yaw
			arrived.emit(self)
	else:
		position += d.normalized() * step
		_yaw_goal = atan2(d.x, d.z)
	_phase += step * STRIDE
	var swing := sin(_phase) * 0.55
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_model.position.y = absf(sin(_phase)) * 0.035
	_head.rotation = Vector3(0, 0, sin(_phase) * 0.04)


func _idle(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	_model.position.y = lerpf(_model.position.y, 0.0, k)
	_legs[0].rotation.x = lerpf(_legs[0].rotation.x, 0.0, k)
	if state == State.WAITING and patience < 0.3:
		# impatient: tap a foot, shake the head now and then
		_legs[1].rotation.x = -absf(sin(_t * 7.0)) * 0.22
		_head.rotation.y = sin(_t * 9.0) * 0.18 if fmod(_t, 3.0) < 0.6 else 0.0
	else:
		_legs[1].rotation.x = lerpf(_legs[1].rotation.x, 0.0, k)
		_head.rotation.y = sin(_t * 0.5) * 0.25 + sin(_t * 1.7) * 0.05   # look around
	_head.rotation.x = sin(_t * 0.9) * 0.05
	_head.rotation.z = lerpf(_head.rotation.z, 0.0, k)


