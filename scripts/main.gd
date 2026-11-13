extends Node3D
## Tutorial level: crash site in a forest clearing. Survive the waves.

const U = preload("res://scripts/util.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")
const PauseMenuScript = preload("res://scripts/pause_menu.gd")
const CompanionScript = preload("res://scripts/companion.gd")
const GS = preload("res://scripts/game_state.gd")
const MB = preload("res://scripts/menu_backdrop.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Cutscene = preload("res://scripts/cutscene.gd")
const AllyScript = preload("res://scripts/ally.gd")
const OverlayScript = preload("res://scripts/overlay.gd")
const Pickup = preload("res://scripts/pickup.gd")
const BASE_CAMP := "res://base.tscn"

const WAVES := [3, 5, 8]
## Testing shortcut: have the droid online from the start.
const DROID_FROM_START := true
const ARENA_RADIUS := 60.0
const CLEARING_RADIUS := 17.0
const WRECK_POS := Vector3(-9.0, 0.0, -8.0)
## The ship came in along this heading (degrees); its furrow lies behind it.
## Set so the ship lies across your view at the start, torn side towards you.
const WRECK_FURROW_DEG := 125.0
const WreckScript = preload("res://scripts/wreck.gd")
## Terrain3D heightmap size in metres (centred on the clearing).
const TERRAIN_SIZE := 384
const TERRAIN_MATERIAL := "res://demo/data/M_terrain.tres"
const TERRAIN_ASSETS := "res://demo/data/assets.tres"
const GRASS_PARTICLES := "res://addons/terrain_3d/extras/particle_example/Terrain3DParticles.tscn"
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]

var player
var hud
var menu
var droid
var wave_index := -1
var alive_enemies := 0
var game_over := false
var rng := RandomNumberGenerator.new()

var terrain  # Terrain3D node (untyped so the game still runs without the addon)
var _noise_roll := FastNoiseLite.new()
var _noise_hill := FastNoiseLite.new()
var _noise_edge := FastNoiseLite.new()
var _fire_lights: Array[OmniLight3D] = []
## Unrelenting Horde mode: endless, ever-bigger waves until you die.
var horde := false
var creatures_killed := 0
var _on_field := 0
const HORDE_MAX_ON_FIELD := 14
const HORDE_SALVAGE_PER_KILL := 3
var _time := 0.0


func _ready() -> void:
	rng.seed = 7
	GS.ensure_loaded()
	if not GS.menu_preview:
		Sfx.loop(self, "forest_loop", -13.0, 6.0, false)
	horde = GS.horde_mode
	_build_environment()
	_build_ground()
	_build_forest()
	_build_rocks()
	_build_wreck()
	if GS.menu_preview:
		var cp := Vector3(9.0, 0.0, 11.0)
		MB.make(self, cp + Vector3(0.0, ground_y(cp) + 2.4, 0.0), WRECK_POS + Vector3(0.0, ground_y(WRECK_POS) + 1.4, 0.0))
		return
	GS.enter_area("res://main.tscn")

	hud = HudScript.new()
	add_child(hud)

	player = PlayerScript.new()
	player.name = "Player"
	GS.ensure_loaded()
	if GS.active_member == "survivor":
		player.character = "survivor"   # playing as her while he recovers at camp
	player.damage = GS.player_damage()
	player.max_health = GS.player_max_health()
	player.health = player.max_health
	player.position = Vector3(0.0, ground_y(Vector3(0.0, 0.0, 5.0)) + 0.1, 5.0)
	add_child(player)
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	player.hit_landed.connect(hud.show_hitmarker)

	menu = PauseMenuScript.new()
	menu.player = player
	add_child(menu)
	hud.set_health(player.health, player.max_health)
	hud.set_wave(1, 0 if horde else WAVES.size())
	hud.set_enemies(0)
	hud.set_hint("WASD walk  ·  Shift run  ·  Click fire  ·  R reload  ·  Q weapon  ·  H heal  ·  G grenade  ·  E use  ·  Tab inventory  ·  Esc menu")
	var overlay = OverlayScript.new()
	overlay.player = player
	overlay.tracker_top = 96.0
	overlay.area_title = "Survive"
	overlay.area_goals = "• Hold out as long as you can" if horde else "• Survive the creature attack"
	add_child(overlay)
	_build_salvage()

	if DROID_FROM_START:
		_spawn_droid()
	if GS.ally_joined:
		var ally = AllyScript.new()
		ally.name = "Ally"
		ally.position = player.position + Vector3(2.0, 0.0, 1.5)
		add_child(ally)
		ally.follow(player)
	_intro()


