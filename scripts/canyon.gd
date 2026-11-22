extends "res://scripts/frontier.gd"
## Spire Canyon: the hub of the canyon country, east of Shipfall Reach.
##
## A deep gorge running west to east, terraced cliffs either side (the north
## rim 36 m up, the south rim 26 m), a shallow river down the middle and two
## waterfalls off sheer faces. Five ways on (world_map.gd CANYON_EXITS):
##   north-west  a slot gorge and a crystal cave into the Glowmire Caverns
##   north-east  a switchback trail up the north wall to the Rimefall Plateau
##   south-west  a flooded side gorge down into the Sunken Mire
##   south-east  a ridge trail up the south wall to the wreck of the VIGILANT
##   east        the east fork, blocked by a bulkhead until the droid's saw
##               cuts it open, then on to the Vaari temple
## On the north wall, half way up, is the Ascendancy supply drop with the
## Strider's frame in its repair cradle (reached by a cave from the floor).

const SELF := "res://canyon.tscn"
const REACH := "res://reach.tscn"
const CAVERNS := "res://caverns.tscn"
const PLATEAU := "res://plateau.tscn"
const SWAMP := "res://swamp.tscn"
const VIGILANT := "res://vigilant.tscn"
const TEMPLE := "res://temple.tscn"
const DROID_GLB := "res://models/droid_parts.glb"

const RIM_N := 36.0
const RIM_S := 26.0
const WATER := -0.3

## Paths cut into the cliffs: points are (x, z, y) on the path; [points, width].
const RAMP_PLATEAU := [[Vector3(26.0, 0.3, -12.0), Vector3(46.0, 5.0, -18.0), Vector3(28.0, 10.0, -25.0), Vector3(48.0, 16.0, -32.0),
	Vector3(30.0, 22.0, -39.0), Vector3(50.0, 28.0, -46.0), Vector3(55.0, 34.0, -58.0), Vector3(55.0, 36.0, -100.0)], 5.5]
const RAMP_VIGILANT := [[Vector3(58.0, 0.3, 17.0), Vector3(78.0, 6.0, 23.0), Vector3(60.0, 12.0, 29.0), Vector3(80.0, 18.0, 35.0),
	Vector3(62.0, 24.0, 42.0), Vector3(55.0, 26.0, 54.0), Vector3(55.0, 26.0, 100.0)], 5.5]
const RAMP_CAVERNS := [[Vector3(-46.0, 0.3, -10.0), Vector3(-52.0, 0.8, -30.0), Vector3(-55.0, 1.6, -60.0), Vector3(-55.0, 2.4, -100.0)], 12.0]
const RAMP_SWAMP := [[Vector3(-44.0, 0.2, 14.0), Vector3(-50.0, -0.6, 40.0), Vector3(-55.0, -1.0, 70.0), Vector3(-55.0, -1.2, 100.0)], 14.0]
## The cave from the canyon floor up to the supply drop's shelf.
const DROP_CAVE := [Vector3(-34.0, 0.4, -10.0), Vector3(-40.0, 4.0, -20.0), Vector3(-34.0, 8.5, -29.0), Vector3(-24.0, 13.0, -32.0),
	Vector3(-17.0, 17.6, -34.0)]
const SHELF := Vector3(-8.0, 18.0, -38.0)
const SHELF_R := 11.0
## Sheer faces with a waterfall: [x, north?].
const FALLS := [[10.0, true], [-12.0, false]]
const BULKHEAD_X := 80.0

var _ramps: Array = []
var _drop_body: Node3D
var _cradle_at := Vector3.ZERO
var _frame: Node3D
var _cradle_it
var _bulk: Node3D
var _bulk_it
var _temple_it
var _cutting := false


