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

const CRASH_SITE := "res://main.tscn"
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]
const ROCK_MATERIAL := "res://demo/assets/materials/M_rock23_tp.tres"

const TERRAIN_SIZE := 192
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

	# She sits by the fire, across from the bedroll, until you've talked.
	ally = AllyScript.new()
	ally.name = "Ally"
	var seat := FIRE_POS + Vector3(1.7, 0.0, 0.7)
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
	add_child(overlay)
	crafting = CraftPanel.new()
	crafting.player = player
	add_child(crafting)
	_build_bench()
	_build_resources()
	_build_pod_wreck()
	Sfx.loop(self, "forest_loop", -16.0, 6.0, false)
	if GS.wake_at_camp:
		GS.wake_at_camp = false
		_wake_up()
	else:
		_show_banner("BASE CAMP\nA dry cave in the cliffs. Check the crates inside.", 5.0)


## Arriving from the story: you come to on the bedroll by the fire.
func _wake_up() -> void:
	# Lying on the bedroll, head at its far end, feet towards the near end.
	var bed := FIRE_POS + Vector3(-2.4, 0.0, -1.0)
	var axis := Vector3(sin(deg_to_rad(20.0)), 0.0, cos(deg_to_rad(20.0)))
	var feet := bed - axis * 0.85
	player.position = feet + Vector3(0.0, _ground(feet) + 0.02, 0.0)
	var yaw := deg_to_rad(20.0)   # body (head) runs along the bedroll
	player.sleeping = true
	player._sleep_amount = 1.0
	player.input_enabled = false
	player._facing_yaw = yaw
	player.model.rotation.y = yaw
	player.cam_yaw.rotation.y = yaw + PI * 0.75
	player.health = player.max_health * 0.5
	droid.position = bed + Vector3(-1.5, _ground(bed) + 0.5, 2.5)
	_show_banner("You wake on a bedroll by a fire.\nShe's sitting across from you, watching the flames.\n\nPress any key to get up", 600.0)
	await get_tree().create_timer(1.5).timeout
	_waiting_get_up = true


var _waiting_get_up := false


func _get_up() -> void:
	_waiting_get_up = false
	_hide_banner()
	player.sleeping = false
	await get_tree().create_timer(1.3).timeout
	player.input_enabled = true
	_show_banner("BASE CAMP\nRest by the fire. Check the crates.", 4.0)


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
	h += smoothstep(26.0, 58.0, d + _noise_hill.get_noise_2d(x * 2.0, z * 2.0) * 8.0) * (10.0 + 16.0 * (0.5 + 0.5 * _noise_hill.get_noise_2d(x, z)))
	var md := Vector2(x, (z - CAVE.z - 3.0) / 0.9).length()
	var mound := (1.0 - smoothstep(13.0, 28.0, md)) * (7.5 + _noise_hill.get_noise_2d(x * 3.0, z * 3.0) * 1.5)
	mound *= smoothstep(CAVE.z + CAVE_R.z + 0.5, CAVE.z + CAVE_R.z - 5.0, z)
	h = maxf(h, mound)
	var e := Vector2(x / (CAVE_R.x + 0.6), (z - CAVE.z) / (CAVE_R.z + 0.6)).length()
	h = lerpf(0.0, h, smoothstep(0.92, 1.12, e))
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


func _build_ground() -> void:
	_noise_roll.seed = 3
	_noise_roll.frequency = 0.035
	_noise_roll.fractal_octaves = 4
	_noise_hill.seed = 17
	_noise_hill.frequency = 0.015
	_noise_hill.fractal_octaves = 4
	terrain = WK.build_terrain(self, TERRAIN_SIZE, _height_at, _paint, 34)
	if terrain == null:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(200.0, 1.0, 200.0)
		cs.shape = box
		cs.position.y = -0.5
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(200.0, 200.0)
		mi.mesh = plane
		mi.material_override = U.mat(Color(0.2, 0.28, 0.14), 0.95)
		body.add_child(mi)
		add_child(body)

	# Keep the player in the valley.
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := StaticBody3D.new()
		var wcs := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(2.0, 80.0, 100.0) if d.x != 0.0 else Vector3(100.0, 80.0, 2.0)
		wcs.shape = wb
		wall.add_child(wcs)
		wall.position = d * 38.0 + Vector3(VALLEY_CENTER.x, 20.0, VALLEY_CENTER.y)
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

	# Boulders framing the mouth hide the seam between the inner and outer walls.
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	if scenes.is_empty():
		return
	var steps := [-1.0, -0.85, -0.6, -0.3, 0.0, 0.3, 0.6, 0.85, 1.0]
	for k in steps:
		var az := deg_to_rad(MOUTH_HALF_DEG * k)
		var el := deg_to_rad(MOUTH_TOP_DEG * sqrt(maxf(0.0, 1.0 - k * k)))
		var p := _shell_point(az, el, 0.8, 0.0)
		var rock: Node3D = scenes[rng.randi() % scenes.size()].instantiate()
		var s := rng.randf_range(0.26, 0.36) if absf(k) < 0.95 else rng.randf_range(0.36, 0.46)
		rock.scale = Vector3.ONE * s
		rock.position = p + Vector3(0.0, 0.3 if absf(k) < 0.95 else 0.6, 0.6)
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		cave.add_child(rock)


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


