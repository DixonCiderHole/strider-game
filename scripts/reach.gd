extends Node3D
## SHIPFALL REACH: the wreck field east of Base Camp, where Ilsa's medical
## missions happen (Items.MED_QUESTS). Everything that flies low over the
## spires comes down somewhere like this.
##
## A large, open area: two wadeable rivers (main one north to south, a stream
## joining it from the east), a broken bulk hauler either side of the river,
## spilled cargo, old Vaari stone ruins round a crystal-lit platform, a K-7
## survey lander nose-down across the stream, and her pathfinder unit's
## waypoint camp by the west trail. Creatures are scattered in packs and come
## back every time the area loads. New assets: models/reach_kit.glb
## (tools/assetgen/reach_gen.py).
##
## World map: the west trail lines up with Base Camp's east trail
## (world_map.gd REACH_LEAD / BASE_EAST). Local axes: +X east, -Z north.

const U = preload("res://scripts/util.gd")
const UI = preload("res://scripts/ui.gd")
const WK = preload("res://scripts/world_kit.gd")
const GS = preload("res://scripts/game_state.gd")
const MB = preload("res://scripts/menu_backdrop.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Items = preload("res://scripts/items.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const CompanionScript = preload("res://scripts/companion.gd")
const OverlayScript = preload("res://scripts/overlay.gd")
const PauseMenuScript = preload("res://scripts/pause_menu.gd")
const Pickup = preload("res://scripts/pickup.gd")
const Interactable = preload("res://scripts/interactable.gd")
const MapPoi = preload("res://scripts/map_poi.gd")
const LorePanel = preload("res://scripts/lore_panel.gd")
const Lore = preload("res://scripts/lore.gd")
const WorldMap = preload("res://scripts/world_map.gd")

const SELF := "res://reach.tscn"
const BASE := "res://base.tscn"
const CANYON := "res://canyon.tscn"
const KIT := "res://models/reach_kit.glb"
const PROPS_GLB := "res://models/camp_props.glb"
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]

const TERRAIN_SIZE := 352
## Where you can walk (world_map.gd AREAS uses the same rect).
const RECT := Rect2(-125.0, -95.0, 250.0, 190.0)
const WATER_Y := -0.2

const CAMP := Vector3(-78.0, 0.0, 10.0)        # her unit's waypoint camp
const FORE := Vector3(-52.0, 0.0, -50.0)       # freighter nose half (torn end)
const AFT := Vector3(-8.0, 0.0, -70.0)         # freighter engine half (torn end)
const RUINS := Vector3(66.0, 0.0, -28.0)
const DAIS := Vector3(70.0, 0.0, -30.0)
const LANDER := Vector3(52.0, 0.0, 66.0)
## Flattened ground: [centre, radius].
const PADS := [[Vector3(-78.0, 0.0, 10.0), 9.0], [Vector3(-59.0, 0.0, -50.0), 12.0], [Vector3(-2.0, 0.0, -70.0), 10.0],
	[Vector3(52.0, 0.0, 66.0), 8.0]]
## Worn foot paths (polylines): camp to the ford, and on from the far bank to the ruins.
const PATHS := [[Vector3(-78.0, 0.0, 10.0), Vector3(-40.0, 0.0, 5.0), Vector3(-17.0, 0.0, 2.0)],
	[Vector3(-2.0, 0.0, -2.0), Vector3(25.0, 0.0, -12.0), Vector3(52.0, 0.0, -21.0)],
	[Vector3(52.0, 0.0, -21.0), Vector3(86.0, 0.0, -8.0), Vector3(104.0, 0.0, -1.0), Vector3(125.0, 0.0, 0.0)]]
## The east gap in the hills: the way into Spire Canyon (world_map.gd).
const EAST_EXIT := Vector3(118.0, 0.0, 0.0)
## Creature packs: [centre, how many]. All dormant until you get close.
const PACKS := [[Vector3(-30.0, 0.0, -60.0), 3], [Vector3(6.0, 0.0, -62.0), 2], [Vector3(-64.0, 0.0, -36.0), 2],
	[Vector3(70.0, 0.0, -30.0), 3], [Vector3(50.0, 0.0, -12.0), 2], [Vector3(88.0, 0.0, -22.0), 2],
	[Vector3(58.0, 0.0, 58.0), 3], [Vector3(-38.0, 0.0, -18.0), 2], [Vector3(96.0, 0.0, 18.0), 2],
	[Vector3(-58.0, 0.0, 60.0), 2], [Vector3(18.0, 0.0, 52.0), 2]]

var terrain
var player
var droid
var menu
var overlay
var rng := RandomNumberGenerator.new()

var _noise_roll := FastNoiseLite.new()
var _noise_hill := FastNoiseLite.new()
var _kit: Node3D
var _props: Node3D
var _time := 0.0
var _ui: CanvasLayer
var _banner: Label
var _banner_tw: Tween
var _fade: ColorRect
var _respawning := false
var _medkit_at := Vector3.ZERO
var _exit_at := Vector3.ZERO
var _east_at := Vector3.ZERO
var _caches: Array = []         # [{pos, lid, it, light, opened}]
var _wet := false
var _lamps: Array = []
var _drone_at := Vector3.ZERO
var _drone_node: Node3D
var _pad_h: Array = []         # ground height at each PADS centre
var _ruins_h := 0.0
var _sunk_its: Array = []


# ---------------------------------------------------------------- shape

func river_x(z: float) -> float:
	return -22.0 + 14.0 * sin(z * 0.028 + 0.5) + 5.0 * sin(z * 0.07)


func river_slope(z: float) -> float:
	return 14.0 * 0.028 * cos(z * 0.028 + 0.5) + 5.0 * 0.07 * cos(z * 0.07)


func river_hw(z: float) -> float:
	return 6.0 + 2.0 * sin(z * 0.05 + 1.0)


## The stream that joins from the east.
func trib_z(x: float) -> float:
	return 42.0 + 8.0 * sin(x * 0.035)


const TRIB_HW := 3.4
## Swimming pools on the main river: [z on the river, radius, depth below the surface].
const POOLS := [[-40.0, 9.0, 4.2], [70.0, 8.0, 3.8]]


## Nearest channel: (distance from its centre line, its half width).
func _river_d(x: float, z: float) -> Vector2:
	var s := river_slope(z)
	var best := Vector2(absf(x - river_x(z)) / sqrt(1.0 + s * s), river_hw(z))
	if x > river_x(trib_z(x)) - 3.0:
		var s2 := 8.0 * 0.035 * cos(x * 0.035)
		var d2 := absf(z - trib_z(x)) / sqrt(1.0 + s2 * s2)
		if d2 - TRIB_HW < best.x - best.y:
			best = Vector2(d2, TRIB_HW)
	return best


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _path_dist(x: float, z: float) -> float:
	var d := INF
	var p := Vector2(x, z)
	for path in PATHS:
		for i in range(path.size() - 1):
			d = minf(d, _seg_dist(p, Vector2(path[i].x, path[i].z), Vector2(path[i + 1].x, path[i + 1].z)))
	return d


## Rolling ground before rivers, pads and edge hills.
func _base_h(x: float, z: float) -> float:
	return 0.9 + _noise_roll.get_noise_2d(x, z) * 1.4 + (0.5 + 0.5 * _noise_hill.get_noise_2d(x * 1.3, z * 1.3)) * 3.0


