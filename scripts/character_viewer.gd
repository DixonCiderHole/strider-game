extends Node3D
## Character test (testing): flat ground in daylight, you control her.
## Press V for the free camera to orbit round and check her animations.
## 1: sit pose, 2: stand up, 3: back to normal.

const PlayerScript = preload("res://scripts/player.gd")
var her


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 150.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.36, 0.26)
	mi.material_override = gm
	body.add_child(mi)
	add_child(body)
	her = PlayerScript.new()
	her.profile = "female"
	add_child(her)
	her.position = Vector3(0, 0.1, 0)
	pass  # _pose_dump() for testing


## Testing: records the pose she is actually in (bones, hands, gun) for a
## few animations, to res://debug/pose_dump.json.
func _pose_dump() -> void:
	var out := {}
	await get_tree().create_timer(2.0).timeout
	out["tree"] = _snap()
	her.force_aim = true
	await get_tree().create_timer(1.0).timeout
	out["aimtree"] = _snap()
	her.force_aim = false
	DirAccess.make_dir_recursive_absolute("res://debug")
	var fa := FileAccess.open("res://debug/pose_dump.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	print("POSE DUMP written")


## Testing: close-up screenshots of her in the game, idle and aiming.
func _photos() -> void:
	DirAccess.make_dir_recursive_absolute("res://debug/photos")
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var fwd: Vector3 = -her.model.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var centre: Vector3 = her.global_position + Vector3.UP * 1.0
	var views := {"front": fwd, "threequarter_r": (fwd + side).normalized(),
		"threequarter_l": (fwd - side).normalized(), "side": side, "back": -fwd,
		"rarm_front": fwd, "rarm_side": side, "rarm_back": (-fwd + side).normalized(), "rarm_top": (fwd + side + Vector3.UP).normalized()}
	for mode in ["idle", "aim"]:
		her.force_aim = mode == "aim"
		await get_tree().create_timer(1.0).timeout
		for v in views:
			var c := centre
			var dist := 3.2
			if String(v).begins_with("rarm"):
				# Close on her right arm (side points to her right).
				c = her.global_position + Vector3.UP * 1.25 + side * 0.18
				dist = 1.1
			cam.global_position = c + views[v] * dist + Vector3.UP * 0.1
			cam.look_at(c, Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://debug/photos/%s_%s.png" % [mode, v])
	her.force_aim = false
	cam.current = false
	cam.queue_free()


func _snap() -> Dictionary:
	var sk: Skeleton3D = her.skeleton
	var bones := {}
	for b in sk.get_bone_count():
		var g := sk.get_bone_global_pose(b)
		var q := g.basis.get_rotation_quaternion()
		var r := sk.get_bone_rest(b)
		var l := sk.get_bone_pose(b)
		bones[sk.get_bone_name(b)] = {"o": [g.origin.x, g.origin.y, g.origin.z], "q": [q.x, q.y, q.z, q.w],
			"p": sk.get_bone_parent(b), "rest_o": [r.origin.x, r.origin.y, r.origin.z],
			"rest_q": _q(r.basis.get_rotation_quaternion()), "pose_q": _q(l.basis.get_rotation_quaternion())}
	var st := sk.global_transform
	var gt: Transform3D = her.gun.global_transform
	return {"bones": bones, "skel": _t(st), "gun": _t(gt)}


func _q(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]


func _t(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


## Testing: writes the raw Mixamo motion data to res://debug/anim_dump.json
## so the retargeting can be checked outside Godot.
func _dump_anims() -> void:
	var out := {}
	for f in ["rifle_idle", "rifle_aim", "f_idle", "f_walk", "rifle_walk_fwd", "rifle_sprint", "f_run"]:
		var path := "res://models/anims/%s.fbx" % f
		if not ResourceLoader.exists(path):
			continue
		var root: Node = load(path).instantiate()
		var sks := root.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			root.free()
			continue
		var sk: Skeleton3D = sks[0]
		var anim: Animation = null
		for p in root.find_children("*", "AnimationPlayer", true, false):
			for n in (p as AnimationPlayer).get_animation_list():
				if String(n) != "RESET":
					anim = (p as AnimationPlayer).get_animation(n)
					break
		var bones := []
		for b in sk.get_bone_count():
			var r := sk.get_bone_rest(b)
			var q := r.basis.get_rotation_quaternion()
			bones.append({"n": sk.get_bone_name(b), "p": sk.get_bone_parent(b),
				"o": [r.origin.x, r.origin.y, r.origin.z], "q": [q.x, q.y, q.z, q.w]})
		var rot := {}
		var pos := {}
		var frames := []
		if anim != null:
			var tl := anim.length
			var nf := maxi(1, int(tl * 10.0))
			for i in nf + 1:
				frames.append(minf(i / 10.0, tl))
			for tr in anim.get_track_count():
				var tp := anim.track_get_path(tr)
				if tp.get_subname_count() == 0:
					continue
				var bn := String(tp.get_subname(0))
				var keys := []
				for t in frames:
					if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
						var q: Quaternion = anim.rotation_track_interpolate(tr, t)
						keys.append([q.x, q.y, q.z, q.w])
					elif anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
						var v: Vector3 = anim.position_track_interpolate(tr, t)
						keys.append([v.x, v.y, v.z])
				if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
					rot[bn] = keys
				elif anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
					pos[bn] = keys
		var chain := []
		var nd: Node = sk
		while nd != null:
			if nd is Node3D:
				var t3: Transform3D = (nd as Node3D).transform
				chain.append([String(nd.name), [t3.basis.x.x, t3.basis.x.y, t3.basis.x.z, t3.basis.y.x, t3.basis.y.y, t3.basis.y.z, t3.basis.z.x, t3.basis.z.y, t3.basis.z.z], [t3.origin.x, t3.origin.y, t3.origin.z]])
			nd = nd.get_parent()
		out[f] = {"bones": bones, "frames": frames, "rot": rot, "pos": pos, "chain": chain}
		root.free()
	DirAccess.make_dir_recursive_absolute("res://debug")
	var fa := FileAccess.open("res://debug/anim_dump.json", FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(out))
		fa.close()
		print("ANIM DUMP written")


func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				her.play_pose("sit_idle")
			KEY_2:
				her.play_pose("sit_to_stand")
			KEY_3:
				her.clear_pose()
			KEY_P:
				_photos()
