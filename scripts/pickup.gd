extends "res://scripts/interactable.gd"
## World pickups: resource piles, supply crates, choppable trees and ore veins.
## Make one with Pickup.spawn(parent, kind, item_id, position).

const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const U = preload("res://scripts/util.gd")
const Sfx = preload("res://scripts/sfx.gd")
const WK = preload("res://scripts/world_kit.gd")

var kind := "resource"   # resource | crate | tree | vein
var item_id := ""
var amount := Vector2i(1, 2)
var uses := 3            # trees / veins
var _lid: Node3D


static func spawn(parent: Node, k: String, id: String, pos: Vector3, amt := Vector2i(1, 2)):
	var p = load("res://scripts/pickup.gd").new()
	p.kind = k
	p.item_id = id
	p.amount = amt
	p.position = pos
	parent.add_child(p)
	return p


func _ready() -> void:
	super._ready()
	rotation.y = randf() * TAU
	match kind:
		"resource":
			_build_resource()
		"crate":
			_build_crate()
			reach = 2.4
		"vein":
			_build_vein()
			reach = 3.0
		"tree":
			reach = 2.8


func get_prompt() -> String:
	if not enabled:
		return ""
	match kind:
		"resource":
			return "Pick up %s" % GS.item(item_id).get("name", item_id)
		"crate":
			return "Search supply crate"
		"tree":
			return "Chop tree" if GS.count("hatchet") > 0 else "Chop tree  (needs a Vibro-Hatchet)"
		"vein":
			return "Mine ore vein" if GS.count("pick") > 0 else "Mine ore vein  (needs a Mining Pick)"
	return ""


func interact() -> void:
	if not enabled:
		return
	var extra := GS.rank("scavenger")
	match kind:
		"resource":
			GS.add_item(item_id, randi_range(amount.x, amount.y) + extra)
			GS.add_xp(1)
			Sfx.ui("ui_click", -6.0, 0.2)
			queue_free()
		"crate":
			_open_crate()
		"tree":
			if GS.count("hatchet") <= 0:
				GS.toast("You need a Vibro-Hatchet. Craft one at the bench.")
				return
			var n := randi_range(2, 3) * (2 if GS.rank("lumberjack") > 0 else 1)
			GS.add_item("wood", n)
			GS.flags["chopped"] = true
			GS.add_xp(2)
			Sfx.at(global_position + Vector3.UP, "impact", -2.0, 0.2, 8.0)
			uses -= 1
			if uses <= 0:
				enabled = false
				GS.toast("This tree is stripped bare.")
		"vein":
			if GS.count("pick") <= 0:
				GS.toast("You need a Mining Pick. Craft one at the bench.")
				return
			var n2 := randi_range(1, 2) * (2 if GS.rank("lumberjack") > 0 else 1)
			GS.add_item("ore", n2)
			GS.add_xp(2)
			Sfx.at(global_position + Vector3.UP * 0.5, "impact", 0.0, 0.3, 8.0)
			uses -= 1
			if uses <= 0:
				enabled = false
				for c in get_children():
					if c is MeshInstance3D:
						(c as MeshInstance3D).material_override = U.mat(Color(0.3, 0.29, 0.28), 0.95)


func _open_crate() -> void:
	enabled = false
	Sfx.ui("crate_open", -4.0, 0.05)
	var got := 0
	for row in Items.CRATE_LOOT:
		if randf() < float(row[3]):
			GS.add_item(row[0], randi_range(row[1], row[2]))
			got += 1
	if GS.rank("lucky") > 0 or got == 0:
		var row = Items.CRATE_LOOT[randi() % Items.CRATE_LOOT.size()]
		GS.add_item(row[0], row[1])
	GS.add_xp(3)
	if _lid != null:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK)


# ---------------------------------------------------------------- visuals

