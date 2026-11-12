extends Node3D
## Base camp: a small valley with a cave in the cliffs. You reach it after
## clearing the crash-site waves. Inside the cave are a campfire and supply
## crates; each crate opens one upgrade track bought with salvage.

const U = preload("res://scripts/util.gd")
const UI = preload("res://scripts/ui.gd")
const WK = preload("res://scripts/world_kit.gd")
const GS = preload("res://scripts/game_state.gd")
const MB = preload("res://scripts/menu_backdrop.gd")
const Sfx = preload("res://scripts/sfx.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CompanionScript = preload("res://scripts/companion.gd")
const AllyScript = preload("res://scripts/ally.gd")
const OverlayScript = preload("res://scripts/overlay.gd")
const CraftPanel = preload("res://scripts/craft_panel.gd")
const Pickup = preload("res://scripts/pickup.gd")
const Items = preload("res://scripts/items.gd")
const Interactable = preload("res://scripts/interactable.gd")
const PauseMenuScript = preload("res://scripts/pause_menu.gd")
const StorageCrate = preload("res://scripts/storage_crate.gd")
const StoragePanel = preload("res://scripts/storage_panel.gd")
const LorePanel = preload("res://scripts/lore_panel.gd")
const Lore = preload("res://scripts/lore.gd")

const CRASH_SITE := "res://main.tscn"
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]
const ROCK_MATERIAL := "res://demo/assets/materials/M_rock23_tp.tres"

const TERRAIN_SIZE := 320
## Half-width of the walkable valley (was 38 m; now about four times the area).
const VALLEY_HALF := 85.0
## Landmarks around the open valley.
const LAKE := Vector3(54.0, 0.0, 8.0)
const LAKE_R := 18.0
const WATER_Y := -0.55
const SPIRES := Vector3(-52.0, 0.0, -4.0)
const OUTPOST := Vector3(40.0, 0.0, -46.0)
const MEADOW := Vector3(-42.0, 0.0, 44.0)
const POD_POS := Vector3(20.0, 0.0, 12.0)
const VALLEY_CENTER := Vector2(0.0, -4.0)
## Cave: an ellipsoid dome set into the cliff, mouth facing +Z (towards the valley).
const CAVE := Vector3(0.0, 0.0, -17.0)
const CAVE_R := Vector3(8.0, 6.0, 10.0)
const MOUTH_HALF_DEG := 36.0
const MOUTH_TOP_DEG := 50.0
const FIRE_POS := Vector3(0.0, 0.0, -12.0)
const INTERACT_RANGE := 2.6

var terrain
var player
var droid
var menu
var rng := RandomNumberGenerator.new()

var _noise_roll := FastNoiseLite.new()
var _noise_hill := FastNoiseLite.new()
var _noise_rock := FastNoiseLite.new()
var _fire_light: OmniLight3D
var _time := 0.0

# Interactables: {pos: Vector3, prompt: String, action: Callable}
var _talk_node
var overlay
var crafting
var _bench_spot
var _bench_model: Node3D

# UI
var _ui: CanvasLayer
var _prompt: Label
var _salvage_label: Label
var _banner: Label
var _panel: PanelContainer
var _panel_track := ""
var ally
var _talk: PanelContainer
var _talk_name: Label
var _talk_text: Label
var _talk_index := -1

## Placeholder conversation by the fire. [speaker, line]
const TALK := [
	["SURVIVOR", "You're awake. I thought that spine had finished you."],
	["YOU", "You pulled me out of there. You're wearing their colours."],
	["SURVIVOR", "And you're wearing yours. Out here it doesn't matter. Those things don't care whose side we were on."],
	["YOU", "Anyone else make it?"],
	["SURVIVOR", "Just us. My unit's gone too. I went back for supplies and found you still breathing."],
	["YOU", "So what now?"],
	["SURVIVOR", "Now we stay alive. You've got a droid that seems to like you, and I've got a rifle. I'll watch your back."],
]
var _p_title: Label
var _p_blurb: Label
var _p_level: Label
var _p_stat: Label
var _p_salvage: Label
var _p_buy: Button
var _p_close: Button


func _ready() -> void:
	rng.seed = 41
	GS.ensure_loaded()

	_build_environment()
	_build_ground()
	_build_cave()
	_build_campfire()
	_build_crates()
	_build_trail_exit()
	_build_lake()
	_build_spires()
	_build_outpost()
	_build_meadow()
	_build_cherry_trees()
	_build_forest()
	if GS.menu_preview:
		var cp := Vector3(6.5, 0.0, 6.0)
		MB.make(self, cp + Vector3(0.0, _ground(cp) + 1.9, 0.0), FIRE_POS + Vector3(0.0, _ground(FIRE_POS) + 0.9, -2.0))
		set_process(false)
		return
	GS.reached_base = true
	GS.horde_mode = false
	GS.enter_area("res://base.tscn")

	player = PlayerScript.new()
	player.name = "Player"
	player.damage = GS.player_damage()
	player.max_health = GS.player_max_health()
	player.health = player.max_health
	player.position = Vector3(0.0, _ground(Vector3(0, 0, 14)) + 0.1, 14.0)
	add_child(player)

	droid = CompanionScript.new()
	droid.name = "Droid"
	droid.player = player
	droid.damage = GS.droid_damage()
	droid.position = Vector3(3.0, _ground(Vector3(3, 0, 12)) + 0.5, 12.0)
	add_child(droid)

	menu = PauseMenuScript.new()
	menu.player = player
	add_child(menu)

	# She sits by the fire, across from the beds, until you've talked.
	ally = AllyScript.new()
	ally.name = "Ally"
	var seat := FIRE_POS + Vector3(1.1, 0.0, 1.45)
	if GS.ally_joined:
		ally.position = player.position + Vector3(2.0, 0.0, 1.0)
		add_child(ally)
		ally.follow(player)
	else:
		ally.mode = "sit"
		ally.position = seat + Vector3(0.0, _ground(seat), 0.0)
		var to_fire := FIRE_POS - seat
		ally.rotation.y = atan2(-to_fire.x, -to_fire.z)
		add_child(ally)
		_talk_node = _add_interact(ally.position, "Talk to her", _start_talk)

	_build_ui()
	overlay = OverlayScript.new()
	overlay.player = player
	overlay.tracker_top = 60.0
	overlay.objective_provider = _quest_target
	add_child(overlay)
	crafting = CraftPanel.new()
	crafting.player = player
	add_child(crafting)
	var lore_panel = LorePanel.new()
	lore_panel.player = player
	add_child(lore_panel)
	var storage_panel = StoragePanel.new()
	storage_panel.player = player
	add_child(storage_panel)
	for d in GS.storage:
		if d.get("area", "") == "res://base.tscn":
			StorageCrate.spawn(self, d)
	_build_bench()
	_build_resources()
	_build_pod_wreck()
	Sfx.loop(self, "forest_loop", -16.0, 6.0, false)
	if GS.wake_at_camp:
		GS.wake_at_camp = false
		_wake_up()
	else:
		_show_banner("BASE CAMP\nA dry cave in the cliffs, fitted out as a shelter.\nCheck the stations inside.", 5.0)


## Arriving from the story: you come to on a cot by the fire.
func _wake_up() -> void:
	# Lying on the left bed, head on the pillow (towards the back of the cave).
	var bed := BED_L
	var yaw := PI + deg_to_rad(4.0)
	var axis := Vector3(sin(yaw), 0.0, cos(yaw))
	var feet := bed - axis * 0.85
	player.position = feet + Vector3(0.0, _ground(bed) + 0.6, 0.0)
	player.sleeping = true
	player._sleep_amount = 1.0
	player.input_enabled = false
	player._facing_yaw = yaw
	player.model.rotation.y = yaw
	player.cam_yaw.rotation.y = yaw + PI * 0.75
	player.health = player.max_health * 0.5
	droid.position = bed + Vector3(-1.5, _ground(bed) + 0.5, 2.5)
	_show_banner("You wake on a cot by a fire.\nShe's sitting across from you, watching the flames.\n\nPress any key to get up", 600.0)
	await get_tree().create_timer(1.5).timeout
	_waiting_get_up = true


var _waiting_get_up := false


func _get_up() -> void:
	_waiting_get_up = false
	_hide_banner()
	player.sleeping = false
	await get_tree().create_timer(1.3).timeout
	player.input_enabled = true
	_show_banner("BASE CAMP\nRest by the fire. Check the stations at the back.", 4.0)


func _process(delta: float) -> void:
	_time += delta
	if _fire_light != null:
		_fire_light.light_energy = 3.2 + sin(_time * 13.0) * 0.5 + sin(_time * 29.0) * 0.35 + sin(_time * 5.0) * 0.3

	_salvage_label.text = "SALVAGE  %d" % GS.salvage
	_process_bench()


func _input(event) -> void:
	if _waiting_get_up:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			get_viewport().set_input_as_handled()
			_get_up()
		return
	if _talk != null and _talk.visible:
		var k: bool = event is InputEventKey and event.pressed and not event.echo
		if (k and event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER]) or (event is InputEventMouseButton and event.pressed):
			get_viewport().set_input_as_handled()
			_next_line()
		elif k and event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_talk_index = TALK.size()
			_next_line()
		return
	# Close the upgrade panel with Esc before the pause menu sees it.
	if _panel != null and _panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_E:
			_close_panel()
			get_viewport().set_input_as_handled()


