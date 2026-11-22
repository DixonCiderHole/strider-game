extends "res://scripts/frontier.gd"
## The Vaari temple, past the bulkhead at the end of Spire Canyon's east fork.
## Explore and loot only: no creatures.
##
## Outside: the gorge from the canyon opens into a walled basin with a
## stepped pyramid (climb its stairs: a cache and a crystal heart on top),
## fallen columns and, at the foot of the east cliff, the temple gate cut
## into the rock.
## Inside (through the gate): the temple hall (canyon_kit.glb TempleHall),
## built away from the terrain at INSIDE: an entry passage lined with
## braziers, the great columned hall with its wall carving and an upper
## gallery up two flights of stairs, the holding room (empty restraint
## cradles), the star room, and the sanctum with the crystal heart.

const SELF := "res://temple.tscn"
const CANYON := "res://canyon.tscn"

const PYRAMID := Vector3(10.0, 0.0, 0.0)
const GATE_X := 56.0
## The hall's origin (its entrance). Far out east, past the fog.
const INSIDE := Vector3(440.0, 10.0, 0.0)

var _inside_spawn := Vector3.ZERO
var _outside_spawn := Vector3.ZERO


func _setup() -> void:
	area_scene = SELF
	area_name = "Vaari Temple"
	area_blurb = "Hand-cut stone, older than anyone's maps."
	rect = Rect2(-85.0, -80.0, 170.0, 160.0)
	terrain_size = 256
	look = {
		"sky_top": Color(0.22, 0.3, 0.42), "sky_horizon": Color(0.66, 0.6, 0.56),
		"ground": Color(0.2, 0.19, 0.17), "fog": Color(0.55, 0.6, 0.64), "fog_density": 0.012,
		"sun": Color(1.0, 0.86, 0.7), "sun_energy": 1.0, "sun_rot": Vector3(-30.0, 110.0, 0.0),
		"ambient": 0.6, "ambient_loop": "forest_loop",
	}
	tree_names = WK.PINES


func _h(x: float, z: float) -> float:
	var h := 0.5 + noise.get_noise_2d(x * 2.0, z * 2.0) * 0.6
	# The gorge in from the canyon, opening into the basin.
	var hw := lerpf(7.0, 58.0, smoothstep(-62.0, -30.0, x))
	var wall := smoothstep(hw, hw + 16.0, absf(z) + noise.get_noise_2d(x, z) * 5.0)
	var rim := 30.0 + noise2.get_noise_2d(x * 0.5, z * 0.5) * 6.0
	# The east cliff behind the gate.
	var east := smoothstep(GATE_X + 2.0, GATE_X + 22.0, x + noise.get_noise_2d(x * 0.7, z) * 3.0)
	var raw := maxf(wall, east) * rim
	var f := raw / 6.0
	var terr := (floorf(f) + smoothstep(0.45, 0.95, f - floorf(f))) * 6.0
	h += lerpf(raw, terr, 0.75)
	# The recess cut into the cliff for the temple doorway.
	if x > GATE_X - 2.0 and x < GATE_X + 12.0 and absf(z) < 7.0:
		h = lerpf(h, 0.6, 1.0 - smoothstep(4.5, 7.0, absf(z)))
	# A raised processional way from the pyramid to the gate.
	if x > PYRAMID.x + 14.0 and x < GATE_X and absf(z) < 6.0:
		h = maxf(h, 0.9)
	return h


