extends Node3D
## The female lead. Uses models/femalelead_rigged.glb (her Meshy model with a
## skeleton added for this game) and animates the bones in code.
## Modes: "idle" (standing, breathing), "drag" (bent over, both hands on
## the trooper's collar, walking backwards) and "sit" (sitting on the ground,
## knees up, forearms on her knees, e.g. by the campfire). Her rifle is slung on her back.

const BoltScript = preload("res://scripts/bolt.gd")
const Sfx = preload("res://scripts/sfx.gd")
const MODEL_PATH := "res://models/femalelead_rigged.glb"
const RIFLE_PATH := "res://models/ally_rifle.glb"
const HEIGHT := 1.72
const MODEL_UNITS_TALL := 1.9   # height of the model file

var mode := "idle"
## Ground speed in m/s, used to pace her steps.
var move_speed := 0.0

var _skel: Skeleton3D
var _bones := {}
var _gait := 0.0
var _time := 0.0
var _move_amt := 0.0
var _drag_amt := 0.0
var _sit_amt := 0.0
var _aim_amt := 0.0

## Follower / fighter (set with follow()). She keeps to your right, shoots
## the nearest creature with her rifle.
var player
var fire_range := 30.0
var fire_interval := 0.55
var damage := 12.0
var _cd := 0.0
var _target
var _rifle_back: Node3D
var _rifle_hands: Node3D
const SPEED := 4.6
const BOLT_COLOR := Color(1.0, 0.55, 0.15)


## Shown on the HUD's party bars while she follows you.
var party_id := "survivor"
var party_name := "SURVIVOR"
var max_health := 100.0
var health := 100.0


func follow(p) -> void:
	player = p
	mode = "idle"
	add_to_group("party_member")


func _ready() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		return
	var visual := Node3D.new()
	visual.rotation.y = PI  # the model faces +Z
	add_child(visual)
	var inst: Node3D = load(MODEL_PATH).instantiate()
	var s := HEIGHT / MODEL_UNITS_TALL
	inst.scale = Vector3.ONE * s
	inst.position.y = 0.95 * s
	visual.add_child(inst)
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	_skel = found[0]
	for i in _skel.get_bone_count():
		_bones[_skel.get_bone_name(i)] = i
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Rifle slung diagonally across her back.
	if ResourceLoader.exists(RIFLE_PATH) and _bones.has("Spine2"):
		var att := BoneAttachment3D.new()
		att.bone_name = "Spine2"
		_skel.add_child(att)
		var rifle: Node3D = load(RIFLE_PATH).instantiate()
		var rs := 0.95 / 1.9 / s   # 0.95 m long, in model units
		rifle.scale = Vector3.ONE * rs
		rifle.position = Vector3(0.0, -0.02, -0.17)
		rifle.rotation = Vector3(0.0, 0.0, deg_to_rad(-50.0))
		att.add_child(rifle)
		_rifle_back = rifle
		# A second copy held at the shoulder when she fights.
		_rifle_hands = load(RIFLE_PATH).instantiate()
		_rifle_hands.scale = Vector3.ONE * (0.95 / 1.9)
		_rifle_hands.visible = false
		add_child(_rifle_hands)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_cd -= delta
	# Keep up on your right, a step behind.
	var pm: Node3D = player.model
	var right: Vector3 = pm.global_transform.basis.x.normalized()
	var back: Vector3 = pm.global_transform.basis.z.normalized()
	var want: Vector3 = player.global_position + right * 1.9 + back * 1.2
	var to := want - global_position
	to.y = 0.0
	var dist := to.length()
	var speed := 0.0
	if dist > 0.6:
		speed = clampf(dist * 2.0, 0.0, SPEED * (1.6 if dist > 8.0 else 1.0))
		global_position += to.normalized() * minf(speed * delta, dist)
	if dist > 25.0:
		global_position = want  # fell too far behind
	move_speed = speed
	_snap_to_ground()

	_target = _pick_target()
	var face_dir := to if dist > 0.6 else -back
	if _target != null:
		face_dir = _target.global_position - global_position
		_try_fire()
	face_dir.y = 0.0
	if face_dir.length() > 0.01:
		var yaw := atan2(-face_dir.x, -face_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(10.0 * delta, 0.0, 1.0))
	_update_rifle()


