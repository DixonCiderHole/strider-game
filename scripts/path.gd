extends Node3D
## The trail: a long, winding forest path from the crash site towards your
## squad's distress beacon. Creatures keep coming out of the woods the whole
## way. Reaching the beacon triggers the "ambushed" cutscene.

const U = preload("res://scripts/util.gd")
const WK = preload("res://scripts/world_kit.gd")
const GS = preload("res://scripts/game_state.gd")
const MB = preload("res://scripts/menu_backdrop.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Cutscene = preload("res://scripts/cutscene.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const CompanionScript = preload("res://scripts/companion.gd")
const HudScript = preload("res://scripts/hud.gd")
const PauseMenuScript = preload("res://scripts/pause_menu.gd")
const TutorialScript = preload("res://scripts/trail_tutorial.gd")

const TERRAIN_SIZE := 384
const Z_START := 150.0
const Z_END := -160.0
const PATH_HALF_WIDTH := 3.5
const WALL_OFFSET := 19.0
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]

## Creature trickle.
const MAX_ALIVE := 6
const SALVAGE_PER_KILL := 4

var terrain
var player
var droid
var hud
var menu
var rng := RandomNumberGenerator.new()
var game_over := false

## Shape of the trail (drag.gd changes these for its own trail).
var curve_a := 30.0
var curve_b := 10.0
var curve_phase := 1.3
var terrain_seed := 21
var z_start := Z_START
var z_end := Z_END

var _noise_roll := FastNoiseLite.new()
var _noise_hill := FastNoiseLite.new()
var _spawn_t := 6.0
## First trip only: teaches the controls (and holds the creature trickle).
var tutorial
var _respawning := false
var _fade: ColorRect
var _alive := 0
var _kills := 0
var _beacon_light: OmniLight3D
var _time := 0.0


# ---------------------------------------------------------------- path shape

func path_x(z: float) -> float:
	return curve_a * sin(z * 0.02) + curve_b * sin(z * 0.045 + curve_phase)


func path_slope(z: float) -> float:
	return curve_a * 0.02 * cos(z * 0.02) + curve_b * 0.045 * cos(z * 0.045 + curve_phase)


func path_y(z: float) -> float:
	return 3.0 * sin(z * 0.013) + 1.5 * sin(z * 0.031 + 0.7)


## Horizontal distance from (x, z) to the centre of the path (approximate).
func path_dist(x: float, z: float) -> float:
	var s := path_slope(z)
	return absf(x - path_x(z)) / sqrt(1.0 + s * s)


func path_point(z: float) -> Vector3:
	var p := Vector3(path_x(z), 0.0, z)
	p.y = _ground(p)
	return p


## Unit vector along the path towards the end (-Z), and the sideways normal.
func path_tangent(z: float) -> Vector3:
	return Vector3(-path_slope(z), 0.0, -1.0).normalized()


func path_normal(z: float) -> Vector3:
	var t := path_tangent(z)
	return Vector3(-t.z, 0.0, t.x)


func _ground(p: Vector3) -> float:
	return WK.ground_y(terrain, p, path_y(p.z))


# ---------------------------------------------------------------- setup

func _ready() -> void:
	rng.seed = 77
	GS.ensure_loaded()
	GS.horde_mode = false
	if not GS.menu_preview:
		Sfx.loop(self, "forest_loop", -13.0, 6.0, false)
	_build_environment()
	_build_ground()
	_build_walls()
	_build_forest()
	_build_beacon()
	if GS.menu_preview:
		_preview()
		return
	GS.enter_area(scene_file_path)

	hud = HudScript.new()
	add_child(hud)

	# Mid-trail checkpoint, if you reached one (GS.enter_area clears it on a new level).
	var start_z := float(GS.flags.get("area_cp", Z_START - 4.0))
	var start := path_point(start_z)
	player = PlayerScript.new()
	player.name = "Player"
	player.damage = GS.player_damage()
	player.max_health = GS.player_max_health()
	player.health = player.max_health
	player.position = start + Vector3(0.0, 0.1, 0.0)
	add_child(player)
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	player.hit_landed.connect(hud.show_hitmarker)
	# Face along the trail.
	var t := path_tangent(start_z)
	player.cam_yaw.rotation.y = atan2(-t.x, -t.z)
	player._facing_yaw = player.cam_yaw.rotation.y

	droid = CompanionScript.new()
	droid.name = "Droid"
	droid.player = player
	droid.damage = GS.droid_damage()
	droid.position = start + path_normal(start_z) * 2.5 + Vector3(0.0, 0.5, 2.0)
	add_child(droid)
	droid.status_changed.connect(hud.set_droid_status)
	hud.show_droid(true)
	hud.set_droid_status(droid.order_text(), droid.weapons_free)

	menu = PauseMenuScript.new()
	menu.player = player
	add_child(menu)

	var overlay = load("res://scripts/overlay.gd").new()
	overlay.player = player
	overlay.tracker_top = 96.0
	overlay.area_title = "Reach the Distress Beacon"
	overlay.area_goals = "• Follow the trail to your squad's beacon"
	add_child(overlay)
	# Supply crates along the trail (ammo for the walk).
	for zc in [100.0, 40.0, -20.0, -90.0]:
		var cp := path_point(zc) + path_normal(zc) * 4.0
		cp.y = _ground(cp)
		load("res://scripts/pickup.gd").spawn(self, "crate", "", cp)
	if not GS.flags.get("trail_tutorial_done", false):
		tutorial = TutorialScript.new()
		tutorial.trail = self
		tutorial.player = player
		tutorial.hud = hud
		add_child(tutorial)
	hud.set_health(player.health, player.max_health)
	hud.set_hint("Follow the trail   ·   WASD walk   ·   Shift run   ·   Left click fire   ·   Esc pause")
	hud.show_message("THE TRAIL\nFollow the path to your squad's distress beacon.", 4.5)
	_update_objective()


