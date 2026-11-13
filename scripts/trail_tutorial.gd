extends Node
## First trip down the trail only: teaches the controls as you go.
##
##   start ......... MOVE / LOOK
##   z 132 ......... SPRINT
##   z 112 ......... one creature comes out of the trees: SHOOT / AIM / RELOAD
##   z  70 ......... a deadfall across the trail: JUMP
##   z  62 ......... CHECKPOINT (saved)
##   z  48 ......... a Vaari sentry drone asleep over the trail: CROUCH to sneak
##   past the drone  DROID ORDERS, and the usual creatures start coming.
##
## Each pop-up is only ever shown once per save (GS.flags "tut:<id>").
## The trail script holds its creature spawns while `holding` is true.

const GS = preload("res://scripts/game_state.gd")
const UI = preload("res://scripts/ui.gd")
const WK = preload("res://scripts/world_kit.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const DroneScript = preload("res://scripts/sentry_drone.gd")

const Z_SPRINT := 132.0
const Z_FIRST_ENEMY := 112.0
const Z_LOG := 70.0
const Z_CHECKPOINT := 62.0
const Z_CROUCH := 50.0
const Z_DRONE := 26.0
const DRONE_HEIGHT := 3.4
const ROCK_SCENES := ["res://demo/assets/models/RockA.tscn", "res://demo/assets/models/RockB.tscn", "res://demo/assets/models/RockC.tscn"]

var trail: Node3D          # the path.gd scene
var player
var hud

## True until you're past the drone; the trail holds its creature trickle.
var holding := true

var _drone
var _first_enemy
var _first_enemy_dead := false
var _passed_drone := false
var _start_pos := Vector3.ZERO

var _layer: CanvasLayer
var _card: PanelContainer
var _card_title: Label
var _card_body: Label
var _card_id := ""
var _card_t := 0.0
var _card_until := ""        # a condition id that dismisses the card
var _queue: Array = []       # [id, title, body, min_time, max_time, until]


func _ready() -> void:
	_start_pos = player.global_position
	_build_ui()
	_build_deadfall()
	_build_drone()
	player.crouch_changed.connect(_on_crouch)
	# Already past the checkpoint (continuing a save): skip the early lessons.
	if player.global_position.z < Z_CHECKPOINT:
		_first_enemy_dead = true
	else:
		_pop("move", "MOVE", "[W] [A] [S] [D]  move      [Mouse]  look around", 2.5, 9.0, "moved")


# ---------------------------------------------------------------- flow

func _process(delta: float) -> void:
	_update_card(delta)
	if player == null or player.is_dead:
		return
	var z: float = player.global_position.z

	if z < Z_SPRINT:
		_pop("sprint", "SPRINT", "Hold [Shift] while moving forward to run.", 2.5, 8.0, "sprinted")

	if not _first_enemy_dead and _first_enemy == null and z < Z_FIRST_ENEMY:
		_spawn_first_enemy()
	if is_instance_valid(_first_enemy) and _first_enemy.global_position.distance_to(player.global_position) < 34.0:
		_pop("shoot", "SHOOT", "[Left Click]  fire      [Right Click]  aim      [R]  reload\nOne of the creatures. Put it down.", 3.0, 14.0, "first_kill")

	if z < Z_LOG + 14.0 and z > Z_LOG - 1.0:
		_pop("jump", "JUMP", "Press [Space] to jump the fallen trees.", 2.0, 30.0, "over_log")

	if z < Z_CHECKPOINT and float(GS.flags.get("area_cp", 999.0)) > Z_CHECKPOINT:
		GS.flags["area_cp"] = Z_CHECKPOINT - 2.0
		GS.save()
		hud.show_message("CHECKPOINT\nProgress saved. If you fall, you'll be back here.", 3.0)

	if not _passed_drone and z < Z_CROUCH:
		_pop("crouch", "CROUCH", "Something hangs over the trail ahead. It's asleep.\nPress [C] to crouch and sneak underneath. Don't run. Don't shoot.", 3.0, 60.0, "past_drone")
	if not _passed_drone and z < Z_DRONE - 7.0 and _drone != null and _drone.is_asleep():
		_passed_drone = true
		holding = false
		_pop("droid", "YOUR DROID", "[1] follow   [2] hold here   [3] send to crosshair   [4] weapons on/off\nMore creatures ahead. Stay sharp.", 3.0, 9.0, "")


func _spawn_first_enemy() -> void:
	var z := Z_FIRST_ENEMY - 22.0
	var p: Vector3 = trail.path_point(z) + trail.path_normal(z) * 9.0
	p.y = trail._ground(p) + 0.4
	var e = EnemyScript.new()
	e.position = p
	e.target = player
	trail.add_child(e)
	e.died.connect(_on_first_enemy_died)
	_first_enemy = e


func _on_first_enemy_died() -> void:
	_first_enemy_dead = true
	_first_enemy = null


func _on_crouch(on: bool) -> void:
	if on:
		_pop("crouching", "CROUCHED", "You're quieter and slower.  [C] to stand.  [Shift] or [Space] also stands you up.", 2.0, 5.0, "")


## The trail calls this after you respawn at a checkpoint.
func on_respawn() -> void:
	if not _first_enemy_dead:
		_first_enemy = null       # it was cleared with the others; it'll come again
	if _drone != null:
		_drone.reset()


# ---------------------------------------------------------------- pop-ups

func _pop(id: String, title: String, body: String, min_t: float, max_t: float, until: String) -> void:
	if GS.flags.get("tut:" + id, false) or _card_id == id:
		return
	for q in _queue:
		if q[0] == id:
			return
	_queue.append([id, title, body, min_t, max_t, until])


func _done(cond: String) -> bool:
	match cond:
		"moved":
			return player.global_position.distance_to(_start_pos) > 5.0
		"sprinted":
			return Vector2(player.velocity.x, player.velocity.z).length() > player.walk_speed + 1.0
		"first_kill":
			return _first_enemy_dead
		"over_log":
			return player.global_position.z < Z_LOG - 1.5
		"past_drone":
			return _passed_drone
	return false


func _update_card(delta: float) -> void:
	if _card_id == "":
		if _queue.is_empty():
			return
		var q: Array = _queue.pop_front()
		_card_id = q[0]
		_card_title.text = q[1]
		_card_body.text = q[2]
		_card_t = 0.0
		_card.set_meta("min_t", q[3])
		_card.set_meta("max_t", q[4])
		_card_until = q[5]
		GS.flags["tut:" + _card_id] = true
		_card.visible = true
		_card.modulate.a = 0.0
		return
	_card_t += delta
	_card.modulate.a = minf(1.0, _card.modulate.a + delta * 4.0)
	var min_t: float = _card.get_meta("min_t")
	var max_t: float = _card.get_meta("max_t")
	var finished := _card_t > max_t or (_card_until != "" and _card_t > min_t and _done(_card_until))
	# Don't keep a lesson up once a newer one is waiting and this one is learned.
	if _card_until == "" and not _queue.is_empty() and _card_t > min_t:
		finished = true
	if finished:
		_card.visible = false
		_card_id = ""


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(anchor)
	_card = PanelContainer.new()
	var st := UI.box(Color(0.04, 0.05, 0.07, 0.86), UI.ACCENT, 2, 6)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	st.shadow_color = Color(UI.ACCENT, 0.3)
	st.shadow_size = 10
	_card.add_theme_stylebox_override("panel", st)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.8
	_card.anchor_bottom = 0.8
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_card)
	var v := UI.vbox(4)
	_card.add_child(v)
	var head := UI.label("CONTROLS", 13, UI.MUTED)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	_card_title = UI.label("", 26, UI.ACCENT)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_card_title)
	_card_body = UI.label("", 18, UI.TEXT)
	_card_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_card_body)
	_card.visible = false