func _height_at(x: float, z: float) -> float:
	var h := _base_h(x, z)
	# A low mound under the ruins.
	var rd0 := Vector2(x - RUINS.x, z - RUINS.z).length()
	if rd0 < 28.0:
		h = lerpf(h, _ruins_h + 0.9, 1.0 - smoothstep(14.0, 28.0, rd0))
	# Flat pads under the camp and the wrecks.
	for i in PADS.size():
		var c: Vector3 = PADS[i][0]
		var r: float = PADS[i][1]
		var d := Vector2(x - c.x, z - c.z).length()
		if d < r + 8.0:
			h = lerpf(h, _pad_h[i], 1.0 - smoothstep(r, r + 8.0, d))
	# Hills all round the edge, with a gap where the west trail comes in.
	var out := maxf(absf(x) - 110.0, absf(z) - 80.0)
	var gap := 1.0
	if x < -90.0:
		gap = smoothstep(5.0, 16.0, WorldMap.reach_lead_dist(x, z))
	elif x > 90.0:
		gap = smoothstep(5.0, 16.0, absf(z - EAST_EXIT.z))
	h += smoothstep(-8.0, 30.0, out + _noise_hill.get_noise_2d(x * 2.0, z * 2.0) * 8.0) \
			* (13.0 + 16.0 * (0.5 + 0.5 * _noise_hill.get_noise_2d(x, z))) * gap
	h = maxf(h, 0.15)
	# Rivers: a shallow bed (wade in to your waist at most) with soft banks.
	# They cut on through the hills, so they run in and out of the area.
	var rv := _river_d(x, z)
	if rv.x < rv.y + 6.0:
		var t := rv.x / rv.y
		var depth := 0.5 + 0.35 * (0.5 + 0.5 * _noise_roll.get_noise_2d(x * 0.5 + 40.0, z * 0.5))
		var bed := WATER_Y - 0.1 - depth * maxf(0.0, 1.0 - t * t)
		var k := 1.0 - smoothstep(rv.y - 0.5, rv.y + 6.0, rv.x)
		h = minf(h, lerpf(h, bed, k))
	# Deep pools where the river slows: deep enough to swim and dive.
	for pool in POOLS:
		var c := Vector2(river_x(pool[0]), pool[0])
		var pr: float = pool[1]
		var pd := Vector2(x, z).distance_to(c) + _noise_roll.get_noise_2d(x * 3.0, z * 3.0) * 1.2
		if pd < pr + 5.0:
			var u := clampf(pd / pr, 0.0, 1.0)
			var pdep: float = pool[2]
			var bowl := WATER_Y - 0.7 - (pdep - 0.7) * (1.0 - u * u)
			h = minf(h, lerpf(bowl, h, smoothstep(pr - 1.0, pr + 5.0, pd)))
	return h


func _paint(data, x: float, z: float) -> void:
	var p := Vector3(x, 0.0, z)
	var n := _noise_roll.get_noise_2d(x * 4.0, z * 4.0)
	var w := 0.0
	var ld := WorldMap.reach_lead_dist(x, z)
	if ld < 8.0:
		w = maxf(w, (1.0 - smoothstep(2.0, 4.5, ld + n * 1.5)) * 0.9)
	var pd := _path_dist(x, z)
	if pd < 6.0:
		w = maxf(w, (1.0 - smoothstep(1.0, 3.0, pd + n * 1.2)) * 0.7)
	var cd := Vector2(x - CAMP.x, z - CAMP.z).length()
	w = maxf(w, (1.0 - smoothstep(4.0, 8.0, cd + n * 2.0)) * 0.85)
	var rv := _river_d(x, z)
	var mud := 0.0
	if rv.x < rv.y + 5.0:
		mud = 1.0 - smoothstep(rv.y + 0.5, rv.y + 5.0, rv.x + n * 1.5)
		w = maxf(w, mud)
	var scorch := 0.0
	for c in [Vector3(-59.0, 0.0, -50.0), Vector3(-2.0, 0.0, -70.0), Vector3(-30.0, 0.0, -60.0), LANDER]:
		var dd := Vector2(x - c.x, z - c.z).length()
		scorch = maxf(scorch, 1.0 - smoothstep(5.0, 15.0, dd + n * 3.0))
	w = maxf(w, scorch * 0.9)
	var rr := Vector2(x - DAIS.x, z - DAIS.z).length()
	w = maxf(w, (1.0 - smoothstep(6.0, 16.0, rr + n * 3.0)) * 0.6)
	if w > 0.03:
		WK.paint_dirt(data, p, w)
	if mud > 0.05:
		data.set_color(p, Color.WHITE.lerp(Color(0.5, 0.47, 0.42), mud))
	if scorch > 0.05:
		data.set_color(p, Color.WHITE.lerp(Color(0.42, 0.38, 0.34), scorch * 0.8))
	var fd := Vector2(x - (CAMP.x + 1.5), z - (CAMP.z + 2.5)).length()
	if fd < 1.6:
		data.set_color(p, Color.WHITE.lerp(Color(0.18, 0.16, 0.15), 1.0 - smoothstep(0.4, 1.6, fd)))


func _ground(p: Vector3) -> float:
	return WK.ground_y(terrain, p, _height_at(p.x, p.z))


func _on_ground(x: float, z: float, lift := 0.0) -> Vector3:
	var p := Vector3(x, 0.0, z)
	p.y = _ground(p) + lift
	return p


# ---------------------------------------------------------------- setup

func _ready() -> void:
	rng.seed = 404
	GS.ensure_loaded()
	GS.horde_mode = false
	_noise_roll.seed = 51
	_noise_roll.frequency = 0.03
	_noise_roll.fractal_octaves = 4
	_noise_hill.seed = 52
	_noise_hill.frequency = 0.012
	_noise_hill.fractal_octaves = 4
	for pad in PADS:
		_pad_h.append(_base_h(pad[0].x, pad[0].z))
	_ruins_h = _base_h(RUINS.x, RUINS.z)
	if ResourceLoader.exists(KIT):
		_kit = load(KIT).instantiate()
	if ResourceLoader.exists(PROPS_GLB):
		_props = load(PROPS_GLB).instantiate()

	_build_environment()
	_build_ground()
	_build_water()
	_build_freighter()
	_build_ruins()
	_build_lander()
	_build_forest()
	_build_river_life()
	if GS.menu_preview:
		var cp := Vector3(-30.0, 0.0, -38.0)
		MB.make(self, cp + Vector3(0.0, _ground(cp) + 2.2, 0.0), Vector3(-6.0, _ground(AFT) + 2.0, -66.0))
		set_process(false)
		return
	GS.enter_area(SELF)
	var as_her: bool = GS.active_member == "survivor"

	# Arrive on the west trail, or at the waypoint camp after a fall.
	var at_camp: bool = GS.flags.get("reach_spawn", "") == "camp"
	GS.flags.erase("reach_spawn")
	var sx := -117.0
	var start := _on_ground(sx, WorldMap.reach_lead_z(sx), 0.1)
	var yaw := -PI * 0.5   # facing east
	if GS.flags.get("came_from", "") == CANYON and not at_camp:
		start = _on_ground(EAST_EXIT.x - 4.0, EAST_EXIT.z, 0.1)
		yaw = PI * 0.5     # facing west, back into the Reach
	GS.flags.erase("came_from")
	if at_camp:
		start = _on_ground(CAMP.x + 3.0, CAMP.z + 4.5, 0.1)
		yaw = -PI * 0.4
	player = PlayerScript.new()
	player.name = "Player"
	if as_her:
		player.character = "survivor"
	player.damage = GS.player_damage()
	player.max_health = GS.player_max_health()
	player.health = player.max_health
	player.position = start
	add_child(player)
	player._facing_yaw = yaw
	player.model.rotation.y = yaw
	player.cam_yaw.rotation.y = yaw
	player.died.connect(_on_player_died)
	player.water_at = func(_p: Vector3) -> float: return WATER_Y

	if GS.droid_online():
		droid = CompanionScript.new()
		droid.name = "Droid"
		droid.player = player
		droid.damage = GS.droid_damage()
		droid.position = start + Vector3(-2.0, 0.5, 2.0)
		add_child(droid)

	menu = PauseMenuScript.new()
	menu.player = player
	add_child(menu)
	_build_ui()
	overlay = OverlayScript.new()
	overlay.player = player
	overlay.tracker_top = 60.0
	overlay.objective_provider = _quest_target
	add_child(overlay)
	var lore_panel = LorePanel.new()
	lore_panel.player = player
	add_child(lore_panel)

	_build_camp()
	_build_caches()
	_build_exit()
	_build_walls()
	_build_pickups()
	_build_sunken_pods()
	_build_map_points()
	_spawn_packs()
	Sfx.loop(self, "forest_loop", -17.0, 6.0, false)

	if at_camp:
		_show_banner("You come to by the cold fire at the waypoint camp.", 3.5)
	elif as_her and not GS.flags.get("reach_seen", false):
		_show_banner("SHIPFALL REACH\nEverything that flies low over the spires ends up here.\nYour unit came through two days after the HALCYON fell.", 6.0)
	else:
		_show_banner("SHIPFALL REACH", 3.0)
	GS.flags["reach_seen"] = true