func _process(delta: float) -> void:
	_time += delta
	for i in _fire_lights.size():
		var l := _fire_lights[i]
		l.light_energy = 2.6 + sin(_time * 11.0 + i * 2.0) * 0.5 + sin(_time * 23.0 + i) * 0.3


# ---------------------------------------------------------------- waves

func _intro() -> void:
	if horde:
		hud.show_message("UNRELENTING HORDE\nThey don't stop coming. Hold out as long as you can.", 4.0)
	else:
		hud.show_message("Your ship is down.\nSomething is moving in the trees...", 4.0)
	await get_tree().create_timer(5.0, false).timeout
	_next_wave()


func _next_wave() -> void:
	if game_over:
		return
	wave_index += 1
	if not horde and wave_index >= WAVES.size():
		_victory()
		return
	var count: int = _horde_count(wave_index) if horde else WAVES[wave_index]
	hud.show_message("WAVE %d" % (wave_index + 1), 2.0)
	Sfx.ui("wave_horn", -5.0)
	hud.set_wave(wave_index + 1, 0 if horde else WAVES.size())
	alive_enemies = count
	hud.set_enemies(alive_enemies)
	var wave := wave_index
	for i in count:
		# Don't flood the clearing: wait for room on the field.
		while horde and _on_field >= HORDE_MAX_ON_FIELD and not game_over:
			await get_tree().create_timer(0.5, false).timeout
		if game_over or wave != wave_index:
			return
		_spawn_enemy()
		var gap := rng.randf_range(0.7, 1.6)
		if horde:
			gap = rng.randf_range(0.4, 1.1) / (1.0 + wave_index * 0.08)
		await get_tree().create_timer(gap, false).timeout


## Horde wave sizes: 4, 6, 8, ... up to 40.
func _horde_count(i: int) -> int:
	return mini(4 + i * 2, 40)


func _spawn_enemy() -> void:
	var e = EnemyScript.new()
	var a := rng.randf() * TAU
	var r := rng.randf_range(30.0, 38.0)
	e.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
	e.position.y = ground_y(e.position) + 0.4
	if horde:
		e.speed += minf(wave_index * 0.45, 4.0)
		e.health += wave_index * 12.0
		e.attack_damage += minf(wave_index * 0.8, 12.0)
	else:
		e.speed += wave_index * 0.7
		e.health += wave_index * 10.0
	_on_field += 1
	e.target = player
	add_child(e)
	e.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	alive_enemies -= 1
	_on_field -= 1
	creatures_killed += 1
	hud.set_enemies(alive_enemies)
	if alive_enemies > 0 or game_over:
		return
	if horde:
		player.heal(25.0)
		if droid == null:
			hud.show_message("Wave %d cleared.\nSomething in the wreckage is powering up..." % (wave_index + 1), 3.0)
			Sfx.ui("wave_clear", -6.0)
			await get_tree().create_timer(2.0, false).timeout
			_spawn_droid()
			await get_tree().create_timer(3.0, false).timeout
		else:
			hud.show_message("Wave %d cleared.\nMore are coming..." % (wave_index + 1), 3.0)
			Sfx.ui("wave_clear", -6.0)
			await get_tree().create_timer(4.0, false).timeout
		_next_wave()
		return
	if wave_index + 1 < WAVES.size():
		player.heal(35.0)
		if droid == null:
			hud.show_message("Wave cleared.\nSomething in the wreckage is powering up...", 3.5)
			Sfx.ui("wave_clear", -6.0)
			await get_tree().create_timer(2.5, false).timeout
			_spawn_droid()
			await get_tree().create_timer(5.0, false).timeout
		else:
			hud.show_message("Wave cleared.\nCatch your breath...", 3.5)
			Sfx.ui("wave_clear", -6.0)
			await get_tree().create_timer(6.0, false).timeout
	_next_wave()