# ---------------------------------------------------------------- crates

func _crate_mesh(parent: Node3D, size: Vector3, body_color: Color, stripe: Color) -> void:
	var metal := U.mat(body_color, 0.55)
	metal.metallic = 0.6
	var dark := U.mat(body_color.darkened(0.45), 0.6)
	dark.metallic = 0.7
	var accent := U.mat(stripe, 0.5, stripe, 0.8)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	body.mesh = bm
	body.position.y = size.y * 0.5
	body.material_override = metal
	parent.add_child(body)

	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(size.x + 0.06, 0.08, size.z + 0.06)
	lid.mesh = lm
	lid.position.y = size.y + 0.02
	lid.material_override = dark
	parent.add_child(lid)

	# Reinforced corners.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.08, size.y, 0.08)
			post.mesh = pm
			post.position = Vector3(sx * size.x * 0.5, size.y * 0.5, sz * size.z * 0.5)
			post.material_override = dark
			parent.add_child(post)

	# Faction stripe and handles.
	var band := MeshInstance3D.new()
	var bandm := BoxMesh.new()
	bandm.size = Vector3(size.x + 0.02, 0.07, size.z + 0.02)
	band.mesh = bandm
	band.position.y = size.y * 0.62
	band.material_override = accent
	parent.add_child(band)
	for sx in [-1.0, 1.0]:
		var handle := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.05, 0.06, size.z * 0.4)
		handle.mesh = hm
		handle.position = Vector3(sx * (size.x * 0.5 + 0.04), size.y * 0.8, 0.0)
		handle.material_override = dark
		parent.add_child(handle)


func _add_crate(pos: Vector3, yaw_deg: float, track: String, color: Color, stripe: Color) -> void:
	var crate := StaticBody3D.new()
	crate.position = pos + Vector3(0.0, _ground(pos), 0.0)
	crate.rotation_degrees.y = yaw_deg
	add_child(crate)
	var size := Vector3(1.4, 0.85, 0.9)
	_crate_mesh(crate, size, color, stripe)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = size.y * 0.5
	crate.add_child(cs)

	var info: Dictionary = GS.TRACKS[track]
	var tag := Label3D.new()
	tag.text = String(info["crate"])
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.modulate = stripe.lightened(0.3)
	tag.outline_size = 8
	tag.position = Vector3(0.0, size.y * 0.35, size.z * 0.5 + 0.01)
	crate.add_child(tag)

	var glow := OmniLight3D.new()
	glow.light_color = stripe
	glow.light_energy = 0.6
	glow.omni_range = 2.5
	glow.position = Vector3(0.0, size.y + 0.4, 0.3)
	crate.add_child(glow)

	_add_interact(crate.position, "Open %s crate  (%s upgrades)" % [info["crate"], info["title"]], func(): _open_panel(track))


## Plain supply clutter that isn't interactive.
func _add_prop_crate(pos: Vector3, yaw_deg: float, s: float) -> void:
	var crate := StaticBody3D.new()
	crate.position = pos + Vector3(0.0, _ground(pos), 0.0)
	crate.rotation_degrees.y = yaw_deg
	add_child(crate)
	var size := Vector3(1.0, 0.7, 0.7) * s
	_crate_mesh(crate, size, Color(0.22, 0.23, 0.22), Color(0.3, 0.3, 0.3))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = size.y * 0.5
	crate.add_child(cs)


