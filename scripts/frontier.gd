extends Node3D
## Shared base for the Spire Canyon country (the canyon hub and the five
## areas off it). Each area script extends this and fills in:
##   AREA vars set in _setup(): scene path, name, RECT, terrain size, look
##   _h(x, z)            terrain height
##   _paint_at(data,x,z) optional terrain painting
##   _build_area()       the landmarks, caves, loot, creatures and exits
##   _entry(from)        [position, yaw] for arriving from scene `from`
## This base builds the sky and light, terrain, edge walls, the player (and
## the droid once it's rebuilt), menus, the quest marker, a banner, deaths
## (you come round at the last entrance and the area reloads), and gives
## helpers for exits, rock architecture, creature packs, guardians, loot
## caches, ore, crystal, readable logs, waterfalls and map points.

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
const Rock = preload("res://scripts/rockgen.gd")
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]
const PROPS_GLB := "res://models/camp_props.glb"
const KIT := "res://models/canyon_kit.glb"

# ---- set by each area in _setup()
var area_scene := ""
var area_name := ""
var area_blurb := ""
var rect := Rect2(-100.0, -100.0, 200.0, 200.0)
var terrain_size := 256
var water_y := -INF
var look := {
	"sky_top": Color(0.25, 0.33, 0.43), "sky_horizon": Color(0.68, 0.62, 0.52),
	"ground": Color(0.2, 0.2, 0.17), "fog": Color(0.56, 0.58, 0.54), "fog_density": 0.011,
	"sun": Color(1.0, 0.88, 0.74), "sun_energy": 1.05, "sun_rot": Vector3(-36.0, 125.0, 0.0),
	"ambient": 0.6, "ambient_loop": "forest_loop",
}
var tree_names: Array = WK.PINES

var terrain
var player
var droid
var menu
var overlay
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var _kit: Node3D
var _props: Node3D
var _ui: CanvasLayer
var _banner: Label
var _banner_tw: Tween
var _fade: ColorRect
var _respawning := false
var _exits := {}            # scene -> Vector3 (where its exit prompt is)
var _clear_spots: Array = []  # [Vector3, radius]: keep trees off these
var _packs: Array = []        # [centre, count, elite_chance]
var _waterfalls: Array = []


func _setup() -> void:
	pass


func _h(_x: float, _z: float) -> float:
	return 0.0


func _paint_at(_data, _x: float, _z: float) -> void:
	pass


func _build_area() -> void:
	pass


## [position, yaw] for arriving from `from` (default: first exit, facing in).
func _entry(_from: String) -> Array:
	return [Vector3.ZERO, 0.0]


func _ready() -> void:
	rng.seed = hash(area_scene)
	noise.seed = 71
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	noise2.seed = 73
	noise2.frequency = 0.06
	noise2.fractal_octaves = 3
	_setup()
	GS.ensure_loaded()
	GS.horde_mode = false
	if ResourceLoader.exists(KIT):
		_kit = load(KIT).instantiate()
	if ResourceLoader.exists(PROPS_GLB):
		_props = load(PROPS_GLB).instantiate()
	_build_environment()
	terrain = WK.build_terrain(self, terrain_size, _h, _paint_at, terrain_size / 2)
	if terrain == null:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(terrain_size, 1.0, terrain_size)
		cs.shape = box
		cs.position.y = -0.5
		body.add_child(cs)
		add_child(body)
	if water_y > -1000.0:
		_build_water()
	_build_walls()
	if GS.menu_preview:
		_build_area()
		return
	GS.enter_area(area_scene)
	var from: String = GS.flags.get("came_from", "")
	var respawn: bool = GS.flags.get("frontier_respawn", "") == area_scene
	GS.flags.erase("frontier_respawn")
	if respawn:
		from = GS.flags.get("frontier_last_from", from)
	GS.flags["frontier_last_from"] = from
	var e := _entry(from)
	var start: Vector3 = e[0]
	start.y = _ground(start) + 0.15
	var yaw: float = e[1]
	player = PlayerScript.new()
	player.name = "Player"
	if GS.active_member == "survivor":
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
	if water_y > -1000.0:
		var wy := water_y
		player.water_at = func(_p: Vector3) -> float: return wy
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
	_build_area()
	_plant_trees()
	_spawn_packs()
	Sfx.loop(self, String(look.get("ambient_loop", "forest_loop")), -17.0, 6.0, false)
	if respawn:
		_show_banner("You come round where you came in.", 3.0)
	else:
		var key := "seen:" + area_scene
		_show_banner(area_name.to_upper() + ("\n" + area_blurb if area_blurb != "" and not GS.flags.get(key, false) else ""), 6.0 if not GS.flags.get(key, false) else 3.0)
		GS.flags[key] = true
	GS.check_quests()
	GS.changed()


