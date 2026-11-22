extends "res://scripts/frontier.gd"
## Rimefall Plateau, north-east off Spire Canyon (up the switchback trail):
## a high, wind-scoured tundra above the canyon. A frozen lake in the middle,
## ice spires everywhere, a Coalition relay iced solid, a survey sledge stuck
## in the frost, and along the east side a long ridge you climb by a trail
## under rock arches. On the ridge's north summit the Rimefall Stalker keeps
## the Strider's rear legs.

const SELF := "res://plateau.tscn"
const CANYON := "res://canyon.tscn"
const LAKE := Vector3(-8.0, 0.0, 8.0)
const LAKE_R := 20.0
const ICE_Y := 0.05
const SUMMIT := Vector3(24.0, 22.0, -52.0)
const TRAIL := [Vector3(14.0, 0.8, 50.0), Vector3(30.0, 5.0, 36.0), Vector3(22.0, 9.0, 20.0), Vector3(36.0, 13.0, 4.0),
	Vector3(28.0, 17.0, -14.0), Vector3(32.0, 20.0, -32.0), Vector3(24.0, 22.0, -46.0)]

var _guard


func _setup() -> void:
	area_scene = SELF
	area_name = "Rimefall Plateau"
	area_blurb = "Above the canyon, where the crystal freezes."
	rect = Rect2(-50.0, -80.0, 100.0, 160.0)
	terrain_size = 256
	look = {
		"sky_top": Color(0.42, 0.52, 0.64), "sky_horizon": Color(0.82, 0.86, 0.9),
		"ground": Color(0.5, 0.52, 0.56), "fog": Color(0.78, 0.83, 0.9), "fog_density": 0.016,
		"sun": Color(0.86, 0.92, 1.0), "sun_energy": 1.15, "sun_rot": Vector3(-24.0, 200.0, 0.0),
		"ambient": 0.85, "ambient_loop": "forest_loop",
	}
	tree_names = WK.PINES


func _h(x: float, z: float) -> float:
	var h := 1.2 + noise.get_noise_2d(x, z) * 2.2 + noise2.get_noise_2d(x * 1.5, z * 1.5) * 0.8
	# The lake basin.
	var ld := Vector2(x - LAKE.x, z - LAKE.z).length() + noise.get_noise_2d(x * 3.0, z * 3.0) * 3.0
	if ld < LAKE_R + 8.0:
		h = lerpf(h, -1.5, 1.0 - smoothstep(LAKE_R - 2.0, LAKE_R + 8.0, ld))
	# The long ridge down the east side, its crest rising north to the summit.
	var crest := lerpf(8.0, 24.0, smoothstep(50.0, -50.0, z))
	var rd := absf(x - (32.0 + 4.0 * sin(z * 0.06)))
	var ridge := crest * (1.0 - smoothstep(4.0, 16.0, rd + noise.get_noise_2d(x * 2.0, z) * 3.0))
	var f := ridge / 5.0
	ridge = lerpf(ridge, (floorf(f) + smoothstep(0.4, 0.95, f - floorf(f))) * 5.0, 0.6)
	h = maxf(h, ridge)
	# The summit platform.
	var sd := Vector2(x - SUMMIT.x, z - SUMMIT.z).length()
	if sd < 14.0:
		h = lerpf(h, SUMMIT.y, 1.0 - smoothstep(9.0, 14.0, sd))
	# The trail up it.
	var q := _trail_at(x, z)
	if q.x < 7.0:
		h = lerpf(h, q.y, 1.0 - smoothstep(2.6, 7.0, q.x))
	# Low hills round the west and north edges.
	var edge := maxf(-x - 34.0, -z - 66.0)
	h += smoothstep(0.0, 16.0, edge) * 14.0
	return h