func _build_crates() -> void:
	var c := CAVE
	_add_crate(c + Vector3(-5.2, 0.0, -3.0), 55.0, "blaster", Color(0.2, 0.2, 0.22), Color(0.9, 0.12, 0.08))
	_add_crate(c + Vector3(0.0, 0.0, -7.6), 0.0, "armor", Color(0.24, 0.24, 0.24), Color(0.95, 0.85, 0.85))
	_add_crate(c + Vector3(5.2, 0.0, -3.0), -55.0, "droid", Color(0.2, 0.21, 0.24), Color(0.25, 0.6, 1.0))
	# Clutter.
	_add_prop_crate(c + Vector3(-6.2, 0.0, 1.5), 80.0, 1.0)
	_add_prop_crate(c + Vector3(-6.0, 0.7, 1.4), 70.0, 0.8)
	_add_prop_crate(c + Vector3(6.3, 0.0, 2.0), -75.0, 1.1)
	_add_prop_crate(c + Vector3(2.8, 0.0, -8.0), 10.0, 0.9)

	# A salvaged work lamp at the back of the cave.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.75, 0.85, 1.0)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	lamp.position = c + Vector3(0.0, 3.5, -5.0)
	add_child(lamp)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.12
	bs.height = 0.24
	bulb.mesh = bs
	bulb.material_override = U.mat(Color(0.8, 0.9, 1.0), 0.3, Color(0.75, 0.85, 1.0), 6.0)
	bulb.position = lamp.position
	add_child(bulb)

	# Bedroll by the fire.
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.12, 2.0)
	bed.mesh = bm
	bed.material_override = U.mat(Color(0.32, 0.08, 0.07), 0.95)
	bed.position = FIRE_POS + Vector3(-2.4, 0.06, -1.0)
	bed.rotation_degrees.y = 20.0
	add_child(bed)


# ---------------------------------------------------------------- trail back

func _build_trail_exit() -> void:
	var pos := Vector3(0.0, 0.0, 24.0)
	pos.y = _ground(pos)
	var signpost := StaticBody3D.new()
	signpost.position = pos
	add_child(signpost)
	var wood := U.mat(Color(0.3, 0.2, 0.12), 0.95)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 2.0, 0.14)
	post.mesh = pm
	post.position.y = 1.0
	post.material_override = wood
	signpost.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.4, 0.06)
	board.mesh = bm
	board.position = Vector3(0.0, 1.7, 0.08)
	board.material_override = wood
	signpost.add_child(board)
	var tag := Label3D.new()
	tag.text = "CRASH SITE"
	tag.font_size = 40
	tag.pixel_size = 0.005
	tag.outline_size = 8
	tag.position = Vector3(0.0, 1.7, 0.12)
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	signpost.add_child(tag)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 2.0, 0.3)
	cs.shape = shape
	cs.position.y = 1.0
	signpost.add_child(cs)

	_add_interact(pos, "Head back to the crash site (fight for more salvage)", func(): get_tree().change_scene_to_file(CRASH_SITE))


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
	while placed < 520 and tries < 5000:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(16.0 * 16.0, 90.0 * 90.0))
		var p := Vector3(VALLEY_CENTER.x + cos(a) * r, 0.0, VALLEY_CENTER.y + sin(a) * r)
		# Keep the cave mouth, the path and the cave itself clear.
		var e := Vector2(p.x / (CAVE_R.x + 3.0), (p.z - CAVE.z) / (CAVE_R.z + 3.0)).length()
		if e < 1.0:
			continue
		if absf(p.x) < 9.0 and p.z > CAVE.z and p.z < 30.0:
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
		if r < 40.0:
			WK.trunk_collider(self, p, s)
		placed += 1
	WK.plant(self, buckets, 220.0)

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
	for i in 260:
		var a := rng.randf() * TAU
		var r := rng.randf_range(9.0, 36.0)
		var p := Vector3(VALLEY_CENTER.x + cos(a) * r, 0.0, VALLEY_CENTER.y + sin(a) * r)
		var e := Vector2(p.x / (CAVE_R.x + 1.5), (p.z - CAVE.z) / (CAVE_R.z + 1.5)).length()
		if e < 1.0 or (absf(p.x) < 3.0 and p.z > CAVE.z):
			continue
		p.y = _ground(p) - 0.05
		var k := rng.randi() % small.size()
		var sc: Vector2 = small_scales[k]
		WK.add_instance(sb, small[k], p, rng.randf_range(sc.x, sc.y), rng)
	WK.plant(self, sb, 90.0)


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
	hint.offset_top = -40
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

