extends "res://scripts/path.gd"
## Pinned: you're sitting impaled against a tree in a rocky corner of the
## clearing where your squad fell; creatures can only come at you from the
## front. You can't move, only aim and shoot, with limited ammo. When the blaster
## runs dry you pass out ("rescued" cutscene, then the drag escape).

const AMMO := 150
const PIN_MAX_ALIVE := 10
const PIN_Z := -10.0

var _pin_kills := 0
var _done := false
## Live creatures; counted from this list (not a counter) so one that dies
## oddly or gets stuck can never stop the spawning.
var _enemies: Array = []
var _stuck_t := {}
var _since_prune := 0.0


func _ready() -> void:
	rng.seed = 123
	curve_a = 26.0
	curve_b = 8.0
	curve_phase = 2.2
	terrain_seed = 44
	z_start = 70.0
	z_end = -80.0
	GS.ensure_loaded()
	GS.horde_mode = false
	if not GS.menu_preview:
		Sfx.loop(self, "forest_loop", -14.0, 6.0, false)
	_build_environment()
	_build_ground()
	_build_walls()
	_build_forest()
	if GS.menu_preview:
		_preview()
		return
	GS.enter_area(scene_file_path)

	hud = HudScript.new()
	add_child(hud)

	# Against a tree at the edge of the trail, facing across it.
	var n := path_normal(PIN_Z)
	var p := path_point(PIN_Z) + n * 4.5
	p.y = _ground(p)
	var face := -n   # towards the trail
	var yaw := atan2(-face.x, -face.z)
	_build_pin_tree(p, face)
	_build_corner(p, face)

	player = PlayerScript.new()
	player.name = "Player"
	player.damage = GS.player_damage()
	player.max_health = GS.player_max_health()
	player.health = player.max_health
	player.health_floor = 1.0
	player.ammo = AMMO
	player.position = p + Vector3(0.0, 0.05, 0.0)
	add_child(player)
	player.pinned = true
	player.seated = true
	player.seat_arc = deg_to_rad(65.0)
	player.cam_yaw.rotation.y = yaw
	player.set_seat_facing(yaw)
	player.health_changed.connect(hud.set_health)
	player.hit_landed.connect(hud.show_hitmarker)
	player.ammo_changed.connect(_on_ammo)

	menu = PauseMenuScript.new()
	menu.player = player
	add_child(menu)

	hud.set_health(player.health, player.max_health)
	hud.set_hint("You can't move   ·   Mouse aim   ·   Left click fire   ·   Esc pause")
	hud.show_message("You're pinned to the tree.\nMake every shot count.", 4.0)
	_spawn_t = 2.0
	_update_pin_hud()


## The tree you're pinned to, and the creature spine through your armor.
func _build_pin_tree(p: Vector3, face: Vector3) -> void:
	var trunk_pos := p - face * 0.55
	var pine := WK.model_mesh("Pine_3")
	if pine != null:
		var mi := MeshInstance3D.new()
		mi.mesh = pine
		mi.scale = Vector3.ONE * 2.2
		mi.position = trunk_pos + Vector3(0.0, -0.2, 0.0)
		add_child(mi)
	WK.trunk_collider(self, trunk_pos, 2.2)
	# A long, curved bone spike from the trunk through the chest.
	var spike := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.01
	cm.bottom_radius = 0.07
	cm.height = 1.4
	cm.radial_segments = 8
	spike.mesh = cm
	spike.material_override = U.mat(Color(0.75, 0.68, 0.55), 0.6)
	var start := trunk_pos + Vector3(0.0, 0.5, 0.0)
	var tip := p + face * 0.6 + Vector3(0.0, 0.62, 0.0)
	spike.transform = Transform3D(Basis(Quaternion(Vector3.UP, (tip - start).normalized())), (start + tip) * 0.5)
	add_child(spike)