func _trail_at(x: float, z: float) -> Vector2:
	var best := Vector2(INF, 0.0)
	var p := Vector2(x, z)
	for i in TRAIL.size() - 1:
		var a := Vector2(TRAIL[i].x, TRAIL[i].z)
		var b := Vector2(TRAIL[i + 1].x, TRAIL[i + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var dd := p.distance_to(a + ab * t)
		if dd < best.x:
			best = Vector2(dd, lerpf(TRAIL[i].y, TRAIL[i + 1].y, t))
	return best


func _paint_at(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var n := noise2.get_noise_2d(x * 3.0, z * 3.0)
	# Frost: everything cold and pale, the trail trodden dark.
	data.set_color(p, Color(0.78, 0.84, 0.92).lerp(Color(0.95, 0.97, 1.0), 0.5 + 0.5 * n))
	var q := _trail_at(x, z)
	if q.x < 4.0:
		data.set_control_auto(p, false)
		data.set_control_base_id(p, 1)
		data.set_control_overlay_id(p, 2)
		data.set_control_blend(p, 1.0 - smoothstep(1.5, 3.5, q.x + n))


func _tree_ok(p: Vector3) -> bool:
	if Vector2(p.x - LAKE.x, p.z - LAKE.z).length() < LAKE_R + 4.0 or _trail_at(p.x, p.z).x < 5.0:
		return false
	return rng.randf() < 0.35


func _plant_trees(count := 700) -> void:
	super._plant_trees(260)


func _entry(_from: String) -> Array:
	return [Vector3(0.0, 0.0, 74.0), 0.0]


func _build_area() -> void:
	exit_to(Vector3(0.0, 0.0, 77.0), "Head down the trail to Spire Canyon", CANYON)
	if terrain != null:
		# Frost-bitten tundra rather than green grass.
		var g = terrain.assets.get_texture_asset(1)
		if g != null:
			g.albedo_color = Color(0.62, 0.68, 0.72)
	_build_lake()
	_build_ice()
	_build_ridge()
	_build_camp()
	_build_snow()
	pack(Vector3(-20.0, 0.0, -20.0), 3)
	pack(Vector3(10.0, 0.0, 30.0), 2)
	pack(Vector3(30.0, 13.0, 4.0), 2, 0.25)
	pack(Vector3(-28.0, 0.0, 44.0), 2)
	MapPoi.add(self, _exits[CANYON], "Trail to Spire Canyon", "exit", "Down the switchbacks into Spire Canyon.")
	MapPoi.add(self, LAKE, "Frozen lake", "landmark", "Solid enough to walk on. Mostly.")
	MapPoi.add(self, SUMMIT, "North summit", "danger", "The top of the ridge. Something big stands up there when it hears you.")


func _build_lake() -> void:
	# Ice sheet over the basin: walkable, glassy.
	var ice := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LAKE_R * 2.6, LAKE_R * 2.6)
	ice.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.86, 0.95, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.1
	m.normal_enabled = true
	m.normal_texture = _noise_tex(256, 0.04, 81, true, 2.0)
	m.uv1_scale = Vector3(3.0, 3.0, 3.0)
	ice.material_override = m
	ice.position = Vector3(LAKE.x, ICE_Y, LAKE.z)
	add_child(ice)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = LAKE_R + 2.0
	cyl.height = 0.4
	cs.shape = cyl
	body.position = Vector3(LAKE.x, ICE_Y - 0.2, LAKE.z)
	body.add_child(cs)
	add_child(body)
	_clear_spots.append([LAKE, LAKE_R + 4.0])
	# Something frozen in it: an escape pod lid and crystal under the ice.
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		crystal_cluster(Vector3(LAKE.x + cos(a) * 9.0, -0.4, LAKE.z + sin(a) * 9.0), 1.2, Color(0.55, 0.85, 1.0))


func _build_ice() -> void:
	var spots := [Vector3(-30.0, 0.0, 20.0), Vector3(-18.0, 0.0, -34.0), Vector3(6.0, 0.0, -40.0), Vector3(-36.0, 0.0, -56.0),
		Vector3(14.0, 0.0, 34.0), Vector3(-34.0, 0.0, 56.0), Vector3(16.0, 0.0, -4.0), Vector3(40.0, 0.0, 60.0)]
	for i in spots.size():
		var p := _on_ground(spots[i].x, spots[i].z, -0.4)
		model("IceSpire", Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * (0.7 + (i % 3) * 0.25)), p))
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.8, 1.0)
		l.light_energy = 0.9
		l.omni_range = 8.0
		l.position = p + Vector3.UP * 3.0
		add_child(l)
		_clear_spots.append([p, 5.0])
	for i in 22:
		var x := rng.randf_range(-44.0, 44.0)
		var z := rng.randf_range(-74.0, 70.0)
		if Vector2(x - LAKE.x, z - LAKE.z).length() < LAKE_R + 3.0:
			continue
		rock(Vector3(x, 0.0, z), rng.randf_range(0.6, 1.5))