func _setup() -> void:
	area_scene = SELF
	area_name = "Spire Canyon"
	area_blurb = "Waterfalls, caves and cliffs. Five ways on."
	rect = Rect2(-100.0, -100.0, 200.0, 200.0)
	terrain_size = 256
	water_y = WATER
	look = {
		"sky_top": Color(0.24, 0.34, 0.46), "sky_horizon": Color(0.7, 0.64, 0.55),
		"ground": Color(0.22, 0.2, 0.17), "fog": Color(0.6, 0.64, 0.66), "fog_density": 0.009,
		"sun": Color(1.0, 0.9, 0.76), "sun_energy": 1.1, "sun_rot": Vector3(-48.0, 150.0, 0.0),
		"ambient": 0.65, "ambient_loop": "forest_loop",
		"water_shallow": Color(0.14, 0.34, 0.36), "water_deep": Color(0.03, 0.09, 0.12),
	}
	tree_names = WK.PINES
	_ramps = [RAMP_PLATEAU, RAMP_VIGILANT, RAMP_CAVERNS, RAMP_SWAMP, [DROP_CAVE.map(func(p): return Vector3(p.x, p.y - 0.25, p.z)), 7.6]]


# ---------------------------------------------------------------- shape

func cz(x: float) -> float:
	return 8.0 * sin(x * 0.025)


## How far from the centre line the floor reaches before the cliffs start.
func _floor_hw(x: float) -> float:
	return lerpf(15.0, 7.0, smoothstep(58.0, 74.0, x))


func _wall_run(x: float, north: bool) -> float:
	var run := 40.0 if north else 30.0
	for f in FALLS:
		if f[1] == north:
			run = lerpf(3.0, run, smoothstep(6.0, 11.0, absf(x - f[0])))
	if x > 60.0:
		run = lerpf(run, 6.0, smoothstep(60.0, 76.0, x))
	return run


func _h(x: float, z: float) -> float:
	var d := z - cz(x)
	var north := d < 0.0
	var hw := _floor_hw(x)
	var run := _wall_run(x, north)
	var rim := (RIM_N if north else RIM_S) + noise2.get_noise_2d(x * 0.6, z * 0.6) * 4.0
	var t := smoothstep(hw, hw + run, absf(d) + noise.get_noise_2d(x, z) * 4.0 * clampf(run / 20.0, 0.0, 1.0))
	# Terraced bands: sheer steps with flat ledges between them.
	var raw := t * rim
	var band := 7.0
	var f := raw / band
	var h := (floorf(f) + smoothstep(0.5, 0.95, f - floorf(f))) * band
	h = lerpf(raw, h, 0.8)
	h += 0.6 + noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5
	# The river down the floor (dies away into the east fork).
	if x < 66.0:
		var rd := absf(d)
		if rd < 7.0:
			var bed := -1.1 + noise2.get_noise_2d(x * 2.0, 0.0) * 0.2
			h = minf(h, lerpf(bed, h, smoothstep(2.5, 7.0, rd)))
	# Plunge pools under the falls.
	for fl in FALLS:
		var fz: float = cz(fl[0]) + (-1.0 if fl[1] else 1.0) * (_floor_hw(fl[0]) + 5.0)
		var pd := Vector2(x - fl[0], z - fz).length()
		if pd < 9.0:
			h = minf(h, lerpf(-2.4, h, smoothstep(3.0, 9.0, pd)))
	# The supply drop's shelf.
	var sd := Vector2(x - SHELF.x, z - SHELF.z).length()
	if sd < SHELF_R + 4.0:
		h = lerpf(h, SHELF.y, 1.0 - smoothstep(SHELF_R, SHELF_R + 4.0, sd))
	# Paths cut into the cliffs.
	for r in _ramps:
		var q := _ramp_at(r[0], x, z)
		var hwid: float = r[1] * 0.5
		if q.x < hwid + 4.0:
			h = lerpf(h, q.y, 1.0 - smoothstep(hwid, hwid + 4.0, q.x))
	return h


