extends "res://scripts/frontier.gd"
## The Sunken Mire, south-west off Spire Canyon (down the flooded gorge):
## a drowned forest of twisted trees and giant roots. Wade the channels or
## keep dry along the hummocks and the root bridges. A half-sunk escape pod
## from the ORLA'S PROMISE, Vaari root cages in the shallows, a rock island
## with a cave through it, and on the island in the south the Mire
## Matriarch, coiled round the Strider's left cannon.

const SELF := "res://swamp.tscn"
const CANYON := "res://canyon.tscn"
const WATER := 0.0
const ISLAND := Vector3(4.0, 0.0, 50.0)
const ISLAND_R := 16.0
const ISLAND_Y := 4.5
const POD := Vector3(-24.0, 0.0, -18.0)
const CAGES := Vector3(22.0, 0.0, 6.0)
## Dry hummocks: [centre, radius].
const HUMMOCKS := [[Vector3(0.0, 0.0, -70.0), 9.0], [Vector3(-14.0, 0.0, -44.0), 7.0], [Vector3(12.0, 0.0, -30.0), 6.0],
	[Vector3(-6.0, 0.0, -8.0), 7.0], [Vector3(-30.0, 0.0, 10.0), 8.0], [Vector3(14.0, 0.0, 22.0), 6.0], [Vector3(-26.0, 0.0, 40.0), 7.0],
	[Vector3(34.0, 0.0, -50.0), 7.0], [Vector3(36.0, 0.0, 40.0), 6.0], [Vector3(-36.0, 0.0, -60.0), 6.0]]

var _guard


func _setup() -> void:
	area_scene = SELF
	area_name = "Sunken Mire"
	area_blurb = "A drowned forest. Lights move on the water at night."
	rect = Rect2(-50.0, -80.0, 100.0, 160.0)
	terrain_size = 256
	water_y = WATER
	look = {
		"sky_top": Color(0.2, 0.26, 0.22), "sky_horizon": Color(0.46, 0.5, 0.4),
		"ground": Color(0.12, 0.13, 0.1), "fog": Color(0.38, 0.45, 0.36), "fog_density": 0.028,
		"sun": Color(0.95, 0.9, 0.7), "sun_energy": 0.7, "sun_rot": Vector3(-42.0, 60.0, 0.0),
		"ambient": 0.55, "ambient_loop": "forest_loop",
		"water_shallow": Color(0.16, 0.22, 0.12), "water_deep": Color(0.04, 0.07, 0.04),
	}
	tree_names = ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5", "DeadTree_1", "DeadTree_2"]


func _h(x: float, z: float) -> float:
	# Mostly just under the water: wading depth, with deeper channels.
	var h := -0.45 + noise.get_noise_2d(x * 1.5, z * 1.5) * 0.5 - absf(noise2.get_noise_2d(x * 0.6, z * 0.6)) * 0.9
	for hm in HUMMOCKS:
		var d := Vector2(x - hm[0].x, z - hm[0].z).length() + noise.get_noise_2d(x * 4.0, z * 4.0) * 2.0
		h = maxf(h, lerpf(0.7, -0.6, smoothstep(hm[1] * 0.6, hm[1] + 3.0, d)))
	# The rock island (a plateau with sloped banks on the north side).
	var id := Vector2(x - ISLAND.x, z - ISLAND.z).length() + noise.get_noise_2d(x * 2.0, z * 2.0) * 3.0
	if id < ISLAND_R + 6.0:
		var bank := ISLAND_Y * (1.0 - smoothstep(ISLAND_R - 2.0, ISLAND_R + 6.0, id))
		# A ramp up from the north.
		if z < ISLAND.z and absf(x - ISLAND.x) < 4.0:
			bank = maxf(bank, lerpf(ISLAND_Y, 0.4, clampf((ISLAND.z - ISLAND_R + 2.0 - z) / 12.0, 0.0, 1.0)))
		h = maxf(h, bank)
	# Banks rising at the edges.
	var edge := maxf(absf(x) - 38.0, absf(z) - 70.0)
	h += smoothstep(0.0, 14.0, edge) * 10.0
	# The way in from the gorge stays wadeable.
	if z < -66.0 and absf(x) < 8.0:
		h = minf(h, 0.3)
	return h


