extends Node3D
## The mini combat drone from the freighter in Shipfall Reach (DRONE_QUESTS).
## Hovers off your shoulder, picks the nearest creature it can see and fires
## short bolts at it. It can't be hurt (it flies above the fight).
## Model: models/companion_drone.glb, used as-is (long axis X, guns at -X).

const BoltScript = preload("res://scripts/bolt.gd")
const Sfx = preload("res://scripts/sfx.gd")
const GS = preload("res://scripts/game_state.gd")
const MODEL := "res://models/companion_drone.glb"
const SIZE := 0.75          # metres, wingtip to wingtip (the model is 1.9 units)
const RANGE := 24.0
const FIRE_GAP := 0.55
## Gun tips in model units (two cannons under the nose).
const GUNS := [Vector3(-0.62, -0.02, 0.27), Vector3(-0.62, -0.02, -0.27)]

var player
var damage := 7.0

var _visual: Node3D
var _light: OmniLight3D
var _target = null
var _think := 0.0
var _cd := 0.0
var _gun := 0
var _time := 0.0
var _yaw := 0.0


func _ready() -> void:
	top_level = true
	_visual = Node3D.new()
	add_child(_visual)
	if ResourceLoader.exists(MODEL):
		var m: Node3D = load(MODEL).instantiate()
		m.scale = Vector3.ONE * (SIZE / 1.9)
		# Model nose is -X; the drone's forward is -Z.
		m.rotation.y = -PI * 0.5
		_visual.add_child(m)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.25, 0.2)
	_light.light_energy = 0.0
	_light.omni_range = 3.0
	add_child(_light)
	damage = GS.drone_damage()
	if player != null:
		global_position = player.global_position + Vector3(0.8, 2.2, 0.6)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	_time += delta
	_cd -= delta
	_think -= delta
	damage = GS.drone_damage()
	_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 30.0)
	# Hover beside your right shoulder, a little behind.
	var fy: float = player._facing_yaw
	var right := Vector3(cos(fy), 0.0, -sin(fy))
	var back := Vector3(sin(fy), 0.0, cos(fy))
	var want: Vector3 = player.global_position + right * 0.95 + back * 0.6 + Vector3(0.0, 2.15 + sin(_time * 2.3) * 0.08, 0.0)
	global_position = global_position.lerp(want, clampf(delta * 4.0, 0.0, 1.0))
	if _think <= 0.0:
		_think = 0.25
		_target = _pick_target()
	var face := fy
	if _target != null and is_instance_valid(_target):
		var to: Vector3 = _target.global_position - global_position
		face = atan2(-to.x, -to.z)
		if _cd <= 0.0:
			_fire()
	_yaw = lerp_angle(_yaw, face, clampf(delta * 6.0, 0.0, 1.0))
	rotation = Vector3(0.0, _yaw, 0.0)
	_visual.rotation.z = sin(_time * 1.7) * 0.06


func _alive(e) -> bool:
	return e != null and is_instance_valid(e) and e.is_in_group("enemy") and not (e.has_method("is_dead") and e.is_dead())


func _pick_target():
	var best = null
	var bd := GS.drone_range() * GS.drone_range()
	var space := get_world_3d().direct_space_state
	for e in get_tree().get_nodes_in_group("enemy"):
		if not _alive(e):
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d >= bd:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position, e.global_position + Vector3.UP, 1)
		if not space.intersect_ray(q).is_empty():
			continue   # no line of sight
		bd = d
		best = e
	return best


func _fire() -> void:
	if not _alive(_target):
		_target = null
		return
	_cd = GS.drone_fire_gap() * randf_range(0.85, 1.15)
	var gun: Vector3 = GUNS[_gun % GUNS.size()]
	_gun += 1
	var from := global_transform * (Basis(Vector3.UP, -PI * 0.5) * (gun * (SIZE / 1.9)))
	var aim: Vector3 = _target.global_position + Vector3.UP * 1.0
	var bolt := BoltScript.new()
	get_parent().add_child(bolt)
	bolt.launch(from, aim, true, Color(1.0, 0.3, 0.2))
	_target.take_damage(damage, (aim - from).normalized())
	_light.global_position = from
	_light.light_energy = 3.0
	Sfx.at(from, "droid_blaster", -12.0, 0.1, 6.0)