func _exit_tree() -> void:
	if _kit != null:
		_kit.free()
	if _props != null:
		_props.free()


func _process(delta: float) -> void:
	_time += delta
	for l in _lamps:
		var ph: float = l.get_meta("phase", 0.0)
		(l as OmniLight3D).light_energy = 1.4 if fmod(_time + ph, 1.6) < 0.18 else 0.0
	if player == null or not is_instance_valid(player) or player.is_dead:
		return
	# (Wading and swimming are handled by the player from water_at.)
	var pp: Vector3 = player.global_position
	# Reaching the waypoint camp (her first mission).
	if GS.med_active() and not GS.flags.get("reach_waypoint", false) \
			and Vector2(pp.x - CAMP.x, pp.z - CAMP.z).length() < 9.0:
		GS.flags["reach_waypoint"] = true
		GS.add_xp(5)
		GS.changed()
		_show_banner("THE WAYPOINT\nSix of you slept round this fire, two days out from the HALCYON.\nNow it's just you. The beacon's still blinking.", 7.0)


func _unhandled_input(event) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_tree().paused or droid == null:
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


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.33, 0.43)
	sky_mat.sky_horizon_color = Color(0.68, 0.62, 0.52)
	sky_mat.ground_horizon_color = Color(0.3, 0.31, 0.25)
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
	env.fog_light_color = Color(0.56, 0.58, 0.54)
	env.fog_density = 0.011
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36.0, 125.0, 0.0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130.0
	add_child(sun)


func _build_ground() -> void:
	terrain = WK.build_terrain(self, TERRAIN_SIZE, _height_at, _paint, TERRAIN_SIZE / 2)
	if terrain == null:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(400.0, 1.0, 400.0)
		cs.shape = box
		cs.position.y = -0.5
		body.add_child(cs)
		add_child(body)


## Keep the player inside RECT.
func _build_walls() -> void:
	var c := RECT.get_center()
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(2.0, 90.0, RECT.size.y + 10.0) if d.x != 0.0 else Vector3(RECT.size.x + 10.0, 90.0, 2.0)
		cs.shape = b
		wall.add_child(cs)
		var half := RECT.size.x * 0.5 if d.x != 0.0 else RECT.size.y * 0.5
		wall.position = Vector3(c.x, 25.0, c.y) + d * half
		add_child(wall)


## River water: one surface at WATER_Y over the whole area. The ground is
## above it everywhere except the river beds, so it only shows in the rivers.
## Refraction of the bed through depth-tinted water, two scrolling ripple
## normals drifting downstream, foam on the shallow edges and round stones.
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.16, 0.36, 0.3);
uniform vec3 deep_col : source_color = vec3(0.03, 0.1, 0.1);
uniform vec3 absorb = vec3(1.4, 0.55, 0.42);
uniform vec2 flow = vec2(0.012, 0.07);
uniform float refract_strength = 0.035;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	VERTEX.y += sin(wpos.x * 0.6 + wpos.z * 0.4 - t * 2.1) * 0.012 + sin(wpos.z * 0.9 - t * 2.7) * 0.008;
}

float scene_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.z / v.w;
}

void fragment() {
	float t = TIME;
	vec3 n1 = texture(normal_a, wpos.xz * 0.08 + flow * t).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_b, wpos.xz * 0.19 + flow * t * 1.7 + vec2(0.3, 0.1)).rgb * 2.0 - 1.0;
	vec3 nm = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.7;

	float depth = max(VERTEX.z - scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX), 0.0);
	vec2 ruv = SCREEN_UV + nm.xy * refract_strength * clamp(depth * 0.9, 0.0, 1.0);
	float z2 = scene_depth(ruv, INV_PROJECTION_MATRIX);
	if (z2 > VERTEX.z) { ruv = SCREEN_UV; } else { depth = max(VERTEX.z - z2, 0.0); }
	vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 trans = exp(-absorb * depth);
	vec3 body_col = mix(shallow_col, deep_col, clamp(depth / 1.6, 0.0, 1.0));
	vec3 body = behind * trans + body_col * (1.0 - trans);

	float fn = texture(foam_tex, wpos.xz * 0.25 + flow * t * 2.5).r;
	float shore = 1.0 - smoothstep(0.0, 0.3, depth);
	float streak = smoothstep(0.62, 0.8, fn) * 0.35;
	float foam = smoothstep(0.45, 0.8, shore * (0.55 + 0.9 * fn) + streak);
	foam *= smoothstep(0.0, 0.03, depth);

	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(body_col * 0.25, vec3(0.86, 0.9, 0.9), foam);
	EMISSION = body * (1.0 - fres) * (1.0 - foam);
	ROUGHNESS = mix(0.04, 0.75, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	ALPHA = clamp(depth * 10.0, 0.0, 1.0);
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


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(TERRAIN_SIZE, TERRAIN_SIZE)
	plane.subdivide_width = 140
	plane.subdivide_depth = 140
	water.mesh = plane
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wm.set_shader_parameter("normal_a", _noise_tex(512, 0.014, 71, true, 5.0))
	wm.set_shader_parameter("normal_b", _noise_tex(512, 0.035, 73, true, 3.0))
	wm.set_shader_parameter("foam_tex", _noise_tex(256, 0.05, 77, false, 0.0))
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0.0, WATER_Y, 0.0)
	add_child(water)
	# The sound of the rivers, along both channels.
	for z in [-70.0, -35.0, 0.0, 35.0, 70.0]:
		_river_sound(Vector3(river_x(z), WATER_Y, z), -10.0)
	for x in [30.0, 75.0, 110.0]:
		_river_sound(Vector3(x, WATER_Y, trib_z(x)), -14.0)


func _river_sound(p: Vector3, vol: float) -> void:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	Sfx.loop(n, "river_loop", vol, 9.0, true)


# ---------------------------------------------------------------- kit helpers

func _kit_mesh(n: String) -> Mesh:
	if _kit == null:
		return null
	var src := _kit.find_child(n, true, false) as MeshInstance3D
	return src.mesh if src != null else null


## A kit model at `xf`, optionally with exact (trimesh) collision.
func _model(n: String, xf: Transform3D, collide := true) -> Node3D:
	var mesh := _kit_mesh(n)
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = n
	body.transform = xf
	add_child(body)
	if mesh == null:
		return body
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
	return body