func _unhandled_input(event) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_tree().paused:
		return
	match event.physical_keycode:
		KEY_1:
			droid.order_follow()
		KEY_2:
			droid.order_hold()
		KEY_3:
			droid.order_go(player.aim_hit())
		KEY_4:
			droid.toggle_weapons()


func _ground(p: Vector3) -> float:
	return WK.ground_y(terrain, p, 0.0)


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.27, 0.33, 0.45)
	sky_mat.sky_horizon_color = Color(0.75, 0.58, 0.45)
	sky_mat.ground_horizon_color = Color(0.3, 0.3, 0.24)
	sky_mat.ground_bottom_color = Color(0.1, 0.11, 0.08)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.52, 0.48)
	env.fog_density = 0.012
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 150.0, 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


## Valley floor, a ring of hills, and a rocky mound with a flat cliff face
## that the cave is set into. The cave footprint is kept flat at y = 0.
func _height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(VALLEY_CENTER)
	var h := _noise_roll.get_noise_2d(x, z) * lerpf(0.15, 1.8, smoothstep(12.0, 30.0, d))
	# Gentle rises across the open valley, then the ring of hills well out.
	h += smoothstep(30.0, 70.0, d) * (0.5 + 0.5 * _noise_hill.get_noise_2d(x * 1.5, z * 1.5)) * 2.2
	h += smoothstep(74.0, 112.0, d + _noise_hill.get_noise_2d(x * 2.0, z * 2.0) * 10.0) * (12.0 + 18.0 * (0.5 + 0.5 * _noise_hill.get_noise_2d(x, z)))
	var md := Vector2(x, (z - CAVE.z - 3.0) / 0.9).length()
	var mound := (1.0 - smoothstep(13.0, 28.0, md)) * (7.5 + _noise_hill.get_noise_2d(x * 3.0, z * 3.0) * 1.5)
	mound *= smoothstep(CAVE.z + CAVE_R.z + 0.5, CAVE.z + CAVE_R.z - 5.0, z)
	h = maxf(h, mound)
	var e := Vector2(x / (CAVE_R.x + 0.6), (z - CAVE.z) / (CAVE_R.z + 0.6)).length()
	h = lerpf(0.0, h, smoothstep(0.92, 1.12, e))
	# Lake basin (after the mound, whose max() would otherwise fill it in).
	var ld := Vector2(x - LAKE.x, z - LAKE.z).length() + _noise_roll.get_noise_2d(x * 2.0, z * 2.0) * 3.0
	h = lerpf(h, -1.9, 1.0 - smoothstep(LAKE_R - 7.0, LAKE_R + 3.0, ld))
	# Flatten the outpost pad.
	var od := Vector2(x - OUTPOST.x, z - OUTPOST.z).length()
	h = lerpf(h, 0.4, 1.0 - smoothstep(10.0, 16.0, od))
	return h


func _paint(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var d := Vector2(x, z).distance_to(VALLEY_CENTER)
	var w := 1.0 - smoothstep(6.0, 14.0, d + _noise_roll.get_noise_2d(x * 4.0, z * 4.0) * 4.0)
	# Worn path from the valley into the cave, and the cave floor itself.
	var path := 1.0 - smoothstep(1.5, 3.5, absf(x + sin(z * 0.15) * 1.5))
	if z > CAVE.z and z < 22.0:
		w = maxf(w, path * 0.9)
	var e := Vector2(x / CAVE_R.x, (z - CAVE.z) / CAVE_R.z).length()
	w = maxf(w, 1.0 - smoothstep(0.8, 1.05, e))
	WK.paint_dirt(data, p, w)
	if e < 1.05:
		data.set_color(p, Color(0.55, 0.5, 0.45))
	var fd := Vector2(x - FIRE_POS.x, z - FIRE_POS.z).length()
	if fd < 2.2:
		data.set_color(p, Color.WHITE.lerp(Color(0.15, 0.13, 0.12), 1.0 - smoothstep(0.5, 2.2, fd)))
	# Muddy lake shore, rocky ground round the spires, and the outpost pad.
	var ld := Vector2(x - LAKE.x, z - LAKE.z).length()
	if ld < LAKE_R + 5.0:
		WK.paint_dirt(data, p, 1.0 - smoothstep(LAKE_R - 2.0, LAKE_R + 5.0, ld))
		if ld < LAKE_R + 1.0:
			data.set_color(p, Color(0.6, 0.55, 0.5))
	var sd := Vector2(x - SPIRES.x, z - SPIRES.z).length()
	if sd < 18.0:
		WK.paint_dirt(data, p, (1.0 - smoothstep(8.0, 18.0, sd)) * 0.8)
	var od := Vector2(x - OUTPOST.x, z - OUTPOST.z).length()
	if od < 16.0:
		WK.paint_dirt(data, p, 1.0 - smoothstep(9.0, 16.0, od))


func _build_ground() -> void:
	_noise_roll.seed = 3
	_noise_roll.frequency = 0.035
	_noise_roll.fractal_octaves = 4
	_noise_hill.seed = 17
	_noise_hill.frequency = 0.015
	_noise_hill.fractal_octaves = 4
	terrain = WK.build_terrain(self, TERRAIN_SIZE, _height_at, _paint, 100)
	if terrain == null:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(320.0, 1.0, 320.0)
		cs.shape = box
		cs.position.y = -0.5
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(320.0, 320.0)
		mi.mesh = plane
		mi.material_override = U.mat(Color(0.2, 0.28, 0.14), 0.95)
		body.add_child(mi)
		add_child(body)

	# Keep the player in the valley.
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := StaticBody3D.new()
		var wcs := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(2.0, 80.0, VALLEY_HALF * 2.0 + 10.0) if d.x != 0.0 else Vector3(VALLEY_HALF * 2.0 + 10.0, 80.0, 2.0)
		wcs.shape = wb
		wall.add_child(wcs)
		wall.position = d * VALLEY_HALF + Vector3(VALLEY_CENTER.x, 20.0, VALLEY_CENTER.y)
		add_child(wall)


# ---------------------------------------------------------------- cave

func _dir(az: float, el: float) -> Vector3:
	return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))


func _in_mouth(az: float, el: float) -> bool:
	var d := rad_to_deg(wrapf(az, -PI, PI))
	if absf(d) >= MOUTH_HALF_DEG:
		return false
	var k := d / MOUTH_HALF_DEG
	return rad_to_deg(el) < MOUTH_TOP_DEG * sqrt(1.0 - k * k)


func _shell_point(az: float, el: float, grow: float, amp: float) -> Vector3:
	var dir := _dir(az, el)
	var p := Vector3(dir.x * (CAVE_R.x + grow), dir.y * (CAVE_R.y + grow), dir.z * (CAVE_R.z + grow))
	var n := _noise_rock.get_noise_3dv(p * 0.35) * amp
	# Keep the bottom edge on the floor so there are no gaps.
	return p + dir * n * smoothstep(-0.1, 0.25, el)


## A rocky dome. `inward` faces the inside (the cave walls); otherwise outside.
func _shell_mesh(grow: float, amp: float, inward: bool) -> ArrayMesh:
	var A := 96
	var E := 22
	var el0 := -0.12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in A:
		for j in E:
			var az_c := TAU * (i + 0.5) / A
			var el_c := lerpf(el0, PI * 0.5, (j + 0.5) / E)
			if _in_mouth(az_c, el_c):
				continue
			var az0 := TAU * i / A
			var az1 := TAU * (i + 1) / A
			var e0 := lerpf(el0, PI * 0.5, float(j) / E)
			var e1 := lerpf(el0, PI * 0.5, float(j + 1) / E)
			var a := _shell_point(az0, e0, grow, amp)
			var b := _shell_point(az1, e0, grow, amp)
			var c := _shell_point(az1, e1, grow, amp)
			var d := _shell_point(az0, e1, grow, amp)
			var want := -_dir(az_c, el_c) if inward else _dir(az_c, el_c)
			_tri(st, a, b, c, want)
			_tri(st, a, c, d, want)
	st.generate_normals()
	return st.commit()