## Title-screen backdrop: looking down the trail at night.
func _preview() -> void:
	var z := z_start - 22.0
	var cam := path_point(z) + path_normal(z) * 1.2 + Vector3(0.0, 2.3, 0.0)
	var look := path_point(z - 32.0) + Vector3(0.0, 1.3, 0.0)
	MB.make(self, cam, look)
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	if _beacon_light != null:
		_beacon_light.light_energy = 6.0 + sin(_time * 4.0) * 4.0
	if game_over or player == null or player.is_dead:
		return
	_update_objective()

	# Keep the creatures coming.
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		var progress := _progress()
		_spawn_t = lerpf(5.0, 2.6, progress) * rng.randf_range(0.75, 1.25)
		var held: bool = tutorial != null and tutorial.holding
		if _alive < MAX_ALIVE and not held:
			_spawn_enemy(progress)

	# Reached the beacon.
	if player.global_position.z < Z_END + 14.0:
		_reach_end()


func _unhandled_input(event) -> void:
	if droid == null or game_over or player.is_dead:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
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


## End key: skip to the end of this section (testing).
func _input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_END:
		_debug_skip()


func _debug_skip() -> void:
	if not game_over:
		_reach_end()


func _progress() -> float:
	return clampf((Z_START - player.global_position.z) / (Z_START - Z_END), 0.0, 1.0)


func _update_objective() -> void:
	var dist := maxf(0.0, player.global_position.z - (Z_END + 14.0))
	hud.set_objective("THE TRAIL", "Distress beacon  %d m   ·   Kills %d" % [int(dist), _kills])


# ---------------------------------------------------------------- creatures

func _spawn_enemy(progress: float) -> void:
	var pz: float = player.global_position.z
	var z := pz - rng.randf_range(24.0, 48.0)
	if rng.randf() < 0.25:
		z = pz + rng.randf_range(20.0, 32.0)  # sometimes from behind
	z = clampf(z, Z_END - 5.0, Z_START + 5.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var p := Vector3(path_x(z), 0.0, z) + path_normal(z) * side * rng.randf_range(11.0, 16.0)
	if p.distance_to(player.global_position) < 16.0:
		return
	p.y = _ground(p) + 0.4
	var e = EnemyScript.new()
	e.position = p
	e.speed += progress * 1.5
	e.health += progress * 30.0
	e.target = player
	add_child(e)
	e.died.connect(_on_enemy_died)
	_alive += 1


func _on_enemy_died() -> void:
	_alive -= 1
	_kills += 1


func _reach_end() -> void:
	game_over = true
	GS.flags["trail_tutorial_done"] = true
	GS.flags.erase("area_cp")
	player.input_enabled = false
	hud.show_message("The beacon... and your squad, scattered across the clearing.\nSomething moves in the trees all around you.", 3.5)
	GS.add_salvage(_kills * SALVAGE_PER_KILL)
	await get_tree().create_timer(4.0).timeout
	Cutscene.play("ambushed")


## Falling on the trail sends you back to the last checkpoint.
func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true
	hud.show_message("", 0.0)
	await get_tree().create_timer(1.4).timeout
	await _fade_to(1.0, 0.5)
	hud.show_message("YOU WERE KILLED", 1.2)
	await get_tree().create_timer(0.9).timeout
	# Clear the creatures and put everything back.
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	_alive = 0
	_spawn_t = 6.0
	var z := float(GS.flags.get("area_cp", Z_START - 4.0))
	var t := path_tangent(z)
	player.revive(path_point(z) + Vector3(0.0, 0.1, 0.0), atan2(-t.x, -t.z))
	if is_instance_valid(droid):
		droid.global_position = path_point(z) + path_normal(z) * 2.5 + Vector3(0.0, 0.5, 2.0)
	if tutorial != null:
		tutorial.on_respawn()
	await _fade_to(0.0, 0.6)
	hud.show_message("Back at the checkpoint.", 2.0)
	_respawning = false


func _fade_to(alpha: float, time: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, time)
	await tw.finished


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.34, 0.42)
	sky_mat.sky_horizon_color = Color(0.6, 0.56, 0.5)
	sky_mat.ground_horizon_color = Color(0.3, 0.32, 0.25)
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.08)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.48, 0.52, 0.5)
	env.fog_density = 0.016
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 60.0, 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)