## A camp_props.glb prop on the ground at `pos` (pos.y lifts it).
func _prop(n: String, pos: Vector3, yaw_deg: float, solid := Vector3.ZERO, s := 1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos + Vector3(0.0, _ground(pos), 0.0)
	body.rotation_degrees.y = yaw_deg
	add_child(body)
	if _props != null:
		var src := _props.find_child(n, true, false) as Node3D
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


func _readable(kind: String, where: Transform3D, id: String) -> void:
	var pad := Node3D.new()
	add_child(pad)
	pad.global_transform = where
	if _props != null:
		var src := _props.find_child(kind, true, false) as Node3D
		if src != null:
			var m := src.duplicate() as Node3D
			m.transform = Transform3D.IDENTITY
			pad.add_child(m)
	var it = Interactable.new()
	it.prompt = "Read: %s" % String(Lore.entry(id).get("title", "log"))
	it.reach = 2.0
	it.action = func(): LorePanel.read(get_tree(), id)
	pad.add_child(it)


func _add_interact(pos: Vector3, prompt: String, action: Callable, reach := 2.6):
	var n = Interactable.new()
	n.prompt = prompt
	n.action = action
	n.reach = reach
	n.position = pos
	add_child(n)
	return n


## A blinking orange pathfinder beacon (kit model) standing at `pos`.
func _beacon(pos: Vector3, phase := 0.0) -> void:
	var p := Vector3(pos.x, _ground(pos), pos.z)
	_model("PathfinderBeacon", Transform3D(Basis(Vector3.UP, phase * 2.0), p), false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.55, 0.15)
	lamp.omni_range = 6.0
	lamp.position = p + Vector3(0.0, 2.05, 0.0)
	lamp.set_meta("phase", phase)
	add_child(lamp)
	_lamps.append(lamp)


func _rocks(center: Vector3, spots: Array, seed_v: int) -> void:
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	if scenes.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	for spec in spots:
		var rp: Vector3 = center + spec[0]
		var rock: Node3D = scenes[r.randi() % scenes.size()].instantiate()
		rock.scale = Vector3.ONE * float(spec[1]) * r.randf_range(0.9, 1.1)
		rock.rotation = Vector3(0.0, r.randf() * TAU, r.randf_range(-0.15, 0.15))
		rock.position = Vector3(rp.x, _ground(rp) - 0.4, rp.z)
		add_child(rock)


func _scatter(names: Array, center: Vector3, r0: float, r1: float, count: int, s0: float, s1: float, seed_v: int, vis := 120.0, dry := true) -> void:
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
		if dry and p.y < WATER_Y + 0.05:
			continue
		WK.add_instance(b, meshes[r.randi() % meshes.size()], p, r.randf_range(s0, s1), r)
	WK.plant(self, b, vis)


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


# ---------------------------------------------------------------- landmarks

## The bulk hauler ORLA'S PROMISE broke in two on the way down: the nose half
## west of the river, the engine half east of it, cargo and plating between.
func _build_freighter() -> void:
	var gf := _base_h(-59.0, -50.0)
	# Nose half: torn end faces east, nose (local +Z) points west and digs in.
	var bf := Basis(Vector3(0, 0, 1), deg_to_rad(5.0)) * Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3(0, 0, 1), deg_to_rad(4.0))
	var fore := _model("FreighterFore", Transform3D(bf, Vector3(FORE.x, gf + 1.55, FORE.z)))
	# Engine half: torn end faces west, drives to the east.
	var ga := _base_h(-2.0, -70.0)
	var ba := Basis(Vector3(0, 0, 1), deg_to_rad(-3.0)) * Basis(Vector3.UP, -PI * 0.5 + deg_to_rad(8.0)) * Basis(Vector3(0, 0, 1), deg_to_rad(-6.0))
	var aft := _model("FreighterAft", Transform3D(ba, Vector3(AFT.x, ga + 1.6, AFT.z)))
	set_meta("aft_xf", aft.global_transform)
	_build_drone(fore.global_transform)
	# Flight recorder on the deck inside the nose half, and a crate.
	_readable("Datapad", fore.global_transform * Transform3D(Basis(Vector3.UP, 0.4), Vector3(-1.2, -1.55, 6.8)), "hauler_recorder")
	Pickup.spawn(self, "crate", "", fore.global_transform * Vector3(1.4, -1.6, 4.0))
	Pickup.spawn(self, "crate", "", aft.global_transform * Vector3(-1.6, -1.6, -2.4))
	# Spilled cargo pods and plating across the gap (some in the river).
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var pod_box := BoxShape3D.new()
	pod_box.size = Vector3(6.0, 2.5, 2.4)
	for spec in [[Vector3(-42.0, 0.0, -56.0), 20.0], [Vector3(-36.0, 0.0, -66.0), 75.0], [Vector3(-18.0, 0.0, -54.0), -30.0],
			[Vector3(-14.0, 0.0, -80.0), 110.0], [Vector3(-60.0, 0.0, -64.0), 160.0]]:
		var p: Vector3 = spec[0]
		var b := Basis(Vector3.UP, deg_to_rad(spec[1])) * Basis(Vector3(1, 0, 0), r.randf_range(-0.12, 0.12)) * Basis(Vector3(0, 0, 1), r.randf_range(-0.2, 0.2))
		var pod := _model("CargoPod", Transform3D(b, Vector3(p.x, _ground(p) + 0.9, p.z)), false)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = pod_box
		body.add_child(cs)
		pod.add_child(body)
	for i in 10:
		var t := r.randf()
		var p := Vector3(lerpf(-56.0, -6.0, t), 0.0, lerpf(-52.0, -70.0, t)) + Vector3(r.randf_range(-6.0, 6.0), 0.0, r.randf_range(-7.0, 7.0))
		var b := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(1, 0, 0), r.randf_range(-0.35, 0.35))
		var s := r.randf_range(0.6, 1.2)
		_model("HullPlate", Transform3D(b.scaled(Vector3.ONE * s), Vector3(p.x, maxf(_ground(p), WATER_Y - 0.4) + 0.15, p.z)), false)
	for v in [Vector3(-46.0, 0.0, -46.0), Vector3(-22.0, 0.0, -62.0), Vector3(-6.0, 0.0, -78.0), Vector3(-64.0, 0.0, -58.0)]:
		Pickup.spawn(self, "resource", "scrap", _on_ground(v.x, v.z), Vector2i(1, 3))
	for v in [Vector3(-40.0, 0.0, -62.0), Vector3(2.0, 0.0, -60.0)]:
		Pickup.spawn(self, "resource", "plastic", _on_ground(v.x, v.z), Vector2i(1, 2))
	# Fuel and heavy cells spilled from the hauler's engine half.
	Pickup.spawn(self, "resource", "fuel", aft.global_transform * Vector3(1.5, -1.6, -6.0), Vector2i(1, 2))
	Pickup.spawn(self, "resource", "fuel", _on_ground(-26.0, -58.0), Vector2i(1, 1))
	Pickup.spawn(self, "resource", "heavy_cell", _on_ground(-44.0, -60.0), Vector2i(1, 1))
	_scatter(["Rock_Medium_1", "Rock_Medium_2", "Pebble_Square_2", "Pebble_Square_4"], Vector3(-30.0, 0.0, -60.0), 4.0, 26.0, 60, 0.5, 1.4, 19)
	_sign("ORLA'S PROMISE", Vector3(-60.0, gf + 7.5, -50.0), Color(1.0, 0.75, 0.45))


## The mini combat drone (DRONE_QUESTS), folded up on top of a cargo rack
## inside the freighter's nose. Gone once it's fixed: it flies with you.
func _build_drone(fore_xf: Transform3D) -> void:
	if GS.flags.get("drone_installed", false):
		return
	_drone_at = fore_xf * Vector3(-1.6, 0.06, 8.0)
	_drone_node = Node3D.new()
	_drone_node.position = _drone_at
	_drone_node.rotation = Vector3(0.0, 0.7, 0.12)
	add_child(_drone_node)
	if ResourceLoader.exists("res://models/companion_drone.glb"):
		var m: Node3D = load("res://models/companion_drone.glb").instantiate()
		m.scale = Vector3.ONE * (0.75 / 1.9)
		m.position.y = 0.11
		_drone_node.add_child(m)
	var blink := OmniLight3D.new()
	blink.light_color = Color(1.0, 0.2, 0.15)
	blink.omni_range = 2.2
	blink.position.y = 0.35
	blink.set_meta("phase", 0.3)
	_drone_node.add_child(blink)
	_lamps.append(blink)
	_add_interact(_drone_at + Vector3(0.0, 0.1, 0.0), "Inspect the drone", _use_drone, 2.8)


func _use_drone() -> void:
	if not GS.drone_active() or GS.med_active():
		_show_banner("A mini combat drone, folded up in its cradle.\nDead weight for now. A red light blinks, very slowly.", 3.5)
		return
	var stage := int(GS.flags["drone_stage"])
	if stage == 0:
		GS.flags["found_drone"] = true
		GS.add_xp(5)
		GS.changed()
		_show_banner("A mini combat drone: twin cannons, folded wings, not a scratch on the frame.\nThe control chip is a melted lump. Build a new one at the workbench.", 6.0)
	elif GS.count("control_chip") > 0:
		GS.remove_item("control_chip", 1)
		GS.flags["drone_installed"] = true
		GS.add_xp(10)
		GS.changed()
		_show_banner("The chip clicks home. The wings unfold, the cannons swing round...\nand it settles in at your shoulder.", 5.0)
		if is_instance_valid(_drone_node):
			_drone_node.queue_free()
		for n in get_tree().get_nodes_in_group("interactable"):
			if n.get("prompt") == "Inspect the drone":
				n.queue_free()
		player._spawn_mini_drone()
	else:
		_show_banner("It needs a new control chip.\nCraft one at the Base Camp workbench.", 3.5)