# ---------------------------------------------------------------- world

## Dead trees fallen across the whole width of the trail, low enough to jump.
func _build_deadfall() -> void:
	var dead := WK.meshes(WK.DEAD)
	var c: Vector3 = trail.path_point(Z_LOG)
	var n: Vector3 = trail.path_normal(Z_LOG)
	var span := 40.0   # wall to wall
	# One low, solid barrier the whole way across (jumpable everywhere).
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, 0.9, 1.1)
	cs.shape = box
	body.add_child(cs)
	body.position = c + Vector3(0.0, 0.45, 0.0)
	body.rotation.y = atan2(n.x, n.z) - PI * 0.5
	trail.add_child(body)
	if dead.is_empty():
		return
	# Logs end to end, each lying on its side along the barrier.
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var offsets := [-15.0, -5.0, 5.0, 15.0]
	for i in offsets.size():
		var mesh: Mesh = dead[i % dead.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var aabb := mesh.get_aabb()
		var tall := maxf(aabb.size.y, 0.01)
		var s := 11.0 / tall           # each log ~11 m long
		var along: Vector3 = n * float(offsets[i])
		var base: Vector3 = c + along - n * 5.5 * (1.0 if i % 2 == 0 else -1.0)
		base.y = trail._ground(base) + 0.35
		# Tree's up axis (+Y) laid along the barrier direction.
		var up_dir: Vector3 = n * (1.0 if i % 2 == 0 else -1.0)
		var fwd := Vector3.UP
		var side := up_dir.cross(fwd).normalized()
		var b := Basis(side, up_dir, fwd).orthonormalized()
		b = b * Basis(Vector3.UP, rng.randf() * TAU)
		mi.transform = Transform3D(b.scaled(Vector3.ONE * s), base)
		trail.add_child(mi)
	# Rocks heaped at the trail edges.
	for path in ROCK_SCENES:
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		for sgn in [-1.0, 1.0]:
			var rp: Vector3 = c + n * sgn * rng.randf_range(4.5, 6.5) + trail.path_tangent(Z_LOG) * rng.randf_range(-1.2, 1.2)
			var rock: Node3D = scene.instantiate()
			var sc := rng.randf_range(0.16, 0.26)
			rock.scale = Vector3.ONE * sc
			rock.position = Vector3(rp.x, trail._ground(rp) + sc * 0.8, rp.z)
			rock.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
			trail.add_child(rock)


func _build_drone() -> void:
	_drone = DroneScript.new()
	_drone.player = player
	var p: Vector3 = trail.path_point(Z_DRONE)
	_drone.position = p + Vector3(0.0, DRONE_HEIGHT, 0.0)
	# Facing back up the trail, towards you.
	var t: Vector3 = trail.path_tangent(Z_DRONE)
	_drone.rotation.y = atan2(t.x, t.z)
	trail.add_child(_drone)
	var MapPoi = load("res://scripts/map_poi.gd")
	MapPoi.add(trail, _drone.position, "Sleeping Sentry", "danger",
			"A Vaari drone asleep over the trail. Crouch [C] and sneak underneath. Don't run, don't shoot.")
	MapPoi.add(trail, trail.path_point(Z_CHECKPOINT), "Checkpoint", "camp",
			"Past the fallen trees. If you fall, you come back here.")
	_drone.woke.connect(func(): hud.show_message("IT'S AWAKE", 1.2))