func _paint_at(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var n := noise2.get_noise_2d(x * 4.0, z * 4.0)
	var w := 0.0
	# Worn path through the gorge and along the processional way.
	w = maxf(w, (1.0 - smoothstep(2.5, 5.0, absf(z) + n * 1.5)) * 0.8)
	var pd := Vector2(x - PYRAMID.x, z - PYRAMID.z).length()
	w = maxf(w, (1.0 - smoothstep(17.0, 24.0, pd + n * 3.0)) * 0.9)
	if w > 0.3:
		data.set_control_auto(p, false)
		data.set_control_base_id(p, 1)
		data.set_control_overlay_id(p, 2)
		data.set_control_blend(p, w)


func _tree_ok(p: Vector3) -> bool:
	# The gorge is wooded; the basin round the pyramid is an open plaza.
	if absf(p.z) < 9.0 or Vector2(p.x - PYRAMID.x, p.z).length() < 34.0 or p.x > GATE_X - 8.0:
		return false
	if p.x > -40.0 and absf(p.z) < 34.0:
		return false
	var slope := absf(_h(p.x + 1.0, p.z) - _h(p.x - 1.0, p.z)) + absf(_h(p.x, p.z + 1.0) - _h(p.x, p.z - 1.0))
	return slope < 1.0


func _plant_trees(count := 700) -> void:
	super._plant_trees(320)


## Inside the temple: thin, dark air instead of the basin's haze.
func _set_inside(inside: bool) -> void:
	var we := find_children("*", "WorldEnvironment", true, false)
	if we.is_empty():
		return
	var env: Environment = (we[0] as WorldEnvironment).environment
	env.fog_density = 0.003 if inside else float(look["fog_density"])
	env.fog_light_color = Color(0.05, 0.09, 0.11) if inside else look["fog"]
	env.ambient_light_energy = 0.25 if inside else float(look["ambient"])


func _entry(_from: String) -> Array:
	return [Vector3(-80.0, 0.0, 0.0), -PI * 0.5]


# ---------------------------------------------------------------- outside

func _build_area() -> void:
	exit_to(Vector3(-82.0, 0.0, 0.0), "Head west, back to Spire Canyon", CANYON)
	_build_outside()
	_build_inside()
	_build_map_points()


func _build_outside() -> void:
	# The pyramid: climb the stairs on its west face.
	var base := Vector3(PYRAMID.x, _ground(PYRAMID) - 0.3, PYRAMID.z)
	model("TempleStep", Transform3D(Basis(Vector3.UP, -PI * 0.5), base))
	_clear_spots.append([PYRAMID, 22.0])
	var top_y := base.y + 13.0
	var heart := OmniLight3D.new()
	heart.light_color = Color(0.35, 0.85, 1.0)
	heart.light_energy = 3.0
	heart.omni_range = 14.0
	heart.position = Vector3(PYRAMID.x, top_y + 2.5, PYRAMID.z)
	add_child(heart)
	cache(Vector3(PYRAMID.x + 2.6, top_y + 0.7, PYRAMID.z + 1.8), "temple_summit", {"crystal": 4, "tech": 2}, 40, "Open the offering chest")
	# The gate at the foot of the east cliff, and the dark doorway behind it.
	var gp := _on_ground(GATE_X, 0.0)
	model("TempleGate", Transform3D(Basis(Vector3.UP, -PI * 0.5), gp + Vector3.DOWN * 0.2))
	for s in [-1.0, 1.0]:
		crag(Vector3(GATE_X + 6.0, 0.0, s * 6.2), Vector3(10.0, 14.0, 3.0), 50.0 + s, PI * 0.5, 0.12, true)
	crag(Vector3(GATE_X + 6.0, 9.5, 0.0), Vector3(10.0, 8.0, 14.0), 55.0, PI * 0.5, 0.14, true)
	var dark := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9.0, 9.5)
	dark.mesh = q
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.0, 0.0, 0.0)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.material_override = dm
	dark.position = gp + Vector3(9.0, 4.6, 0.0)
	dark.rotation.y = -PI * 0.5
	add_child(dark)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.35, 0.85, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = 10.0
	glow.position = gp + Vector3(2.0, 5.0, 0.0)
	add_child(glow)
	_outside_spawn = gp + Vector3(-4.0, 0.2, 0.0)
	add_interact(gp + Vector3(1.5, 1.2, 0.0), "Enter the temple", func():
		_go(true), 3.4)
	# Fallen columns and blocks along the processional way.
	var reach_kit: Node3D = null
	if ResourceLoader.exists("res://models/reach_kit.glb"):
		reach_kit = load("res://models/reach_kit.glb").instantiate()
	for i in 6:
		var x := lerpf(PYRAMID.x + 18.0, GATE_X - 6.0, i / 5.0)
		for s in [-1.0, 1.0]:
			var p := _on_ground(x, s * 7.0)
			if reach_kit != null:
				var nm := "RuinPillar" if (i + int(s)) % 3 != 0 else "RuinPillarBroken"
				var src := reach_kit.find_child(nm, true, false) as MeshInstance3D
				if src != null:
					var body := StaticBody3D.new()
					body.position = p
					body.rotation.y = rng.randf() * TAU
					add_child(body)
					var mi := MeshInstance3D.new()
					mi.mesh = src.mesh
					body.add_child(mi)
					var cs := CollisionShape3D.new()
					cs.shape = src.mesh.create_convex_shape()
					body.add_child(cs)
					continue
			crag(p, Vector3(1.6, 6.0, 1.6), x + s, 0.0, 0.1)
	if reach_kit != null:
		reach_kit.free()
	for p in [Vector3(-20.0, 0.0, 22.0), Vector3(-26.0, 0.0, -20.0), Vector3(34.0, 0.0, 26.0), Vector3(40.0, 0.0, -30.0)]:
		crag(p, Vector3(4.0, 3.0, 3.0), p.x, p.z * 0.1, 0.2)
	for i in 30:
		rock(Vector3(rng.randf_range(-70.0, 50.0), 0.0, rng.randf_range(-55.0, 55.0)), rng.randf_range(0.5, 1.2))
	cache(Vector3(-30.0, 0.0, -38.0), "temple_basin", {"ore": 4, "scrap": 5}, 25)
	readable(Vector3(GATE_X - 4.0, 0.0, 3.5), "canyon_rim_carving")
	for p in [Vector3(-12.0, 0.0, 30.0), Vector3(36.0, 0.0, -18.0), Vector3(44.0, 0.0, 20.0)]:
		crystal(p)
	for p in [Vector3(-45.0, 0.0, 34.0), Vector3(30.0, 0.0, -45.0)]:
		ore_vein(p)