func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 3.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0, 1))
	if not hit.is_empty():
		global_position.y = hit["position"].y


func _pick_target():
	if _target != null and is_instance_valid(_target) and not _target.is_dead() \
			and global_position.distance_to(_target.global_position) < fire_range + 4.0:
		return _target
	var best = null
	var best_d := fire_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.is_dead():
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _muzzle() -> Vector3:
	return global_position + Vector3.UP * 1.38 + (-global_transform.basis.z) * 0.75


func _try_fire() -> void:
	if _cd > 0.0 or _aim_amt < 0.8:
		return
	var aim: Vector3 = _target.global_position + Vector3.UP * 1.0
	var fwd := -global_transform.basis.z
	var to_t := aim - global_position
	to_t.y = 0.0
	if fwd.angle_to(to_t.normalized()) > deg_to_rad(20.0):
		return
	_cd = fire_interval * randf_range(0.85, 1.2)
	var from := _muzzle()
	_target.take_damage(damage, (aim - from).normalized())
	var bolt := BoltScript.new()
	get_parent().add_child(bolt)
	bolt.launch(from, aim, true, BOLT_COLOR)
	Sfx.at(from, "blaster", -8.0, 0.1, 7.0)


func _update_rifle() -> void:
	var fighting := _target != null and player != null
	if _rifle_back != null:
		_rifle_back.visible = not fighting
	if _rifle_hands != null:
		_rifle_hands.visible = fighting
		if fighting:
			# Shouldered: stock at the right shoulder, barrel forward.
			_rifle_hands.position = Vector3(0.12, 1.36, -0.25)
			_rifle_hands.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)