## (distance to a ramp, its height there).
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
	var w := 0.0
	for r in _ramps:
		var q := _ramp_at(r[0], x, z)
		w = maxf(w, (1.0 - smoothstep(r[1] * 0.35, r[1] * 0.6, q.x + n * 1.2)) * 0.85)
	var rd := absf(z - cz(x))
	if x < 66.0 and rd < 9.0:
		w = maxf(w, 1.0 - smoothstep(4.0, 9.0, rd + n * 2.0))
	if w > 0.3:
		data.set_control_auto(p, false)
		data.set_control_base_id(p, 1)
		data.set_control_overlay_id(p, 2)
		data.set_control_blend(p, w)


func _tree_ok(p: Vector3) -> bool:
	# Trees on the floor's banks and the rims, not on cliff faces or paths.
	if _h(p.x, p.z) < 0.4:
		return false
	for r in _ramps:
		if _ramp_at(r[0], p.x, p.z).x < r[1] * 0.5 + 2.0:
			return false
	var slope := absf(_h(p.x + 1.0, p.z) - _h(p.x - 1.0, p.z)) + absf(_h(p.x, p.z + 1.0) - _h(p.x, p.z - 1.0))
	return slope < 1.2


func _entry(from: String) -> Array:
	match from:
		CAVERNS:
			return [Vector3(-55.0, 0.0, -92.0), PI]
		PLATEAU:
			return [Vector3(55.0, 0.0, -92.0), PI]
		SWAMP:
			return [Vector3(-55.0, 0.0, 92.0), 0.0]
		VIGILANT:
			return [Vector3(55.0, 0.0, 92.0), 0.0]
		TEMPLE:
			return [Vector3(92.0, 0.0, cz(92.0)), PI * 0.5]
	return [Vector3(-93.0, 0.0, cz(-93.0)), -PI * 0.5]


# ---------------------------------------------------------------- build

func _build_area() -> void:
	if not GS.flags.has("strider_stage") and not GS.droid_online():
		GS.flags["strider_stage"] = 0
	_build_exits()
	_build_falls()
	_build_drop()
	_build_bulkhead()
	_build_rocks()
	_build_loot()
	_build_creatures()
	_build_map_points()


func _build_exits() -> void:
	exit_to(Vector3(-96.0, 0.0, cz(-96.0)), "Head west to Shipfall Reach", REACH)
	exit_to(Vector3(-55.0, 0.0, -96.0), "Go north into the Glowmire Caverns", CAVERNS)
	exit_to(Vector3(55.0, 0.0, -96.0), "Go north onto the Rimefall Plateau", PLATEAU)
	exit_to(Vector3(-55.0, 0.0, 96.0), "Wade south into the Sunken Mire", SWAMP)
	exit_to(Vector3(55.0, 0.0, 96.0), "Go south to the wreck of the VIGILANT", VIGILANT)
	# The temple way only opens once the bulkhead is cut.
	var tp := _on_ground(96.0, cz(96.0))
	_exits[TEMPLE] = tp
	_temple_it = add_interact(tp + Vector3.UP, "Go east to the Vaari temple", func():
		GS.flags["came_from"] = area_scene
		GS.save()
		get_tree().change_scene_to_file(TEMPLE))
	_temple_it.enabled = GS.flags.get("bulkhead_cut", false)


func _build_falls() -> void:
	for f in FALLS:
		var x: float = f[0]
		var north: bool = f[1]
		var s := -1.0 if north else 1.0
		var face_d := _floor_hw(x) + 3.5
		var top := Vector3(x, (RIM_N if north else RIM_S) + 1.0, cz(x) + s * (face_d - 1.0))
		var bottom := Vector3(x, WATER, cz(x) + s * (face_d - 1.0))
		waterfall(top, bottom, 6.0, 0.0 if north else PI)
		# A stream along the rim feeding it.
		_clear_spots.append([Vector3(x, 0.0, top.z + s * 8.0), 8.0])