func _spawn_droid() -> void:
	droid = CompanionScript.new()
	droid.name = "Droid"
	droid.player = player
	droid.damage = GS.droid_damage()
	droid.position = WRECK_POS + Vector3(3.0, 0.0, 4.0)
	droid.position.y = ground_y(droid.position) + 0.5
	add_child(droid)
	droid.status_changed.connect(hud.set_droid_status)
	Sfx.ui("droid_power", -6.0)
	hud.show_droid(true)
	hud.set_droid_status(droid.order_text(), droid.weapons_free)
	hud.show_message("Your salvaged droid is online.\n1 Follow  ·  2 Hold  ·  3 Go / Attack  ·  4 Fire on/off", 5.0)


## End key: skip the waves (testing).
func _input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_END:
		if not horde and not game_over:
			_victory()


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


func _victory() -> void:
	game_over = true
	var total := 0
	for n in WAVES:
		total += n
	var earned: int = total * GS.SALVAGE_PER_KILL + GS.CLEAR_BONUS
	GS.add_salvage(earned)
	hud.show_message("You survived.  +%d salvage\nThe creatures pull back into the trees..." % earned, 5.0)
	if GS.reached_base:
		# Coming back from camp: the trail is the tutorial, so after the
		# waves you go straight back to the cave.
		hud.show_message("You survived.  +%d salvage\nHeading back to camp..." % earned, 5.0)
		await get_tree().create_timer(5.0).timeout
		if not player.is_dead:
			GS.save()
			get_tree().change_scene_to_file("res://base.tscn")
		return
	_launch_flare()
	await get_tree().create_timer(6.0).timeout
	if not player.is_dead:
		Cutscene.play("leave_crash")


func _on_player_died() -> void:
	game_over = true
	if horde:
		var survived := maxi(wave_index, 0)  # waves fully cleared
		var earned := creatures_killed * HORDE_SALVAGE_PER_KILL
		var best := survived > GS.horde_best_wave
		if best:
			GS.horde_best_wave = survived
		GS.add_salvage(earned)
		hud.show_message("", 0.0)
		menu.show_end("THE HORDE WINS", ("New record! " if best else "") + "You held out through %d waves." % survived,
				"Reached wave %d   ·   Creatures killed: %d   ·   Best: %d waves   ·   +%d salvage" % [wave_index + 1, creatures_killed, GS.horde_best_wave, earned], 2.5)
		return
	hud.show_message("", 0.0)
	menu.show_end("YOU WERE OVERRUN", "The creatures took the crash site.",
			"Reached wave %d of %d   ·   Creatures killed: %d" % [wave_index + 1, WAVES.size(), hud.kills()], 2.5)


func _launch_flare() -> void:
	var flare := Node3D.new()
	add_child(flare)
	flare.position = Vector3(30.0, ground_y(Vector3(30.0, 0.0, -42.0)) + 6.0, -42.0)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	mi.material_override = U.mat(Color(1, 0.3, 0.2), 0.5, Color(1.0, 0.2, 0.1), 12.0)
	flare.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.2)
	light.light_energy = 8.0
	light.omni_range = 40.0
	flare.add_child(light)
	var tw := create_tween()
	tw.tween_property(flare, "position:y", flare.position.y + 40.0, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.38, 0.46)
	sky_mat.sky_horizon_color = Color(0.66, 0.6, 0.5)
	sky_mat.ground_horizon_color = Color(0.3, 0.32, 0.25)
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.08)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.55, 0.5)
	env.fog_density = 0.011
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