## Adds a triangle wound so its front face points along `want`
## (Godot treats clockwise as front-facing).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-5:
		return
	if n.dot(want) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _build_cave() -> void:
	_noise_rock.seed = 9
	_noise_rock.frequency = 0.35
	_noise_rock.fractal_octaves = 3
	var mat: Material
	if ResourceLoader.exists(ROCK_MATERIAL):
		mat = load(ROCK_MATERIAL).duplicate()
	else:
		mat = U.mat(Color(0.35, 0.33, 0.31), 0.95)

	var cave := StaticBody3D.new()
	cave.name = "Cave"
	cave.position = CAVE
	add_child(cave)

	var inner := _shell_mesh(0.0, 1.0, true)
	var inner_mi := MeshInstance3D.new()
	inner_mi.mesh = inner
	inner_mi.material_override = mat
	inner_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	cave.add_child(inner_mi)
	var outer_mi := MeshInstance3D.new()
	outer_mi.mesh = _shell_mesh(1.6, 1.4, false)
	outer_mi.material_override = mat
	outer_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	cave.add_child(outer_mi)

	var cs := CollisionShape3D.new()
	var shape := inner.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape
	cave.add_child(cs)

	# Darker ambient light inside the cave so the fire carries it.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(CAVE_R.x * 2.0, CAVE_R.y + 1.0, CAVE_R.z * 2.0 - 2.0)
	probe.position = Vector3(0.0, CAVE_R.y * 0.5, -1.5)
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.25, 0.2, 0.17)
	probe.ambient_color_energy = 0.35
	probe.interior = true
	probe.blend_distance = 2.0
	cave.add_child(probe)

	# Solid lip round the mouth: joins the inner wall to the outer wall so
	# there's no open gap (that gap made the old edge boulders look like they
	# were floating).
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = _rim_mesh(0.0, 1.0, 1.6, 1.4)
	rim_mi.material_override = mat
	rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	cave.add_child(rim_mi)

	# A few boulders sitting on the ground at the foot of the mouth.
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	if scenes.is_empty():
		return
	for side in [-1.0, 1.0]:
		for k in 2:
			var az := deg_to_rad((MOUTH_HALF_DEG + 6.0 + k * 9.0) * side)
			var foot := _shell_point(az, 0.0, 2.2 + k * 0.8, 0.0)
			var world := CAVE + Vector3(foot.x, 0.0, foot.z)
			var rock: Node3D = scenes[rng.randi() % scenes.size()].instantiate()
			rock.scale = Vector3.ONE * rng.randf_range(0.42, 0.58) * (1.0 - k * 0.25)
			rock.position = Vector3(foot.x, _ground(world) - CAVE.y - 0.35, foot.z)
			rock.rotation = Vector3(0.0, rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
			cave.add_child(rock)


## Bridges the inner and outer cave shells along every edge of the mouth
## opening (both shells skip exactly the same cells, so the edges line up).
func _rim_mesh(grow_in: float, amp_in: float, grow_out: float, amp_out: float) -> ArrayMesh:
	var A := 96
	var E := 22
	var el0 := -0.12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell_in_mouth := func(i: int, j: int) -> bool:
		if j < 0 or j >= E:
			return false
		var ii := posmod(i, A)
		return _in_mouth(TAU * (ii + 0.5) / A, lerpf(el0, PI * 0.5, (j + 0.5) / E))
	for i in A:
		for j in E:
			if cell_in_mouth.call(i, j):
				continue
			var az0 := TAU * i / A
			var az1 := TAU * (i + 1) / A
			var e0 := lerpf(el0, PI * 0.5, float(j) / E)
			var e1 := lerpf(el0, PI * 0.5, float(j + 1) / E)
			var edges := []
			if cell_in_mouth.call(i + 1, j):
				edges.append([az1, e0, az1, e1])
			if cell_in_mouth.call(i - 1, j):
				edges.append([az0, e0, az0, e1])
			if cell_in_mouth.call(i, j + 1):
				edges.append([az0, e1, az1, e1])
			if cell_in_mouth.call(i, j - 1):
				edges.append([az0, e0, az1, e0])
			for ed in edges:
				var a := _shell_point(ed[0], ed[1], grow_in, amp_in)
				var b := _shell_point(ed[2], ed[3], grow_in, amp_in)
				var c := _shell_point(ed[2], ed[3], grow_out, amp_out)
				var d := _shell_point(ed[0], ed[1], grow_out, amp_out)
				# Both faces, each with its own flat normal, so the lip shows
				# and lights correctly from either side.
				var n: Vector3 = (b - a).cross(c - a).normalized()
				for tri in [[a, b, c, -n], [a, c, d, -n], [a, c, b, n], [a, d, c, n]]:
					st.set_normal(tri[3])
					st.add_vertex(tri[0])
					st.set_normal(tri[3])
					st.add_vertex(tri[1])
					st.set_normal(tri[3])
					st.add_vertex(tri[2])
	return st.commit()


# ---------------------------------------------------------------- campfire

func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _particles(amount: int, lifetime: float, colors: Gradient, size: float, rise: float, spread: float, additive: bool) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = spread
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = rise * 0.6
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0.0, rise * 0.6, 0.0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	pm.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.25 if additive else 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat

	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = pm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 8, 4))
	return p


func _build_campfire() -> void:
	var fire := Node3D.new()
	fire.name = "Campfire"
	fire.position = FIRE_POS + Vector3(0.0, _ground(FIRE_POS), 0.0)
	add_child(fire)

	# Stone ring.
	var stone := WK.model_mesh("Pebble_Round_1")
	var stone_mat := U.mat(Color(0.3, 0.29, 0.28), 0.95)
	for i in 10:
		var a := TAU * i / 10.0
		var mi := MeshInstance3D.new()
		if stone != null:
			mi.mesh = stone
			mi.scale = Vector3.ONE * rng.randf_range(0.9, 1.3)
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.22
			mi.mesh = sm
			mi.material_override = stone_mat
		mi.position = Vector3(cos(a) * 0.7, 0.02, sin(a) * 0.7)
		mi.rotation.y = rng.randf() * TAU
		fire.add_child(mi)

	# Logs, leaning into a cone.
	var log_mat := U.mat(Color(0.22, 0.14, 0.09), 0.95)
	var char_mat := U.mat(Color(0.06, 0.05, 0.05), 1.0, Color(1.0, 0.3, 0.05), 0.6)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.08
		cm.height = 0.9
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = log_mat if i % 2 == 0 else char_mat
		var foot := Vector3(cos(a) * 0.42, 0.04, sin(a) * 0.42)
		var tip := Vector3(cos(a) * 0.05, 0.62, sin(a) * 0.05)
		mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (tip - foot).normalized())), (foot + tip) * 0.5)
		fire.add_child(mi)

	# Glowing embers bed.
	var embers := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.42
	em.bottom_radius = 0.48
	em.height = 0.06
	embers.mesh = em
	embers.position.y = 0.03
	embers.material_override = U.mat(Color(0.2, 0.05, 0.02), 0.9, Color(1.0, 0.35, 0.08), 2.5)
	fire.add_child(embers)

	var flame_colors := Gradient.new()
	flame_colors.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	flame_colors.set_color(1, Color(0.8, 0.12, 0.02, 0.0))
	flame_colors.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
	var flames := _particles(48, 0.8, flame_colors, 0.45, 1.3, 0.22, true)
	flames.position.y = 0.15
	fire.add_child(flames)

	var spark_colors := Gradient.new()
	spark_colors.set_color(0, Color(1.0, 0.7, 0.3, 1.0))
	spark_colors.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var sparks := _particles(16, 1.6, spark_colors, 0.05, 2.4, 0.3, true)
	sparks.position.y = 0.3
	fire.add_child(sparks)

	var smoke_colors := Gradient.new()
	smoke_colors.set_color(0, Color(0.3, 0.3, 0.3, 0.0))
	smoke_colors.set_color(1, Color(0.25, 0.25, 0.25, 0.0))
	smoke_colors.add_point(0.25, Color(0.28, 0.28, 0.28, 0.35))
	var smoke := _particles(20, 4.0, smoke_colors, 1.0, 0.9, 0.3, false)
	smoke.position.y = 0.9
	fire.add_child(smoke)

	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.22)
	_fire_light.light_energy = 3.2
	_fire_light.omni_range = 13.0
	_fire_light.shadow_enabled = true
	_fire_light.position.y = 0.9
	fire.add_child(_fire_light)
	Sfx.loop(fire, "fire_loop", 0.0, 4.0)

	_add_interact(fire.position, "Rest by the fire (restore health)", _rest)


func _rest() -> void:
	player.heal(player.max_health)
	_show_banner("You rest by the fire.\nHealth restored.", 2.5)


# ---------------------------------------------------------------- camp interior

const PROPS_GLB := "res://models/camp_props.glb"
const BED_L := Vector3(-2.75, 0.0, -12.5)
const BED_R := Vector3(2.75, 0.0, -12.5)
var _props_lib: Node3D


func _exit_tree() -> void:
	if _props_lib != null:
		_props_lib.free()


## Places a prop from models/camp_props.glb (front = +Z) on the ground at
## `pos` (pos.y lifts it), with an optional solid box of `solid` size.
func _prop(prop_name: String, pos: Vector3, yaw_deg: float, solid := Vector3.ZERO, s := 1.0) -> StaticBody3D:
	if _props_lib == null and ResourceLoader.exists(PROPS_GLB):
		_props_lib = load(PROPS_GLB).instantiate()
	var body := StaticBody3D.new()
	body.name = prop_name
	body.position = pos + Vector3(0.0, _ground(pos), 0.0)
	body.rotation_degrees.y = yaw_deg
	add_child(body)
	if _props_lib != null:
		var src := _props_lib.find_child(prop_name, true, false) as Node3D
		if src != null:
			var m := src.duplicate() as Node3D
			m.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * s)
			body.add_child(m)
	if solid != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = solid * s
		cs.shape = box
		cs.position.y = solid.y * s * 0.5
		body.add_child(cs)
	return body


## A readable datapad / journal lying at `local` on top of `on` (or in the world).
func _readable(kind: String, on: Node3D, local: Vector3, yaw_deg: float, id: String) -> void:
	var where: Transform3D = on.global_transform if on != null else Transform3D.IDENTITY
	var pad := Node3D.new()
	add_child(pad)
	pad.global_transform = where * Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), local)
	if _props_lib != null:
		var src := _props_lib.find_child(kind, true, false) as Node3D
		if src != null:
			var m := src.duplicate() as Node3D
			m.transform = Transform3D.IDENTITY
			pad.add_child(m)
	var title := String(Lore.entry(id).get("title", "log"))
	var it = Interactable.new()
	it.prompt = "Read: %s" % title
	it.reach = 1.8
	it.action = func(): LorePanel.read(get_tree(), id)
	pad.add_child(it)