func _build_rocks() -> void:
	# Rock spurs and boulders on the floor, the odd pillar on the rims.
	var spots := [[-70.0, -8.0, 5.0], [-20.0, 14.0, 4.0], [20.0, -12.0, 4.5], [38.0, 13.0, 3.5], [-82.0, 12.0, 4.0], [64.0, -7.0, 3.0]]
	for s in spots:
		crag(Vector3(s[0], 0.0, cz(s[0]) + s[1]), Vector3(s[2], s[2] * 1.4, s[2] * 0.9), s[0] * 0.13, s[1], 0.22)
	for i in 40:
		var x := rng.randf_range(-95.0, 70.0)
		var z := cz(x) + rng.randf_range(-12.0, 12.0)
		if absf(z - cz(x)) < 5.0:
			continue
		rock(Vector3(x, 0.0, z), rng.randf_range(0.5, 1.4))
	# Tall pillars on the rims, the high ridges.
	for p in [Vector3(-40.0, 0.0, -70.0), Vector3(20.0, 0.0, -80.0), Vector3(-75.0, 0.0, 60.0), Vector3(20.0, 0.0, 70.0)]:
		crag(p, Vector3(6.0, 18.0, 5.0), p.x * 0.07, p.z * 0.01, 0.25, true)
	# Ledges you can stand on beside the trails (handholds and lookouts).
	ledge(Vector3(52.0, 16.6, -30.5), Vector3(5.0, 3.0, 4.0), 1.0, 0.3)
	ledge(Vector3(83.0, 18.6, 34.0), Vector3(5.0, 3.0, 4.0), 2.0, -0.2)
	ledge(Vector3(4.0, 18.4, -40.0), Vector3(6.0, 3.0, 5.0), 3.0, 0.5)
	# The crystal cave up to the supply drop.
	cave(DROP_CAVE, 3.0, 4.0)
	# And a cave arch over the slot gorge into the caverns.
	cave([Vector3(-53.0, 1.0, -38.0), Vector3(-54.5, 1.4, -52.0), Vector3(-55.0, 1.8, -66.0)], 4.6, 7.0, Color(0.3, 1.0, 0.8))
	# Glowcaps at the caverns' gorge, ice at the plateau trail's top, roots at the swamp's.
	var shroom := kit_mesh("GiantShroomB")
	if shroom != null:
		for p in [Vector3(-60.0, 0.0, -24.0), Vector3(-47.0, 0.0, -28.0), Vector3(-61.0, 0.0, -78.0)]:
			model("GiantShroomB", Transform3D(Basis(Vector3.UP, p.x), _on_ground(p.x, p.z)).scaled_local(Vector3.ONE * 0.8))
	model("IceSpire", Transform3D(Basis(Vector3.UP, 0.6), _on_ground(62.0, -72.0)).scaled_local(Vector3.ONE * 0.6))
	model("RootArch", Transform3D(Basis(Vector3.UP, PI * 0.5), _on_ground(-52.0, 46.0) + Vector3.DOWN * 0.5), true)


# ---------------------------------------------------------------- the supply drop

func _build_drop() -> void:
	var at := Vector3(SHELF.x, SHELF.y, SHELF.z)
	_drop_body = model("SupplyDrop", Transform3D(Basis(Vector3.UP, 0.4), at + Vector3.DOWN * 0.1))
	var marker := _drop_body.get_node_or_null("SupplyDrop") as Node3D
	_cradle_at = _drop_body.transform * Vector3(3.6, 0.3, 0.0)
	var src: Node3D = _kit.find_child("CradleAt", true, false) as Node3D if _kit != null else null
	if src != null:
		_cradle_at = _drop_body.transform * src.position
	_clear_spots.append([at, 9.0])
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.2)
	l.light_energy = 1.4
	l.omni_range = 7.0
	l.position = _cradle_at + Vector3.UP * 2.5
	add_child(l)
	readable(at + Vector3(-3.0, 0.0, 3.5), "drop_manifest")
	if not GS.droid_online():
		_frame = _make_frame()
	_cradle_it = add_interact(_cradle_at + Vector3.UP * 1.0, "", func(): _use_cradle(), 3.0)
	_refresh_cradle()


