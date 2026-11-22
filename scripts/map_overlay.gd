extends Control
## Drawn over the top-down map: an icon and name for every place on the map
## (MapPoi nodes), arrows at the edge for places out of view, your own arrow,
## a north marker and a scale bar. The pause menu feeds it each refresh.

const MapPoi = preload("res://scripts/map_poi.gd")
const WorldMap = preload("res://scripts/world_map.gd")

## WORLD view: every area on one map (world_map.gd) instead of the local
## top-down view. world_you is your world-map position, world_here your scene.
var world_mode := false
var world_you := Vector2.ZERO
var world_here := ""

var centre := Vector3.ZERO      # world position at the middle of the map
var px_per_m := 4.0
var player_yaw := 0.0
var pois: Array = []            # [{pos, label, kind}]

const EDGE := 22.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func to_map(p: Vector3) -> Vector2:
	# North (-Z) is up, east (+X) is right.
	return size * 0.5 + Vector2(p.x - centre.x, p.z - centre.z) * px_per_m


func _draw() -> void:
	var font := get_theme_default_font()
	if world_mode:
		_draw_world(font)
		return
	var inner := Rect2(Vector2(EDGE, EDGE), size - Vector2(EDGE, EDGE) * 2.0)
	for poi in pois:
		var mp := to_map(poi["pos"])
		var col: Color = MapPoi.colour(poi["kind"])
		if inner.has_point(mp):
			_icon(mp, poi["kind"], col)
			_text(font, mp + Vector2(12, 5), poi["label"], 14, col)
		else:
			# Off the map: pin it to the edge, pointing the way.
			var dir := (mp - size * 0.5).normalized()
			var edge := _clip_to_rect(size * 0.5, dir, inner)
			var dist := Vector2(poi["pos"].x - centre.x, poi["pos"].z - centre.z).length()
			_edge_arrow(edge, dir, col)
			var t := "%s  %d m" % [poi["label"], int(dist)]
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tp := edge - dir * 16.0 + Vector2(-w * 0.5, 4)
			tp.x = clampf(tp.x, 4.0, size.x - w - 4.0)
			tp.y = clampf(tp.y, 14.0, size.y - 6.0)
			_text(font, tp, t, 12, col)
	# You.
	var c := size * 0.5
	var fwd := Vector2(-sin(player_yaw), -cos(player_yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := c + fwd * 13.0
	var pts := PackedVector2Array([tip, c - fwd * 8.0 + side * 8.0, c - fwd * 4.0, c - fwd * 8.0 - side * 8.0])
	draw_colored_polygon(pts, Color(1.0, 0.3, 0.2))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.8), 1.5)
	# North marker.
	var n := Vector2(size.x - 30.0, 34.0)
	draw_colored_polygon(PackedVector2Array([n + Vector2(0, -16), n + Vector2(7, 4), n + Vector2(-7, 4)]), Color(0.86, 0.13, 0.1))
	_text(font, n + Vector2(-5, 22), "N", 16, Color.WHITE)
	# Scale bar: 25 m.
	var bar := 25.0 * px_per_m
	var b0 := Vector2(16.0, size.y - 18.0)
	draw_line(b0, b0 + Vector2(bar, 0), Color.WHITE, 2.0)
	draw_line(b0, b0 + Vector2(0, -6), Color.WHITE, 2.0)
	draw_line(b0 + Vector2(bar, 0), b0 + Vector2(bar, -6), Color.WHITE, 2.0)
	_text(font, b0 + Vector2(bar + 6.0, 4.0), "25 m", 13, Color.WHITE)