## Old Vaari stone ruins on a low mound east of the river: a stepped
## platform with a crystal heart, an arch, columns and broken walls.
func _build_ruins() -> void:
	var g := _ground(DAIS)
	_model("RuinDais", Transform3D(Basis(Vector3.UP, 0.3), Vector3(DAIS.x, g - 0.05, DAIS.z)), false)
	# Walkable collision for the platform: a gentle cone you can climb, and
	# the four standing stones.
	var dais_body := StaticBody3D.new()
	dais_body.position = Vector3(DAIS.x, g - 0.05, DAIS.z)
	add_child(dais_body)
	var pts := PackedVector3Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector3(cos(a) * 5.3, -0.3, sin(a) * 5.3))
		pts.append(Vector3(cos(a) * 2.3, 1.12, sin(a) * 2.3))
	var cone := ConvexPolygonShape3D.new()
	cone.points = pts
	var ccs := CollisionShape3D.new()
	ccs.shape = cone
	dais_body.add_child(ccs)
	# (the model is turned 0.3 rad, so each stone's angle is a - 0.3)
	for k in 5:
		var a := k * PI * 0.5 + 0.4 - 0.3
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4
		cyl.height = 2.4
		var scs := CollisionShape3D.new()
		scs.shape = cyl
		scs.position = Vector3(cos(a) * 4.0, 1.6, sin(a) * 4.0)
		if k == 4:   # the crystal heart in the middle
			cyl.radius = 0.8
			scs.position = Vector3(0.0, 2.0, 0.0)
		dais_body.add_child(scs)
	var heart := OmniLight3D.new()
	heart.light_color = Color(0.3, 0.8, 1.0)
	heart.light_energy = 2.2
	heart.omni_range = 9.0
	heart.position = Vector3(DAIS.x, g + 2.2, DAIS.z)
	add_child(heart)
	# The arch over the approach from the river (walk through east-west).
	var ap := Vector3(54.0, 0.0, -21.0)
	_model("RuinArch", Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.25), Vector3(ap.x, _ground(ap) - 0.15, ap.z)))
	var r := RandomNumberGenerator.new()
	r.seed = 12
	for i in 9:
		var a := TAU * i / 9.0 + r.randf_range(-0.15, 0.15)
		var d := r.randf_range(11.0, 16.0)
		var p := DAIS + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if p.distance_to(ap) < 6.0:
			continue
		var broken := r.randf() < 0.5
		var b := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(1, 0, 0), r.randf_range(-0.05, 0.05))
		_model("RuinPillarBroken" if broken else "RuinPillar", Transform3D(b, Vector3(p.x, _ground(p) - 0.2, p.z)))
		if broken:
			var dp := p + Vector3(r.randf_range(-2.5, 2.5), 0.0, r.randf_range(-2.5, 2.5))
			_model("RuinDrum", Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(dp.x, _ground(dp) - 0.15, dp.z)))
	for spec in [[Vector3(82.0, 0.0, -14.0), 25.0], [Vector3(58.0, 0.0, -44.0), -55.0], [Vector3(87.0, 0.0, -39.0), 100.0]]:
		var wp: Vector3 = spec[0]
		_model("RuinWall", Transform3D(Basis(Vector3.UP, deg_to_rad(spec[1])), Vector3(wp.x, _ground(wp) - 0.2, wp.z)))
	# Crystal growing up through the stones.
	for spec in [Vector3(62.0, 0.0, -36.0), Vector3(79.0, 0.0, -24.0), Vector3(66.0, 0.0, -17.0), Vector3(84.0, 0.0, -33.0), Vector3(57.0, 0.0, -29.0)]:
		var cp: Vector3 = spec
		var s := r.randf_range(0.7, 1.2)
		_model("CrystalCluster", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), Vector3(cp.x, _ground(cp) - 0.1, cp.z)), false)
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.3, 0.8, 1.0)
		gl.light_energy = 1.1
		gl.omni_range = 4.5
		gl.position = Vector3(cp.x, _ground(cp) + 0.8, cp.z)
		add_child(gl)
	# The ID tag, and the drag marks beside it (LORE: the Vaari take people).
	var tp := DAIS + Vector3(-6.2, 0.0, 2.0)
	var tag := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.025
	tm.bottom_radius = 0.025
	tm.height = 0.004
	tm.radial_segments = 12
	tag.mesh = tm
	tag.scale = Vector3(1.6, 1.0, 1.0)
	var metal := U.mat(Color(0.75, 0.76, 0.78), 0.3)
	metal.metallic = 1.0
	tag.material_override = metal
	tag.position = Vector3(tp.x, _ground(tp) + 0.02, tp.z)
	add_child(tag)
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.95, 0.85)
	glint.light_energy = 0.5
	glint.omni_range = 1.2
	glint.position = tag.position + Vector3(0.0, 0.3, 0.0)
	add_child(glint)
	_add_interact(tag.position + Vector3(0.0, 0.5, 0.0), "Read: %s" % String(Lore.entry("dog_tag").get("title", "tag")),
			func(): LorePanel.read(get_tree(), "dog_tag"), 2.0)
	# Ore veins in the old quarried stone, and crystal to chip off.
	for v in [Vector3(-9.0, 0.0, 9.0), Vector3(12.0, 0.0, -10.0), Vector3(16.0, 0.0, 7.0)]:
		Pickup.spawn(self, "vein", "ore", _on_ground(DAIS.x + v.x, DAIS.z + v.z))
	for v in [Vector3(-8.0, 0.0, -9.0), Vector3(10.0, 0.0, 12.0), Vector3(-14.0, 0.0, 2.0)]:
		Pickup.spawn(self, "crystal", "crystal", _on_ground(DAIS.x + v.x, DAIS.z + v.z))
		_scatter(["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3", "Pebble_Square_1", "Pebble_Square_4"], DAIS, 5.5, 20.0, 80, 0.5, 1.4, 13)
	_scatter(["Grass_Wispy_Tall", "Fern_1", "Plant_1_Big"], DAIS, 6.0, 18.0, 90, 0.6, 1.2, 14)
	_sign("VAARI RUINS", Vector3(DAIS.x, g + 7.5, DAIS.z), Color(0.6, 0.9, 1.0))


