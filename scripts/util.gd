extends RefCounted
## Small shared helpers: materials and fitting imported models to a size.


static func mat(color: Color, roughness := 0.8, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


## Bounding box of every mesh under `root`, in root's own local space.
## `root` must already be inside the scene tree.
static func collect_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


## Uniformly scales `root` so its size along `axis` equals `target`,
## then moves it so it is centred (and optionally standing on y = 0).
static func fit(root: Node3D, target: float, axis: int, stand_on_ground: bool) -> void:
	var box := collect_aabb(root)
	var dim: float = box.size[axis]
	if dim <= 0.0001:
		return
	var s := target / dim
	root.scale = Vector3.ONE * s
	var c := box.get_center() * s
	if stand_on_ground:
		root.position = Vector3(-c.x, -box.position.y * s, -c.z)
	else:
		root.position = -c


static func fit_longest(root: Node3D, target: float) -> void:
	var size := collect_aabb(root).size
	var axis := 0
	if size.y > size[axis]:
		axis = 1
	if size.z > size[axis]:
		axis = 2
	fit(root, target, axis, false)