## The Strider as it lies in the cradle: just its body, no legs or arms.
func _make_frame() -> Node3D:
	if not ResourceLoader.exists(DROID_GLB):
		return null
	var inst: Node3D = load(DROID_GLB).instantiate()
	add_child(inst)
	U.fit(inst, 1.5, 1, true)
	for n in ["Leg_LF", "Leg_RF", "Leg_LB", "Leg_RB", "Arm_L", "Arm_R"]:
		var c := inst.find_child(n, true, false) as Node3D
		if c != null:
			c.visible = false
	inst.position = _cradle_at + Vector3.UP * 0.55
	inst.rotation.y = _drop_body.rotation.y + PI * 0.5
	return inst


const PARTS := ["strider_legs_f", "strider_legs_b", "strider_arm_l", "strider_arm_r"]


func _parts_have() -> int:
	var n := 0
	for p in PARTS:
		if GS.count(p) > 0:
			n += 1
	return n


func _refresh_cradle() -> void:
	if _cradle_it == null:
		return
	if GS.droid_online():
		_cradle_it.enabled = false
		return
	if not GS.flags.get("found_cradle", false):
		_cradle_it.prompt = "Search the supply drop"
	else:
		_cradle_it.prompt = "Rebuild the Strider  (%d/4 parts)" % _parts_have()


func _use_cradle() -> void:
	if GS.droid_online():
		return
	if not GS.flags.get("found_cradle", false):
		GS.flags["found_cradle"] = true
		_show_banner("A Strider escort droid, stripped to the frame.\nIts legs and arms were torn off and dragged away.", 5.0)
		GS.check_quests()
		GS.changed()
		_refresh_cradle()
		return
	if _parts_have() < 4:
		var missing := []
		for p in PARTS:
			if GS.count(p) == 0:
				missing.append(String(GS.item(p).get("name", p)))
		_show_banner("Still missing: " + ", ".join(missing), 4.0)
		return
	for p in PARTS:
		GS.remove_item(p, 1)
	GS.flags["droid_rebuilt"] = true
	GS.add_xp(60)
	_cradle_it.enabled = false
	Sfx.ui("upgrade", -2.0)
	_show_banner("Bolted on and powered up.\nThe Strider's optics flicker, find you, and lock on.", 5.0)
	if _frame != null:
		_frame.queue_free()
		_frame = null
	droid = CompanionScript.new()
	droid.name = "Droid"
	droid.player = player
	droid.damage = GS.droid_damage()
	droid.position = _cradle_at + Vector3.UP * 0.4
	add_child(droid)
	GS.check_quests()
	GS.changed()


# ---------------------------------------------------------------- the bulkhead

func _build_bulkhead() -> void:
	var z := cz(BULKHEAD_X)
	var base := Vector3(BULKHEAD_X, _ground(Vector3(BULKHEAD_X, 0.0, z)) - 0.3, z)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), base)
	var cut: bool = GS.flags.get("bulkhead_cut", false)
	_bulk = model("BulkheadCut" if cut else "Bulkhead", xf)
	if cut:
		model("BulkheadSlab", Transform3D(Basis(Vector3.UP, PI * 0.5).rotated(Vector3.FORWARD, 0.06), base + Vector3(-3.2, 0.15, 0.0)))
	# Seal the gaps at the ends against the gorge walls.
	for s in [-1.0, 1.0]:
		crag(Vector3(BULKHEAD_X + 0.5, 0.0, z + s * 8.6), Vector3(4.0, 16.0, 4.0), 30.0 + s, 0.0, 0.18)
	_clear_spots.append([base, 12.0])
	_bulk_it = add_interact(base + Vector3(-2.2, 1.4, 0.0), "", func(): _use_bulkhead(), 3.2)
	_refresh_bulkhead()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 1.0
	l.omni_range = 9.0
	l.position = base + Vector3(-4.0, 6.0, 0.0)
	add_child(l)