## Every area on one map, fitted to the panel. North up.
func _draw_world(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.06))
	var shapes := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for scene in WorldMap.areas():
		var pts: PackedVector2Array = WorldMap.outline(scene)
		shapes[scene] = pts
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
	var margin := 40.0
	var span := hi - lo
	var s := minf((size.x - margin * 2.0) / maxf(span.x, 1.0), (size.y - margin * 2.0) / maxf(span.y, 1.0))
	var origin := size * 0.5 - (lo + span * 0.5) * s
	var tf := func(p: Vector2) -> Vector2: return origin + p * s

	var offs: Dictionary = WorldMap.offsets()
	for scene in WorldMap.areas():
		var here: bool = scene == world_here
		var poly := PackedVector2Array()
		for p in shapes[scene]:
			poly.append(tf.call(p))
		var fill := Color(0.25, 0.42, 0.22, 0.85) if here else Color(0.16, 0.24, 0.15, 0.75)
		draw_colored_polygon(poly, fill)
		var ring := poly.duplicate()
		ring.append(poly[0])
		draw_polyline(ring, Color(1.0, 0.8, 0.3) if here else Color(0.45, 0.55, 0.45), 2.0 if here else 1.0)
		for path in WorldMap.lines(scene):
			var line := PackedVector2Array()
			for p in path:
				line.append(tf.call(p))
			if line.size() > 1:
				draw_polyline(line, Color(0.72, 0.62, 0.42), 2.0)
		# Name, to the right of the area.
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= float(poly.size())
		var right := -INF
		for p in poly:
			right = maxf(right, p.x)
		_text(font, Vector2(right + 8.0, c.y + 5.0), WorldMap.AREAS[scene]["name"].to_upper(), 14,
				Color(1.0, 0.85, 0.4) if here else Color(0.85, 0.85, 0.9))
	# Where each area's exit meets the next one's entrance.
	for link in WorldMap.links():
		var sc: String = link[0]
		var p: Vector2 = tf.call(offs[sc] + WorldMap.exit_to(sc, link[1]))
		_icon(p, "exit", MapPoi.colour("exit"))
	# You.
	if world_here != "":
		var c := tf.call(world_you) as Vector2
		var fwd := Vector2(-sin(player_yaw), -cos(player_yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var pts := PackedVector2Array([c + fwd * 11.0, c - fwd * 7.0 + side * 7.0, c - fwd * 3.0, c - fwd * 7.0 - side * 7.0])
		draw_colored_polygon(pts, Color(1.0, 0.3, 0.2))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.8), 1.5)
	# North marker and a 100 m scale bar.
	var n := Vector2(size.x - 30.0, 34.0)
	draw_colored_polygon(PackedVector2Array([n + Vector2(0, -16), n + Vector2(7, 4), n + Vector2(-7, 4)]), Color(0.86, 0.13, 0.1))
	_text(font, n + Vector2(-5, 22), "N", 16, Color.WHITE)
	var bar := 100.0 * s
	var b0 := Vector2(16.0, size.y - 18.0)
	draw_line(b0, b0 + Vector2(bar, 0), Color.WHITE, 2.0)
	draw_line(b0, b0 + Vector2(0, -6), Color.WHITE, 2.0)
	draw_line(b0 + Vector2(bar, 0), b0 + Vector2(bar, -6), Color.WHITE, 2.0)
	_text(font, b0 + Vector2(bar + 6.0, 4.0), "100 m", 13, Color.WHITE)


func _text(font: Font, p: Vector2, t: String, fs: int, col: Color) -> void:
	draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _icon(p: Vector2, kind: String, col: Color) -> void:
	var outline := Color(0, 0, 0, 0.85)
	match kind:
		"camp":
			draw_circle(p, 8.0, outline)
			draw_circle(p, 6.0, col)
			draw_circle(p, 2.5, Color(0.1, 0.05, 0.02))
		"exit":
			var pts := PackedVector2Array([p + Vector2(-7, -7), p + Vector2(8, 0), p + Vector2(-7, 7), p + Vector2(-3, 0)])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), outline, 1.5)
		"objective":
			var star := PackedVector2Array()
			for i in 10:
				var r := 9.0 if i % 2 == 0 else 4.0
				var a := -PI * 0.5 + i * PI / 5.0
				star.append(p + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(star, col)
			star.append(star[0])
			draw_polyline(star, outline, 1.5)
		"resource":
			var r := Rect2(p - Vector2(5, 5), Vector2(10, 10))
			draw_rect(r.grow(1.5), outline)
			draw_rect(r, col)
		"danger":
			var tri := PackedVector2Array([p + Vector2(0, -9), p + Vector2(8, 6), p + Vector2(-8, 6)])
			draw_colored_polygon(tri, col)
			tri.append(tri[0])
			draw_polyline(tri, outline, 1.5)
			draw_line(p + Vector2(0, -4), p + Vector2(0, 1), Color.BLACK, 2.0)
		_:
			var d := PackedVector2Array([p + Vector2(0, -8), p + Vector2(7, 0), p + Vector2(0, 8), p + Vector2(-7, 0)])
			draw_colored_polygon(d, col)
			d.append(d[0])
			draw_polyline(d, outline, 1.5)


func _edge_arrow(p: Vector2, dir: Vector2, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * 10.0, p - dir * 4.0 + side * 7.0, p - dir * 4.0 - side * 7.0])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.85), 1.5)


## Where a ray from `o` along `d` leaves `r`.
func _clip_to_rect(o: Vector2, d: Vector2, r: Rect2) -> Vector2:
	var t := INF
	if absf(d.x) > 0.0001:
		t = minf(t, ((r.end.x if d.x > 0.0 else r.position.x) - o.x) / d.x)
	if absf(d.y) > 0.0001:
		t = minf(t, ((r.end.y if d.y > 0.0 else r.position.y) - o.y) / d.y)
	return o + d * t