## Rock walls on both sides so the only way in is straight ahead.
func _build_corner(p: Vector3, face: Vector3) -> void:
	var scenes := []
	for path in ROCK_SCENES:
		if ResourceLoader.exists(path):
			scenes.append(load(path))
	var side_dir := face.cross(Vector3.UP).normalized()
	for side in [-1.0, 1.0]:
		# A wall angled out from the tree like the sides of a V.
		var out: Vector3 = (face * 0.45 + side_dir * side * 0.9).normalized()
		for k in 5:
			var c: Vector3 = p + out * (3.2 + k * 2.4)
			c.y = _ground(c)
			if not scenes.is_empty():
				var rock: Node3D = scenes[(k + int(side > 0.0)) % scenes.size()].instantiate()
				var s := rng.randf_range(0.28, 0.36)
				rock.scale = Vector3.ONE * s
				rock.position = c + Vector3(0.0, s * 1.4, 0.0)
				rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
				add_child(rock)
		# Solid wall behind the rocks so nothing slips through.
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.5, 6.0, 12.0)
		cs.shape = box
		wall.add_child(cs)
		var mid: Vector3 = p + out * 8.0
		wall.position = Vector3(mid.x, _ground(mid) + 2.0, mid.z)
		wall.rotation.y = atan2(out.x, out.z)
		add_child(wall)
	# Thick brush behind the tree.
	var back := StaticBody3D.new()
	var bcs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(8.0, 6.0, 1.0)
	bcs.shape = bb
	back.add_child(bcs)
	var bp := p - face * 1.6
	back.position = Vector3(bp.x, _ground(bp) + 2.0, bp.z)
	back.rotation.y = atan2(face.x, face.z)
	add_child(back)


func _debug_skip() -> void:
	if not _done:
		player.ammo = 0
		_on_ammo(0)


func _physics_process(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	_time += delta
	_since_prune += delta
	if _done or player == null:
		return
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		# Faster and faster until the blaster runs dry.
		var used := 1.0 - float(player.ammo) / AMMO
		_spawn_t = rng.randf_range(0.9, 1.5) * lerpf(1.0, 0.55, used)
		_prune()
		if _enemies.size() < PIN_MAX_ALIVE:
			_spawn_front()


## Drops dead ones; removes any that have been stuck far off for 12 s and
## brings a fresh one in its place.
func _prune() -> void:
	var keep: Array = []
	for e in _enemies:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d > 7.0:
			_stuck_t[e] = _stuck_t.get(e, 0.0) + _since_prune
		else:
			_stuck_t[e] = 0.0
		if _stuck_t[e] > 12.0 or d > 60.0 or e.global_position.y < _ground(e.global_position) - 3.0:
			_stuck_t.erase(e)
			e.queue_free()
			continue
		keep.append(e)
	_enemies = keep
	for k in _stuck_t.keys():
		if not is_instance_valid(k):
			_stuck_t.erase(k)
	_since_prune = 0.0


func _unhandled_input(_event) -> void:
	pass


## Creatures come out of the trees in front of you and along the trail.
func _spawn_front() -> void:
	var fwd: Vector3 = -player.model.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ang := rng.randf_range(-0.4, 0.4)
	var dir := fwd.rotated(Vector3.UP, ang)
	var p: Vector3 = player.global_position + dir * rng.randf_range(16.0, 24.0)
	p.y = _ground(p) + 0.4
	var e = EnemyScript.new()
	e.position = p
	e.speed += 0.6
	e.attack_damage *= 0.5
	e.target = player
	add_child(e)
	e.died.connect(_on_pin_enemy_died)
	_alive += 1
	_enemies.append(e)


func _on_pin_enemy_died() -> void:
	_alive -= 1
	_pin_kills += 1
	_update_pin_hud()


func _on_ammo(left: int) -> void:
	_update_pin_hud()
	if left == 0 and not _done:
		_out_of_ammo()


func _update_pin_hud() -> void:
	hud.set_objective("PINNED", "Ammo %d   ·   Kills %d" % [player.ammo, _pin_kills])


func _out_of_ammo() -> void:
	_done = true
	hud.show_message("*click*\nThe blaster's empty.", 3.0)
	await get_tree().create_timer(3.5).timeout
	GS.add_salvage(_pin_kills * SALVAGE_PER_KILL)
	Cutscene.play("rescued")


func _on_player_died() -> void:
	pass  # can't die here (health floor); you pass out when the ammo is gone
