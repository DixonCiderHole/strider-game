extends RefCounted
## Shared helpers for building outdoor areas: Terrain3D ground, nature-kit
## models (Quaternius Stylized Nature MegaKit, CC0) and multimesh planting.

const TERRAIN_MATERIAL := "res://demo/data/M_terrain.tres"
const TERRAIN_ASSETS := "res://demo/data/assets.tres"
const GRASS_PARTICLES := "res://addons/terrain_3d/extras/particle_example/Terrain3DParticles.tscn"
const NATURE := "res://glTF/"
const PINES := ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const LEAFY := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]
const DEAD := ["DeadTree_1", "DeadTree_2", "DeadTree_3"]


## Builds a Terrain3D node from `height` (Callable(x, z) -> float, metres).
## `paint` (Callable(data, x, z) or an empty Callable) runs for every vertex
## within `paint_radius` of the centre to paint textures and colour.
## Texture ids: 0 cliff rock, 1 grass, 2 trampled dirt. Returns null without the addon.
static func build_terrain(parent: Node, size: int, height: Callable, paint: Callable, paint_radius: int):
	if not ClassDB.class_exists("Terrain3D"):
		return null
	var terrain = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.free_editor_textures = false
	terrain.material = load(TERRAIN_MATERIAL).duplicate(true)
	var assets = load(TERRAIN_ASSETS).duplicate(true)
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
	terrain.collision_mode = 3
	parent.add_child(terrain)

	var half: int = size >> 1
	var img := Image.create_empty(size, size, false, Image.FORMAT_RF)
	for py in size:
		for px in size:
			img.set_pixel(px, py, Color(height.call(float(px - half), float(py - half)), 0.0, 0.0, 1.0))
	terrain.data.import_images([img, null, null], Vector3(-half, 0.0, -half), 0.0, 1.0)

	if paint.is_valid():
		for x in range(-paint_radius, paint_radius + 1):
			for z in range(-paint_radius, paint_radius + 1):
				paint.call(terrain.data, float(x), float(z))
		terrain.data.update_maps()

	if ResourceLoader.exists(GRASS_PARTICLES):
		var grass_fx = load(GRASS_PARTICLES).instantiate()
		terrain.add_child(grass_fx)
		grass_fx.terrain = terrain
	return terrain


## Paints one vertex as a grass/dirt blend (w = 0 grass .. 1 dirt).
static func paint_dirt(data, p: Vector3, w: float) -> void:
	if w <= 0.03:
		return
	data.set_control_auto(p, false)
	data.set_control_base_id(p, 1)
	data.set_control_overlay_id(p, 2)
	data.set_control_blend(p, clampf(w, 0.0, 1.0))


static func ground_y(terrain, p: Vector3, fallback := 0.0) -> float:
	if terrain == null:
		return fallback
	var h: float = terrain.data.get_height(Vector3(p.x, 0.0, p.z))
	if is_nan(h) or absf(h) > 1000.0:
		return fallback
	return h


## High-detail procedural trees (tools/assetgen/tree_gen.py). Same names
## and sizes as the old kit trees, so every scene that asks for "Pine_2"
## etc. gets these instead; plus Cherry_1..3 and FallenLog.
const TREES_GLB := "res://models/trees.glb"
const TREE_PREFIXES := ["Pine_", "CommonTree_", "DeadTree_", "TwistedTree_", "Cherry_", "FallenLog"]
static var _tree_meshes := {}
static var _tree_lods := {}     # full-detail Mesh -> [medium Mesh, far Mesh]

## Distances (m) where trees switch to the medium and far versions. The far
## version has no end distance, so every tree on the map stays visible.
const LOD1_AT := 55.0
const LOD2_AT := 140.0

const WIND_SHADER := """
shader_type spatial;
render_mode depth_draw_opaque, cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool foliage = true;
uniform float cutoff = 0.5;
uniform float roughness = 0.8;
uniform vec3 translucency : source_color = vec3(0.32, 0.36, 0.14);
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = origin.x * 0.21 + origin.z * 0.17;
	float h = max(VERTEX.y, 0.0);
	vec2 gust = vec2(sin(TIME * 0.8 + ph), cos(TIME * 0.63 + ph * 1.7)) * (0.6 + 0.4 * sin(TIME * 0.21 + ph));
	VERTEX.xz += gust * h * h * 0.0016;
	if (foliage) {
		VERTEX += NORMAL * sin(TIME * 4.5 + dot(VERTEX, vec3(3.1, 2.3, 2.7)) + ph) * 0.012 * min(h, 5.0);
	}
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * COLOR.rgb;
	if (foliage) {
		ALPHA = a.a;
		ALPHA_SCISSOR_THRESHOLD = cutoff;
		BACKLIGHT = translucency * a.rgb * 2.0;
		SPECULAR = 0.3;
	}
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = foliage ? 0.6 : 1.0;
	ROUGHNESS = roughness;
}
"""


static func _is_tree(model: String) -> bool:
	for p in TREE_PREFIXES:
		if model.begins_with(p):
			return true
	return false


