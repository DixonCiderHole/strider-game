extends "res://scripts/frontier.gd"
## Glowmire Caverns, north-west off Spire Canyon: a deep, narrow fungal gorge
## that the sun barely reaches. Giant glowcaps, crystal-lit caves, a pool
## under a waterfall, a trail up the east wall to a hidden alcove, and at
## the far end the brood chamber where the Glowmire Broodmother sits on the
## Strider's front legs.

const SELF := "res://caverns.tscn"
const CANYON := "res://canyon.tscn"
const WALL := 42.0
const CHAMBER := Vector3(0.0, 0.0, -52.0)
const RAMP := [[Vector3(14.0, 0.3, 44.0), Vector3(22.0, 5.0, 26.0), Vector3(14.0, 9.5, 12.0), Vector3(22.0, 14.0, -4.0), Vector3(26.0, 14.5, -14.0)], 5.0]
const ALCOVE := Vector3(27.0, 14.5, -16.0)
const POOL := Vector3(-14.0, 0.0, 22.0)

var _guard


func _setup() -> void:
	area_scene = SELF
	area_name = "Glowmire Caverns"
	area_blurb = "Where the glowcaps grow as tall as trees."
	rect = Rect2(-50.0, -80.0, 100.0, 160.0)
	terrain_size = 256
	water_y = -0.4
	look = {
		"sky_top": Color(0.08, 0.14, 0.16), "sky_horizon": Color(0.16, 0.3, 0.3),
		"ground": Color(0.06, 0.1, 0.1), "fog": Color(0.12, 0.3, 0.3), "fog_density": 0.03,
		"sun": Color(0.55, 0.8, 0.85), "sun_energy": 0.35, "sun_rot": Vector3(-70.0, 160.0, 0.0),
		"ambient": 0.35, "ambient_loop": "forest_loop",
		"water_shallow": Color(0.06, 0.3, 0.28), "water_deep": Color(0.01, 0.06, 0.07),
	}
	tree_names = []


## The gorge's half width at z (narrow at the mouth, wide in the chamber).
func _hw(z: float) -> float:
	var w := 18.0 + 6.0 * sin(z * 0.05)
	w = lerpf(w, 7.0, smoothstep(58.0, 76.0, z))
	w = lerpf(w, 30.0, 1.0 - smoothstep(10.0, 26.0, absf(z - CHAMBER.z)))
	return w


func _cx(z: float) -> float:
	return 6.0 * sin(z * 0.035)


func _h(x: float, z: float) -> float:
	var d := absf(x - _cx(z))
	var hw := _hw(z)
	var t := smoothstep(hw, hw + 9.0, d + noise.get_noise_2d(x, z) * 4.0)
	var h := t * (WALL + noise2.get_noise_2d(x * 0.5, z * 0.5) * 6.0)
	h += noise.get_noise_2d(x * 2.5, z * 2.5) * 0.8 + 0.6
	# The pool under the waterfall.
	var pd := Vector2(x - POOL.x, z - POOL.z).length()
	if pd < 11.0:
		h = minf(h, lerpf(-2.2, h, smoothstep(4.0, 11.0, pd)))
	# The trail up the east wall.
	var q := _ramp_at(RAMP[0], x, z)
	if q.x < 6.5:
		h = lerpf(h, q.y, 1.0 - smoothstep(2.5, 6.5, q.x))
	var ad := Vector2(x - ALCOVE.x, z - ALCOVE.z).length()
	if ad < 9.0:
		h = lerpf(h, ALCOVE.y, 1.0 - smoothstep(5.0, 9.0, ad))
	return h


func _ramp_at(pts: Array, x: float, z: float) -> Vector2:
	var best := Vector2(INF, 0.0)
	var p := Vector2(x, z)
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var dd := p.distance_to(a + ab * t)
		if dd < best.x:
			best = Vector2(dd, lerpf(pts[i].y, pts[i + 1].y, t))
	return best


