extends "res://scripts/interactable.gd"
## A placed storage crate (Wooden Crate: 10 slots, Metal Crate: 20 slots).
## `data` is its entry in GS.storage, so whatever is put in it is saved.
## Make one with StorageCrate.spawn(parent, data).

const GS = preload("res://scripts/game_state.gd")
const U = preload("res://scripts/util.gd")

var data: Dictionary
var _lamp: MeshInstance3D


static func spawn(parent: Node, d: Dictionary):
	var c = load("res://scripts/storage_crate.gd").new()
	c.data = d
	c.position = d["pos"]
	c.rotation.y = float(d.get("yaw", 0.0))
	parent.add_child(c)
	return c


func _ready() -> void:
	super._ready()
	reach = 2.4
	add_to_group("storage_crate")
	if data["type"] == "crate_metal":
		_build_metal()
	else:
		_build_wood()


func get_prompt() -> String:
	var used := 0
	for s in data["items"]:
		if s != null:
			used += 1
	return "Open %s   (%d / %d)" % [GS.item(data["type"])["name"], used, data["items"].size()]


func interact() -> void:
	for p in get_tree().get_nodes_in_group("storage_panel"):
		p.open_crate(self)
		return


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _solid(size: Vector3, centre_y: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = centre_y
	body.add_child(cs)
	add_child(body)


## Timber slats on a dark scrap-metal frame, with a glowing mag-lock.
func _build_wood() -> void:
	var w := Vector3(1.0, 0.62, 0.66)
	var wood := U.mat(Color(0.46, 0.32, 0.19), 0.85)
	var wood_dark := U.mat(Color(0.33, 0.22, 0.13), 0.9)
	var frame := U.mat(Color(0.16, 0.17, 0.19), 0.45)
	frame.metallic = 0.7
	var glow := U.mat(Color(1.0, 0.6, 0.2), 0.3, Color(1.0, 0.55, 0.15), 3.0)
	_box(Vector3(w.x - 0.04, w.y - 0.04, w.z - 0.04), Vector3(0, w.y * 0.5, 0), wood)
	for k in 3:   # slat grooves
		var y := 0.14 + k * 0.17
		_box(Vector3(w.x - 0.02, 0.025, w.z + 0.005), Vector3(0, y, 0), wood_dark)
	# Frame edges
	var t := 0.06
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(t, w.y, t), Vector3(sx * (w.x - t) * 0.5, w.y * 0.5, sz * (w.z - t) * 0.5), frame)
	for sy in [t * 0.5, w.y - t * 0.5]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(w.x, t, t), Vector3(0, sy, sz * (w.z - t) * 0.5), frame)
		for sx in [-1.0, 1.0]:
			_box(Vector3(t, t, w.z), Vector3(sx * (w.x - t) * 0.5, sy, 0), frame)
	# Mag-lock panel on the front
	_box(Vector3(0.2, 0.14, 0.03), Vector3(0, w.y * 0.62, w.z * 0.5 + 0.01), frame)
	_lamp = _box(Vector3(0.12, 0.03, 0.02), Vector3(0, w.y * 0.62, w.z * 0.5 + 0.03), glow)
	_solid(w, w.y * 0.5)


## Ribbed alloy container with a red stripe and a cyan lit lid seam.
func _build_metal() -> void:
	var w := Vector3(1.2, 0.72, 0.74)
	var hull := U.mat(Color(0.25, 0.27, 0.31), 0.4)
	hull.metallic = 0.75
	var rib := U.mat(Color(0.17, 0.18, 0.21), 0.45)
	rib.metallic = 0.8
	var red := U.mat(Color(0.8, 0.12, 0.09), 0.5)
	var cyan := U.mat(Color(0.3, 0.85, 1.0), 0.3, Color(0.25, 0.8, 1.0), 3.5)
	_box(Vector3(w.x, w.y - 0.08, w.z), Vector3(0, (w.y - 0.08) * 0.5 + 0.04, 0), hull)
	_box(Vector3(w.x + 0.04, 0.08, w.z + 0.04), Vector3(0, 0.04, 0), rib)               # base skid
	_box(Vector3(w.x + 0.04, 0.1, w.z + 0.04), Vector3(0, w.y - 0.05, 0), rib)          # lid
	_box(Vector3(w.x + 0.05, 0.02, w.z + 0.05), Vector3(0, w.y - 0.11, 0), cyan)        # lid seam
	for k in 5:   # ribs
		var x := -w.x * 0.4 + k * w.x * 0.2
		_box(Vector3(0.05, w.y - 0.2, w.z + 0.03), Vector3(x, w.y * 0.47, 0), rib)
	_box(Vector3(w.x + 0.01, 0.07, w.z + 0.035), Vector3(0, w.y * 0.32, 0), red)
	for sx in [-1.0, 1.0]:   # handles
		_box(Vector3(0.04, 0.05, 0.3), Vector3(sx * (w.x * 0.5 + 0.04), w.y * 0.6, 0), rib)
	# Lock panel
	_box(Vector3(0.26, 0.18, 0.03), Vector3(0, w.y * 0.55, w.z * 0.5 + 0.02), rib)
	_lamp = _box(Vector3(0.08, 0.08, 0.02), Vector3(0, w.y * 0.55, w.z * 0.5 + 0.04), cyan)
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 0.8, 1.0)
	l.light_energy = 0.6
	l.omni_range = 1.6
	l.position = Vector3(0, w.y * 0.55, w.z * 0.5 + 0.2)
	add_child(l)
	_solid(w, w.y * 0.5)
