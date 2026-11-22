extends "res://scripts/frontier.gd"
## The wreck of the VIGILANT, south-east off Spire Canyon (up the ridge
## trail): the Ascendancy cruiser that dropped the supply pods, broken on a
## high stony plateau. A long scorched furrow leads to its torn bow; inside
## is hangar two: a 60 m deck under the ribs, catwalks up to the upper deck,
## crew lockers and the bridge recorder still looping. Something armoured
## has moved into the hangar, and it has the Strider's right arm mount.

const SELF := "res://vigilant.tscn"
const CANYON := "res://canyon.tscn"
const HULL := Vector3(0.0, 0.0, 4.0)      # hangar section centre (deck level)
const HULL_L := 60.0
const HULL_HW := 15.0
const STERN := Vector3(9.0, -1.2, 62.0)    # the second, broken-off section

var _guard
var _lights: Array = []
var _t := 0.0


func _setup() -> void:
	area_scene = SELF
	area_name = "Wreck of the VIGILANT"
	area_blurb = "Ascendancy cruiser. Escort for the K-7 advance teams."
	rect = Rect2(-50.0, -80.0, 100.0, 160.0)
	terrain_size = 256
	look = {
		"sky_top": Color(0.3, 0.33, 0.4), "sky_horizon": Color(0.72, 0.6, 0.48),
		"ground": Color(0.2, 0.18, 0.16), "fog": Color(0.62, 0.58, 0.54), "fog_density": 0.012,
		"sun": Color(1.0, 0.82, 0.62), "sun_energy": 1.1, "sun_rot": Vector3(-28.0, 30.0, 0.0),
		"ambient": 0.6, "ambient_loop": "forest_loop",
	}
	tree_names = WK.DEAD


func _in_hull(x: float, z: float, pad := 0.0) -> bool:
	return absf(x - HULL.x) < HULL_HW - 1.0 + pad and absf(z - HULL.z) < HULL_L * 0.5 + pad


func _h(x: float, z: float) -> float:
	var h := 1.0 + noise.get_noise_2d(x, z) * 2.0 + noise2.get_noise_2d(x * 2.0, z * 2.0) * 0.5
	# The furrow the hull ploughed on its way in.
	var fd := absf(x - HULL.x - (z - HULL.z) * 0.05)
	if z < HULL.z:
		h = lerpf(h, -0.2 + fd * 0.04, 1.0 - smoothstep(8.0, 18.0, fd))
	# Rubble banked up against the hull sides.
	var sx := absf(x - HULL.x)
	if absf(z - HULL.z) < HULL_L * 0.5 + 4.0:
		h = maxf(h, 3.5 * (1.0 - smoothstep(HULL_HW, HULL_HW + 9.0, sx)) + noise.get_noise_2d(x * 3.0, z * 3.0))
	# Under the deck: keep the ground below it.
	if _in_hull(x, z, 0.5):
		h = minf(h, -0.8)
	# Rocky edges.
	var edge := maxf(absf(x) - 38.0, absf(z) - 70.0)
	h += smoothstep(0.0, 14.0, edge) * 12.0
	if z < -66.0 and absf(x) < 8.0:
		h = minf(h, 1.5 + noise.get_noise_2d(x, z))
	return h


func _paint_at(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var n := noise2.get_noise_2d(x * 4.0, z * 4.0)
	var fd := absf(x - HULL.x - (z - HULL.z) * 0.05)
	var burn := 0.0
	if z < HULL.z + HULL_L * 0.5:
		burn = 1.0 - smoothstep(6.0, 16.0, fd + n * 3.0)
	burn = maxf(burn, 1.0 - smoothstep(HULL_HW, HULL_HW + 12.0, absf(x - HULL.x) + n * 3.0) if absf(z - HULL.z) < HULL_L * 0.5 + 6.0 else 0.0)
	if burn > 0.2:
		data.set_control_auto(p, false)
		data.set_control_base_id(p, 1)
		data.set_control_overlay_id(p, 2)
		data.set_control_blend(p, burn)
		data.set_color(p, Color.WHITE.lerp(Color(0.18, 0.16, 0.14), burn * 0.8))


func _tree_ok(p: Vector3) -> bool:
	return not _in_hull(p.x, p.z, 14.0) and rng.randf() < 0.4


func _plant_trees(count := 700) -> void:
	super._plant_trees(140)


func _entry(_from: String) -> Array:
	return [Vector3(0.0, 0.0, -74.0), PI]


func _build_area() -> void:
	exit_to(Vector3(0.0, 0.0, -77.0), "Head north, down the ridge to Spire Canyon", CANYON)
	var deck := Vector3(HULL.x, -0.2, HULL.z)
	model("HangarShell", Transform3D(Basis.IDENTITY, deck))
	_clear_spots.append([HULL, 40.0])
	# The broken-off stern section, tipped over beyond.
	model("HangarShell", Transform3D(Basis(Vector3.UP, 0.35).rotated(Vector3.BACK, 0.22), STERN))
	# Debris along the furrow.
	for i in 9:
		var z := lerpf(-62.0, HULL.z - 34.0, i / 8.0)
		var x := HULL.x + (z - HULL.z) * 0.05 + rng.randf_range(-12.0, 12.0)
		model_from("res://models/reach_kit.glb", "HullPlate", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)), _on_ground(x, z, -0.3)))
	model("Bulkhead", Transform3D(Basis(Vector3.UP, 0.4).rotated(Vector3.RIGHT, -1.35), _on_ground(-24.0, -36.0, 0.4)))
	model("SupplyDrop", Transform3D(Basis(Vector3.UP, 2.1), _on_ground(28.0, -44.0, -0.2)))
	_build_hangar(deck)
	_build_outside()