## Upgrade station (armory locker, med bench, droid bench): opens that track's panel.
func _add_station(prop_name: String, pos: Vector3, yaw_deg: float, size: Vector3, track: String, stripe: Color) -> StaticBody3D:
	var body := _prop(prop_name, pos, yaw_deg, size)
	var info: Dictionary = GS.TRACKS[track]
	var tag := Label3D.new()
	tag.text = String(info["crate"])
	tag.font_size = 40
	tag.pixel_size = 0.004
	tag.modulate = stripe.lightened(0.3)
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.position = Vector3(0.0, size.y + 0.3, 0.0)
	body.add_child(tag)
	var glow := OmniLight3D.new()
	glow.light_color = stripe
	glow.light_energy = 0.5
	glow.omni_range = 2.6
	glow.position = Vector3(0.0, size.y * 0.7, size.z * 0.5 + 0.5)
	body.add_child(glow)
	var front := body.global_transform * Vector3(0.0, 0.0, size.z * 0.5 + 0.35)
	_add_interact(front, "Use %s  (%s upgrades)" % [String(info["crate"]).capitalize(), info["title"]], func(): _open_panel(track))
	return body


func _yaw_to(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.x - from.x, to.z - from.z))


func _build_crates() -> void:
	var mid := CAVE + Vector3(0.0, 0.0, 0.5)
	# Upgrade stations round the back of the cave.
	var lp := Vector3(-5.6, 0.0, -19.6)
	_add_station("ArmoryLocker", lp, _yaw_to(lp, mid), Vector3(1.28, 2.12, 0.66), "blaster", Color(0.9, 0.12, 0.08))
	var mp := Vector3(0.0, 0.0, -25.2)
	var med := _add_station("MedBench", mp, 0.0, Vector3(1.66, 1.9, 0.72), "armor", Color(0.45, 1.0, 0.7))
	var dp := Vector3(5.5, 0.0, -19.8)
	var droid_bench := _add_station("DroidBench", dp, _yaw_to(dp, mid), Vector3(1.92, 1.95, 0.84), "droid", Color(0.25, 0.6, 1.0))
	_readable("Datapad", med, Vector3(-0.62, 0.862, 0.12), 15.0, "med_log")
	_readable("Datapad", droid_bench, Vector3(-0.68, 0.902, 0.27), -10.0, "droid_manual")

	# Two field beds either side of the fire, a cook pot over it.
	_prop("Bed", BED_L, 4.0, Vector3(1.06, 0.6, 2.2))
	_prop("Bed", BED_R, -4.0, Vector3(1.06, 0.6, 2.2))
	_prop("CookPot", FIRE_POS, 20.0)
	var stand := _prop("SupplyCrate", BED_L + Vector3(-1.05, 0.0, -0.75), 8.0, Vector3(1.0, 0.7, 0.7), 0.6)
	_readable("Journal", stand, Vector3(0.05, 0.422, 0.02), -20.0, "survivor_journal")

	# Supplies and clutter.
	var c := CAVE
	_prop("SupplyCrate", c + Vector3(-6.2, 0.0, 1.5), 80.0, Vector3(1.0, 0.7, 0.7))
	var top := _prop("SupplyCrate", c + Vector3(-6.05, 0.7, 1.4), 68.0, Vector3(1.0, 0.7, 0.7), 0.8)
	_readable("Datapad", top, Vector3(0.0, 0.562, 0.0), 30.0, "quartermaster")
	var rc := _prop("SupplyCrate", c + Vector3(6.3, 0.0, 2.0), -75.0, Vector3(1.0, 0.7, 0.7), 1.1)
	var radio := _prop("Radio", rc.position - Vector3(0.0, _ground(rc.position), 0.0) + Vector3(0.0, 0.77, 0.0), -75.0)
	_add_interact(radio.global_position + Vector3(0.0, 0.2, 0.0), "Listen to the radio", func(): LorePanel.read(get_tree(), "radio"))
	_prop("SupplyCrate", c + Vector3(2.8, 0.0, -8.0), 10.0, Vector3(1.0, 0.7, 0.7), 0.9)
	_prop("Shelf", Vector3(-3.4, 0.0, -24.5), 25.0, Vector3(1.2, 1.85, 0.45))
	_prop("Purifier", Vector3(-6.6, 0.0, -17.2), 80.0, Vector3(0.62, 1.15, 0.62))
	var gen := _prop("Generator", Vector3(3.7, 0.0, -24.1), -20.0, Vector3(1.1, 1.4, 0.8))
	var core := OmniLight3D.new()
	core.light_color = Color(0.35, 0.75, 1.0)
	core.light_energy = 0.9
	core.omni_range = 3.5
	core.position = Vector3(0.0, 1.05, 0.3)
	gen.add_child(core)
	var tw := core.create_tween().set_loops()
	tw.tween_property(core, "light_energy", 1.2, 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(core, "light_energy", 0.7, 1.4).set_trans(Tween.TRANS_SINE)
	_prop("Rug", Vector3(0.0, 0.0, -20.6), 0.0)
	var holo := _prop("HoloMap", Vector3(0.0, 0.0, -20.6), 0.0, Vector3(1.0, 0.9, 1.0))
	var hl := OmniLight3D.new()
	hl.light_color = Color(1.0, 0.75, 0.4)
	hl.light_energy = 0.7
	hl.omni_range = 2.5
	hl.position = Vector3(0.0, 1.3, 0.0)
	holo.add_child(hl)
	_add_interact(holo.global_position + Vector3(0.0, 0.9, 0.0), "Read: Survey Map", func(): LorePanel.read(get_tree(), "survey_map"))

	# Work lamps light the back of the cave (replacing the old bare bulb).
	for spec in [[Vector3(-3.9, 0.0, -22.3), true], [Vector3(3.9, 0.0, -22.1), false]]:
		var lpos: Vector3 = spec[0]
		var lamp := _prop("WorkLamp", lpos, _yaw_to(lpos, mid), Vector3(0.3, 2.0, 0.3))
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.9, 0.75)
		spot.light_energy = 3.0
		spot.spot_range = 12.0
		spot.spot_angle = 55.0
		spot.shadow_enabled = spec[1]
		spot.position = Vector3(0.0, 1.9, 0.12)
		spot.rotation = Vector3(-0.45, PI, 0.0)
		lamp.add_child(spot)


# ---------------------------------------------------------------- trail back

## The way back to the crash site: no sign, just a gap in the trees where the
## path squeezes between two mossy boulders, a fallen log beside it and
## ferns closing in.
func _build_trail_exit() -> void:
	var pos := Vector3(0.0, 0.0, 24.0)
	pos.y = _ground(pos)
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	var r := RandomNumberGenerator.new()
	r.seed = 24
	if not scenes.is_empty():
		for spec in [[Vector3(-2.9, 0.0, 0.4), 0.85], [Vector3(3.1, 0.0, -0.6), 0.7], [Vector3(-4.3, 0.0, 2.2), 0.5], [Vector3(4.4, 0.0, 1.6), 0.45]]:
			var rp: Vector3 = pos + spec[0]
			var rock: Node3D = scenes[r.randi() % scenes.size()].instantiate()
			rock.scale = Vector3.ONE * float(spec[1]) * r.randf_range(0.9, 1.1)
			rock.rotation = Vector3(0.0, r.randf() * TAU, r.randf_range(-0.15, 0.15))
			rock.position = Vector3(rp.x, _ground(rp) - 0.4, rp.z)
			add_child(rock)
	var log_mesh := WK.model_mesh("FallenLog")
	if log_mesh != null:
		var lg := MeshInstance3D.new()
		lg.mesh = log_mesh
		var lp := pos + Vector3(-4.0, 0.0, -1.4)
		lg.position = Vector3(lp.x, _ground(lp) - 0.12, lp.z)
		lg.rotation = Vector3(0.0, deg_to_rad(62.0), deg_to_rad(-4.0))
		add_child(lg)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.34
		cap.height = 5.0
		cs.shape = cap
		cs.rotation.z = PI * 0.5
		body.add_child(cs)
		body.position = lg.position + Vector3(0.0, 0.3, 0.0)
		body.rotation = lg.rotation
		add_child(body)
	_scatter(["Fern_1", "Plant_1_Big", "Bush_Common", "Grass_Wispy_Tall", "Grass_Common_Tall"], pos, 2.2, 6.5, 46, 0.7, 1.4, 25)
	_scatter(["Fern_1", "Grass_Wispy_Short", "Clover_1"], pos + Vector3(0.0, 0.0, -2.5), 1.2, 3.0, 14, 0.5, 0.9, 26)
	_add_interact(pos + Vector3(0.0, 1.0, 0.0), "Follow the trail back to the crash site (fight for more salvage)", func(): get_tree().change_scene_to_file(CRASH_SITE))


## A few cherry trees in full blossom scattered through the open valley.
const CHERRY_SPOTS := [Vector3(-13.0, 0.0, 15.0), Vector3(15.5, 0.0, 19.0), Vector3(-24.0, 0.0, 2.0), Vector3(30.0, 0.0, 26.0),
	Vector3(-33.0, 0.0, 33.0), Vector3(26.0, 0.0, -14.0), Vector3(-9.0, 0.0, 34.0)]

func _build_cherry_trees() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 88
	for i in CHERRY_SPOTS.size():
		var p: Vector3 = CHERRY_SPOTS[i]
		var mesh := WK.model_mesh("Cherry_%d" % (i % 3 + 1))
		if mesh == null:
			return
		var s := r.randf_range(1.1, 1.4)
		p.y = _ground(p) - 0.12
		WK.place(self, mesh, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), p))
		WK.trunk_collider(self, p, s * 0.95)


# ---------------------------------------------------------------- forest