func _exit_tree() -> void:
	if _kit != null:
		_kit.free()
	if _props != null:
		_props.free()


func _unhandled_input(event) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_tree().paused or droid == null or not is_instance_valid(droid):
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


# ---------------------------------------------------------------- ground

func _ground(p: Vector3) -> float:
	return WK.ground_y(terrain, p, _h(p.x, p.z))


func _on_ground(x: float, z: float, lift := 0.0) -> Vector3:
	var p := Vector3(x, 0.0, z)
	p.y = _ground(p) + lift
	return p


## 0 inside, rising to 1 over `soft` metres outside a circle.
static func disc(x: float, z: float, c: Vector3, r: float, soft: float) -> float:
	var d := Vector2(x - c.x, z - c.z).length()
	return 1.0 - smoothstep(r, r + soft, d)


## Distance from (x, z) to a polyline of Vector3s (in XZ).
static func line_dist(x: float, z: float, pts: Array) -> float:
	var best := INF
	var p := Vector2(x, z)
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = look["sky_top"]
	sky_mat.sky_horizon_color = look["sky_horizon"]
	sky_mat.ground_horizon_color = (look["ground"] as Color).lightened(0.2)
	sky_mat.ground_bottom_color = look["ground"]
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = look["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = look["fog"]
	env.fog_density = look["fog_density"]
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = look["sun_rot"]
	sun.light_energy = look["sun_energy"]
	sun.light_color = look["sun"]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _build_walls() -> void:
	var c := rect.get_center()
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(2.0, 300.0, rect.size.y + 10.0) if d.x != 0.0 else Vector3(rect.size.x + 10.0, 300.0, 2.0)
		cs.shape = b
		wall.add_child(cs)
		var half := rect.size.x * 0.5 if d.x != 0.0 else rect.size.y * 0.5
		wall.position = Vector3(c.x, 60.0, c.y) + d * half
		add_child(wall)


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


## A soft round dot (for snow, fireflies and other small particles).
func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


## One water surface at water_y over the whole area (Shipfall Reach's shader).
func _water_material(shallow := Color(0.16, 0.36, 0.3), deep := Color(0.03, 0.1, 0.1)) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = load("res://scripts/reach.gd").WATER_SHADER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wm.set_shader_parameter("normal_a", _noise_tex(512, 0.014, 71, true, 5.0))
	wm.set_shader_parameter("normal_b", _noise_tex(512, 0.035, 73, true, 3.0))
	wm.set_shader_parameter("foam_tex", _noise_tex(256, 0.05, 77, false, 0.0))
	wm.set_shader_parameter("shallow_col", shallow)
	wm.set_shader_parameter("deep_col", deep)
	return wm


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain_size, terrain_size)
	plane.subdivide_width = 120
	plane.subdivide_depth = 120
	water.mesh = plane
	water.material_override = _water_material(look.get("water_shallow", Color(0.16, 0.36, 0.3)), look.get("water_deep", Color(0.03, 0.1, 0.1)))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0.0, water_y, 0.0)
	add_child(water)