## Height of the ground under `p` (only x and z are used).
func ground_y(p: Vector3) -> float:
	if terrain != null:
		var h: float = terrain.data.get_height(Vector3(p.x, 0.0, p.z))
		if not is_nan(h) and absf(h) < 1000.0:
			return h
		return _height_at(p.x, p.z)
	return 0.0


## The landscape: a nearly flat clearing, rolling forest floor, and a ring of
## hills that closes the arena in. A shallow gouge marks where the ship hit.
func _height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var roll := _noise_roll.get_noise_2d(x, z)
	var h := roll * lerpf(0.25, 2.4, smoothstep(CLEARING_RADIUS - 3.0, 48.0, d))
	var hill := 0.5 + 0.5 * _noise_hill.get_noise_2d(x, z)
	h += smoothstep(52.0, 105.0, d + _noise_edge.get_noise_2d(x, z) * 10.0) * (12.0 + 26.0 * hill)
	# Crash gouge: a long shallow trench running into the wreck.
	var local := Vector2(x - WRECK_POS.x, z - WRECK_POS.z).rotated(deg_to_rad(WRECK_FURROW_DEG))
	var along := clampf((local.y + 10.0) / 40.0, 0.0, 1.0)
	var across := absf(local.x) / lerpf(4.5, 2.0, along)
	if local.y > -14.0 and local.y < 32.0:
		var cut := (1.0 - smoothstep(0.0, 1.0, across)) * 1.3 * (1.0 - along) * smoothstep(-14.0, -9.0, local.y)
		# Dirt shoved up in a berm in front of the nose and along the edges.
		var berm := smoothstep(0.7, 1.0, across) * (1.0 - smoothstep(1.0, 1.6, across)) * 0.45 * (1.0 - along)
		berm += (1.0 - smoothstep(0.0, 1.2, across)) * smoothstep(-14.0, -11.5, local.y) * (1.0 - smoothstep(-11.5, -9.5, local.y)) * 1.1
		h += berm - cut
	return h


func _build_ground() -> void:
	if ClassDB.class_exists("Terrain3D"):
		_build_terrain()
	else:
		_build_flat_ground()

	# Invisible walls at the edge of the map.
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := StaticBody3D.new()
		var wcs := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(2.0, 80.0, 130.0) if d.x != 0.0 else Vector3(130.0, 80.0, 2.0)
		wcs.shape = wb
		wall.add_child(wcs)
		wall.position = d * ARENA_RADIUS + Vector3(0.0, 20.0, 0.0)
		add_child(wall)