func _refresh_bulkhead() -> void:
	if _bulk_it == null:
		return
	if GS.flags.get("bulkhead_cut", false):
		_bulk_it.enabled = false
		return
	_bulk_it.prompt = "Cut through the bulkhead" if _can_cut() else "Examine the bulkhead"


func _can_cut() -> bool:
	return droid != null and is_instance_valid(droid) and not droid.is_dead and droid.has_method("has_saw") and droid.has_saw()


func _use_bulkhead() -> void:
	if _cutting or GS.flags.get("bulkhead_cut", false):
		return
	if not _can_cut():
		if not GS.droid_online():
			_show_banner("A whole warship bulkhead, jammed across the gorge.\nNothing you carry will get through that.", 4.5)
		elif GS.droid_arm() != "saw_arm":
			_show_banner("The Strider's cannon won't touch it.\nFit a saw arm (party menu, P) and bring the droid here.", 4.5)
		else:
			_show_banner("Bring the droid with you.", 3.0)
		return
	_cutting = true
	_bulk_it.enabled = false
	var z := cz(BULKHEAD_X)
	var door := Vector3(BULKHEAD_X - 1.0, _ground(Vector3(BULKHEAD_X, 0.0, z)) + 1.6, z)
	droid.order_hold()
	droid.global_position = Vector3(BULKHEAD_X - 2.2, _ground(Vector3(BULKHEAD_X - 2.2, 0.0, z)) + 0.3, z + 0.9)
	droid.hold_pos = droid.global_position
	droid.look_at(Vector3(door.x, droid.global_position.y, door.z), Vector3.UP)
	_show_banner("The saw bites in.", 2.5)
	# Trace the doorway: up one side, across, down the other.
	var path := [door + Vector3(0.0, -1.5, 1.8), door + Vector3(0.0, 2.9, 1.8), door + Vector3(0.0, 2.9, -1.8), door + Vector3(0.0, -1.5, -1.8)]
	for i in path.size() - 1:
		var steps := 8
		for k in steps:
			droid.set_cutting(true, path[i].lerp(path[i + 1], float(k) / steps))
			Sfx.at(door, "impact", -6.0, 0.2, 14.0, 0.2)
			await get_tree().create_timer(0.16).timeout
	droid.set_cutting(false)
	var xf := _bulk.transform
	_bulk.queue_free()
	_bulk = model("BulkheadCut", xf)
	model("BulkheadSlab", Transform3D(Basis(Vector3.UP, PI * 0.5).rotated(Vector3.FORWARD, 0.06), xf.origin + Vector3(-3.2, 0.15, 0.0)))
	Sfx.at(door, "crate_open", 0.0, 0.1, 20.0)
	GS.flags["bulkhead_cut"] = true
	_temple_it.enabled = true
	droid.order_follow()
	_show_banner("The slab drops out with a boom that rolls down the canyon.\nThe way east is open.", 5.0)
	GS.add_xp(40)
	GS.check_quests()
	GS.changed()
	_cutting = false


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 20 == 0:
		_refresh_cradle()
		_refresh_bulkhead()


# ---------------------------------------------------------------- loot + creatures