func _process(delta: float) -> void:
	if _skel == null:
		return
	_time += delta
	_move_amt = lerpf(_move_amt, clampf(move_speed / 1.4, 0.0, 1.0), clampf(6.0 * delta, 0.0, 1.0))
	_drag_amt = lerpf(_drag_amt, 1.0 if mode == "drag" else 0.0, clampf(4.0 * delta, 0.0, 1.0))
	_aim_amt = lerpf(_aim_amt, 1.0 if (_target != null and player != null) else 0.0, clampf(8.0 * delta, 0.0, 1.0))
	_sit_amt = 1.0 if mode == "sit" else lerpf(_sit_amt, 0.0, clampf(4.0 * delta, 0.0, 1.0))
	_gait += delta * (2.0 + move_speed * 3.2) * (1.0 if _move_amt > 0.05 else 0.0)

	var p := {}
	for n in _bones:
		p[n] = Vector3.ZERO

	# Breathing and a slow look around.
	var br := sin(_time * 1.9)
	p["Spine1"] += Vector3(br * 1.5, 0.0, 0.0)
	p["Spine2"] += Vector3(br * 1.5, 0.0, 0.0)
	p["Head"] += Vector3(sin(_time * 0.8) * 3.0, sin(_time * 0.5) * 12.0 * (1.0 - _drag_amt), 0.0)
	p["LeftArm"] += Vector3(0.0, 0.0, 6.0 + br)
	p["RightArm"] += Vector3(0.0, 0.0, -6.0 - br)

	# Dragging: bent at the hips, both hands forward and down on the collar.
	var d := _drag_amt
	var heave := sin(_gait * 2.0) * 0.5 + 0.5   # pulls on each step
	p["Spine"] += Vector3(32.0 * d + heave * 4.0 * d, 0.0, 0.0)
	p["Spine1"] += Vector3(14.0 * d, 0.0, 0.0)
	p["Spine2"] += Vector3(-4.0 * d, 0.0, 0.0)
	p["Neck"] += Vector3(-12.0 * d, 0.0, 0.0)
	p["Head"] += Vector3(-14.0 * d, 0.0, 0.0)
	p["LeftArm"] += Vector3(-38.0 * d, 0.0, -8.0 * d)
	p["RightArm"] += Vector3(-38.0 * d, 0.0, 8.0 * d)
	p["LeftForeArm"] += Vector3(-14.0 * d + heave * 6.0 * d, 0.0, 0.0)
	p["RightForeArm"] += Vector3(-14.0 * d + heave * 6.0 * d, 0.0, 0.0)
	p["LeftHand"] += Vector3(-20.0 * d, 0.0, 0.0)
	p["RightHand"] += Vector3(-20.0 * d, 0.0, 0.0)
	# Deep crouch so her hands are down at your waist.
	p["LeftUpLeg"] += Vector3(-40.0 * d, 0.0, 0.0)
	p["RightUpLeg"] += Vector3(-40.0 * d, 0.0, 0.0)
	p["LeftLeg"] += Vector3(78.0 * d, 0.0, 0.0)
	p["RightLeg"] += Vector3(78.0 * d, 0.0, 0.0)
	p["LeftFoot"] += Vector3(-38.0 * d, 0.0, 0.0)
	p["RightFoot"] += Vector3(-38.0 * d, 0.0, 0.0)

	# Aiming the rifle: both arms forward at shoulder height.
	var am := _aim_amt
	if am > 0.001:
		p["RightArm"] += Vector3(-80.0 * am, 0.0, 12.0 * am)
		p["RightForeArm"] += Vector3(-40.0 * am, -25.0 * am, 0.0)
		p["LeftArm"] += Vector3(-88.0 * am, 0.0, 30.0 * am)
		p["LeftForeArm"] += Vector3(-10.0 * am, 20.0 * am, 0.0)
		p["Head"] += Vector3(5.0 * am, 0.0, 0.0)

	# Sitting: knees drawn up, forearms resting on them, head turned to the fire.
	var st := _sit_amt
	if st > 0.001:
		for side in ["Left", "Right"]:
			var sx := 1.0 if side == "Left" else -1.0
			p[side + "UpLeg"] += Vector3(-95.0 * st, 0.0, sx * 8.0 * st)
			p[side + "Leg"] += Vector3(115.0 * st, 0.0, 0.0)
			p[side + "Foot"] += Vector3(-20.0 * st, 0.0, 0.0)
			p[side + "Arm"] += Vector3(-38.0 * st, 0.0, -sx * 4.0 * st)
			p[side + "ForeArm"] += Vector3(-55.0 * st, sx * 20.0 * st, 0.0)
		p["Spine"] += Vector3(14.0 * st, 0.0, 0.0)
		p["Spine1"] += Vector3(6.0 * st, 0.0, 0.0)
		p["Head"] += Vector3(10.0 * st, 0.0, 0.0)

	# Walking (backwards while dragging): legs swing, knees lift.
	var m := _move_amt
	if m > 0.01:
		var dir := -1.0 if mode == "drag" else 1.0
		_leg(p, "Left", _gait, m, dir)
		_leg(p, "Right", _gait + PI, m, dir)
		p["Hips"] += Vector3(0.0, sin(_gait) * 5.0 * m, sin(_gait) * 3.0 * m)

	for n in p:
		var e: Vector3 = p[n] * (PI / 180.0)
		_skel.set_bone_pose_rotation(_bones[n], Quaternion.from_euler(e))
	var hips: int = _bones.get("Hips", -1)
	if hips >= 0:
		var bob := -absf(sin(_gait)) * 0.03 * m - 0.22 * d - 0.78 * _sit_amt
		_skel.set_bone_pose_position(hips, _skel.get_bone_rest(hips).origin + Vector3(0.0, bob / (HEIGHT / MODEL_UNITS_TALL), 0.0))


## dir = 1 walking forwards, -1 backwards.
func _leg(p: Dictionary, side: String, phase: float, amt: float, dir: float) -> void:
	var s := sin(phase)
	var lift := maxf(0.0, cos(phase))
	p[side + "UpLeg"] += Vector3(-s * 28.0 * amt * dir - lift * 10.0 * amt, 0.0, 0.0)
	p[side + "Leg"] += Vector3(lift * 40.0 * amt, 0.0, 0.0)
	p[side + "Foot"] += Vector3((s * 10.0 * dir - lift * 15.0) * amt, 0.0, 0.0)
