extends RefCounted
## Blaster pistol model, built from parts in the same units and axes as
## blaster.glb (long axis X, muzzle towards -X, Y up) so it drops into the
## player's gun mount: its grip sits where the rifle's grip is.

## Where the bolts come out (gun-model units).
const MUZZLE := Vector3(0.1, 0.05, 0.0)


static func _mat(col: Color, rough: float, metal := 0.0, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


static func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_z := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.z = rot_z
	root.add_child(mi)


static func _cyl(root: Node3D, radius: float, length: float, x: float, y: float, mat: Material, sides := 12) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(x, y, 0.0)
	mi.rotation.z = PI * 0.5   # along X
	root.add_child(mi)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "BlasterPistol"
	var gunmetal := _mat(Color(0.2, 0.21, 0.24), 0.35, 0.8)
	var polymer := _mat(Color(0.08, 0.085, 0.095), 0.7, 0.1)
	var steel := _mat(Color(0.5, 0.52, 0.56), 0.3, 0.9)
	var red := _mat(Color(1.0, 0.22, 0.12), 0.4, 0.0, Color(1.0, 0.18, 0.08), 3.0)
	var cell := _mat(Color(1.0, 0.55, 0.2), 0.3, 0.0, Color(1.0, 0.45, 0.12), 2.2)

	# Slide and top rail
	_box(root, Vector3(0.74, 0.17, 0.12), Vector3(0.6, 0.05, 0.0), gunmetal)
	_box(root, Vector3(0.62, 0.035, 0.07), Vector3(0.6, 0.155, 0.0), polymer)
	_box(root, Vector3(0.04, 0.05, 0.05), Vector3(0.94, 0.16, 0.0), steel)     # rear sight
	_box(root, Vector3(0.03, 0.045, 0.025), Vector3(0.3, 0.165, 0.0), red)     # front sight dot
	# Heat vents along both sides of the slide
	for i in 3:
		for side in [-1.0, 1.0]:
			_box(root, Vector3(0.07, 0.03, 0.01), Vector3(0.42 + i * 0.1, 0.08, side * 0.061), red)
	# Red stripe down the slide
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.58, 0.015, 0.006), Vector3(0.62, 0.0, side * 0.0615), red)
	# Emitter shroud and muzzle ring
	_cyl(root, 0.062, 0.14, 0.2, 0.05, gunmetal, 8)
	_cyl(root, 0.045, 0.05, 0.12, 0.05, steel, 16)
	_cyl(root, 0.03, 0.02, 0.095, 0.05, red, 16)
	# Lower frame, trigger guard and trigger
	_box(root, Vector3(0.56, 0.08, 0.1), Vector3(0.62, -0.075, 0.0), polymer)
	_box(root, Vector3(0.18, 0.025, 0.06), Vector3(0.66, -0.2, 0.0), polymer)
	_box(root, Vector3(0.025, 0.08, 0.06), Vector3(0.57, -0.16, 0.0), polymer)
	_box(root, Vector3(0.025, 0.07, 0.025), Vector3(0.7, -0.15, 0.0), steel, 0.2)
	# Grip (raked back) with a glowing power cell window
	_box(root, Vector3(0.15, 0.38, 0.11), Vector3(0.86, -0.24, 0.0), polymer, -0.22)
	_box(root, Vector3(0.16, 0.06, 0.12), Vector3(0.91, -0.43, 0.0), gunmetal, -0.22)   # base plate
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.05, 0.2, 0.006), Vector3(0.87, -0.24, side * 0.057), cell, -0.22)
	return root