## A waterfall: a sheet of falling water from `top` down to `bottom`, `width`
## wide, facing `facing` (world yaw), with mist and the roar of it.
const FALL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;
uniform sampler2D streaks : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.75, 0.88, 0.92);
void fragment() {
	float s1 = texture(streaks, vec2(UV.x * 2.0, UV.y * 0.6 - TIME * 1.6)).r;
	float s2 = texture(streaks, vec2(UV.x * 3.3 + 0.4, UV.y * 0.9 - TIME * 2.3)).r;
	float s = smoothstep(0.35, 0.8, s1 * 0.6 + s2 * 0.6);
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	ALBEDO = mix(tint * 0.6, vec3(0.95, 0.98, 1.0), s);
	ALPHA = (0.45 + 0.5 * s) * edge * smoothstep(0.0, 0.05, UV.y);
}
"""

func waterfall(top: Vector3, bottom: Vector3, width: float, facing: float) -> void:
	var h := top.y - bottom.y
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width, h)
	mi.mesh = qm
	var sh := Shader.new()
	sh.code = FALL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("streaks", _noise_tex(256, 0.08, 91, false, 0.0))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(top.x, (top.y + bottom.y) * 0.5, top.z)
	mi.rotation.y = facing
	mi.rotation.x = -0.05
	add_child(mi)
	# Mist where it lands.
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.3, 1.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -0.6, 0)
	pm.scale_min = 1.5
	pm.scale_max = 3.5
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.albedo_color = Color(0.9, 0.95, 1.0, 0.12)
	mm.albedo_texture = _noise_tex(64, 0.1, 93, false, 0.0)
	quad.material = mm
	p.draw_pass_1 = quad
	p.amount = 40
	p.lifetime = 2.5
	p.position = Vector3(bottom.x, bottom.y + 0.3, bottom.z)
	p.rotation.y = facing
	add_child(p)
	var snd := Node3D.new()
	snd.position = bottom
	add_child(snd)
	Sfx.loop(snd, "river_loop", -4.0, 18.0, true)


# ---------------------------------------------------------------- props

func kit_mesh(n: String) -> Mesh:
	if _kit == null:
		return null
	var src := _kit.find_child(n, true, false) as MeshInstance3D
	return src.mesh if src != null else null


## A canyon_kit.glb model at `xf`, optionally with exact collision.
func model(n: String, xf: Transform3D, collide := true) -> Node3D:
	var mesh := kit_mesh(n)
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


## A model from another kit .glb (e.g. reach_kit.glb's wrecks), like model().
static var _other_kits := {}

func model_from(glb: String, n: String, xf: Transform3D, collide := true) -> Node3D:
	if not _other_kits.has(glb):
		var meshes := {}
		if ResourceLoader.exists(glb):
			var inst: Node3D = load(glb).instantiate()
			for c in inst.find_children("*", "MeshInstance3D", true, false):
				meshes[String(c.name)] = (c as MeshInstance3D).mesh
			inst.free()
		_other_kits[glb] = meshes
	var mesh: Mesh = _other_kits[glb].get(n)
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


func prop(n: String, pos: Vector3, yaw_deg: float, solid := Vector3.ZERO, s := 1.0) -> StaticBody3D:
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


func add_interact(pos: Vector3, prompt: String, action: Callable, reach := 2.6):
	var n = Interactable.new()
	n.prompt = prompt
	n.action = action
	n.reach = reach
	n.position = pos
	add_child(n)
	return n


## A readable log (datapad prop) lying at `pos` (on the ground unless lift).
func readable(pos: Vector3, id: String, kind := "Datapad", lift := -1.0) -> void:
	var pad := Node3D.new()
	add_child(pad)
	pad.position = Vector3(pos.x, (_ground(pos) + 0.05) if lift < 0.0 else lift, pos.z)
	pad.rotation.y = rng.randf() * TAU
	if _props != null:
		var src := _props.find_child(kind, true, false) as Node3D
		if src != null:
			var m := src.duplicate() as Node3D
			m.transform = Transform3D.IDENTITY
			pad.add_child(m)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.4, 0.8, 1.0)
	glow.light_energy = 0.6
	glow.omni_range = 1.6
	glow.position.y = 0.3
	pad.add_child(glow)
	var it = Interactable.new()
	it.prompt = "Read: %s" % String(Lore.entry(id).get("title", "log"))
	it.reach = 2.2
	it.action = func(): LorePanel.read(get_tree(), id)
	pad.add_child(it)


## A demo rock (A/B/C) at `pos`, scale `s`, sunk a little into the ground.
func rock(pos: Vector3, s: float, sink := 0.4, collide := true) -> Node3D:
	var path: String = ROCK_SCENES[rng.randi() % ROCK_SCENES.size()]
	if not ResourceLoader.exists(path):
		return null
	var r: Node3D = load(path).instantiate()
	r.scale = Vector3.ONE * s * rng.randf_range(0.9, 1.1)
	r.rotation = Vector3(0.0, rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
	r.position = Vector3(pos.x, (pos.y if pos.y != 0.0 else _ground(pos)) - sink * s, pos.z)
	add_child(r)
	if not collide:
		for c in r.find_children("*", "CollisionShape3D", true, false):
			c.disabled = true
	_clear_spots.append([pos, 2.5 * s])
	return r


## A walkable rock ledge (flat top at `top`), `size` across.
func ledge(top: Vector3, size: Vector3, seed_v := 0.0, yaw := 0.0) -> Node3D:
	var m := Rock.block(size, seed_v, 0.12, true)
	var xf := Transform3D(Basis(Vector3.UP, yaw), top - Vector3(0.0, size.y, 0.0))
	_clear_spots.append([top, maxf(size.x, size.z) * 0.6])
	return Rock.place(self, m, xf)


## A big rock mass (pillar, spur, boulder) standing on the ground at `base`.
func crag(base: Vector3, size: Vector3, seed_v := 0.0, yaw := 0.0, rough := 0.2, dark := false) -> Node3D:
	var m := Rock.block(size, seed_v, rough, false)
	var p := Vector3(base.x, (base.y if base.y != 0.0 else _ground(base)) - 1.0, base.z)
	_clear_spots.append([base, maxf(size.x, size.z) * 0.6])
	return Rock.place(self, m, Transform3D(Basis(Vector3.UP, yaw), p), true, Rock.material(dark))


## A cave passage along `pts` (floor centre line, world coords).
func cave(pts: Array, radius := 3.2, seed_v := 0.0, glow := Color(0.35, 0.85, 1.0)) -> Node3D:
	var m := Rock.cave(pts, radius, seed_v)
	for p in pts:
		_clear_spots.append([p, radius + 4.0])
	var body := Rock.place(self, m, Transform3D.IDENTITY)
	# Crystal lamps along the way so the passage isn't pitch black.
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var mid := (a + b) * 0.5 + Vector3.UP * radius * 0.9
		var l := OmniLight3D.new()
		l.light_color = glow
		l.light_energy = 1.4
		l.omni_range = radius * 3.0
		l.position = mid
		add_child(l)
		crystal_cluster((a + b) * 0.5 + (b - a).cross(Vector3.UP).normalized() * radius * 0.8, 0.6, glow)
	return body


## A glowing crystal cluster (decoration; Shipfall Reach kit model if present).
func crystal_cluster(pos: Vector3, s := 1.0, col := Color(0.35, 0.85, 1.0)) -> void:
	var p := pos
	if p.y == 0.0:
		p.y = _ground(p)
	var mesh: Mesh = null
	if ResourceLoader.exists("res://models/reach_kit.glb"):
		var kit: Node3D = load("res://models/reach_kit.glb").instantiate()
		var src := kit.find_child("CrystalCluster", true, false) as MeshInstance3D
		if src != null:
			mesh = src.mesh
		kit.free()
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = Vector3.ONE * s
		mi.position = p
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.9
	l.omni_range = 3.5 * s + 1.0
	l.position = p + Vector3.UP * 0.8 * s
	add_child(l)


# ---------------------------------------------------------------- exits

## An exit: walk up and press E to travel to `scene`.
func exit_to(pos: Vector3, prompt: String, scene: String) -> void:
	var p := pos
	p.y = _ground(p)
	_exits[scene] = p
	_clear_spots.append([p, 6.0])
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.2)
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	lamp.position = p + Vector3.UP * 2.0
	add_child(lamp)
	add_interact(p + Vector3.UP, prompt, func():
		GS.flags["came_from"] = area_scene
		GS.save()
		get_tree().change_scene_to_file(scene))


## Moves the player (and the droid) to `pos` facing `yaw`, behind a fade.
## For going inside a building that's built away from the terrain.
func teleport(pos: Vector3, yaw: float, banner := "") -> void:
	await _fade_to(1.0, 0.4)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player._facing_yaw = yaw
	player.model.rotation.y = yaw
	player.cam_yaw.rotation.y = yaw
	if droid != null and is_instance_valid(droid):
		droid.global_position = pos + Basis(Vector3.UP, yaw) * Vector3(-1.5, 0.4, 2.0)
		droid.velocity = Vector3.ZERO
		droid.hold_pos = droid.global_position
	await get_tree().create_timer(0.25).timeout
	await _fade_to(0.0, 0.5)
	if banner != "":
		_show_banner(banner, 3.5)


# ---------------------------------------------------------------- loot

## A salvage cache (crate) that opens once and gives `loot` {item: n}.
func cache(pos: Vector3, key: String, loot: Dictionary, salvage := 0, prompt := "Open the supply cache") -> void:
	var opened: bool = GS.flags.get("cache:" + key, false)
	var body := prop("SupplyCrate", pos, rng.randf() * 360.0, Vector3(1.0, 0.7, 0.7))
	if pos.y != 0.0:
		body.position.y = pos.y
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 0.0 if opened else 0.9
	l.omni_range = 3.0
	l.position = Vector3(0.0, 1.2, 0.0)
	body.add_child(l)
	var it = add_interact(body.global_position + Vector3.UP * 0.9, prompt, func(): pass, 2.4)
	it.enabled = not opened
	it.action = func():
		if GS.flags.get("cache:" + key, false):
			return
		GS.flags["cache:" + key] = true
		it.enabled = false
		l.light_energy = 0.0
		var got := []
		for id in loot:
			GS.add_item(id, int(loot[id]))
			got.append("%s x%d" % [String(GS.item(id).get("name", id)), int(loot[id])])
		if salvage > 0:
			GS.add_salvage(salvage)
			got.append("%d salvage" % salvage)
		GS.add_xp(8)
		GS.changed()
		Sfx.ui("crate_open", -4.0, 0.05)
		_show_banner(", ".join(got), 4.0)


func ore_vein(pos: Vector3) -> void:
	var p := pos
	if p.y == 0.0:
		p.y = _ground(p)
	Pickup.spawn(self, "vein", "ore", p, Vector2i(3, 4))


func crystal(pos: Vector3) -> void:
	var p := pos
	if p.y == 0.0:
		p.y = _ground(p)
	Pickup.spawn(self, "crystal", "crystal", p, Vector2i(1, 2))


func resource(pos: Vector3, id: String, n := Vector2i(1, 2)) -> void:
	var p := pos
	if p.y == 0.0:
		p.y = _ground(p) + 0.05
	Pickup.spawn(self, "resource", id, p, n)


## One of the Strider's missing limbs (droid_parts.glb nodes `nodes`), lying
## at `pos`. Take it once `guard` (its guardian, or null) is dead.
func droid_part(pos: Vector3, id: String, nodes: Array, guard = null) -> void:
	if GS.flags.get("part:" + id, false) or GS.count(id) > 0 or GS.droid_online():
		return
	var p := pos
	if p.y == 0.0:
		p.y = _ground(p)
	var holder := Node3D.new()
	holder.position = p
	holder.rotation = Vector3(0.0, rng.randf() * TAU, 0.25)
	add_child(holder)
	if ResourceLoader.exists("res://models/droid_parts.glb"):
		var inst: Node3D = load("res://models/droid_parts.glb").instantiate()
		holder.add_child(inst)
		U.fit(inst, 1.5, 1, true)
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			if not (String(c.name) in nodes):
				(c as MeshInstance3D).visible = false
		inst.position.y -= 0.35
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 0.8, 1.0)
	l.light_energy = 1.6
	l.omni_range = 4.0
	l.position = Vector3.UP * 1.2
	holder.add_child(l)
	var nm := String(GS.item(id).get("name", id))
	var it = add_interact(p + Vector3.UP * 0.8, "Take: " + nm, func(): pass, 2.8)
	it.action = func():
		if guard != null and is_instance_valid(guard) and not guard._dead:
			_show_banner("Not with that thing still alive.", 2.5)
			guard.wake()
			return
		GS.add_item(id, 1)
		GS.flags["part:" + id] = true
		it.enabled = false
		holder.queue_free()
		Sfx.ui("crate_open", -4.0, 0.05)
		_show_banner("Recovered: " + nm, 3.5)
		GS.check_quests()
		GS.changed()
	_clear_spots.append([p, 4.0])


# ---------------------------------------------------------------- creatures

func pack(centre: Vector3, count: int, elite_chance := 0.12) -> void:
	_packs.append([centre, count, elite_chance])


func _spawn_packs() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	for pk in _packs:
		var c: Vector3 = pk[0]
		for i in int(pk[1]):
			var p := c + Vector3(r.randf_range(-4.0, 4.0), 0.0, r.randf_range(-4.0, 4.0))
			if player != null and p.distance_to(player.global_position) < 30.0:
				continue
			p.y = (c.y if c.y != 0.0 else _ground(p)) + 0.4
			if water_y > -1000.0:
				p.y = maxf(p.y, water_y + 0.4)
			var e = EnemyScript.new()
			e.dormant = true
			e.elite_chance = float(pk[2])
			e.position = p
			e.rotation.y = r.randf() * TAU
			e.target = player
			add_child(e)


## A guardian: a huge elite creature with its own glow colour and name,
## sitting on something worth guarding. Dies once for good (flag).
func guardian(pos: Vector3, key: String, title: String, col: Color, hp_mult := 4.0, mods := {}) -> Node:
	if GS.flags.get("guardian:" + key, false):
		return null
	var e = EnemyScript.new()
	e.dormant = true
	e.elite = true
	e.elite_chance = 0.0
	e.wake_range = 20.0
	e.position = Vector3(pos.x, (pos.y if pos.y != 0.0 else _ground(pos)) + 0.5, pos.z)
	e.target = player
	add_child(e)
	e.health *= hp_mult
	e.attack_damage *= 1.25
	e._visual.scale = Vector3.ONE * float(mods.get("scale", 1.75))
	e.speed *= float(mods.get("speed", 1.0))
	e.attack_damage *= float(mods.get("damage", 1.0))
	e.attack_cooldown *= float(mods.get("cooldown", 1.0))
	_grow_crystals(e, col)
	for l in e.find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).light_color = col
		(l as OmniLight3D).light_energy = 3.5
		(l as OmniLight3D).omni_range = 5.0
	var tag := Label3D.new()
	tag.text = title
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.006
	tag.modulate = col.lightened(0.3)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0.0, 4.6, 0.0)
	e.add_child(tag)
	e.died.connect(func():
		GS.flags["guardian:" + key] = true
		GS.add_salvage(60)
		GS.add_xp(60)
		GS.toast("%s is down  ·  +60 salvage" % title)
		GS.changed())
	return e


## Crystal growths along a guardian's spine and skull (they ride the bones).
func _grow_crystals(e, col: Color) -> void:
	if e._skel == null or not ResourceLoader.exists("res://models/reach_kit.glb"):
		return
	var kit: Node3D = load("res://models/reach_kit.glb").instantiate()
	var src := kit.find_child("CrystalCluster", true, false) as MeshInstance3D
	var mesh: Mesh = src.mesh if src != null else null
	kit.free()
	if mesh == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.1
	var spots := [["Hips", Vector3(0.0, 0.25, 0.0), 0.35], ["Spine", Vector3(0.0, 0.3, 0.05), 0.45], ["Chest", Vector3(0.0, 0.3, 0.0), 0.5],
		["Head", Vector3(0.0, 0.25, -0.05), 0.3]]
	for sp in spots:
		if e._skel.find_bone(sp[0]) < 0:
			continue
		var ba := BoneAttachment3D.new()
		ba.bone_name = sp[0]
		e._skel.add_child(ba)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.position = sp[1]
		mi.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
		mi.scale = Vector3.ONE * float(sp[2])
		ba.add_child(mi)


# ---------------------------------------------------------------- trees

## Scatters `tree_names` trees over the area, avoiding cleared spots, exits,
## steep ground and water. Override _tree_ok for area rules.
func _tree_ok(_p: Vector3) -> bool:
	return true


func _plant_trees(count := 700) -> void:
	if tree_names.is_empty():
		return
	var meshes := WK.meshes(tree_names)
	if meshes.is_empty():
		return
	var buckets := {}
	var placed := 0
	var tries := 0
	var area := rect.grow(40.0)
	while placed < count and tries < count * 12:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0.0, rng.randf_range(area.position.y, area.end.y))
		var bad := false
		for c in _clear_spots:
			if Vector2(p.x - c[0].x, p.z - c[0].z).length() < float(c[1]):
				bad = true
				break
		if bad or not _tree_ok(p):
			continue
		var h := _h(p.x, p.z)
		if water_y > -1000.0 and h < water_y + 0.2:
			continue
		var slope := absf(_h(p.x + 1.0, p.z) - _h(p.x - 1.0, p.z)) + absf(_h(p.x, p.z + 1.0) - _h(p.x, p.z - 1.0))
		if slope > 1.6:
			continue
		p.y = _ground(p) - 0.15
		var s := rng.randf_range(1.4, 2.3)
		WK.add_instance(buckets, meshes[rng.randi() % meshes.size()], p, s, rng)
		if rect.grow(2.0).has_point(Vector2(p.x, p.z)):
			WK.trunk_collider(self, p, s)
		placed += 1
	WK.plant(self, buckets, 260.0)


# ---------------------------------------------------------------- quests

func _quest_target():
	var q := GS.current_quest()
	if q.is_empty():
		return null
	for g in q["goals"]:
		var id := String(g[0])
		if GS.goal_done(id):
			continue
		var t = _goal_target(id)
		if t != null:
			return t
		break
	# Anything else happens back towards Base Camp: point at the way out.
	for s in _exits:
		if s in ["res://canyon.tscn", "res://reach.tscn"]:
			return _exits[s]
	return null


## Area-specific quest marker for a goal id (null = not here).
func _goal_target(_id: String):
	return null


# ---------------------------------------------------------------- death + UI

func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true
	await get_tree().create_timer(1.6).timeout
	await _fade_to(1.0, 0.6)
	GS.flags["frontier_respawn"] = area_scene
	GS.save()
	get_tree().reload_current_scene()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := UI.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
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