static func _load_trees() -> void:
	if not _tree_meshes.is_empty() or not ResourceLoader.exists(TREES_GLB):
		return
	var sh := Shader.new()
	sh.code = WIND_SHADER
	var inst: Node = load(TREES_GLB).instantiate()
	var swapped := {}
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as StandardMaterial3D
			if m == null:
				continue
			var nm := m.resource_name
			if not (nm.begins_with("Foliage_") or nm.begins_with("Bark_")):
				m.vertex_color_use_as_albedo = true
				continue
			if not swapped.has(nm):
				var w := ShaderMaterial.new()
				w.shader = sh
				w.set_shader_parameter("albedo_tex", m.albedo_texture)
				w.set_shader_parameter("normal_tex", m.normal_texture)
				w.set_shader_parameter("foliage", nm.begins_with("Foliage_"))
				w.set_shader_parameter("roughness", 0.8 if nm.begins_with("Foliage_") else 0.92)
				if nm == "Foliage_Cherry":
					w.set_shader_parameter("translucency", Color(0.45, 0.3, 0.32))
				swapped[nm] = w
			mesh.surface_set_material(si, swapped[nm])
		_tree_meshes[String(mi.name)] = mesh
	for key in _tree_meshes.keys():
		if String(key).contains("_LOD"):
			continue
		var l1 = _tree_meshes.get(String(key) + "_LOD1")
		var l2 = _tree_meshes.get(String(key) + "_LOD2")
		if l1 != null and l2 != null:
			_tree_lods[_tree_meshes[key]] = [l1, l2]
	inst.free()


## Visibility window [begin, end] for detail level `lv` (end 0 = no limit).
static func _lod_window(lv: int) -> Vector2:
	match lv:
		0:
			return Vector2(0.0, LOD1_AT)
		1:
			return Vector2(LOD1_AT, LOD2_AT)
	return Vector2(LOD2_AT, 0.0)


static func _apply_lod(g: GeometryInstance3D, lv: int) -> void:
	var w := _lod_window(lv)
	g.visibility_range_begin = w.x
	g.visibility_range_begin_margin = 4.0 if lv > 0 else 0.0
	g.visibility_range_end = w.y
	g.visibility_range_end_margin = 4.0 if w.y > 0.0 else 0.0
	if lv == 2:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A single tree (or other mesh) at `xf`; trees get all three detail levels.
static func place(parent: Node, mesh: Mesh, xf: Transform3D) -> void:
	var levels: Array = [mesh] + (_tree_lods[mesh] as Array if _tree_lods.has(mesh) else [])
	for lv in levels.size():
		var mi := MeshInstance3D.new()
		mi.mesh = levels[lv]
		mi.transform = xf
		if levels.size() > 1:
			_apply_lod(mi, lv)
		parent.add_child(mi)


## First mesh in a nature-kit model, or null if it isn't there.
static func model_mesh(model: String) -> Mesh:
	if _is_tree(model):
		_load_trees()
		if _tree_meshes.has(model):
			return _tree_meshes[model]
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


static func meshes(names: Array) -> Array:
	var out := []
	for n in names:
		var m := model_mesh(n)
		if m != null:
			out.append(m)
	return out


static func add_instance(buckets: Dictionary, mesh: Mesh, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	if not buckets.has(mesh):
		buckets[mesh] = []
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
	buckets[mesh].append(Transform3D(b, p))


## MultiMeshInstance3Ds for `buckets` (Mesh -> Array of Transform3D), split
## into 32 m cells. Trees get a medium and a far version that take over with
## distance (the far one is never culled).
const PLANT_CELL := 32.0

static func plant(parent: Node, buckets: Dictionary, visibility_end: float) -> void:
	for mesh in buckets:
		var cells := {}
		for x in buckets[mesh]:
			var t: Transform3D = x
			var key := Vector2i(floori(t.origin.x / PLANT_CELL), floori(t.origin.z / PLANT_CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(t)
		for key in cells:
			var xforms: Array = cells[key]
			var centre := Vector3((key.x + 0.5) * PLANT_CELL, 0.0, (key.y + 0.5) * PLANT_CELL)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in xforms.size():
				var t: Transform3D = xforms[i]
				mm.set_instance_transform(i, Transform3D(t.basis, t.origin - centre))
			var levels: Array = [mesh] + (_tree_lods[mesh] as Array if _tree_lods.has(mesh) else [])
			for lv in levels.size():
				var lmm := mm if lv == 0 else (mm.duplicate() as MultiMesh)
				lmm.mesh = levels[lv]
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = lmm
				mmi.position = centre
				if levels.size() > 1:
					_apply_lod(mmi, lv)
				else:
					mmi.visibility_range_end = visibility_end
					mmi.visibility_range_end_margin = 12.0
				parent.add_child(mmi)


## Trunk collider so trees block movement and bolts.
static func trunk_collider(parent: Node, p: Vector3, s: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.22 * s
	shape.height = 8.0
	cs.shape = shape
	cs.position.y = 4.0
	body.add_child(cs)
	body.position = p
	parent.add_child(body)