func _build_forest() -> void:
	var pines := WK.meshes(WK.PINES)
	if pines.is_empty():
		return
	var leafy := WK.meshes(WK.LEAFY)
	var dead := WK.meshes(WK.DEAD)
	var buckets := {}
	var tries := 0
	var placed := 0
	while placed < 1150 and tries < 14000:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(16.0 * 16.0, 150.0 * 150.0))
		var p := Vector3(VALLEY_CENTER.x + cos(a) * r, 0.0, VALLEY_CENTER.y + sin(a) * r)
		# Keep the cave mouth, the path and the cave itself clear.
		var e := Vector2(p.x / (CAVE_R.x + 3.0), (p.z - CAVE.z) / (CAVE_R.z + 3.0)).length()
		if e < 1.0:
			continue
		if absf(p.x) < 9.0 and p.z > CAVE.z and p.z < 30.0:
			continue
		if _landmark_clear(p, 4.0):
			continue
		# The open valley gets scattered groves; the dense forest starts at the hills.
		if r < 70.0 and _noise_hill.get_noise_2d(p.x * 4.0, p.z * 4.0) < 0.12:
			continue
		p.y = _ground(p) - 0.15
		var roll := rng.randf()
		var mesh: Mesh = pines[rng.randi() % pines.size()]
		if roll < 0.06 and not dead.is_empty():
			mesh = dead[rng.randi() % dead.size()]
		elif roll < 0.3 and not leafy.is_empty():
			mesh = leafy[rng.randi() % leafy.size()]
		var s := rng.randf_range(1.5, 2.4)
		WK.add_instance(buckets, mesh, p, s, rng)
		if r < 92.0:
			WK.trunk_collider(self, p, s)
		placed += 1
	WK.plant(self, buckets, 260.0)

	var small_names := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1_Big", "Mushroom_Common", "Rock_Medium_1", "Rock_Medium_2"]
	var scales := [Vector2(0.9, 1.5), Vector2(0.9, 1.4), Vector2(0.15, 0.25), Vector2(0.6, 1.0), Vector2(0.8, 1.3), Vector2(0.5, 1.1), Vector2(0.5, 1.1)]
	var small := []
	var small_scales := []
	for i in small_names.size():
		var m := WK.model_mesh(small_names[i])
		if m != null:
			small.append(m)
			small_scales.append(scales[i])
	if small.is_empty():
		return
	var sb := {}
	for i in 760:
		var a := rng.randf() * TAU
		var r := rng.randf_range(9.0, 80.0)
		var p := Vector3(VALLEY_CENTER.x + cos(a) * r, 0.0, VALLEY_CENTER.y + sin(a) * r)
		var e := Vector2(p.x / (CAVE_R.x + 1.5), (p.z - CAVE.z) / (CAVE_R.z + 1.5)).length()
		if e < 1.0 or (absf(p.x) < 3.0 and p.z > CAVE.z) or _landmark_clear(p, 0.0):
			continue
		p.y = _ground(p) - 0.05
		var k := rng.randi() % small.size()
		var sc: Vector2 = small_scales[k]
		WK.add_instance(sb, small[k], p, rng.randf_range(sc.x, sc.y), rng)
	WK.plant(self, sb, 110.0)


## True where trees and clutter should stay clear (water, landmarks, the pod).
func _landmark_clear(p: Vector3, pad: float) -> bool:
	var q := Vector2(p.x, p.z)
	for c in CHERRY_SPOTS:
		if q.distance_to(Vector2(c.x, c.z)) < 4.0 + pad * 0.5:
			return true
	return q.distance_to(Vector2(LAKE.x, LAKE.z)) < LAKE_R + 2.0 + pad \
		or q.distance_to(Vector2(SPIRES.x, SPIRES.z)) < 13.0 + pad \
		or q.distance_to(Vector2(OUTPOST.x, OUTPOST.z)) < 16.0 + pad \
		or q.distance_to(Vector2(MEADOW.x, MEADOW.z)) < 9.0 + pad \
		or q.distance_to(Vector2(POD_POS.x, POD_POS.z)) < 6.0 + pad


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	_salvage_label = UI.label("SALVAGE  0", 24, Color(1.0, 0.8, 0.45))
	_salvage_label.position = Vector2(28, 20)
	root.add_child(_salvage_label)

	var hint := UI.label("WASD move  ·  E interact  ·  Tab inventory  ·  H heal  ·  R reload  ·  Q weapon  ·  G grenade  ·  Esc menu", 16, UI.MUTED)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_right = 1.0
	hint.offset_top = -66
	hint.offset_bottom = -14
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.offset_left = 390
	hint.offset_right = -390
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	_prompt = UI.label("", 24, UI.TEXT)
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = -150
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	root.add_child(_prompt)

	_banner = UI.label("", 34, UI.TEXT)
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.22
	_banner.anchor_bottom = 0.22
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	var center := UI.full_rect(CenterContainer.new())
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = UI.panel()
	_panel.visible = false
	center.add_child(_panel)
	var v := UI.vbox(10)
	_panel.add_child(v)
	_p_title = UI.label("", 34, UI.ACCENT)
	v.add_child(_p_title)
	_p_blurb = UI.label("", 18, UI.MUTED)
	v.add_child(_p_blurb)
	_p_level = UI.label("", 22, UI.TEXT)
	v.add_child(_p_level)
	_p_stat = UI.label("", 22, UI.TEXT)
	v.add_child(_p_stat)
	_p_salvage = UI.label("", 20, Color(1.0, 0.8, 0.45))
	v.add_child(_p_salvage)
	_p_buy = UI.button("UPGRADE", 380)
	_p_buy.pressed.connect(_buy)
	v.add_child(_p_buy)
	_p_close = UI.button("CLOSE", 380)
	_p_close.pressed.connect(_close_panel)
	v.add_child(_p_close)


var _banner_tw: Tween


func _hide_banner() -> void:
	if _banner_tw != null:
		_banner_tw.kill()
	_banner_tw = create_tween()
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _show_banner(text: String, duration: float) -> void:
	_banner.text = text
	if _banner_tw != null:
		_banner_tw.kill()
	var tw := create_tween()
	_banner_tw = tw
	tw.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(duration)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.8)


func _open_panel(track: String) -> void:
	Sfx.ui("crate_open", -4.0, 0.05)
	_panel_track = track
	_refresh_panel()
	_panel.visible = true
	_prompt.visible = false
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _p_buy.disabled:
		_p_close.grab_focus()
	else:
		_p_buy.grab_focus()


func _close_panel() -> void:
	_panel.visible = false
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_panel() -> void:
	var t: Dictionary = GS.TRACKS[_panel_track]
	var lvl := GS.level(_panel_track)
	var mx: int = t["max"]
	_p_title.text = "%s  ·  %s" % [t["crate"], t["title"]]
	_p_blurb.text = t["blurb"]
	_p_level.text = "Level %d / %d" % [lvl, mx]
	var now := GS.stat_at(_panel_track, lvl)
	if GS.is_maxed(_panel_track):
		_p_stat.text = "%s: %d  (fully upgraded)" % [t["stat"], int(now)]
		_p_buy.text = "MAXED OUT"
		_p_buy.disabled = true
	else:
		var nxt := GS.stat_at(_panel_track, lvl + 1)
		_p_stat.text = "%s: %d  →  %d" % [t["stat"], int(now), int(nxt)]
		_p_buy.text = "UPGRADE  ·  %d salvage" % GS.cost(_panel_track)
		_p_buy.disabled = not GS.can_upgrade(_panel_track)
	_p_salvage.text = "You have %d salvage" % GS.salvage


func _buy() -> void:
	if not GS.upgrade(_panel_track):
		return
	Sfx.ui("upgrade", -4.0)
	# Apply straight away.
	player.damage = GS.player_damage()
	var old_max: float = player.max_health
	player.max_health = GS.player_max_health()
	if player.max_health > old_max:
		player.heal(player.max_health - old_max)
	droid.damage = GS.droid_damage()
	_refresh_panel()
	if _p_buy.disabled:
		_p_close.grab_focus()


# ---------------------------------------------------------------- talking

func _start_talk() -> void:
	if _talk == null:
		_talk = UI.panel()
		_talk.anchor_left = 0.2
		_talk.anchor_right = 0.8
		_talk.anchor_top = 1.0
		_talk.anchor_bottom = 1.0
		_talk.offset_top = -230
		_talk.offset_bottom = -60
		_ui.add_child(_talk)
		var v := UI.vbox(8)
		_talk.add_child(v)
		_talk_name = UI.label("", 22, UI.ACCENT)
		v.add_child(_talk_name)
		_talk_text = UI.label("", 22, UI.TEXT)
		_talk_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_talk_text.custom_minimum_size = Vector2(600, 0)
		v.add_child(_talk_text)
		v.add_child(UI.label("E / Space: continue   ·   Esc: skip", 14, UI.MUTED))
	_talk.visible = true
	_prompt.visible = false
	player.input_enabled = false
	_talk_index = -1
	_next_line()


func _next_line() -> void:
	_talk_index += 1
	if _talk_index >= TALK.size():
		_end_talk()
		return
	var line: Array = TALK[_talk_index]
	_talk_name.text = line[0]
	_talk_text.text = line[1]


func _end_talk() -> void:
	_talk.visible = false
	player.input_enabled = true
	# She gets up and comes with you from now on.
	GS.ally_joined = true
	GS.add_xp(15)
	GS.changed()
	if _talk_node != null:
		_talk_node.queue_free()
		_talk_node = null
	ally.follow(player)
	_show_banner("She shoulders her rifle and falls in beside you.\nShe'll fight with you from now on.", 4.0)