func _paint_at(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var h := _h(x, z)
	var mud := 1.0 - smoothstep(-0.1, 0.6, h)
	data.set_color(p, Color(0.62, 0.66, 0.5))
	if mud > 0.3:
		data.set_control_auto(p, false)
		data.set_control_base_id(p, 1)
		data.set_control_overlay_id(p, 2)
		data.set_control_blend(p, mud)


func _tree_ok(p: Vector3) -> bool:
	return _h(p.x, p.z) > WATER - 0.35 and Vector2(p.x - ISLAND.x, p.z - ISLAND.z).length() > 10.0


func _entry(_from: String) -> Array:
	return [Vector3(0.0, 0.0, -74.0), PI]


func _build_area() -> void:
	exit_to(Vector3(0.0, 0.0, -77.0), "Head north, back up the gorge to Spire Canyon", CANYON)
	if terrain != null:
		var g = terrain.assets.get_texture_asset(1)
		if g != null:
			g.albedo_color = Color(0.42, 0.48, 0.32)
	# Giant roots arching between the hummocks.
	var roots := [[Vector3(-14.0, 0.0, -44.0), Vector3(-6.0, 0.0, -8.0)], [Vector3(-6.0, 0.0, -8.0), Vector3(14.0, 0.0, 22.0)],
		[Vector3(12.0, 0.0, -30.0), Vector3(34.0, 0.0, -50.0)], [Vector3(-30.0, 0.0, 10.0), Vector3(-26.0, 0.0, 40.0)]]
	for r in roots:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var mid := (a + b) * 0.5
		var yaw := atan2(b.x - a.x, b.z - a.z) + PI * 0.5
		var s := a.distance_to(b) / 18.0
		model("RootArch", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, 0.9, 1.0)), Vector3(mid.x, WATER - 0.3, mid.z)))
	for p in [Vector3(-38.0, 0.0, -20.0), Vector3(30.0, 0.0, 60.0), Vector3(40.0, 0.0, 0.0)]:
		model("RootArch", Transform3D(Basis(Vector3.UP, p.x * 0.1), Vector3(p.x, WATER - 0.5, p.z)))
	# The escape pod, nose down in the shallows.
	var pp := Vector3(POD.x, _ground(POD) - 0.6, POD.z)
	model_from("res://models/reach_kit.glb", "CargoPod", Transform3D(Basis(Vector3.UP, 0.9).rotated(Vector3.RIGHT, 0.35), pp))
	readable(POD + Vector3(4.0, 0.0, 2.5), "swamp_pod")
	cache(POD + Vector3(-3.0, 0.0, 4.0), "swamp_pod", {"medpack": 1, "bandage": 3, "ration": 2}, 25, "Search the pod's locker")
	# Vaari root cages in the shallows.
	for i in 4:
		var c := CAGES + Vector3((i % 2) * 6.0 - 3.0, 0.0, (i / 2) * 6.0 - 3.0)
		_cage(Vector3(c.x, _ground(c), c.z), i)
	readable(CAGES + Vector3(-6.0, 0.0, -4.0), "swamp_cages")
	# The island: a cave through its rock crown, the guardian, the cannon.
	var top := Vector3(ISLAND.x, ISLAND_Y, ISLAND.z)
	crag(top + Vector3(8.0, 0.0, 6.0), Vector3(10.0, 9.0, 8.0), 21.0, 0.6, 0.22, true)
	crag(top + Vector3(-9.0, 0.0, 7.0), Vector3(8.0, 7.0, 9.0), 22.0, -0.4, 0.22, true)
	cave([top + Vector3(-2.0, 0.05, 2.0), top + Vector3(-1.0, 0.05, 9.0), top + Vector3(3.0, 0.05, 15.0)], 3.0, 14.0, Color(0.6, 1.0, 0.5))
	_guard = guardian(top + Vector3(0.0, 0.0, -2.0), "matriarch", "MIRE MATRIARCH", Color(0.6, 1.0, 0.45), 5.0, {"scale": 2.0, "speed": 1.0, "damage": 1.35})
	droid_part(top + Vector3(1.0, 0.0, 12.0), "strider_arm_l", ["Arm_L"], _guard)
	cache(top + Vector3(4.0, 0.0, 17.0), "swamp_island", {"crystal": 3, "tech": 2, "antivenom": 1}, 40, "Search the nest")
	_glow(top + Vector3(0.0, 3.0, 8.0), Color(0.6, 1.0, 0.5), 2.0, 14.0)
	# Rocks, resources, lights on the water, creatures.
	for i in 18:
		rock(Vector3(rng.randf_range(-42.0, 42.0), 0.0, rng.randf_range(-70.0, 70.0)), rng.randf_range(0.5, 1.3))
	for p in [Vector3(-36.0, 0.0, -60.0), Vector3(36.0, 0.0, 40.0), Vector3(-26.0, 0.0, 40.0)]:
		ore_vein(p)
	for p in [Vector3(-14.0, 0.0, -44.0), Vector3(14.0, 0.0, 22.0), Vector3(34.0, 0.0, -50.0), Vector3(-30.0, 0.0, 10.0)]:
		resource(p + Vector3(2.0, 0.0, 1.0), "glowcap", Vector2i(1, 3))
	for p in [Vector3(12.0, 0.0, -30.0), Vector3(-6.0, 0.0, -8.0)]:
		resource(p, "fiber", Vector2i(2, 3))
	crystal(Vector3(ISLAND.x - 6.0, ISLAND_Y, ISLAND.z - 6.0))
	_fireflies()
	pack(Vector3(-6.0, 0.0, -8.0), 3)
	pack(Vector3(30.0, 0.0, -10.0), 2)
	pack(Vector3(-28.0, 0.0, 30.0), 3, 0.2)
	MapPoi.add(self, _exits[CANYON], "Gorge to Spire Canyon", "exit", "Back north up the flooded gorge.")
	MapPoi.add(self, POD, "Escape pod", "landmark", "One of the ORLA'S PROMISE's pods, nose down in the mud.")
	MapPoi.add(self, CAGES, "Root cages", "danger", "Cages woven from living root, half under the water.")
	MapPoi.add(self, ISLAND, "The island", "danger", "A rock island in the south of the mire. Its crown is hollow.")


## A cage of woven root lashed with crystal thread.
func _cage(c: Vector3, i: int) -> void:
	for k in 3:
		var yaw := k * PI / 3.0 + i * 0.4
		model("RootArch", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.16, 0.38, 0.35)), c + Vector3.DOWN * 0.1), k == 0)
	_glow(c + Vector3.UP * 1.0, Color(0.5, 1.0, 0.8), 0.5, 3.0)


func _glow(p: Vector3, col: Color, energy: float, r: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = r
	l.position = p
	add_child(l)


func _fireflies() -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40.0, 1.5, 70.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.scale_min = 0.05
	pm.scale_max = 0.1
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.7, 1.0, 0.5)
	m.albedo_texture = _soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.7, 1.0, 0.5)
	q.material = m
	p.draw_pass_1 = q
	p.amount = 260
	p.lifetime = 8.0
	p.visibility_aabb = AABB(Vector3(-45, -3, -75), Vector3(90, 8, 150))
	p.position = Vector3(0.0, 1.6, 0.0)
	add_child(p)


func _goal_target(id: String):
	if id == "have:strider_arm_l:1":
		return Vector3(ISLAND.x + 1.0, ISLAND_Y + 1.0, ISLAND.z + 12.0)
	return null
