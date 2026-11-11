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


## First mesh in a nature-kit model, or null if it isn't there.
static func model_mesh(model: String) -> Mesh:
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


## One MultiMeshInstance3D per mesh in `buckets` (Mesh -> Array of Transform3D).
static func plant(parent: Node, buckets: Dictionary, visibility_end: float) -> void:
	for mesh in buckets:
		var xforms: Array = buckets[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = visibility_end
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