## A path through a forested ravine: flat-ish trail, banks rising on both
## sides, and a dead end beyond each end of the trail.
func _height_at(x: float, z: float) -> float:
	var d := path_dist(x, z)
	var h := path_y(z)
	h += _noise_roll.get_noise_2d(x, z) * lerpf(0.1, 2.2, smoothstep(PATH_HALF_WIDTH, 14.0, d))
	h += smoothstep(12.0, 42.0, d + _noise_hill.get_noise_2d(x * 2.0, z * 2.0) * 6.0) * (7.0 + 14.0 * (0.5 + 0.5 * _noise_hill.get_noise_2d(x, z)))
	h += smoothstep(z_start + 4.0, z_start + 30.0, z) * 16.0
	h += smoothstep(z_end - 4.0, z_end - 30.0, z) * 16.0
	return h


func _paint(data, x: float, z: float) -> void:
	var d := path_dist(x, z)
	if d > PATH_HALF_WIDTH + 4.0:
		return
	var w := 1.0 - smoothstep(PATH_HALF_WIDTH - 1.5, PATH_HALF_WIDTH + 2.0, d + _noise_roll.get_noise_2d(x * 4.0, z * 4.0) * 1.5)
	WK.paint_dirt(data, Vector3(x, 0.0, z), w)


func _build_ground() -> void:
	_noise_roll.seed = terrain_seed
	_noise_roll.frequency = 0.035
	_noise_roll.fractal_octaves = 4
	_noise_hill.seed = terrain_seed + 10
	_noise_hill.frequency = 0.013
	_noise_hill.fractal_octaves = 4
	terrain = WK.build_terrain(self, TERRAIN_SIZE, _height_at, _paint, 175)
	if terrain == null:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(400.0, 1.0, 400.0)
		cs.shape = box
		cs.position.y = -0.5
		body.add_child(cs)
		add_child(body)


## Invisible walls along both banks so the trail can't be left.
func _build_walls() -> void:
	var z := z_start + 12.0
	while z > z_end - 12.0:
		var z2 := z - 5.0
		for side in [-1.0, 1.0]:
			var a: Vector3 = Vector3(path_x(z), 0.0, z) + path_normal(z) * side * WALL_OFFSET
			var b: Vector3 = Vector3(path_x(z2), 0.0, z2) + path_normal(z2) * side * WALL_OFFSET
			var wall := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.0, 60.0, a.distance_to(b) + 1.5)
			cs.shape = box
			wall.add_child(cs)
			wall.position = (a + b) * 0.5 + Vector3(0.0, path_y(z) + 10.0, 0.0)
			wall.rotation.y = atan2(b.x - a.x, b.z - a.z)
			add_child(wall)
		z = z2
	# Caps at both ends.
	for zc in [z_start + 12.0, z_end - 12.0]:
		var cap := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WALL_OFFSET * 2.6, 60.0, 1.0)
		cs.shape = box
		cap.add_child(cs)
		cap.position = Vector3(path_x(zc), path_y(zc) + 10.0, zc)
		add_child(cap)