func _build_terrain() -> void:
	_noise_roll.seed = 11
	_noise_roll.frequency = 0.035
	_noise_roll.fractal_octaves = 4
	_noise_hill.seed = 23
	_noise_hill.frequency = 0.012
	_noise_hill.fractal_octaves = 5
	_noise_edge.seed = 5
	_noise_edge.frequency = 0.02

	terrain = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.free_editor_textures = false
	terrain.material = load(TERRAIN_MATERIAL).duplicate(true)
	var assets = load(TERRAIN_ASSETS).duplicate(true)
	# 0 = cliff rock, 1 = grass (from the Terrain3D demo). Add 2 = trampled dirt.
	var grass = assets.get_texture_asset(1)
	grass.albedo_color = Color(0.5, 0.6, 0.45)
	var dirt = ClassDB.instantiate("Terrain3DTextureAsset")
	dirt.name = "Dirt"
	dirt.albedo_texture = grass.albedo_texture
	dirt.normal_texture = grass.normal_texture
	dirt.albedo_color = Color(0.62, 0.48, 0.34)
	dirt.normal_depth = 1.2
	dirt.ao_strength = 1.0
	dirt.uv_scale = 0.15
	assets.set_texture_asset(2, dirt)
	terrain.assets = assets
	terrain.collision_mode = 3  # full collision, in game
	add_child(terrain)

	# Heightmap, in metres.
	var n := TERRAIN_SIZE
	var half: int = n >> 1
	var img := Image.create_empty(n, n, false, Image.FORMAT_RF)
	for py in n:
		for px in n:
			img.set_pixel(px, py, Color(_height_at(px - half, py - half), 0.0, 0.0, 1.0))
	terrain.data.import_images([img, null, null], Vector3(-half, 0.0, -half), 0.0, 1.0)

	# Paint the clearing as trampled dirt and scorch the ground round the wreck.
	var data = terrain.data
	var r := int(CLEARING_RADIUS + 6.0)
	for x in range(-r, r + 1):
		for z in range(-r, r + 1):
			var p := Vector3(x, 0.0, z)
			var d := Vector2(x, z).length() + _noise_edge.get_noise_2d(x * 3.0, z * 3.0) * 4.0
			var w := 1.0 - smoothstep(CLEARING_RADIUS - 8.0, CLEARING_RADIUS + 2.0, d)
			var dw := Vector2(x - WRECK_POS.x, z - WRECK_POS.z).length()
			# Churned dirt along the whole furrow, scorched around the wreck.
			var lc := Vector2(x - WRECK_POS.x, z - WRECK_POS.z).rotated(deg_to_rad(WRECK_FURROW_DEG))
			var furrow := 0.0
			if lc.y > -15.0 and lc.y < 34.0:
				var width := lerpf(6.0, 3.0, clampf((lc.y + 10.0) / 40.0, 0.0, 1.0))
				furrow = 1.0 - smoothstep(width * 0.8, width * 1.3, absf(lc.x) + _noise_roll.get_noise_2d(x * 3.0, z * 3.0) * 1.5)
			w = maxf(w, maxf(furrow, 1.0 - smoothstep(8.0, 13.0, dw)))
			if w > 0.03:
				data.set_control_auto(p, false)
				data.set_control_base_id(p, 1)
				data.set_control_overlay_id(p, 2)
				data.set_control_blend(p, w)
			if dw < 16.0 or furrow > 0.0:
				var burn := 1.0 - smoothstep(4.0, 15.0, dw + _noise_roll.get_noise_2d(x * 4.0, z * 4.0) * 3.0)
				burn = maxf(burn, furrow * 0.55)
				data.set_color(p, Color.WHITE.lerp(Color(0.16, 0.14, 0.12), burn))
	data.update_maps()

	# GPU grass that grows on the grass texture.
	if ResourceLoader.exists(GRASS_PARTICLES):
		var grass_fx = load(GRASS_PARTICLES).instantiate()
		terrain.add_child(grass_fx)
		grass_fx.terrain = terrain


func _build_flat_ground() -> void:
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


## Tree and undergrowth models from Quaternius' Stylized Nature MegaKit (CC0).
const NATURE := "res://glTF/"
const WK = preload("res://scripts/world_kit.gd")
const PINES := ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const LEAFY := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]
const DEAD := ["DeadTree_1", "DeadTree_2", "DeadTree_3"]
const UNDERGROWTH := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1_Big", "Plant_7_Big", "Mushroom_Common", "Rock_Medium_1", "Rock_Medium_2"]


## First mesh in a model file, or null if it isn't there.
func _model_mesh(model: String) -> Mesh:
	if WK._is_tree(model):
		return WK.model_mesh(model)
	var path := NATURE + model + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	var inst: Node = load(path).instantiate()
	var mesh: Mesh = null
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	inst.free()
	return mesh


## Picks a tree model: mostly pines, some broadleaf, the odd dead tree.
func _pick_tree(pines: Array, leafy: Array, dead: Array) -> Mesh:
	var r := rng.randf()
	if r < 0.06 and not dead.is_empty():
		return dead[rng.randi() % dead.size()]
	if r < 0.32 and not leafy.is_empty():
		return leafy[rng.randi() % leafy.size()]
	return pines[rng.randi() % pines.size()]