func _build_loot() -> void:
	cache(Vector3(-4.0, SHELF.y, -44.0), "canyon_drop", {"tech": 3, "heavy_cell": 2, "medpack": 1}, 25, "Open the drop's supply locker")
	cache(Vector3(40.0, 0.0, -72.0), "canyon_rim_n", {"scrap": 6, "ore": 3, "cartridge": 2}, 30)
	cache(Vector3(72.0, 0.0, 66.0), "canyon_rim_s", {"tech": 2, "crystal": 2, "ration": 2}, 30)
	cache(Vector3(4.0, 18.4, -40.0), "canyon_ledge", {"heavy_cell": 2, "plastic": 3}, 20, "Open the cache wedged on the ledge")
	readable(Vector3(-70.0, 0.0, cz(-70.0) - 6.0), "canyon_pathfinder")
	readable(Vector3(70.0, 0.0, cz(70.0) + 3.0), "canyon_bulkhead")
	readable(Vector3(22.0, 0.0, -78.0), "canyon_rim_carving")
	for p in [Vector3(-26.0, 0.0, cz(-26.0) - 11.0), Vector3(30.0, 0.0, cz(30.0) + 12.0), Vector3(-84.0, 0.0, cz(-84.0) + 11.0), Vector3(-60.0, 0.0, -84.0)]:
		ore_vein(p)
	for p in [Vector3(-36.0, 0.0, -30.0) + Vector3(0.0, 9.0, 0.0), Vector3(12.0, 0.0, cz(12.0) - 22.0), Vector3(48.0, 0.0, 80.0), Vector3(-30.0, 0.0, 66.0)]:
		if p.y > 0.0:
			crystal(Vector3(p.x, _ground(p) + 0.05, p.z))
		else:
			crystal(p)
	for i in 6:
		var x := rng.randf_range(-90.0, 60.0)
		resource(Vector3(x, 0.0, cz(x) + rng.randf_range(-12.0, 12.0)), "scrap", Vector2i(1, 3))


func _build_creatures() -> void:
	pack(Vector3(-40.0, 0.0, cz(-40.0) + 6.0), 3)
	pack(Vector3(20.0, 0.0, cz(20.0) - 6.0), 3)
	pack(Vector3(62.0, 0.0, cz(62.0)), 2, 0.25)
	pack(Vector3(SHELF.x + 5.0, SHELF.y, SHELF.z + 4.0), 2)
	pack(Vector3(55.0, 36.0, -80.0), 2)
	pack(Vector3(55.0, 26.0, 78.0), 2)


func _build_map_points() -> void:
	MapPoi.add(self, _exits[REACH], "Way to Shipfall Reach", "exit", "The gap west, back to Shipfall Reach.")
	MapPoi.add(self, _exits[CAVERNS], "Glowmire Caverns", "exit", "A slot gorge and a glowing cave, north into the fungal caverns.")
	MapPoi.add(self, _exits[PLATEAU], "Rimefall Plateau", "exit", "The switchback trail up the north wall leads onto a frozen plateau.")
	MapPoi.add(self, _exits[SWAMP], "Sunken Mire", "exit", "A flooded gorge drops south into the swamp.")
	MapPoi.add(self, _exits[VIGILANT], "Wreck of the VIGILANT", "exit", "The ridge trail up the south wall, to where a capital ship came down.")
	MapPoi.add(self, _exits[TEMPLE], "East fork", "exit", "Beyond the bulkhead the gorge runs on east to a Vaari temple.")
	MapPoi.add(self, SHELF, "Supply drop", "landmark", "An Ascendancy supply drop on a shelf half way up the north wall. A cave climbs to it from the canyon floor.")
	MapPoi.add(self, Vector3(BULKHEAD_X, 0.0, cz(BULKHEAD_X)), "The bulkhead", "danger", "A warship bulkhead jammed across the east fork.")


func _goal_target(id: String):
	match id:
		"found_cradle", "droid_rebuilt":
			if id == "droid_rebuilt" and _parts_have() < 4:
				return null
			return _cradle_at + Vector3.UP
		"have:strider_legs_f:1":
			return _exits[CAVERNS]
		"have:strider_legs_b:1":
			return _exits[PLATEAU]
		"have:strider_arm_l:1":
			return _exits[SWAMP]
		"have:strider_arm_r:1":
			return _exits[VIGILANT]
		"fitted:saw_arm", "bulkhead_cut":
			return _bulk.global_position + Vector3(-2.0, 2.0, 0.0) if is_instance_valid(_bulk) else null
		"crafted:saw_arm":
			return _exits[REACH]
	return null