# ---------------------------------------------------------------- interactables

func _add_interact(pos: Vector3, prompt: String, action: Callable):
	var n = Interactable.new()
	n.prompt = prompt
	n.action = action
	n.position = pos
	add_child(n)
	return n


# ---------------------------------------------------------------- crafting bench

const BENCH_POS := Vector3(-5.35, 0.0, -13.4)

func _build_bench() -> void:
	var p := BENCH_POS + Vector3(0.0, _ground(BENCH_POS), 0.0)
	_bench_spot = _add_interact(p, "", _use_bench)
	_update_bench()


func _bench_prompt() -> String:
	if GS.bench_level <= 0:
		var c: Dictionary = Items.BENCH_LEVELS[1]["in"]
		return "Build crafting bench  (Wood %d/%d, Metal Scrap %d/%d)" % [GS.count("wood"), c["wood"], GS.count("scrap"), c["scrap"]]
	return "Use crafting bench"


func _use_bench() -> void:
	if GS.bench_level <= 0:
		if GS.upgrade_bench():
			Sfx.ui("upgrade", -3.0)
			_update_bench()
		else:
			GS.toast("Need 4 Wood and 3 Metal Scrap to build the bench.")
		return
	crafting.open()


func _process_bench() -> void:
	if _bench_spot != null:
		_bench_spot.prompt = _bench_prompt()


func _update_bench() -> void:
	if _bench_model != null:
		_bench_model.queue_free()
		_bench_model = null
	var lv := clampi(GS.bench_level, 0, 2)
	_bench_model = _prop("CraftBench%d" % lv, BENCH_POS, 70.0, Vector3.ZERO if lv == 0 else Vector3(1.8, 0.95, 0.8))
	if lv <= 0:
		return
	var tag := Label3D.new()
	tag.text = "CRAFTING BENCH  Lv%d" % GS.bench_level
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.position = Vector3(0.0, 1.75, 0.0)
	_bench_model.add_child(tag)
	if lv >= 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 0.8
		l.omni_range = 2.5
		l.position = Vector3(-0.55, 1.55, 0.0)
		_bench_model.add_child(l)


# ---------------------------------------------------------------- resources

## Sticks, fibre plants and loose ore around the valley.
func _build_resources() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	# Wood piles close to camp, out in front of the cave, so the first quest
	# can always be done without wandering.
	for wp in [Vector3(-5.0, 0, -3.0), Vector3(4.5, 0, -2.0), Vector3(-8.0, 0, 3.0), Vector3(7.5, 0, 4.0),
			Vector3(-3.0, 0, 7.0), Vector3(2.5, 0, 10.0), Vector3(-10.5, 0, 9.0), Vector3(10.0, 0, 11.0)]:
		var q: Vector3 = wp
		q.y = _ground(q)
		Pickup.spawn(self, "resource", "wood", q, Vector2i(1, 2))
	var spots := {"wood": 22, "fiber": 20, "ore": 8}
	for id in spots:
		for i in spots[id]:
			var a := r.randf() * TAU
			var d := r.randf_range(8.0, 66.0)
			var p := Vector3(VALLEY_CENTER.x + cos(a) * d, 0.0, VALLEY_CENTER.y + sin(a) * d)
			var e := Vector2(p.x / (CAVE_R.x + 2.0), (p.z - CAVE.z) / (CAVE_R.z + 2.0)).length()
			if e < 1.0 or Vector2(p.x - LAKE.x, p.z - LAKE.z).length() < LAKE_R + 1.0:
				continue
			p.y = _ground(p)
			Pickup.spawn(self, "resource", id, p, Vector2i(1, 2))
	# Choppable trees near the valley floor and two ore veins at the cliff foot.
	for t in [Vector3(-14, 0, 10), Vector3(15, 0, 6), Vector3(-19, 0, -2), Vector3(18, 0, -6), Vector3(-9, 0, 20)]:
		var tp: Vector3 = t
		tp.y = _ground(tp)
		Pickup.spawn(self, "tree", "", tp)
		var pine := WK.model_mesh("Pine_2")
		if pine != null:
			WK.place(self, pine, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.9), tp + Vector3(0.0, -0.15, 0.0)))
		WK.trunk_collider(self, tp, 1.9)
	for v in [Vector3(-11, 0, -8), Vector3(12, 0, -10)]:
		var vp: Vector3 = v
		vp.y = _ground(vp)
		Pickup.spawn(self, "vein", "ore", vp)


## A crashed escape pod east of camp: scrap, plastic and supply crates.
func _build_pod_wreck() -> void:
	var c := POD_POS
	c.y = _ground(c)
	var root := Node3D.new()
	root.name = "EscapePod"
	root.position = c - Vector3(0.0, 0.15, 0.0)
	root.rotation.y = deg_to_rad(30.0)
	add_child(root)
	if ResourceLoader.exists("res://models/escape_pod.glb"):
		var pod: Node3D = load("res://models/escape_pod.glb").instantiate()
		root.add_child(pod)
		var hull := pod.find_child("Pod", true, false) as MeshInstance3D
		if hull != null:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := hull.mesh.create_trimesh_shape()
			shape.backface_collision = true
			cs.shape = shape
			body.add_child(cs)
			hull.add_child(body)
		var lamp := pod.find_child("Beacon", true, false) as GeometryInstance3D
		if lamp != null:
			var tw := lamp.create_tween().set_loops()
			tw.tween_callback(func(): lamp.visible = true)
			tw.tween_interval(0.25)
			tw.tween_callback(func(): lamp.visible = false)
			tw.tween_interval(1.1)
	# Red emergency strobe, the heat shield's ember glow and its smoke.
	var strobe := OmniLight3D.new()
	strobe.light_color = Color(1.0, 0.15, 0.08)
	strobe.omni_range = 6.0
	strobe.position = Vector3(-0.4, 2.1, 1.3)
	root.add_child(strobe)
	var stw := strobe.create_tween().set_loops()
	stw.tween_property(strobe, "light_energy", 2.5, 0.05)
	stw.tween_interval(0.2)
	stw.tween_property(strobe, "light_energy", 0.0, 0.1)
	stw.tween_interval(1.0)
	var ember := OmniLight3D.new()
	ember.light_color = Color(1.0, 0.45, 0.15)
	ember.light_energy = 1.4
	ember.omni_range = 4.5
	ember.position = Vector3(0.0, 0.9, -3.0)
	root.add_child(ember)
	var smoke_colors := Gradient.new()
	smoke_colors.set_color(0, Color(0.25, 0.24, 0.23, 0.0))
	smoke_colors.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	smoke_colors.add_point(0.2, Color(0.22, 0.21, 0.2, 0.45))
	var smoke := _particles(18, 5.0, smoke_colors, 1.4, 1.1, 0.5, false)
	smoke.position = Vector3(0.0, 1.0, -2.6)
	root.add_child(smoke)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for k in 5:
		var id := "scrap" if k < 3 else "plastic"
		var a := r.randf() * TAU
		var p := c + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(3.6, 6.0)
		p.y = _ground(p)
		Pickup.spawn(self, "resource", id, p, Vector2i(1, 3))
	for k in 3:
		var p2 := c + Vector3(-3.0 + k * 3.0, 0.0, 3.2 + (k % 2) * 0.8)
		p2.y = _ground(p2)
		Pickup.spawn(self, "crate", "", p2)
	var tag := Label3D.new()
	tag.text = "ESCAPE POD"
	tag.font_size = 40
	tag.pixel_size = 0.005
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.modulate = Color(1.0, 0.7, 0.4)
	tag.position = c + Vector3(0.0, 3.2, 0.0)
	add_child(tag)


# ---------------------------------------------------------------- compass

## Where the current camp quest wants you to go (gold marker on the compass).
func _quest_target():
	var q := GS.current_quest()
	if q.is_empty():
		return null
	for g in q["goals"]:
		var id: String = g[0]
		if GS.goal_done(id):
			continue
		var parts := id.split(":")
		match parts[0]:
			"talk":
				return ally.global_position if is_instance_valid(ally) else null
			"have":
				if parts[1] == "tech":
					return _nearest_pickup("crate", "")
				if parts[1] == "scrap":
					var sp = _nearest_pickup("resource", "scrap")
					return sp if sp != null else POD_POS
				return _nearest_pickup("resource", parts[1])
			"bench", "crafted", "equipped_module":
				return BENCH_POS + Vector3(0.0, _ground(BENCH_POS), 0.0)
			"chopped":
				return _nearest_pickup("tree", "")
			_:
				return null
	return null


func _nearest_pickup(kind: String, id: String):
	var best = null
	var bd := INF
	var from: Vector3 = player.global_position if is_instance_valid(player) else Vector3.ZERO
	for n in get_tree().get_nodes_in_group("interactable"):
		if not ("kind" in n) or n.kind != kind or (id != "" and n.item_id != id):
			continue
		if not n.enabled or not n.is_visible_in_tree():
			continue
		var d := from.distance_squared_to(n.global_position)
		if d < bd:
			bd = d
			best = n.global_position
	return best


# ---------------------------------------------------------------- landmarks