func _meshes(names: Array) -> Array:
	var out := []
	for n in names:
		var m := _model_mesh(n)
		if m != null:
			out.append(m)
	return out


func _build_forest() -> void:
	var pines := _meshes(PINES)
	if pines.is_empty():
		_build_cone_forest()
		return
	var leafy := _meshes(LEAFY)
	var dead := _meshes(DEAD)
	var buckets := {}  # Mesh -> Array[Transform3D]

	# Trees inside the arena: thinner near the clearing, each with a trunk collider.
	var placed := 0
	var tries := 0
	while placed < 230 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-ARENA_RADIUS, ARENA_RADIUS), 0.0, rng.randf_range(-ARENA_RADIUS, ARENA_RADIUS))
		var d := p.length()
		if d < CLEARING_RADIUS + 1.0 or d > ARENA_RADIUS + 4.0:
			continue
		if d < 27.0 and rng.randf() < 0.55:
			continue
		p.y = ground_y(p) - 0.15
		var s := rng.randf_range(1.5, 2.3)
		_add_instance(buckets, _pick_tree(pines, leafy, dead), p, s)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.22 * s
		shape.height = 8.0
		cs.shape = shape
		cs.position.y = 4.0
		body.add_child(cs)
		body.position = p
		add_child(body)
		placed += 1

	# Hills outside the arena: no colliders, they're out of reach.
	if terrain != null:
		tries = 0
		var far := 0
		while far < 900 and tries < 4000:
			tries += 1
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(64.0 * 64.0, 175.0 * 175.0))
			var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
			p.y = ground_y(p) - 0.3
			_add_instance(buckets, _pick_tree(pines, leafy, dead), p, rng.randf_range(1.7, 2.6))
			far += 1

	WK.plant(self, buckets, 230.0)

	# Undergrowth: bushes, ferns, plants and mushrooms around the trees.
	var small := _meshes(UNDERGROWTH)
	if small.is_empty():
		return
	var scales := {
		"Bush_Common": Vector2(0.9, 1.6), "Bush_Common_Flowers": Vector2(0.9, 1.5), "Fern_1": Vector2(0.15, 0.25),
		"Plant_1_Big": Vector2(0.6, 1.1), "Plant_7_Big": Vector2(0.6, 1.1), "Mushroom_Common": Vector2(0.8, 1.4),
		"Rock_Medium_1": Vector2(0.5, 1.2), "Rock_Medium_2": Vector2(0.5, 1.2),
	}
	var names := []
	for n in UNDERGROWTH:
		if _model_mesh(n) != null:
			names.append(n)
	var small_buckets := {}
	for i in 420:
		var a := rng.randf() * TAU
		var r := rng.randf_range(CLEARING_RADIUS - 3.0, ARENA_RADIUS + 10.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if p.distance_to(WRECK_POS) < 13.0:
			continue
		p.y = ground_y(p) - 0.05
		var k := rng.randi() % names.size()
		var sc: Vector2 = scales[names[k]]
		_add_instance(small_buckets, small[k], p, rng.randf_range(sc.x, sc.y))
	for mesh in small_buckets:
		var mmi := _multimesh(mesh, null, small_buckets[mesh], Vector3.ZERO)
		mmi.visibility_range_end = 90.0


func _add_instance(buckets: Dictionary, mesh: Mesh, p: Vector3, s: float) -> void:
	if not buckets.has(mesh):
		var arr: Array[Transform3D] = []
		buckets[mesh] = arr
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
	buckets[mesh].append(Transform3D(b, p))


## Fallback if the nature kit is missing: simple cone trees.
func _build_cone_forest() -> void:
	var trunk_mat := U.mat(Color(0.25, 0.18, 0.12), 0.95)
	var leaf_mats := [
		U.mat(Color(0.12, 0.24, 0.12), 0.9),
		U.mat(Color(0.16, 0.3, 0.14), 0.9),
		U.mat(Color(0.1, 0.2, 0.14), 0.9),
	]
	var placed := 0
	var tries := 0
	while placed < 260 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-ARENA_RADIUS, ARENA_RADIUS), 0.0, rng.randf_range(-ARENA_RADIUS, ARENA_RADIUS))
		var d := p.length()
		if d < CLEARING_RADIUS:
			continue
		if d < 26.0 and rng.randf() < 0.6:
			continue
		p.y = ground_y(p) - 0.2
		_add_tree(p, trunk_mat, leaf_mats[rng.randi() % leaf_mats.size()])
		placed += 1