## Survey lander K7-2, nose-down on the far side of the stream.
func _build_lander() -> void:
	var g := _base_h(LANDER.x, LANDER.z)
	var b := Basis(Vector3.UP, deg_to_rad(150.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(24.0)) * Basis(Vector3(0, 0, 1), deg_to_rad(9.0))
	var lander := _model("SurveyLander", Transform3D(b, Vector3(LANDER.x, g + 1.3, LANDER.z)))
	var side := lander.global_transform * Vector3(2.4, -0.6, -0.8)
	side.y = _ground(side)
	_readable("Datapad", Transform3D(Basis(Vector3.UP, 1.2), side + Vector3(0.0, 0.03, 0.0)), "lander_log")
	Pickup.spawn(self, "crate", "", _on_ground(LANDER.x - 4.0, LANDER.z + 3.0))
	Pickup.spawn(self, "resource", "tech", _on_ground(LANDER.x + 3.5, LANDER.z + 4.0), Vector2i(1, 1))
	Pickup.spawn(self, "resource", "fuel", _on_ground(LANDER.x - 2.5, LANDER.z + 5.0), Vector2i(1, 1))
	Pickup.spawn(self, "vein", "ore", _on_ground(LANDER.x + 9.0, LANDER.z + 6.0))
	_scatter(["Rock_Medium_1", "Pebble_Square_2", "Pebble_Square_4"], LANDER, 2.0, 12.0, 30, 0.5, 1.2, 23)
	_sign("SURVEY LANDER K7-2", Vector3(LANDER.x, g + 6.5, LANDER.z), Color(0.65, 0.95, 0.95))


## Her pathfinder unit's waypoint camp: a collapsed lean-to, the cold fire,
## a field med kit (where she cooks remedies and studies samples), the
## unit log and a beacon.
func _build_camp() -> void:
	var c := CAMP
	_model("FieldShelter", Transform3D(Basis(Vector3.UP, deg_to_rad(15.0)), _on_ground(c.x - 1.0, c.z - 2.5)), false)
	_prop("Rug", c + Vector3(-1.0, 0.02, -2.4), 15.0)
	_beacon(c + Vector3(4.8, 0.0, 0.5), 0.0)
	var kit := _prop("MedBench", c + Vector3(-4.6, 0.0, 1.8), 70.0, Vector3(1.66, 1.9, 0.72))
	_medkit_at = kit.global_transform * Vector3(0.0, 0.0, 0.75)
	var lamp := _prop("WorkLamp", c + Vector3(-4.2, 0.0, 3.6), 120.0)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.85, 0.6)
	ll.light_energy = 1.3
	ll.omni_range = 6.0
	ll.position = Vector3(0.0, 1.7, 0.2)
	lamp.add_child(ll)
	_add_interact(_medkit_at + Vector3(0.0, 1.0, 0.0), "Use the field med kit", _use_med_kit)
	var crate := _prop("SupplyCrate", c + Vector3(1.6, 0.0, -3.4), -20.0, Vector3(1.0, 0.7, 0.7), 0.8)
	_readable("Datapad", crate.global_transform * Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.0, 0.562, 0.0)), "pathfinder_log")
	_prop("SupplyCrate", c + Vector3(2.8, 0.0, -2.6), 35.0, Vector3(1.0, 0.7, 0.7), 0.7)
	_prop("Radio", c + Vector3(2.8, 0.49, -2.6), 35.0)
	# Cold fire: a ring of stones round the ashes.
	var fire := c + Vector3(1.5, 0.0, 2.5)
	var stones := WK.meshes(["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3"])
	if not stones.is_empty():
		var b := {}
		for i in 10:
			var a := TAU * i / 10.0
			var p := fire + Vector3(cos(a) * 0.75, 0.0, sin(a) * 0.75)
			p.y = _ground(p) - 0.02
			WK.add_instance(b, stones[i % stones.size()], p, rng.randf_range(1.6, 2.2), rng)
		WK.plant(self, b, 80.0)
	var log_mesh := WK.model_mesh("FallenLog")
	if log_mesh != null:
		for spec in [[Vector3(-0.2, 0.0, 1.6), 70.0], [Vector3(3.4, 0.0, 3.0), -20.0]]:
			var lp: Vector3 = fire + spec[0]
			var lg := MeshInstance3D.new()
			lg.mesh = log_mesh
			lg.position = Vector3(lp.x, _ground(lp) - 0.1, lp.z)
			lg.rotation = Vector3(0.0, deg_to_rad(spec[1]), 0.0)
			lg.scale = Vector3.ONE * 0.6
			add_child(lg)
	_scatter(["Fern_1", "Grass_Wispy_Tall", "Bush_Common"], c, 7.0, 12.0, 40, 0.7, 1.3, 41)
	_sign("WAYPOINT CAMP", c + Vector3(0.0, _ground(c) + 4.5, 0.0), Color(1.0, 0.7, 0.4))


## Her unit's three med caches, each by a pathfinder beacon.
const CACHE_LINES := [
	"Still sealed. Still yours.\nYou check the vials by habit: half of them cracked in the cold.",
	"Wedged under the platform where you left it, crystal light all over the lid.\nSomething's been scratching at the case.",
	"Right where the sergeant said it would be safe.\nThe stream's risen. The case is wet, but the seals held.",
]

func _build_caches() -> void:
	var aft_xf: Transform3D = get_meta("aft_xf", Transform3D.IDENTITY)
	var spots := [
		aft_xf * Vector3(1.3, -1.6, -3.6),
		DAIS + Vector3(1.6, _ground(DAIS) + 1.07, 1.0),
		_on_ground(LANDER.x + 3.0, LANDER.z - 4.0),
	]
	var beacons := [aft_xf * Vector3(-2.0, -1.6, 1.5), DAIS + Vector3(-2.4, 0.0, -6.3), Vector3(LANDER.x + 5.5, 0.0, LANDER.z - 2.0)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var root := Node3D.new()
		root.position = p
		root.rotation.y = rng.randf_range(-0.6, 0.6)
		add_child(root)
		var body := MeshInstance3D.new()
		body.mesh = _kit_mesh("MedCase")
		root.add_child(body)
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, 0.36, -0.31)
		root.add_child(hinge)
		var lid := MeshInstance3D.new()
		lid.mesh = _kit_mesh("MedCaseLid")
		hinge.add_child(lid)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.2)
		light.light_energy = 0.6
		light.omni_range = 2.0
		light.position = Vector3(0.0, 0.7, 0.4)
		root.add_child(light)
		var col := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 0.5, 0.62)
		cs.shape = box
		cs.position.y = 0.25
		col.add_child(cs)
		root.add_child(col)
		_beacon(beacons[i], i * 0.5)
		var opened: bool = GS.flags.get("reach_cache_%d" % i, false)
		var it = _add_interact(p + Vector3(0.0, 0.6, 0.0), "Open your unit's med cache", _open_cache.bind(i), 2.4)
		var entry := {"pos": p, "hinge": hinge, "it": it, "light": light, "opened": opened}
		_caches.append(entry)
		if opened:
			hinge.rotation.x = -1.9
			it.enabled = false
			light.light_color = Color(0.4, 1.0, 0.5)