func _build_ridge() -> void:
	# Frost-blackened rock arches over the trail.
	for a in [[Vector3(29.0, 11.0, 12.0), 0.9], [Vector3(31.0, 18.5, -23.0), -0.2]]:
		var m := Rock.block(Vector3(12.0, 3.0, 4.0), a[0].x, 0.2)
		Rock.place(self, m, Transform3D(Basis(Vector3.UP, a[1]), a[0] + Vector3.UP * 5.0), true, Rock.material(true, Color(0.85, 0.92, 1.0)))
		for s in [-1.0, 1.0]:
			crag(a[0] + Basis(Vector3.UP, a[1]) * Vector3(s * 5.0, -1.0, 0.0), Vector3(2.5, 7.0, 3.0), a[0].z + s, a[1], 0.2, true)
	# Wind-cut rock ledges along the trail.
	ledge(Vector3(40.0, 13.2, 6.0), Vector3(5.0, 3.0, 4.0), 5.0)
	ledge(Vector3(38.0, 20.2, -30.0), Vector3(6.0, 3.0, 5.0), 6.0)
	# The summit: the guardian and the legs, and a lookout cache.
	var s := Vector3(SUMMIT.x, _ground(SUMMIT), SUMMIT.z)
	for i in 5:
		var a := TAU * i / 5.0
		model("IceSpire", Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * 0.55), s + Vector3(cos(a) * 9.0, -0.3, sin(a) * 9.0)))
	_guard = guardian(s, "stalker", "RIMEFALL STALKER", Color(0.55, 0.85, 1.0), 4.5, {"scale": 1.8, "speed": 1.25, "damage": 1.15})
	droid_part(s + Vector3(-3.0, 0.0, -5.0), "strider_legs_b", ["Leg_LB", "Leg_RB"], _guard)
	cache(s + Vector3(5.0, 0.0, -4.0), "plateau_summit", {"heavy_cell": 2, "crystal": 3, "tech": 2}, 45)
	readable(s + Vector3(-5.0, 0.0, 3.0), "plateau_sledge")


func _build_camp() -> void:
	# The frozen survey sledge (a K-7 cargo pod) and the iced-up Coalition relay.
	var sp := _on_ground(-24.0, -6.0, -0.3)
	model_from("res://models/reach_kit.glb", "CargoPod", Transform3D(Basis(Vector3.UP, 0.7).rotated(Vector3.FORWARD, 0.12), sp))
	cache(sp + Vector3(3.0, 0.3, 2.0), "plateau_sledge", {"scrap": 6, "ration": 2, "plastic": 3}, 25, "Search the sledge")
	var rp := _on_ground(-30.0, -46.0)
	model_from("res://models/reach_kit.glb", "PathfinderBeacon", Transform3D(Basis(Vector3.UP, 0.3).scaled(Vector3.ONE * 1.8), rp))
	readable(rp + Vector3(1.6, 0.0, 1.0), "plateau_relay", "Radio")
	for p in [Vector3(-38.0, 0.0, -10.0), Vector3(12.0, 0.0, -58.0), Vector3(40.0, 0.0, 30.0)]:
		ore_vein(p)
	for p in [Vector3(-16.0, 0.0, -30.0), Vector3(4.0, 0.0, -36.0), Vector3(-38.0, 0.0, 30.0), Vector3(20.0, 0.0, 44.0)]:
		crystal(p)
	cache(Vector3(-40.0, 0.0, 62.0), "plateau_cairn", {"ore": 3, "fiber": 4}, 20, "Search under the cairn")


func _build_snow() -> void:
	# Snow drifting across the plateau (follows the player).
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 1.0, 30.0)
	pm.direction = Vector3(0.4, -1.0, 0.1)
	pm.spread = 15.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(1.5, -1.0, 0.0)
	pm.scale_min = 0.12
	pm.scale_max = 0.24
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	m.albedo_texture = _soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.draw_pass_1 = q
	p.amount = 900
	p.lifetime = 6.0
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	p.position = Vector3(0.0, 14.0, 0.0)
	if player != null:
		player.add_child(p)
	else:
		add_child(p)


func _goal_target(id: String):
	if id == "have:strider_legs_b:1":
		return Vector3(SUMMIT.x, _ground(SUMMIT) + 1.0, SUMMIT.z)
	return null