func _multimesh(mesh: Mesh, material: Material, xforms: Array, offset: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		mm.set_instance_transform(i, t * Transform3D(Basis(), offset))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material != null:
		mmi.material_override = material
	add_child(mmi)
	return mmi


func _add_tree(p: Vector3, trunk_mat: Material, leaf_mat: Material) -> void:
	var h := rng.randf_range(7.0, 13.0)
	var r := rng.randf_range(0.25, 0.5)
	var tree := StaticBody3D.new()
	tree.position = p
	tree.rotation.y = rng.randf() * TAU

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = r * 0.6
	tm.bottom_radius = r
	tm.height = h
	trunk.mesh = tm
	trunk.position.y = h * 0.5
	trunk.material_override = trunk_mat
	tree.add_child(trunk)

	var layers := rng.randi_range(2, 3)
	for i in layers:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(2.0, 3.2) * (1.0 - i * 0.25)
		cm.height = h * 0.45
		cone.mesh = cm
		cone.position.y = h * 0.45 + i * h * 0.2
		cone.material_override = leaf_mat
		tree.add_child(cone)

	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	cs.position.y = h * 0.5
	tree.add_child(cs)
	add_child(tree)


func _build_rocks() -> void:
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	var rock_mat := U.mat(Color(0.38, 0.38, 0.36), 0.95)
	for i in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 55.0)
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if pos.distance_to(WRECK_POS) < 14.0 or pos.distance_to(Vector3(0, 0, 5)) < 4.0:
			continue
		var s := rng.randf_range(0.12, 0.5)
		if not scenes.is_empty():
			var rock: Node3D = scenes[rng.randi() % scenes.size()].instantiate()
			rock.scale = Vector3.ONE * s
			rock.position = Vector3(pos.x, ground_y(pos) + s * 1.2, pos.z)
			rock.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
			add_child(rock)
		else:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			mi.mesh = sm
			mi.scale = Vector3.ONE * s * 3.0
			mi.position = Vector3(pos.x, ground_y(pos), pos.z)
			mi.material_override = rock_mat
			add_child(mi)


## Your crashed ship: smoking hull plates and fires.
func _build_wreck() -> void:
	var w := WreckScript.build(self, Vector3(WRECK_POS.x, ground_y(WRECK_POS), WRECK_POS.z), WRECK_FURROW_DEG + 180.0, ground_y, _fire_lights)
	w.add_to_group("objective")   # defend the ship: gold marker on the compass
	Sfx.loop(w, "fire_loop", -4.0, 4.0)


## Supply crates and debris in the wreckage of your ship.
func _build_salvage() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for k in 4:
		var a := r.randf() * TAU
		var p := WRECK_POS + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(10.0, 13.0)
		p.y = ground_y(p)
		Pickup.spawn(self, "crate", "", p)
	for k in 8:
		var a2 := r.randf() * TAU
		var p2 := WRECK_POS + Vector3(cos(a2), 0.0, sin(a2)) * r.randf_range(10.0, 18.0)
		p2.y = ground_y(p2)
		Pickup.spawn(self, "resource", "scrap" if k % 2 == 0 else "plastic", p2, Vector2i(1, 3))
	for k in 6:
		var a3 := r.randf() * TAU
		var p3 := Vector3(cos(a3), 0.0, sin(a3)) * r.randf_range(10.0, 24.0)
		p3.y = ground_y(p3)
		Pickup.spawn(self, "resource", "wood" if k % 2 == 0 else "fiber", p3)