func _build_forest() -> void:
	var pines := WK.meshes(WK.PINES)
	if pines.is_empty():
		return
	var leafy := WK.meshes(WK.LEAFY)
	var dead := WK.meshes(WK.DEAD)
	var buckets := {}
	var placed := 0
	var tries := 0
	while placed < 1300 and tries < 8000:
		tries += 1
		var z := rng.randf_range(z_end - 40.0, z_start + 40.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var d := PATH_HALF_WIDTH + 2.5 + pow(rng.randf(), 1.4) * 75.0
		var p := Vector3(path_x(z), 0.0, z) + path_normal(z) * side * d
		p.y = _ground(p) - 0.15
		var roll := rng.randf()
		var mesh: Mesh = pines[rng.randi() % pines.size()]
		if roll < 0.07 and not dead.is_empty():
			mesh = dead[rng.randi() % dead.size()]
		elif roll < 0.3 and not leafy.is_empty():
			mesh = leafy[rng.randi() % leafy.size()]
		var s := rng.randf_range(1.5, 2.4)
		WK.add_instance(buckets, mesh, p, s, rng)
		if d < WALL_OFFSET + 2.0:
			WK.trunk_collider(self, p, s)
		placed += 1
	WK.plant(self, buckets, 200.0)

	# Undergrowth and rocks along the banks.
	var small_names := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1_Big", "Mushroom_Common", "Rock_Medium_1", "Rock_Medium_2"]
	var scales := [Vector2(0.9, 1.5), Vector2(0.9, 1.4), Vector2(0.15, 0.25), Vector2(0.6, 1.0), Vector2(0.8, 1.3), Vector2(0.5, 1.1), Vector2(0.5, 1.1)]
	var small := []
	var small_scales := []
	for i in small_names.size():
		var m := WK.model_mesh(small_names[i])
		if m != null:
			small.append(m)
			small_scales.append(scales[i])
	if not small.is_empty():
		var sb := {}
		for i in 650:
			var z := rng.randf_range(z_end - 20.0, z_start + 20.0)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var p := Vector3(path_x(z), 0.0, z) + path_normal(z) * side * rng.randf_range(PATH_HALF_WIDTH + 0.5, 22.0)
			p.y = _ground(p) - 0.05
			var k := rng.randi() % small.size()
			var sc: Vector2 = small_scales[k]
			WK.add_instance(sb, small[k], p, rng.randf_range(sc.x, sc.y), rng)
		WK.plant(self, sb, 80.0)

	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	if scenes.is_empty():
		return
	for i in 40:
		var z := rng.randf_range(z_end, z_start)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := Vector3(path_x(z), 0.0, z) + path_normal(z) * side * rng.randf_range(7.0, 18.0)
		var s := rng.randf_range(0.12, 0.4)
		var rock: Node3D = scenes[rng.randi() % scenes.size()].instantiate()
		rock.scale = Vector3.ONE * s
		rock.position = Vector3(p.x, _ground(p) + s * 1.2, p.z)
		rock.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		add_child(rock)


## Your squad's distress beacon at the end of the trail: a pulsing red light
## and a beam you can see over the trees.
func _build_beacon() -> void:
	var p := path_point(Z_END + 4.0)
	var beacon := Node3D.new()
	beacon.position = p
	beacon.add_to_group("objective")   # gold marker on the compass
	beacon.set_meta("label", "Distress Beacon")
	beacon.set_meta("info", "Your squad's beacon at the end of the trail. Follow the path north through the forest.")
	add_child(beacon)
	var dark := U.mat(Color(0.15, 0.15, 0.16), 0.5)
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.35
	cm.height = 1.2
	base.mesh = cm
	base.position.y = 0.6
	base.material_override = dark
	beacon.add_child(base)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	lamp.mesh = sm
	lamp.position.y = 1.3
	lamp.material_override = U.mat(Color(1, 0.1, 0.05), 0.3, Color(1.0, 0.1, 0.05), 8.0)
	beacon.add_child(lamp)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.6
	bm.bottom_radius = 0.25
	bm.height = 60.0
	beam.mesh = bm
	beam.position.y = 31.0
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(1.0, 0.15, 0.08, 0.18)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(beam)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = Color(1.0, 0.15, 0.08)
	_beacon_light.omni_range = 18.0
	_beacon_light.position.y = 2.0
	beacon.add_child(_beacon_light)

	# Fallen squad gear scattered round the beacon.
	var armor := U.mat(Color(0.12, 0.12, 0.13), 0.5)
	for i in 6:
		var piece := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(0.3, 0.8), rng.randf_range(0.15, 0.4), rng.randf_range(0.3, 0.9))
		piece.mesh = b
		piece.material_override = armor
		var off := Vector3(rng.randf_range(-5, 5), 0.0, rng.randf_range(-4, 4))
		piece.position = p + off + Vector3(0.0, _ground(p + off) - p.y + 0.1, 0.0)
		piece.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
		add_child(piece)