func _open_cache(i: int) -> void:
	var c: Dictionary = _caches[i]
	if c["opened"]:
		return
	if GS.active_member != "survivor":
		_show_banner("A Coalition med cache, locked with a pathfinder code.\nShe'd know it.", 3.0)
		return
	c["opened"] = true
	GS.flags["reach_cache_%d" % i] = true
	(c["it"] as Node).set("enabled", false)
	var tw := create_tween()
	tw.tween_property(c["hinge"], "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK)
	(c["light"] as OmniLight3D).light_color = Color(0.4, 1.0, 0.5)
	Sfx.ui("crate_open", -4.0, 0.05)
	GS.add_item("medpack", 1)
	GS.add_xp(5)
	_show_banner(CACHE_LINES[i], 5.0)


## Field med kit: cooks glowcaps into coagulant, and studies tissue samples.
func _use_med_kit() -> void:
	if GS.active_member != "survivor":
		_show_banner("A Coalition field med kit: burner, mortar, sample scanner.\nEvery label is in her shorthand.", 3.5)
		return
	var stage := int(GS.flags.get("med_stage", -1))
	if GS.med_active() and stage == 2 and not GS.goal_done("analysed_tissue"):
		if GS.count("tissue") >= 3:
			GS.remove_item("tissue", 3)
			GS.flags["analysed_tissue"] = true
			GS.add_xp(10)
			GS.changed()
			_show_banner("Under the lamp the sample curls away from the light, hours after the creature died.\nThe anticoagulant's there. So is something else: crystal threads grown through the muscle\nin neat, even rows. Nothing grows that neatly on its own.", 9.0)
			return
		GS.toast("You need 3 tissue samples to study (you have %d)." % GS.count("tissue"))
	if GS.count("glowcap") >= 4:
		var first: bool = not GS.flags.get("crafted:coagulant", false)
		GS.remove_item("glowcap", 4)
		GS.add_item("coagulant", 2)
		GS.flags["crafted:coagulant"] = true
		GS.add_xp(4)
		GS.changed()
		if first:
			_show_banner("You crush the glowcaps and cook the sap down over the burner.\nIt sets like resin. It'll hold a wound closed.", 5.0)
		return
	if stage != 2:
		_show_banner("Field med kit: burner, mortar, sample scanner.\nFour glowcaps make two doses of coagulant (you have %d)." % GS.count("glowcap"), 4.0)


# ---------------------------------------------------------------- nature

func _clear(p: Vector3, pad: float) -> bool:
	var q := Vector2(p.x, p.z)
	var rv := _river_d(p.x, p.z)
	if rv.x < rv.y + 2.5 + pad:
		return true
	for pool in POOLS:
		if q.distance_to(Vector2(river_x(pool[0]), pool[0])) < float(pool[1]) + 3.0 + pad:
			return true
	if WorldMap.reach_lead_dist(p.x, p.z) < 4.0 + pad or _path_dist(p.x, p.z) < 2.5 + pad:
		return true
	for spec in [[CAMP, 11.0], [Vector3(-59.0, 0.0, -50.0), 14.0], [Vector3(-2.0, 0.0, -70.0), 13.0], [DAIS, 20.0], [LANDER, 11.0]]:
		var c: Vector3 = spec[0]
		if q.distance_to(Vector2(c.x, c.z)) < float(spec[1]) + pad:
			return true
	# The debris corridor between the freighter halves.
	if _seg_dist(q, Vector2(-56.0, -52.0), Vector2(-6.0, -70.0)) < 9.0 + pad:
		return true
	return false


func _build_forest() -> void:
	var pines := WK.meshes(WK.PINES)
	if pines.is_empty():
		return
	var leafy := WK.meshes(WK.LEAFY)
	var dead := WK.meshes(WK.DEAD)
	var buckets := {}
	var tries := 0
	var placed := 0
	while placed < 1400 and tries < 16000:
		tries += 1
		var p := Vector3(rng.randf_range(-170.0, 170.0), 0.0, rng.randf_range(-170.0, 170.0))
		if _clear(p, 1.0):
			continue
		var out := maxf(absf(p.x) - 110.0, absf(p.z) - 80.0)
		# Open ground in the middle has groves; the woods close in at the edges.
		if out < -10.0 and _noise_hill.get_noise_2d(p.x * 4.0, p.z * 4.0) < 0.1:
			continue
		p.y = _ground(p) - 0.15
		var roll := rng.randf()
		var mesh: Mesh = pines[rng.randi() % pines.size()]
		if roll < 0.12 and not dead.is_empty():
			mesh = dead[rng.randi() % dead.size()]   # more dead wood out here
		elif roll < 0.4 and not leafy.is_empty():
			mesh = leafy[rng.randi() % leafy.size()]
		var s := rng.randf_range(1.5, 2.4)
		WK.add_instance(buckets, mesh, p, s, rng)
		if RECT.grow(4.0).has_point(Vector2(p.x, p.z)):
			WK.trunk_collider(self, p, s)
		placed += 1
	WK.plant(self, buckets, 280.0)

	var small_names := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1_Big", "Mushroom_Common", "Rock_Medium_1", "Rock_Medium_2", "Grass_Wispy_Tall"]
	var scales := [Vector2(0.9, 1.5), Vector2(0.9, 1.4), Vector2(0.15, 0.25), Vector2(0.6, 1.0), Vector2(0.8, 1.3), Vector2(0.5, 1.1), Vector2(0.5, 1.1), Vector2(0.8, 1.4)]
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
	for i in 1300:
		var p := Vector3(rng.randf_range(RECT.position.x, RECT.end.x), 0.0, rng.randf_range(RECT.position.y, RECT.end.y))
		var rv := _river_d(p.x, p.z)
		if rv.x < rv.y + 1.5 or WorldMap.reach_lead_dist(p.x, p.z) < 2.5 or _path_dist(p.x, p.z) < 1.5:
			continue
		if Vector2(p.x - CAMP.x, p.z - CAMP.z).length() < 6.0:
			continue
		p.y = _ground(p) - 0.05
		var k := rng.randi() % small.size()
		var sc: Vector2 = small_scales[k]
		WK.add_instance(sb, small[k], p, rng.randf_range(sc.x, sc.y), rng)
	WK.plant(self, sb, 120.0)


## Reeds and ferns on the banks, pebbles on the river bed, and a few fallen
## logs across the shallows.
func _build_river_life() -> void:
	var reeds := WK.meshes(["Grass_Wispy_Tall", "Grass_Common_Tall", "Plant_7_Big", "Fern_1"])
	var pebbles := WK.meshes(["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_2"])
	var rb := {}
	var pb := {}
	var r := RandomNumberGenerator.new()
	r.seed = 33
	for i in 900:
		var on_trib := r.randf() < 0.35
		var p := Vector3.ZERO
		var hw := 0.0
		var nrm := Vector2.ZERO
		if on_trib:
			var x := r.randf_range(river_x(40.0) + 6.0, 140.0)
			p = Vector3(x, 0.0, trib_z(x))
			hw = TRIB_HW
			nrm = Vector2(-8.0 * 0.035 * cos(x * 0.035), 1.0).normalized()
		else:
			var z := r.randf_range(-130.0, 130.0)
			p = Vector3(river_x(z), 0.0, z)
			hw = river_hw(z)
			nrm = Vector2(1.0, -river_slope(z)).normalized()
		var side := 1.0 if r.randf() < 0.5 else -1.0
		if r.randf() < 0.55:
			# On the bank.
			var off := hw + r.randf_range(0.5, 3.5)
			var q := p + Vector3(nrm.x, 0.0, nrm.y) * off * side
			q.y = _ground(q) - 0.05
			if not reeds.is_empty():
				WK.add_instance(rb, reeds[r.randi() % reeds.size()], q, r.randf_range(0.8, 1.6), r)
		else:
			# On the bed, under the water.
			var q2 := p + Vector3(nrm.x, 0.0, nrm.y) * r.randf_range(0.0, hw * 0.95) * side
			q2.y = _ground(q2) - 0.03
			if not pebbles.is_empty():
				WK.add_instance(pb, pebbles[r.randi() % pebbles.size()], q2, r.randf_range(1.0, 3.2), r)
	WK.plant(self, rb, 110.0)
	WK.plant(self, pb, 70.0)
	var log_mesh := WK.model_mesh("FallenLog")
	if log_mesh != null:
		for z in [-28.0, 22.0, 58.0]:
			var p := Vector3(river_x(z), 0.0, z)
			var lg := MeshInstance3D.new()
			lg.mesh = log_mesh
			lg.position = Vector3(p.x + r.randf_range(-2.0, 2.0), WATER_Y - 0.15, p.z)
			lg.rotation = Vector3(0.0, atan2(1.0, -river_slope(z)) + r.randf_range(-0.3, 0.3), deg_to_rad(r.randf_range(-4.0, 4.0)))
			lg.scale = Vector3.ONE * 1.4
			add_child(lg)


## Glowcaps on the damp banks (they come back every visit), plus fibre.
func _build_pickups() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 61
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 400:
		tries += 1
		var p := Vector3.ZERO
		var hw := 0.0
		var nrm := Vector2.ZERO
		if r.randf() < 0.35:
			var x := r.randf_range(river_x(40.0) + 8.0, 105.0)
			p = Vector3(x, 0.0, trib_z(x))
			hw = TRIB_HW
			nrm = Vector2(-8.0 * 0.035 * cos(x * 0.035), 1.0).normalized()
		else:
			var z := r.randf_range(-75.0, 75.0)
			p = Vector3(river_x(z), 0.0, z)
			hw = river_hw(z)
			nrm = Vector2(1.0, -river_slope(z)).normalized()
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var q := p + Vector3(nrm.x, 0.0, nrm.y) * (hw + r.randf_range(1.5, 3.0)) * side
		q.y = _ground(q)
		if q.y < WATER_Y + 0.08 or not RECT.grow(-8.0).has_point(Vector2(q.x, q.z)):
			continue
		Pickup.spawn(self, "resource", "glowcap", q, Vector2i(1, 2))
		placed += 1
	for v in [Vector3(-90.0, 0.0, 22.0), Vector3(-66.0, 0.0, 26.0), Vector3(30.0, 0.0, 20.0), Vector3(90.0, 0.0, 40.0), Vector3(-30.0, 0.0, 40.0)]:
		Pickup.spawn(self, "resource", "fiber", _on_ground(v.x, v.z), Vector2i(1, 3))


## Cargo pods that came down in the river with the freighter. They sank in
## the deep pools: dive for them (each opens once).
const SUNKEN_LOOT := [
	{"heavy_cell": 2, "crystal": 2, "tech": 3, "mod_cooling": 1},
	{"fuel": 2, "ore": 3, "tech": 2, "stun_grenade": 2, "mod_loader": 1},
]

func _build_sunken_pods() -> void:
	for i in POOLS.size():
		var z: float = POOLS[i][0]
		var c := Vector3(river_x(z) + 1.2, 0.0, z - 0.8)
		c.y = _ground(c) + 0.05
		var b := Basis(Vector3.UP, 0.7 + i * 1.9) * Basis(Vector3(0, 0, 1), deg_to_rad(9.0))
		_model("CargoPod", Transform3D(b, c), true)
		var light := OmniLight3D.new()
		light.light_color = Color(0.3, 0.9, 1.0)
		light.light_energy = 0.0 if GS.flags.get("reach_sunk_%d" % i, false) else 1.2
		light.omni_range = 4.0
		light.position = c + Vector3(0.0, 1.6, 0.0)
		add_child(light)
		var it = _add_interact(c + Vector3(0.0, 1.0, 0.0), "Pry open the sunken cargo pod", _open_sunken.bind(i, light), 3.0)
		_sunk_its.append(it)
		if GS.flags.get("reach_sunk_%d" % i, false):
			it.enabled = false
		MapPoi.add(self, c, "Deep Pool", "landmark", "Swim out and dive: something big sank here.")


func _open_sunken(i: int, light: OmniLight3D) -> void:
	if GS.flags.get("reach_sunk_%d" % i, false):
		return
	GS.flags["reach_sunk_%d" % i] = true
	light.light_energy = 0.0
	var got := []
	for id in SUNKEN_LOOT[i]:
		GS.add_item(id, SUNKEN_LOOT[i][id])
		got.append("%s x%d" % [String(Items.ITEMS.get(id, {}).get("name", id)), SUNKEN_LOOT[i][id]])
	GS.add_xp(10)
	GS.changed()
	Sfx.ui("crate_open", -4.0, 0.05)
	_show_banner("SUNKEN CARGO POD\n" + ", ".join(got), 5.0)
	if _sunk_its.size() > i:
		_sunk_its[i].enabled = false


# ---------------------------------------------------------------- exits + map

## The west trail's end: back to Base Camp (world_map.gd REACH_LEAD).
func _build_exit() -> void:
	var x := float(WorldMap.REACH_LEAD["x0"]) + 6.0
	_exit_at = _on_ground(x, WorldMap.reach_lead_z(x))
	_rocks(_exit_at, [[Vector3(-0.6, 0.0, -4.2), 0.8], [Vector3(0.4, 0.0, 4.4), 0.75], [Vector3(-2.4, 0.0, -5.6), 0.55], [Vector3(-2.0, 0.0, 5.8), 0.5]], 34)
	_beacon(_exit_at + Vector3(1.0, 0.0, 2.6), 0.8)
	_add_interact(_exit_at + Vector3(0.0, 1.0, 0.0), "Head west to Base Camp", func():
		GS.flags["came_from"] = SELF
		get_tree().change_scene_to_file(BASE))
	# East: the gap in the hills into Spire Canyon.
	_east_at = _on_ground(EAST_EXIT.x, EAST_EXIT.z)
	_rocks(_east_at, [[Vector3(0.6, 0.0, -4.4), 0.85], [Vector3(-0.4, 0.0, 4.6), 0.8], [Vector3(2.2, 0.0, -6.0), 0.6]], 35)
	_beacon(_east_at + Vector3(-1.0, 0.0, 2.6), 0.8)
	_add_interact(_east_at + Vector3(0.0, 1.0, 0.0), "Go east into Spire Canyon", func():
		GS.flags["came_from"] = SELF
		get_tree().change_scene_to_file(CANYON))


func _build_map_points() -> void:
	MapPoi.add(self, CAMP, "Waypoint Camp", "camp",
			"Her pathfinder unit's last camp before the ambush: a collapsed lean-to, a cold fire and a field med kit for cooking coagulant and studying samples.")
	MapPoi.add(self, _exit_at, "Trail to Base Camp", "exit", "The trail west, back over the hills to Base Camp.")
	MapPoi.add(self, _east_at, "Way to Spire Canyon", "exit", "A gap in the eastern hills. Beyond it the ground drops into a deep canyon full of waterfalls.")
	MapPoi.add(self, Vector3(-30.0, 0.0, -60.0), "Orla's Promise", "landmark",
			"A bulk hauler that broke in two on the way down. The nose lies west of the river, the engines east. You can walk into both halves.")
	MapPoi.add(self, DAIS, "Vaari Ruins", "danger",
			"Hand-cut stone round a stepped platform with a crystal heart. Old, and not human. Creatures nest here.")
	MapPoi.add(self, DAIS + Vector3(-9.0, 0.0, 9.0), "Ore & crystal", "resource",
			"Ore veins and spire crystal round the Vaari ruins. Mine them with a pick (E).")
	MapPoi.add(self, LANDER, "Survey Lander K7-2", "landmark",
			"A K-7 survey lander nose-down beyond the southern stream.")
	MapPoi.add(self, Vector3(river_x(0.0), 0.0, 0.0), "The River", "landmark",
			"Shallow enough to wade almost anywhere: the water comes up to your waist at most and slows you down. Glowcaps grow on the banks.")


func _quest_target():
	var q := GS.current_quest()
	if q.is_empty():
		return null
	if not GS.med_active():
		if GS.strider_active() and not GS.drone_active():
			for g in q["goals"]:
				if GS.goal_done(g[0]):
					continue
				return _exit_at if String(g[0]).begins_with("crafted:") else _east_at
		if GS.drone_active():
			for g in q["goals"]:
				if GS.goal_done(g[0]):
					continue
				if g[0] in ["found_drone", "drone_installed"] and _drone_at != Vector3.ZERO:
					return _drone_at
				return _exit_at
		return _exit_at   # the camp missions happen back at Base Camp
	for g in q["goals"]:
		var id := String(g[0])
		if GS.goal_done(id):
			continue
		match id:
			"reach_waypoint":
				return Vector3(CAMP.x, _ground(CAMP), CAMP.z)
			"have:medpack:3":
				return _nearest_cache()
			"have:glowcap:4":
				return _nearest_pickup("glowcap")
			"crafted:coagulant", "analysed_tissue":
				return _medkit_at
			"have:tissue:3":
				var t = _nearest_pickup("tissue")
				return t if t != null else _nearest_enemy()
			"treated_trooper":
				return _exit_at
		return null
	return null


func _nearest_cache():
	var best = null
	var bd := INF
	for c in _caches:
		if c["opened"]:
			continue
		var d: float = player.global_position.distance_squared_to(c["pos"])
		if d < bd:
			bd = d
			best = c["pos"]
	return best


func _nearest_pickup(id: String):
	var best = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if not ("item_id" in n) or n.item_id != id or not n.enabled:
			continue
		var d: float = player.global_position.distance_squared_to(n.global_position)
		if d < bd:
			bd = d
			best = n.global_position
	return best


func _nearest_enemy():
	var best = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: float = player.global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = e.global_position
	return best


# ---------------------------------------------------------------- creatures

## Every pack comes back each time the area loads.
func _spawn_packs() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	for pack in PACKS:
		var c: Vector3 = pack[0]
		for i in int(pack[1]):
			var p := c + Vector3(r.randf_range(-4.0, 4.0), 0.0, r.randf_range(-4.0, 4.0))
			if p.distance_to(player.global_position) < 30.0:
				continue
			p.y = maxf(_ground(p), WATER_Y) + 0.4
			var e = EnemyScript.new()
			e.dormant = true
			e.position = p
			e.rotation.y = r.randf() * TAU
			e.target = player
			add_child(e)
			e.died.connect(_on_enemy_died.bind(e))


func _on_enemy_died(e) -> void:
	# While she's after tissue samples, every body gives one.
	if not is_instance_valid(e) or not GS.med_active() or int(GS.flags.get("med_stage", -1)) != 2:
		return
	var p: Vector3 = e.global_position + Vector3(0.6, 0.0, 0.0)
	p.y = _ground(p) + 0.05
	_drop_tissue.call_deferred(p)


func _drop_tissue(p: Vector3) -> void:
	Pickup.spawn(self, "resource", "tissue", p, Vector2i(1, 1))


## A fall here brings you round at the waypoint camp; the area reloads, so
## the creatures are back too.
func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true
	await get_tree().create_timer(1.6).timeout
	await _fade_to(1.0, 0.6)
	GS.flags["reach_spawn"] = "camp"
	GS.save()
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var hint := UI.label("WASD move  ·  E interact  ·  C crouch  ·  Z prone  ·  Tab inventory  ·  H heal  ·  R reload  ·  Esc menu", 16, UI.MUTED)
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
	_banner = UI.label("", 30, UI.TEXT)
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.2
	_banner.anchor_bottom = 0.2
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)


func _show_banner(text: String, duration: float) -> void:
	if _banner == null:
		return
	_banner.text = text
	if _banner_tw != null:
		_banner_tw.kill()
	var tw := create_tween()
	_banner_tw = tw
	tw.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(duration)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.8)


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
