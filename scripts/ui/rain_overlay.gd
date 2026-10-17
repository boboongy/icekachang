class_name RainOverlay
extends Control
## Rainy days, waiting view: a faint grey-blue tint (also dims the glowing signs, which the
## lights don't touch) and thin slanted streaks falling across the screen, drawn in 2D at the
## low internal resolution (cheap on phones). Never takes touches.

const DROPS := 80
const SPEED := Vector2(330.0, 460.0)       ## px per second
const LEN := Vector2(6.0, 11.0)
const SLANT := -0.22                       ## x drift per px of fall
const COLOR := Color(0.8, 0.87, 1.0, 0.55)
const TINT := Color(0.16, 0.2, 0.3, 0.2)

var _drops: Array[Vector3] = []            # x, y, speed


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	var sz := size
	if _drops.is_empty():
		for i in DROPS:
			_drops.append(Vector3(randf() * sz.x, randf() * sz.y, randf_range(SPEED.x, SPEED.y)))
	for i in _drops.size():
		var d := _drops[i]
		d.y += d.z * delta
		d.x += d.z * delta * SLANT
		if d.y > sz.y + LEN.y:
			d = Vector3(randf() * (sz.x + 60.0), -randf() * 20.0, randf_range(SPEED.x, SPEED.y))
		elif d.x < -10.0:
			d.x += sz.x + 20.0
		_drops[i] = d
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TINT)
	for d in _drops:
		var l := lerpf(LEN.x, LEN.y, (d.z - SPEED.x) / (SPEED.y - SPEED.x))
		var p := Vector2(d.x, d.y).round()
		draw_line(p, p - Vector2(SLANT * l, l).round(), COLOR, 1.0)