func _mat(col: Color, rough: float, metal := 0.0, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	var m := U.mat(col, rough, emit, emit_e) if emit_e > 0.0 else U.mat(col, rough)
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid := true, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		body.rotation = rot
		parent.add_child(body)
	return mi


func _sign(text: String, pos: Vector3, col: Color) -> void:
	var tag := Label3D.new()
	tag.text = text
	tag.font_size = 42
	tag.pixel_size = 0.006
	tag.outline_size = 10
	tag.modulate = col
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.position = pos
	add_child(tag)


func _scatter(names: Array, center: Vector3, r0: float, r1: float, count: int, s0: float, s1: float, seed_v: int, vis := 120.0) -> void:
	var meshes := WK.meshes(names)
	if meshes.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var b := {}
	for i in count:
		var a := r.randf() * TAU
		var d := sqrt(r.randf_range(r0 * r0, r1 * r1))
		var p := center + Vector3(cos(a) * d, 0.0, sin(a) * d)
		p.y = _ground(p) - 0.05
		WK.add_instance(b, meshes[r.randi() % meshes.size()], p, r.randf_range(s0, s1), r)
	WK.plant(self, b, vis)


## A still lake in the east of the valley, with reeds and a small jetty.
## Lake surface: refraction of the lake bed through depth-tinted water
## (red light absorbed first), two scrolling ripple normal maps, sky
## reflection via the fresnel term, foam where the water gets shallow
## (shore, rocks, dock posts) and slow swell in the vertices.
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.11, 0.34, 0.32);
uniform vec3 deep_col : source_color = vec3(0.015, 0.07, 0.09);
uniform vec3 absorb = vec3(1.1, 0.42, 0.3);
uniform float radius = 25.0;
uniform float refract_strength = 0.04;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	VERTEX.y += sin(wpos.x * 0.33 + t * 1.05) * 0.022 + sin(wpos.z * 0.47 - t * 0.85) * 0.018
		+ sin((wpos.x + wpos.z) * 0.9 + t * 1.7) * 0.008;
}

float scene_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.z / v.w;
}