const BENCH_POS := Vector3(-4.6, 0.0, -13.2)

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
	var p := BENCH_POS + Vector3(0.0, _ground(BENCH_POS), 0.0)
	_bench_model = StaticBody3D.new()
	_bench_model.position = p
	_bench_model.rotation_degrees.y = 70.0
	add_child(_bench_model)
	if GS.bench_level <= 0:
		# A marked-out spot with a few planks lying ready.
		var plank := U.mat(Color(0.4, 0.28, 0.16), 0.95)
		for i in 3:
			var mi := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(1.4, 0.05, 0.2)
			mi.mesh = b
			mi.material_override = plank
			mi.position = Vector3(0.0, 0.03 + i * 0.05, -0.25 + i * 0.25)
			mi.rotation.y = randf_range(-0.2, 0.2)
			_bench_model.add_child(mi)
		return
	var wood := U.mat(Color(0.38, 0.26, 0.15), 0.9)
	var metal := U.mat(Color(0.3, 0.31, 0.33), 0.5)
	metal.metallic = 0.7
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.8, 0.08, 0.8)
	top.mesh = tb
	top.material_override = wood if GS.bench_level < 2 else metal
	top.position.y = 0.9
	_bench_model.add_child(top)
	for x in [-0.8, 0.8]:
		for z in [-0.32, 0.32]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.08, 0.9, 0.08)
			leg.mesh = lb
			leg.material_override = wood
			leg.position = Vector3(x, 0.45, z)
			_bench_model.add_child(leg)
	# Vise, tools and (at level 2) a lamp and power cell.
	var vise := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.25, 0.18, 0.2)
	vise.mesh = vb
	vise.material_override = metal
	vise.position = Vector3(-0.6, 1.03, 0.0)
	_bench_model.add_child(vise)
	if GS.bench_level >= 2:
		var cell := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.1
		cm.height = 0.3
		cell.mesh = cm
		cell.material_override = U.mat(Color(0.2, 0.5, 0.9), 0.3, Color(0.3, 0.6, 1.0), 2.0)
		cell.position = Vector3(0.6, 1.09, 0.1)
		_bench_model.add_child(cell)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.95, 0.8)
	cs.shape = bs
	cs.position.y = 0.47
	_bench_model.add_child(cs)
	var tag := Label3D.new()
	tag.text = "CRAFTING BENCH  Lv%d" % GS.bench_level
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.position = Vector3(0.0, 1.5, 0.0)
	_bench_model.add_child(tag)


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
	var spots := {"wood": 12, "fiber": 10, "ore": 5}
	for id in spots:
		for i in spots[id]:
			var a := r.randf() * TAU
			var d := r.randf_range(8.0, 30.0)
			var p := Vector3(VALLEY_CENTER.x + cos(a) * d, 0.0, VALLEY_CENTER.y + sin(a) * d)
			var e := Vector2(p.x / (CAVE_R.x + 2.0), (p.z - CAVE.z) / (CAVE_R.z + 2.0)).length()
			if e < 1.0:
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
			var mi := MeshInstance3D.new()
			mi.mesh = pine
			mi.scale = Vector3.ONE * 1.9
			mi.position = tp + Vector3(0.0, -0.15, 0.0)
			add_child(mi)
		WK.trunk_collider(self, tp, 1.9)
	for v in [Vector3(-11, 0, -8), Vector3(12, 0, -10)]:
		var vp: Vector3 = v
		vp.y = _ground(vp)
		Pickup.spawn(self, "vein", "ore", vp)


## A crashed escape pod east of camp: scrap, plastic and supply crates.
func _build_pod_wreck() -> void:
	var c := Vector3(20.0, 0.0, 12.0)
	c.y = _ground(c)
	var hull := U.mat(Color(0.2, 0.21, 0.23), 0.5)
	hull.metallic = 0.6
	var pod := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 1.3
	cap.height = 4.5
	pod.mesh = cap
	pod.material_override = hull
	pod.position = c + Vector3(0.0, 0.7, 0.0)
	pod.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(30.0), deg_to_rad(10.0))
	add_child(pod)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 1.3
	shape.height = 4.5
	cs.shape = shape
	body.add_child(cs)
	body.transform = pod.transform
	add_child(body)
	var smoke := OmniLight3D.new()
	smoke.light_color = Color(1.0, 0.5, 0.2)
	smoke.light_energy = 1.5
	smoke.omni_range = 5.0
	smoke.position = c + Vector3(0.0, 1.5, 0.0)
	add_child(smoke)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for k in 5:
		var id := "scrap" if k < 3 else "plastic"
		var a := r.randf() * TAU
		var p := c + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(2.5, 5.0)
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