# ---------------------------------------------------------------- inside

func _build_inside() -> void:
	var o := INSIDE
	model("TempleHall", Transform3D(Basis.IDENTITY, o))
	_inside_spawn = o + Vector3(0.0, 0.15, -3.0)
	add_interact(o + Vector3(0.0, 1.2, -1.2), "Leave the temple", func():
		_go(false), 2.6)
	# Firelight and crystal light: braziers, the obelisk, the heart.
	var cyan := Color(0.35, 0.85, 1.0)
	var warm := Color(1.0, 0.62, 0.32)
	for z in [-5.0, -11.0, -17.0]:
		_light(o + Vector3(0.0, 4.0, z), cyan, 1.4, 9.0)
	for z in [-26.0, -50.0]:
		for s in [-1.0, 1.0]:
			_light(o + Vector3(s * 4.5, 2.2, z), cyan, 1.6, 10.0)
	_light(o + Vector3(0.0, 7.0, -38.0), cyan, 3.0, 22.0)
	_light(o + Vector3(0.0, 12.0, -30.0), warm, 1.0, 26.0, false)
	_light(o + Vector3(0.0, 12.0, -46.0), warm, 1.0, 26.0, false)
	for s in [-1.0, 1.0]:
		_light(o + Vector3(s * 10.0, 8.0, -52.5), cyan, 1.4, 10.0)
		_light(o + Vector3(s * 23.5, 4.0, -27.5), cyan if s > 0 else Color(0.6, 0.9, 1.0), 1.5, 12.0)
	_light(o + Vector3(0.0, 4.0, -66.0), cyan, 4.0, 18.0)
	_light(o + Vector3(0.0, 9.0, -60.0), warm, 0.8, 18.0, false)
	# Logs.
	readable(o + Vector3(3.6, 0.0, -11.6), "temple_k7", "Datapad", o.y + 0.05)
	readable(o + Vector3(14.6, 0.0, -38.0), "temple_mural", "Datapad", o.y + 0.05)
	readable(o + Vector3(-26.5, 0.0, -29.5), "temple_cradles", "Datapad", o.y + 0.05)
	readable(o + Vector3(2.4, 0.0, -59.5), "temple_sanctum", "Datapad", o.y + 0.05)
	# Loot: up on the gallery, in the side rooms and the sanctum.
	cache(o + Vector3(-12.0, 6.0, -52.5), "temple_gallery_w", {"crystal": 3, "heavy_cell": 2}, 35, "Open the stone chest")
	cache(o + Vector3(12.0, 6.0, -52.5), "temple_gallery_e", {"tech": 3, "stim": 1}, 35, "Open the stone chest")
	cache(o + Vector3(27.5, 0.0, -32.0), "temple_star", {"crystal": 2, "medpack": 1, "ration": 2}, 30, "Open the stone chest")
	cache(o + Vector3(-27.0, 0.0, -22.5), "temple_holding", {"scrap": 6, "cartridge": 3}, 25, "Search the pile of gear")
	cache(o + Vector3(6.5, 0.0, -71.5), "temple_sanctum", {"crystal": 5, "tech": 3}, 60, "Open the reliquary")
	for p in [Vector3(-5.0, 0.0, -71.0), Vector3(-7.5, 0.0, -60.0), Vector3(7.5, 0.0, -61.0), Vector3(20.0, 0.0, -23.0)]:
		crystal(o + p + Vector3(0.0, 0.05, 0.0))


func _go(inside: bool) -> void:
	await _fade_to(1.0, 0.4)
	_set_inside(inside)
	await teleport(_inside_spawn if inside else _outside_spawn, 0.0 if inside else PI * 0.5, "Inside the temple" if inside else "")


func _light(p: Vector3, col: Color, energy: float, rng_m: float, shadow := false) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = shadow
	l.position = p
	add_child(l)


func _build_map_points() -> void:
	MapPoi.add(self, _exits[CANYON], "Way to Spire Canyon", "exit", "The gorge west, back through the cut bulkhead into Spire Canyon.")
	MapPoi.add(self, PYRAMID, "Stepped pyramid", "landmark", "A Vaari pyramid with a crystal heart on top. Stairs climb its west face.")
	MapPoi.add(self, Vector3(GATE_X, 0.0, 0.0), "Temple gate", "landmark", "The way into the temple, cut into the east cliff.")