void fragment() {
	if (length(wpos.xz - NODE_POSITION_WORLD.xz) > radius) { discard; }
	float t = TIME;
	vec3 n1 = texture(normal_a, wpos.xz * 0.06 + vec2(t * 0.011, t * 0.006)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_b, wpos.xz * 0.14 + vec2(-t * 0.009, t * 0.015)).rgb * 2.0 - 1.0;
	vec3 nm = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.55;

	float depth = max(VERTEX.z - scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX), 0.0);
	vec2 ruv = SCREEN_UV + nm.xy * refract_strength * clamp(depth * 0.7, 0.0, 1.0);
	float z2 = scene_depth(ruv, INV_PROJECTION_MATRIX);
	if (z2 > VERTEX.z) { ruv = SCREEN_UV; } else { depth = max(VERTEX.z - z2, 0.0); }
	vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 trans = exp(-absorb * depth);
	vec3 body_col = mix(shallow_col, deep_col, clamp(depth / 5.0, 0.0, 1.0));
	vec3 body = behind * trans + body_col * (1.0 - trans);

	float fn = texture(foam_tex, wpos.xz * 0.22 + vec2(t * 0.015, -t * 0.01)).r;
	float shore = 1.0 - smoothstep(0.0, 0.45, depth);
	float foam = smoothstep(0.45, 0.8, shore * (0.55 + 0.9 * fn) + 0.12 * sin(t * 1.4 + fn * 6.0));
	foam *= smoothstep(0.0, 0.04, depth);

	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(body_col * 0.25, vec3(0.86, 0.9, 0.9), foam);
	EMISSION = body * (1.0 - fres) * (1.0 - foam);
	ROUGHNESS = mix(0.035, 0.75, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	ALPHA = clamp(depth * 8.0, 0.0, 1.0);
}
"""


func _noise_tex(size: int, freq: float, seed_v: int, normal: bool, bump: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.noise = n
	tex.generate_mipmaps = true
	if normal:
		tex.as_normal_map = true
		tex.bump_strength = bump
	return tex


## Clusters of lily pads (some flowering) in the shallows round the lake.
func _build_lily_pads() -> void:
	if _props_lib == null and ResourceLoader.exists(PROPS_GLB):
		_props_lib = load(PROPS_GLB).instantiate()
	if _props_lib == null:
		return
	var src := _props_lib.find_child("LilyPads", true, false) as MeshInstance3D
	if src == null:
		return
	var r := RandomNumberGenerator.new()
	r.seed = 61
	for k in 9:
		var a := r.randf() * TAU
		if absf(wrapf(a - atan2(0.25, -1.0), -PI, PI)) < 0.5:
			continue   # keep the dock approach clear
		var d := r.randf_range(LAKE_R - 6.0, LAKE_R - 1.5)
		var p := LAKE + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if _ground(p) > WATER_Y - 0.05:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		mi.position = Vector3(p.x, WATER_Y + 0.015, p.z)
		mi.rotation.y = r.randf() * TAU
		mi.scale = Vector3.ONE * r.randf_range(0.8, 1.25)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_lake() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (LAKE_R + 7.0) * 2.0
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	water.mesh = plane
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wm.set_shader_parameter("radius", LAKE_R + 7.0)
	wm.set_shader_parameter("normal_a", _noise_tex(512, 0.012, 11, true, 5.0))
	wm.set_shader_parameter("normal_b", _noise_tex(512, 0.03, 23, true, 3.0))
	wm.set_shader_parameter("foam_tex", _noise_tex(256, 0.05, 37, false, 0.0))
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(LAKE.x, WATER_Y, LAKE.z)
	add_child(water)
	_build_lily_pads()
	# Wade in to your knees, no further.
	var block := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = LAKE_R - 4.5
	cyl.height = 8.0
	cs.shape = cyl
	block.add_child(cs)
	block.position = Vector3(LAKE.x, 2.0, LAKE.z)
	add_child(block)
	# Reeds, ferns and pebbles round the shore.
	_scatter(["Grass_Wispy_Tall", "Grass_Common_Tall", "Plant_7_Big", "Fern_1"], LAKE, LAKE_R - 1.0, LAKE_R + 4.0, 140, 0.8, 1.6, 51)
	_scatter(["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_2"], LAKE, LAKE_R - 2.0, LAKE_R + 3.0, 60, 0.8, 2.0, 52)
	# A weathered jetty from the west shore (models/dock.glb, runs along local -Z).
	var dir := Vector3(-1.0, 0.0, 0.25).normalized()
	var start := LAKE + dir * (LAKE_R + 4.5)
	var jetty := StaticBody3D.new()
	jetty.name = "Dock"
	jetty.position = Vector3(start.x, WATER_Y + 0.4, start.z)
	jetty.rotation.y = atan2(dir.x, dir.z)
	add_child(jetty)
	if ResourceLoader.exists("res://models/dock.glb"):
		var dock: Node3D = load("res://models/dock.glb").instantiate()
		jetty.add_child(dock)
		var lamp_at := dock.find_child("LampLight", true, false) as Node3D
		if lamp_at != null:
			var ll := OmniLight3D.new()
			ll.light_color = Color(0.45, 0.85, 1.0)
			ll.light_energy = 1.4
			ll.omni_range = 7.0
			ll.position = lamp_at.position
			jetty.add_child(ll)
			var tw := ll.create_tween().set_loops()
			tw.tween_property(ll, "light_energy", 1.4, 3.0)
			tw.tween_property(ll, "light_energy", 0.2, 0.06)
			tw.tween_property(ll, "light_energy", 1.3, 0.1)
			tw.tween_property(ll, "light_energy", 0.4, 0.05)
			tw.tween_property(ll, "light_energy", 1.4, 0.12)
	# Walkable surfaces: walkway, end platform, gangway up to the shore.
	for spec in [[Vector3(2.4, 0.12, 6.7), Vector3(0.0, -0.06, -3.3), 0.0],
			[Vector3(3.9, 0.12, 2.3), Vector3(0.0, -0.06, -7.7), 0.0],
			[Vector3(2.2, 0.1, 1.75), Vector3(0.0, 0.14, 0.82), 0.22]]:
		var deck_cs := CollisionShape3D.new()
		var deck_box := BoxShape3D.new()
		deck_box.size = spec[0]
		deck_cs.shape = deck_box
		deck_cs.position = spec[1]
		deck_cs.rotation.x = spec[2]
		jetty.add_child(deck_cs)
	_sign("STILLWATER", LAKE + Vector3(0.0, 4.0, 0.0), Color(0.75, 0.9, 1.0))


## Tall rock spires in the west with glowing crystal growths and two ore veins.
func _build_spires() -> void:
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	if scenes.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var spots := [Vector3(-4, 0, -3), Vector3(5, 0, -5), Vector3(-7, 0, 6), Vector3(3, 0, 7), Vector3(9, 0, 1), Vector3(-10, 0, -8), Vector3(0, 0, 11)]
	for k in spots.size():
		var p: Vector3 = SPIRES + spots[k]
		var rock: Node3D = scenes[r.randi() % scenes.size()].instantiate()
		var s := r.randf_range(0.7, 1.05)
		rock.scale = Vector3(s, s * r.randf_range(2.4, 3.6), s)
		rock.rotation = Vector3(r.randf_range(-0.08, 0.08), r.randf() * TAU, r.randf_range(-0.08, 0.08))
		rock.position = p + Vector3(0.0, _ground(p) - 0.6, 0.0)
		add_child(rock)
	# Natural arch between two spires.
	var cap: Node3D = scenes[0].instantiate()
	cap.scale = Vector3(1.6, 0.45, 0.55)
	cap.position = SPIRES + Vector3(0.5, _ground(SPIRES) + 7.4, -4.0)
	cap.rotation = Vector3(0.0, 0.1, 0.12)
	add_child(cap)
	# Crystal clusters.
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color(0.35, 0.85, 1.0, 0.85)
	crystal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal.emission_enabled = true
	crystal.emission = Color(0.2, 0.75, 1.0)
	crystal.emission_energy_multiplier = 2.4
	crystal.roughness = 0.1
	for k in 9:
		var a := r.randf() * TAU
		var p2 := SPIRES + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(2.0, 11.0)
		var cl := Node3D.new()
		cl.position = p2 + Vector3(0.0, _ground(p2) - 0.1, 0.0)
		add_child(cl)
		for c in r.randi_range(3, 6):
			var mi := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.0
			pm.bottom_radius = r.randf_range(0.08, 0.18)
			pm.height = r.randf_range(0.5, 1.4)
			pm.radial_segments = 6
			pm.rings = 1
			mi.mesh = pm
			mi.material_override = crystal
			mi.position = Vector3(r.randf_range(-0.3, 0.3), pm.height * 0.4, r.randf_range(-0.3, 0.3))
			mi.rotation = Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5))
			cl.add_child(mi)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.3, 0.8, 1.0)
		glow.light_energy = 1.2
		glow.omni_range = 4.0
		glow.position.y = 0.6
		cl.add_child(glow)
	for v in [Vector3(-2, 0, 2), Vector3(6, 0, -1)]:
		var vp: Vector3 = SPIRES + v
		vp.y = _ground(vp)
		Pickup.spawn(self, "vein", "ore", vp)
	_scatter(["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3", "Pebble_Square_1", "Pebble_Square_4"], SPIRES, 2.0, 14.0, 70, 0.6, 1.6, 78)
	_sign("CRYSTAL SPIRES", SPIRES + Vector3(0.0, _ground(SPIRES) + 9.5, 0.0), Color(0.6, 0.9, 1.0))


## An abandoned survey outpost to the north-east: two damaged prefab
## buildings (models/outpost_hab.glb, outpost_lab.glb) you can walk into
## through their sliding doors, with loot inside.
const OUTPOST_BUILDINGS := [
	["res://models/outpost_hab.glb", Vector3(-4.5, 0.0, 2.0), 0.0, "HABITAT"],
	["res://models/outpost_lab.glb", Vector3(6.0, 0.0, -3.5), 25.0, "SURVEY LAB"],
]

func _build_outpost() -> void:
	var base_y := _ground(OUTPOST)
	# Doors face back towards the cave.
	var to_cave := Vector3(CAVE.x - OUTPOST.x, 0.0, CAVE.z - OUTPOST.z)
	var face := atan2(to_cave.x, to_cave.z)
	for b in OUTPOST_BUILDINGS:
		if not ResourceLoader.exists(b[0]):
			continue
		var root := Node3D.new()
		var off: Vector3 = (b[1] as Vector3).rotated(Vector3.UP, face)
		root.position = OUTPOST + off + Vector3(0.0, base_y, 0.0)
		root.rotation.y = face + deg_to_rad(b[2])
		add_child(root)
		var inst: Node3D = load(b[0]).instantiate()
		root.add_child(inst)
		var shell := inst.find_child("Shell", true, false) as MeshInstance3D
		if shell != null:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := shell.mesh.create_trimesh_shape()
			shape.backface_collision = true
			cs.shape = shape
			body.add_child(cs)
			shell.add_child(body)
		var door := inst.find_child("Door", true, false) as Node3D
		if door != null:
			_make_door(door, root)
		var ladder := inst.find_child("Ladder", true, false) as MeshInstance3D
		if ladder != null:
			# Climb zone round the ladder (its local +X points away from the wall).
			var roof := ladder.get_aabb().end.y - 1.05
			var zone := Node3D.new()
			zone.name = "LadderZone"
			zone.add_to_group("ladder")
			zone.set_meta("centre", Vector3(-0.05, (roof + 1.0) * 0.5, 0.0))
			zone.set_meta("half", Vector3(0.95, (roof + 1.6) * 0.5, 0.45))
			zone.set_meta("roof", roof)
			ladder.add_child(zone)
		var growth := inst.find_child("Overgrowth", true, false) as GeometryInstance3D
		if growth != null:
			growth.visibility_range_end = 90.0
		_building_lights(root, b[3] == "HABITAT")
		# Loot inside.
		for c in ([Vector3(-2.6, 0.08, 0.6), Vector3(2.2, 0.08, -1.2)] if b[3] == "HABITAT" else [Vector3(-1.0, 0.08, 1.4), Vector3(1.6, 0.08, 1.6)]):
			Pickup.spawn(self, "crate", "", root.global_transform * c)
		Pickup.spawn(self, "resource", "tech", root.global_transform * Vector3(0.6, 0.1, 0.4), Vector2i(1, 2))
		if _props_lib == null and ResourceLoader.exists(PROPS_GLB):
			_props_lib = load(PROPS_GLB).instantiate()
		if b[3] == "HABITAT":
			_readable("Datapad", root, Vector3(-0.35, 0.812, 0.15), 20.0, "k7_roster")
		else:
			_readable("Datapad", root, Vector3(-1.8, 0.902, -2.3), -15.0, "specimen_log")
	_sign("SURVEY OUTPOST K-7", OUTPOST + Vector3(0.0, base_y + 6.0, 0.0), Color(1.0, 0.75, 0.6))


## Split sliding door: E opens / closes it; the two halves part sideways
## into the wall.
func _make_door(door: Node3D, building: Node3D) -> void:
	var closed_x := door.position.x
	var right := door.duplicate() as Node3D
	door.get_parent().add_child(right)
	var halves := [door, right]
	for k in 2:
		var h: Node3D = halves[k]
		h.scale.x = 0.5
		h.position.x = closed_x + (-0.375 if k == 0 else 0.375)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.5, 2.3, 0.14)   # scaled to 0.75 wide with the half
		cs.shape = sh
		cs.position.y = 1.15
		body.add_child(cs)
		h.add_child(body)
	var it := Interactable.new()
	it.reach = 2.6
	it.position = door.position + Vector3(0.375, 1.0, 1.0)
	building.add_child(it)
	var state := {"open": false, "busy": false}
	var refresh := func():
		it.prompt = "Close door" if state["open"] else "Open door"
	refresh.call()
	it.action = func():
		if state["busy"]:
			return
		state["busy"] = true
		state["open"] = not state["open"]
		Sfx.at(door.global_position, "crate_open", -4.0, 0.0, 6.0)
		var tw := door.create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		var gap := 0.72 if state["open"] else 0.0
		tw.tween_property(door, "position:x", closed_x - 0.375 - gap, 0.55)
		tw.tween_property(right, "position:x", closed_x + 0.375 + gap, 0.55)
		tw.chain().tween_callback(func():
			state["busy"] = false
			refresh.call())


## Dim interior light with a failing flicker, plus the console glow.
func _building_lights(root: Node3D, hab: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.85, 1.0)
	l.light_energy = 1.6
	l.omni_range = 7.0
	l.shadow_enabled = true
	l.position = Vector3(-0.8, 3.0, 0.0)
	root.add_child(l)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "light_energy", 1.6, 2.6)
	tw.tween_property(l, "light_energy", 0.15, 0.05)
	tw.tween_property(l, "light_energy", 1.4, 0.08)
	tw.tween_property(l, "light_energy", 0.3, 0.06)
	tw.tween_property(l, "light_energy", 1.6, 0.1)
	var c := OmniLight3D.new()
	c.light_color = Color(0.35, 0.8, 1.0)
	c.light_energy = 0.8
	c.omni_range = 3.0
	c.position = Vector3(0.6, 1.3, -1.4) if hab else Vector3(0.0, 1.4, -1.8)
	root.add_child(c)


## A flower meadow in the south-west with twisted old trees.
func _build_meadow() -> void:
	_scatter(["Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single"], MEADOW, 0.0, 16.0, 380, 0.7, 1.4, 91)
	_scatter(["Grass_Wispy_Short", "Grass_Common_Short", "Clover_1", "Clover_2"], MEADOW, 0.0, 18.0, 260, 0.8, 1.5, 92)
	_scatter(["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"], MEADOW, 10.0, 17.0, 7, 1.4, 2.0, 93, 260.0)
	_scatter(["Mushroom_Laetiporus", "Mushroom_Common"], MEADOW, 6.0, 18.0, 30, 0.8, 1.4, 94)
	var r := RandomNumberGenerator.new()
	r.seed = 95
	for i in 6:
		var a := r.randf() * TAU
		var p := MEADOW + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(2.0, 12.0)
		p.y = _ground(p)
		Pickup.spawn(self, "resource", "fiber", p, Vector2i(2, 3))



# ---------------------------------------------------------------- storage

## Puts a storage crate down in front of you (called when you PLACE one
## from the backpack). Returns false if there's no room.
func place_crate(id: String) -> bool:
	if not is_instance_valid(player):
		return false
	var fwd: Vector3 = -player.cam_yaw.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var p: Vector3 = player.global_position + fwd * 1.8
	for c in get_tree().get_nodes_in_group("storage_crate"):
		if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < 1.1:
			GS.toast("Not enough room here.")
			return false
	p.y = _ground(p)
	var slots := []
	slots.resize(int(GS.item(id).get("slots", 10)))
	var d := {"area": "res://base.tscn", "type": id, "pos": p, "yaw": atan2(-fwd.x, -fwd.z), "items": slots}
	GS.storage.append(d)
	StorageCrate.spawn(self, d)
	GS.save()
	return true
