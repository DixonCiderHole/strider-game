extends "res://scripts/path.gd"
## The escape: she drags you by the collar along a forest trail while you sit
## facing back and shoot the creatures chasing you. Kill enough of them and
## she reaches a cave ("escaped" cutscene, then the base camp).

const AllyScript = preload("res://scripts/ally.gd")

const DRAG_SPEED := 1.3
const KILLS_NEEDED := 18
const DRAG_MAX_ALIVE := 7

var ally
var _drag_z := 0.0
var _drag_kills := 0
var _done := false


func _ready() -> void:
	rng.seed = 91
	curve_a = 22.0
	curve_b = 9.0
	curve_phase = 4.0
	terrain_seed = 57
	z_start = 140.0
	z_end = -170.0
	GS.ensure_loaded()
	GS.horde_mode = false
	if not GS.menu_preview:
		Sfx.loop(self, "forest_loop", -13.0, 6.0, false)
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

	_drag_z = z_start - 6.0
	player = PlayerScript.new()
	player.name = "Player"
	player.damage = GS.player_damage()
	player.max_health = GS.player_max_health()
	player.health = player.max_health
	player.position = path_point(_drag_z) + Vector3(0.0, 0.05, 0.0)
	add_child(player)
	player.seated = true
	player.infinite_ammo = true
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	player.hit_landed.connect(hud.show_hitmarker)
	var t := path_tangent(_drag_z)
	player.cam_yaw.rotation.y = atan2(t.x, t.z)
	player.set_seat_facing(atan2(t.x, t.z))

	ally = AllyScript.new()
	ally.name = "Ally"
	ally.mode = "drag"
	add_child(ally)

	menu = PauseMenuScript.new()
	menu.player = player
	add_child(menu)

	hud.set_health(player.health, player.max_health)
	hud.set_hint("Mouse aim   ·   Left click fire   ·   Right click aim   ·   Esc pause")
	hud.show_message("She's dragging you out.\nKeep them off you!", 4.0)
	_spawn_t = 4.0
	_update_drag_hud()
	_place(0.0)


func _physics_process(delta: float) -> void:
	if _done or player == null or player.is_dead:
		if ally != null:
			ally.move_speed = 0.0
		return
	_place(delta)


## Moves the pair along the trail; you face back the way you came.
func _place(delta: float) -> void:
	_drag_z = maxf(_drag_z - DRAG_SPEED * delta, z_end + 10.0)
	var moving := _drag_z > z_end + 10.0
	var t := path_tangent(_drag_z)
	var p := path_point(_drag_z)
	# Hauled up off the ground a little, hips lifted, legs trailing.
	player.global_position = p + Vector3(0.0, 0.18, 0.0)
	player.set_seat_facing(atan2(t.x, t.z))
	# Right behind you, hands on your collar.
	var a := p + t * 0.42
	a.y = _ground(a)
	ally.global_position = a
	ally.rotation.y = atan2(t.x, t.z)
	ally.move_speed = DRAG_SPEED if moving else 0.0
	if _side_cam != null and _side_cam.current:
		var n := path_normal(_drag_z)
		_side_cam.global_position = p + n * 2.6 + Vector3(0.0, 1.0, 0.0) + t * 0.25
		_side_cam.look_at(p + t * 0.25 + Vector3(0.0, 0.7, 0.0))


func _process(delta: float) -> void:
	_time += delta
	if _done or player == null or player.is_dead:
		return
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = rng.randf_range(1.8, 3.2)
		if _alive < DRAG_MAX_ALIVE:
			_spawn_chaser()


func _debug_skip() -> void:
	if not _done:
		_escape()


func _unhandled_input(event) -> void:
	# F3 (testing): side-on camera to check her grip.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		if _side_cam == null:
			_side_cam = Camera3D.new()
			add_child(_side_cam)
		if _side_cam.current:
			player.camera.make_current()
		else:
			_side_cam.make_current()


var _side_cam: Camera3D


func _spawn_chaser() -> void:
	var t := path_tangent(_drag_z)
	var n := path_normal(_drag_z)
	var p: Vector3 = player.global_position - t * rng.randf_range(20.0, 34.0) + n * rng.randf_range(-12.0, 12.0)
	if rng.randf() < 0.3:
		# Out of the trees to one side.
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		p = player.global_position - t * rng.randf_range(4.0, 14.0) + n * side * rng.randf_range(13.0, 16.0)
	p.y = _ground(p) + 0.4
	var e = EnemyScript.new()
	e.position = p
	var prog := float(_drag_kills) / KILLS_NEEDED
	e.speed += 0.5 + prog * 1.2
	e.health += prog * 25.0
	e.target = player
	add_child(e)
	e.died.connect(_on_chaser_died)
	_alive += 1


func _on_chaser_died() -> void:
	_alive -= 1
	_drag_kills += 1
	_update_drag_hud()
	if _drag_kills >= KILLS_NEEDED and not _done:
		_escape()


func _update_drag_hud() -> void:
	hud.set_objective("ESCAPE", "Hold them off   ·   %d / %d" % [mini(_drag_kills, KILLS_NEEDED), KILLS_NEEDED])


func _escape() -> void:
	_done = true
	player.input_enabled = false
	ally.move_speed = 0.0
	GS.add_salvage(_drag_kills * SALVAGE_PER_KILL)
	GS.wake_at_camp = true
	hud.show_message("The rest of them fall back.\nShe hauls you towards a cave in the cliffs...", 3.5)
	await get_tree().create_timer(4.0).timeout
	Cutscene.play("escaped")


func _on_player_died() -> void:
	_done = true
	hud.show_message("", 0.0)
	menu.show_end("YOU WERE OVERRUN", "They caught up with you both.", "Kills: %d / %d" % [_drag_kills, KILLS_NEEDED], 2.5)