func _paint_at(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var n := noise2.get_noise_2d(x * 4.0, z * 4.0)
	var d := absf(x - _cx(z))
	var w := 1.0 - smoothstep(_hw(z) - 4.0, _hw(z), d + n * 2.0)
	if w > 0.3:
		data.set_control_auto(p, false)
		data.set_control_base_id(p, 1)
		data.set_control_overlay_id(p, 2)
		data.set_control_blend(p, w)
		data.set_color(p, Color(0.45, 0.55, 0.5))


func _entry(_from: String) -> Array:
	return [Vector3(_cx(74.0), 0.0, 74.0), 0.0]


func _build_area() -> void:
	exit_to(Vector3(_cx(77.0), 0.0, 77.0), "Head south, back to Spire Canyon", CANYON)
	# Giant glowcaps along the floor, smaller ones clustered between.
	var spots := [[-10.0, 50.0, 1.0], [12.0, 30.0, 0.8], [-16.0, 2.0, 1.1], [14.0, -24.0, 0.9], [-20.0, -40.0, 1.2], [20.0, -60.0, 1.0],
		[-6.0, -70.0, 0.9], [8.0, 60.0, 0.7]]
	for s in spots:
		var p := _on_ground(s[0], s[1], -0.2)
		model("GiantShroomA" if int(s[1]) % 2 == 0 else "GiantShroomB", Transform3D(Basis(Vector3.UP, s[0] * 0.3).scaled(Vector3.ONE * s[2]), p))
		_glow(p + Vector3.UP * 6.0 * s[2], Color(0.25, 1.0, 0.8), 2.2, 14.0)
	for i in 26:
		var z := rng.randf_range(-74.0, 70.0)
		var x := _cx(z) + rng.randf_range(-_hw(z) + 3.0, _hw(z) - 3.0)
		var p := _on_ground(x, z, -0.1)
		if p.y < 0.0:
			continue
		model("GiantShroomB", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.18, 0.35)), p), false)
		if i % 3 == 0:
			_glow(p + Vector3.UP * 1.5, Color(0.3, 1.0, 0.75), 0.8, 5.0)
	# Crystal clusters on the walls.
	for i in 14:
		var z := rng.randf_range(-70.0, 70.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := _cx(z) + side * (_hw(z) + 1.0)
		crystal_cluster(_on_ground(x, z, -0.3), rng.randf_range(0.7, 1.3), Color(0.3, 1.0, 0.85))
	# The waterfall into the pool, off the west wall.
	var fx := _cx(POOL.z) - _hw(POOL.z) - 1.0
	waterfall(Vector3(fx + 2.0, WALL - 2.0, POOL.z), Vector3(fx + 2.0, water_y, POOL.z), 5.0, PI * 0.5)
	# A cave through a rock spur on the west side (a short cut past the pool).
	crag(Vector3(-17.0, 0.0, -12.0), Vector3(12.0, 10.0, 20.0), 3.0, 0.1, 0.22, true)
	cave([_on_ground(-6.0, -2.0, 0.1), _on_ground(-18.0, -8.0, 0.1), _on_ground(-20.0, -20.0, 0.1), _on_ground(-8.0, -26.0, 0.1)], 3.0, 9.0, Color(0.3, 1.0, 0.8))
	# Rock arches spanning the gorge overhead.
	for z in [36.0, -30.0]:
		var c := _cx(z)
		var span := _hw(z) * 2.0 + 10.0
		var y := WALL * 0.62
		var m := Rock.block(Vector3(span, 4.0, 5.0), z, 0.22)
		Rock.place(self, m, Transform3D(Basis(Vector3.UP, 0.15), Vector3(c, y, z)), true, Rock.material(true))
	# The hidden alcove up the east trail.
	ledge(Vector3(ALCOVE.x - 4.0, ALCOVE.y + 0.1, ALCOVE.z + 2.0), Vector3(6.0, 2.0, 5.0), 4.0)
	cache(Vector3(ALCOVE.x + 1.0, ALCOVE.y + 0.2, ALCOVE.z - 1.0), "caverns_alcove", {"crystal": 3, "tech": 2, "heavy_cell": 1}, 40)
	readable(Vector3(ALCOVE.x - 1.5, 0.0, ALCOVE.z + 1.5), "caverns_survey", "Datapad", ALCOVE.y + 0.25)
	_glow(Vector3(ALCOVE.x, ALCOVE.y + 2.5, ALCOVE.z), Color(1.0, 0.7, 0.35), 1.2, 7.0)
	# The brood chamber.
	readable(CHAMBER + Vector3(-18.0, 0.0, 8.0), "caverns_cocoons")
	for i in 10:
		var a := TAU * i / 10.0
		var p := CHAMBER + Vector3(cos(a) * 22.0, 0.0, sin(a) * 18.0)
		crag(p, Vector3(3.0, 7.0 + (i % 3) * 3.0, 3.0), float(i), a, 0.25, true)
		crystal_cluster(_on_ground(p.x * 0.85, CHAMBER.z + (p.z - CHAMBER.z) * 0.85), 1.0, Color(0.3, 1.0, 0.85))
	_glow(CHAMBER + Vector3(0.0, 9.0, 0.0), Color(0.3, 1.0, 0.8), 3.0, 30.0)
	_guard = guardian(CHAMBER, "broodmother", "GLOWMIRE BROODMOTHER", Color(0.3, 1.0, 0.75), 5.0,
		{"scale": 1.9, "speed": 0.9, "damage": 1.3})
	droid_part(CHAMBER + Vector3(2.0, 0.0, -8.0), "strider_legs_f", ["Leg_LF", "Leg_RF"], _guard)
	cache(CHAMBER + Vector3(-6.0, 0.0, -14.0), "caverns_brood", {"tissue": 3, "crystal": 2}, 35, "Search the remains")
	# Resources.
	for p in [Vector3(-14.0, 0.0, 44.0), Vector3(16.0, 0.0, 4.0), Vector3(-18.0, 0.0, -58.0)]:
		ore_vein(p)
	for p in [Vector3(10.0, 0.0, 52.0), Vector3(-4.0, 0.0, -10.0), Vector3(18.0, 0.0, -46.0), Vector3(-12.0, 0.0, -66.0)]:
		crystal(p)
	for p in [Vector3(4.0, 0.0, 40.0), Vector3(-8.0, 0.0, 14.0), Vector3(10.0, 0.0, -36.0)]:
		resource(p, "glowcap", Vector2i(1, 2))
	pack(Vector3(_cx(30.0), 0.0, 30.0), 3)
	pack(Vector3(_cx(-14.0), 0.0, -14.0), 3, 0.2)
	pack(Vector3(ALCOVE.x - 4.0, ALCOVE.y, ALCOVE.z + 6.0), 2)
	MapPoi.add(self, _exits[CANYON], "Way to Spire Canyon", "exit", "The slot gorge south, back to Spire Canyon.")
	MapPoi.add(self, CHAMBER, "Brood chamber", "danger", "Something huge nests here, on top of what it took from the drop pod.")
	MapPoi.add(self, ALCOVE, "Alcove", "landmark", "A dry alcove up the east wall. The trail up starts near the mouth of the gorge.")


func _glow(p: Vector3, col: Color, energy: float, r: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = r
	l.position = p
	add_child(l)


func _goal_target(id: String):
	if id == "have:strider_legs_f:1":
		return CHAMBER + Vector3(2.0, 1.0, -8.0)
	return null
