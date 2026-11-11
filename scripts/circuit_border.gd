extends Control
## Geometric circuit-board traces drawn as lines only (the world shows
## through). Used along the top and bottom of the title screen.
## A three-lane bus with 45° jogs, branches that end in pads and vias,
## a few chips, and light pulses running along the bus.

@export var color := Color(0.42, 0.8, 1.0)
@export var flip := false          # true = bottom border (mirrored)
@export var band := 120.0          # height of the band in pixels
@export var seed_value := 3

var _lines: Array = []    # PackedVector2Array polylines (band space)
var _pads: Array = []     # [center, radius]
var _vias: Array = []     # centers (filled dots)
var _chips: Array = []    # Rect2
var _bus: PackedVector2Array
var _bus_len := 1.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_generate)
	_generate()


func _generate() -> void:
	_lines.clear()
	_pads.clear()
	_vias.clear()
	_chips.clear()
	var w := size.x
	if w <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lane := 11.0
	var y_min := 26.0
	var y_max := band - 34.0

	# Bus: three parallel lanes that jog together at 45 degrees.
	var pts := PackedVector2Array()
	var x := -20.0
	var y := rng.randf_range(y_min + lane, y_max - lane * 2.0)
	pts.append(Vector2(x, y))
	while x < w + 20.0:
		x += rng.randf_range(90.0, 240.0)
		pts.append(Vector2(x, y))
		var dy := rng.randf_range(10.0, 26.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var ny := clampf(y + dy, y_min, y_max - lane * 2.0)
		dy = ny - y
		x += absf(dy)
		y = ny
		pts.append(Vector2(x, y))
	for k in 3:
		var lanepts := PackedVector2Array()
		for i in pts.size():
			lanepts.append(pts[i] + Vector2(0.0, lane * k))
		_lines.append(lanepts)
	_bus = _lines[1]
	_bus_len = 0.0
	for i in range(1, _bus.size()):
		_bus_len += _bus[i - 1].distance_to(_bus[i])

	# Branches off the outer lane towards the screen edge, ending in pads.
	var bx := rng.randf_range(30.0, 90.0)
	while bx < w - 20.0:
		var by := _y_on(_lines[0], bx)
		var up := rng.randf_range(10.0, by - 8.0)
		if up > 8.0:
			var b := PackedVector2Array([Vector2(bx, by)])
			var mid := Vector2(bx, by - up * 0.5)
			b.append(mid)
			var d := rng.randf_range(-1.0, 1.0) * up * 0.5
			var end := mid + Vector2(d, -absf(d) - 4.0)
			end.y = clampf(end.y, 7.0, by - 6.0)
			b.append(end)
			_lines.append(b)
			_vias.append(Vector2(bx, by))
			_pads.append([end, rng.randf_range(3.0, 5.0)])
		bx += rng.randf_range(45.0, 140.0)

	# Short stubs off the inner lane, into the screen, ending in pads.
	var sx := rng.randf_range(60.0, 160.0)
	while sx < w - 20.0:
		var sy := _y_on(_lines[2], sx)
		var length := rng.randf_range(12.0, 30.0)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var s := PackedVector2Array([Vector2(sx, sy), Vector2(sx, sy + length * 0.5), Vector2(sx + dir * length * 0.5, sy + length)])
		_lines.append(s)
		_vias.append(Vector2(sx, sy))
		_pads.append([s[2], 3.0])
		sx += rng.randf_range(110.0, 300.0)

	# A few chips sitting near the edge, pins wired to the bus.
	var cx := rng.randf_range(160.0, 320.0)
	while cx < w - 120.0:
		var cw := rng.randf_range(44.0, 80.0)
		var r := Rect2(cx, 4.0, cw, 14.0)
		_chips.append(r)
		var px := r.position.x + 6.0
		while px < r.end.x - 4.0:
			var top := _y_on(_lines[0], px)
			if top > r.end.y + 6.0:
				_lines.append(PackedVector2Array([Vector2(px, r.end.y), Vector2(px, top)]))
			px += 9.0
		cx += rng.randf_range(380.0, 700.0)
	queue_redraw()


func _y_on(line: PackedVector2Array, x: float) -> float:
	for i in range(1, line.size()):
		if x <= line[i].x:
			var a := line[i - 1]
			var b := line[i]
			var t := 0.0 if b.x == a.x else (x - a.x) / (b.x - a.x)
			return lerpf(a.y, b.y, t)
	return line[line.size() - 1].y


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _map(p: Vector2) -> Vector2:
	return Vector2(p.x, size.y - p.y) if flip else p


func _draw() -> void:
	var glow := Color(color.r, color.g, color.b, 0.12)
	for l in _lines:
		var m := PackedVector2Array()
		for p in l:
			m.append(_map(p))
		draw_polyline(m, glow, 6.0, true)
		draw_polyline(m, color, 1.6, true)
	for v in _vias:
		draw_circle(_map(v), 3.2, color)
	for pd in _pads:
		draw_arc(_map(pd[0]), pd[1], 0.0, TAU, 16, color, 1.5, true)
		draw_circle(_map(pd[0]), pd[1] * 0.35, color)
	for r in _chips:
		var a := _map(r.position)
		var b := _map(r.end)
		var rr := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
		draw_rect(rr, Color(color.r, color.g, color.b, 0.08), true)
		draw_rect(rr, color, false, 1.5)
	# Light pulses running along the middle lane.
	if _bus.size() > 1:
		for k in 3:
			var d := fmod(_t * 260.0 + k * _bus_len / 3.0, _bus_len)
			var p := _point_at(d)
			draw_circle(_map(p), 9.0, Color(color.r, color.g, color.b, 0.12))
			draw_circle(_map(p), 4.5, Color(color.r, color.g, color.b, 0.45))
			draw_circle(_map(p), 2.2, Color(0.9, 0.97, 1.0))


func _point_at(d: float) -> Vector2:
	for i in range(1, _bus.size()):
		var seg := _bus[i - 1].distance_to(_bus[i])
		if d <= seg:
			return _bus[i - 1].lerp(_bus[i], d / maxf(seg, 0.001))
		d -= seg
	return _bus[_bus.size() - 1]