func _mesh(m: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	add_child(mi)
	return mi


func _build_resource() -> void:
	match item_id:
		"wood":
			# A small pile of cut logs, big enough to see over the grass.
			var mat := U.mat(Color(0.45, 0.3, 0.17), 0.95)
			var ends := U.mat(Color(0.78, 0.62, 0.4), 0.9)
			var logs := [Vector3(-0.14, 0.11, 0.0), Vector3(0.14, 0.11, 0.0), Vector3(0.0, 0.3, 0.0)]
			for i in logs.size():
				var c := CylinderMesh.new()
				c.top_radius = 0.1
				c.bottom_radius = 0.11
				c.height = randf_range(1.0, 1.3)
				c.radial_segments = 8
				var lg := _mesh(c, mat, logs[i], Vector3(PI * 0.5, 0.0, 0.0))
				var cap := CylinderMesh.new()
				cap.top_radius = 0.095
				cap.bottom_radius = 0.095
				cap.height = c.height + 0.01
				cap.radial_segments = 8
				cap.cap_top = true
				cap.cap_bottom = true
				var ce := MeshInstance3D.new()
				ce.mesh = cap
				ce.material_override = ends
				lg.add_child(ce)
		"scrap":
			var mat2 := U.mat(Color(0.32, 0.33, 0.35), 0.6)
			mat2.metallic = 0.7
			for i in 4:
				var b := BoxMesh.new()
				b.size = Vector3(randf_range(0.2, 0.5), randf_range(0.03, 0.08), randf_range(0.15, 0.4))
				_mesh(b, mat2, Vector3(randf_range(-0.25, 0.25), 0.05 + i * 0.04, randf_range(-0.25, 0.25)), Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4)))
		"plastic":
			var mat3 := U.mat(Color(0.82, 0.82, 0.78), 0.4)
			for i in 3:
				var b2 := BoxMesh.new()
				b2.size = Vector3(randf_range(0.25, 0.45), 0.02, randf_range(0.2, 0.35))
				_mesh(b2, mat3, Vector3(randf_range(-0.2, 0.2), 0.03 + i * 0.03, randf_range(-0.2, 0.2)), Vector3(randf_range(-0.3, 0.3), randf() * TAU, 0.0))
		"fiber":
			var plant := WK.model_mesh("Plant_1_Big")
			if plant != null:
				_mesh(plant, null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.8)
			else:
				var s := SphereMesh.new()
				s.radius = 0.35
				s.height = 0.5
				_mesh(s, U.mat(Color(0.3, 0.5, 0.2), 0.9), Vector3(0, 0.2, 0))
		"ore":
			var mat4 := U.mat(Color(0.45, 0.25, 0.18), 0.8, Color(1.0, 0.45, 0.15), 0.6)
			for i in 3:
				var s2 := SphereMesh.new()
				s2.radius = randf_range(0.1, 0.16)
				s2.height = s2.radius * 1.6
				_mesh(s2, mat4, Vector3(randf_range(-0.2, 0.2), 0.08, randf_range(-0.2, 0.2)))
		_:
			var b3 := BoxMesh.new()
			b3.size = Vector3(0.25, 0.15, 0.25)
			_mesh(b3, U.mat(GS.item(item_id).get("color", Color.WHITE), 0.6), Vector3(0, 0.08, 0))
	# A small floating marker so pickups stand out from the grass.
	var col: Color = GS.item(item_id).get("color", Color.WHITE)
	var mk := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.16, 0.16, 0.16)
	mk.mesh = pm
	mk.material_override = U.mat(col, 0.4, col.lightened(0.3), 1.6)
	mk.rotation.z = PI
	mk.position.y = 1.0
	mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mk)
	var tw := mk.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(mk, "position:y", 1.15, 0.9)
	tw.tween_property(mk, "position:y", 1.0, 0.9)
	# A faint glow so pickups can be spotted.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.5)
	glow.light_energy = 0.4
	glow.omni_range = 1.4
	glow.position.y = 0.5
	add_child(glow)


func _build_crate() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.55, 0.6)
	cs.shape = box
	cs.position.y = 0.27
	body.add_child(cs)
	var dark := U.mat(Color(0.18, 0.19, 0.2), 0.6)
	dark.metallic = 0.6
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.5, 0.6)
	_mesh(bm, dark, Vector3(0, 0.25, 0))
	var band := BoxMesh.new()
	band.size = Vector3(0.92, 0.06, 0.62)
	_mesh(band, U.mat(Color(1.0, 0.5, 0.15), 0.5, Color(1.0, 0.45, 0.1), 0.8), Vector3(0, 0.33, 0))
	# Lid hinged at the back edge.
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.5, -0.3)
	add_child(_lid)
	var lm := BoxMesh.new()
	lm.size = Vector3(0.94, 0.07, 0.64)
	var lid := MeshInstance3D.new()
	lid.mesh = lm
	lid.material_override = dark
	lid.position = Vector3(0, 0.035, 0.3)
	_lid.add_child(lid)


func _build_vein() -> void:
	var rock := U.mat(Color(0.32, 0.3, 0.3), 0.9)
	var vein := U.mat(Color(0.6, 0.3, 0.15), 0.6, Color(1.0, 0.5, 0.15), 1.6)
	var s := SphereMesh.new()
	s.radius = 0.8
	s.height = 1.1
	_mesh(s, rock, Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1.3, 1.0, 1.0))
	for i in 5:
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.06, 0.08)
		_mesh(b, vein, Vector3(randf_range(-0.5, 0.5), randf_range(0.3, 0.8), randf_range(-0.4, 0.4)).normalized() * 0.8 + Vector3(0, 0.35, 0), Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.8
	cs.shape = sh
	cs.position.y = 0.35
	body.add_child(cs)