func _build_hangar(deck: Vector3) -> void:
	var top := deck.y + 0.2
	# Catwalks to the upper deck on both sides.
	model("HangarGantry", Transform3D(Basis.IDENTITY, Vector3(HULL.x - 9.5, top, HULL.z - 14.0)))
	model("HangarGantry", Transform3D(Basis(Vector3.UP, PI), Vector3(HULL.x + 9.5, top, HULL.z + 12.0)))
	# Red emergency lights (they flicker) and the strip lights.
	for z in range(-26, 27, 10):
		_lights.append(_light(Vector3(HULL.x, top + 9.0, HULL.z + z), Color(1.0, 0.25, 0.18), 1.4, 14.0))
	for s in [-1.0, 1.0]:
		_light(Vector3(HULL.x + s * 11.0, top + 3.0, HULL.z), Color(0.6, 0.85, 1.0), 0.8, 12.0)
	# Logs and lockers.
	readable(Vector3(HULL.x + 4.0, 0.0, HULL.z + 26.0), "vigilant_bridge", "Radio", top + 0.05)
	readable(Vector3(HULL.x - 12.0, 0.0, HULL.z - 8.0), "vigilant_quarters", "Journal", top + 0.05)
	readable(Vector3(HULL.x - 9.5, 0.0, HULL.z - 18.0), "vigilant_hangar", "Datapad", top + 5.15)
	cache(Vector3(HULL.x - 9.5, top + 5.1, HULL.z - 10.0), "vigilant_gantry_w", {"heavy_cell": 2, "cartridge": 4, "tech": 2}, 40, "Open the ammo locker")
	cache(Vector3(HULL.x + 9.5, top + 5.1, HULL.z + 7.0), "vigilant_gantry_e", {"tech": 3, "stim": 1, "plastic": 3}, 35, "Open the parts locker")
	cache(Vector3(HULL.x - 11.0, top, HULL.z + 18.0), "vigilant_deck", {"scrap": 8, "ration": 3}, 30, "Open the crew locker")
	for p in [Vector3(-6.0, 0.0, -20.0), Vector3(7.0, 0.0, -4.0), Vector3(-5.0, 0.0, 14.0)]:
		resource(Vector3(HULL.x + p.x, top + 0.05, HULL.z + p.z), "scrap", Vector2i(2, 3))
	# The guardian and the arm mount at the far end of the deck.
	_guard = guardian(Vector3(HULL.x, top, HULL.z + 14.0), "brute", "HANGAR BRUTE", Color(1.0, 0.45, 0.2), 5.5, {"scale": 2.0, "speed": 0.95, "damage": 1.4, "cooldown": 0.9})
	droid_part(Vector3(HULL.x + 1.5, top + 0.05, HULL.z + 24.0), "strider_arm_r", ["Arm_R"], _guard)
	pack(Vector3(HULL.x, top, HULL.z - 18.0), 2)


func _build_outside() -> void:
	for i in 24:
		var x := rng.randf_range(-44.0, 44.0)
		var z := rng.randf_range(-70.0, 70.0)
		if _in_hull(x, z, 10.0):
			continue
		rock(Vector3(x, 0.0, z), rng.randf_range(0.6, 1.5))
	for p in [Vector3(-34.0, 0.0, 20.0), Vector3(34.0, 0.0, -20.0), Vector3(-30.0, 0.0, -56.0)]:
		crag(p, Vector3(7.0, 9.0, 6.0), p.x, p.z * 0.05, 0.22)
	for p in [Vector3(-34.0, 0.0, 30.0), Vector3(36.0, 0.0, -30.0), Vector3(-38.0, 0.0, -48.0)]:
		ore_vein(p)
	for p in [Vector3(30.0, 0.0, 30.0), Vector3(-26.0, 0.0, -10.0)]:
		crystal(p)
	cache(Vector3(28.0, 0.0, -40.0), "vigilant_pod", {"ration": 2, "heavy_cell": 1}, 25, "Search the drop pod")
	pack(Vector3(-20.0, 0.0, -40.0), 3)
	pack(Vector3(26.0, 0.0, 44.0), 2, 0.2)
	MapPoi.add(self, _exits[CANYON], "Ridge trail to Spire Canyon", "exit", "Back north, down the ridge into Spire Canyon.")
	MapPoi.add(self, HULL + Vector3(0.0, 0.0, -HULL_L * 0.5), "Torn bow", "landmark", "The way into hangar two.")
	MapPoi.add(self, HULL + Vector3(0.0, 0.0, 14.0), "Hangar two", "danger", "Something armoured has made the hangar its den.")


func _light(p: Vector3, col: Color, energy: float, r: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = r
	l.position = p
	add_child(l)
	return l


func _process(delta: float) -> void:
	_t += delta
	for i in _lights.size():
		var l: OmniLight3D = _lights[i]
		l.light_energy = 1.4 * (0.55 + 0.45 * sin(_t * 2.4 + i * 1.7)) * (0.3 if fmod(_t * 3.0 + i, 7.0) < 0.15 else 1.0)


func _goal_target(id: String):
	if id == "have:strider_arm_r:1":
		return Vector3(HULL.x + 1.5, 1.0, HULL.z + 24.0)
	return null
