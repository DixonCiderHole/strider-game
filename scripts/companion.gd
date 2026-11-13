extends CharacterBody3D
const GS = preload("res://scripts/game_state.gd")
## The salvaged droid: follows you, fights creatures, and takes orders.
##   1  Follow me        2  Hold position
##   3  Go there / attack what the crosshair is on
##   4  Toggle weapons free / hold fire
##
## Animation is procedural (no keyframes): the model is split into a body,
## two cannon arms (pivot at the shoulder) and four lower legs (pivot at the knee).

signal status_changed(order_text: String, weapons_free: bool)

const U = preload("res://scripts/util.gd")
const BoltScript = preload("res://scripts/bolt.gd")
const Sfx = preload("res://scripts/sfx.gd")
const MODEL_PATH := "res://models/droid_parts.glb"
const BOLT_COLOR := Color(0.3, 0.75, 1.0)
const ARM_MAX_TURN := deg_to_rad(45.0)    # how far the cannons can swing from rest
const AIM_TOLERANCE := deg_to_rad(10.0)   # cannon must be this close to the target to fire

enum Order { FOLLOW, HOLD, MOVE, ATTACK }

## Turn this if the droid walks sideways or backwards.
@export var model_yaw_offset_deg := 180.0
@export var height := 1.5
@export var speed := 5.0
@export var fire_range := 28.0
@export var fire_interval := 0.45
@export var damage := 14.0

## Shown on the HUD's party bars.
var party_id := "droid"
var party_name := "STRIDER DROID"
var max_health := 100.0
var health := 100.0
## Shown in a menu portrait only: just idles, no AI, no party bars.
var display_only := false
var player
var order := Order.FOLLOW
var weapons_free := true
var hold_pos := Vector3.ZERO
var focus_target = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var model: Node3D
var visual: Node3D
var _model_root: Node3D
var _eye: OmniLight3D

# Parts
var _legs: Array = []    # {node, rest, phase, side, tap}
var _arms: Array = []    # {node, rest, muzzle, side, rot: Quaternion, recoil}
var _next_arm := 0

# Timers / state
var _cd := 0.0
## Fires in quick bursts like a heavy repeater. Same damage over time as one
## full shot every fire_interval: each bolt does BOLT_MULT of the droid's
## damage, four to a burst, then a pause.
const BURST := 4
const BOLT_MULT := 0.6
var _burst_left := 0
var _gait_t := 0.0
var _time := 0.0
var _last_yaw := 0.0
var _side := 1.0
var _strafe_timer := 0.0
var _idle_tap_timer := 3.0
var _target = null


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	if display_only:
		collision_layer = 0
		collision_mask = 0
	else:
		add_to_group("companion")
		add_to_group("party_member")
		# Droid-parts station modules.
		max_health *= GS.droid_health_mult()
		health = max_health
		fire_interval /= GS.droid_fire_rate_mult()
		var talk = load("res://scripts/talk_point.gd").new()
		talk.name = "Talk"
		talk.who = "droid"
		talk.member = self
		add_child(talk)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.4
	cs.shape = cap
	cs.position.y = 0.7
	add_child(cs)

	model = Node3D.new()
	add_child(model)
	visual = Node3D.new()
	model.add_child(visual)
	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(model_yaw_offset_deg)
	visual.add_child(holder)

	if ResourceLoader.exists(MODEL_PATH):
		var inst: Node3D = load(MODEL_PATH).instantiate()
		holder.add_child(inst)
		U.fit(inst, height, 1, true)
		_model_root = inst
		_collect_parts(inst)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 1.0, 1.4)
		mi.mesh = bm
		mi.position.y = 0.8
		mi.material_override = U.mat(Color(0.2, 0.22, 0.25), 0.4)
		holder.add_child(mi)

	var box := U.collect_aabb(visual)
	_eye = OmniLight3D.new()
	_eye.light_color = BOLT_COLOR
	_eye.light_energy = 1.5
	_eye.omni_range = 2.5
	_eye.position = Vector3(0.0, box.position.y + box.size.y * 0.9, box.position.z * 0.4)
	visual.add_child(_eye)

	_side = 1.0 if randf() < 0.5 else -1.0
	_emit_status()


func _collect_parts(inst: Node3D) -> void:
	# Diagonal pairs step together: left-front + right-back, then the other two.
	var phases := {"Leg_LF": 0.0, "Leg_RB": 0.0, "Leg_RF": PI, "Leg_LB": PI}
	for leg_name in phases:
		var n := inst.find_child(leg_name, true, false) as Node3D
		if n != null:
			_legs.append({
				"node": n, "rest": n.transform, "phase": phases[leg_name],
				"side": 1.0 if String(leg_name).begins_with("Leg_L") else -1.0, "tap": 0.0,
			})
	for arm_name in ["Arm_L", "Arm_R"]:
		var a := inst.find_child(arm_name, true, false) as Node3D
		if a == null:
			continue
		var m := a.find_child("Muzzle_" + arm_name.right(1), true, false) as Node3D
		_arms.append({
			"node": a, "rest": a.transform, "muzzle": m,
			"side": 1.0 if arm_name == "Arm_L" else -1.0,
			"rot": Quaternion.IDENTITY, "recoil": 0.0,
		})


# ------------------------------------------------------------ orders

func order_follow() -> void:
	order = Order.FOLLOW
	focus_target = null
	_emit_status()


func order_hold() -> void:
	order = Order.HOLD
	hold_pos = global_position
	focus_target = null
	_emit_status()


## Order 3: attack the creature under the crosshair, or move to where it points.
func order_go(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var col = hit.get("collider")
	if col != null and col.is_in_group("enemy"):
		order = Order.ATTACK
		focus_target = col
		weapons_free = true
	else:
		order = Order.MOVE
		hold_pos = hit["position"]
		focus_target = null
		_spawn_marker(hold_pos)
	_emit_status()


func toggle_weapons() -> void:
	weapons_free = not weapons_free
	_emit_status()


func order_text() -> String:
	match order:
		Order.FOLLOW:
			return "FOLLOWING"
		Order.HOLD:
			return "HOLDING POSITION"
		Order.MOVE:
			return "MOVING TO POINT"
		Order.ATTACK:
			return "ATTACKING TARGET"
	return ""


func _emit_status() -> void:
	status_changed.emit(order_text(), weapons_free)


# ------------------------------------------------------------ behaviour

func _physics_process(delta: float) -> void:
	_time += delta
	if display_only:
		velocity = Vector3.ZERO
		_animate(delta)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if player == null or not is_instance_valid(player):
		return

	if order == Order.ATTACK and not _valid_enemy(focus_target):
		order = Order.FOLLOW
		focus_target = null
		_emit_status()

	_target = _pick_target()

	# Where to stand.
	var goal := global_position
	var stop_dist := 1.0
	match order:
		Order.FOLLOW:
			# On the player's left, level with them, clear of the over-the-shoulder camera.
			goal = player.global_position + player.model.global_transform.basis * Vector3(-2.6, 0.0, 0.4)
			stop_dist = 1.5
			if global_position.distance_to(player.global_position) > 35.0:
				global_position = player.global_position + Vector3(-2.0, 0.5, 2.0)
		Order.HOLD, Order.MOVE:
			goal = hold_pos
		Order.ATTACK:
			var tp: Vector3 = focus_target.global_position
			var away := global_position - tp
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3.BACK
			goal = tp + away.normalized() * 10.0
			stop_dist = 3.0

	var to_goal := goal - global_position
	to_goal.y = 0.0
	var desired := Vector3.ZERO
	if to_goal.length() > stop_dist:
		var spd := speed * (1.6 if to_goal.length() > 10.0 else 1.0)
		desired = to_goal.normalized() * spd
		if is_on_wall():
			desired += to_goal.normalized().cross(Vector3.UP) * _side * spd

	# In a fight: keep facing the target and side-step around it, backing off if it's too close.
	if _target != null:
		var to_t: Vector3 = _target.global_position - global_position
		to_t.y = 0.0
		var dist := to_t.length()
		var t_dir := to_t.normalized() if dist > 0.01 else Vector3.FORWARD
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.8, 3.5)
			_side = -_side
		var strafe := t_dir.cross(Vector3.UP) * _side * speed * 0.45
		if order == Order.HOLD:
			strafe *= 0.4   # holding: only small shuffles
		desired += strafe
		if dist < 5.0:
			desired -= t_dir * speed * 0.8
		if desired.length() > speed * 1.6:
			desired = desired.normalized() * speed * 1.6

	var t := clampf(5.0 * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, desired.x, t)
	velocity.z = lerpf(velocity.z, desired.z, t)
	move_and_slide()

	# Body facing: the target if there is one, else where we're walking, else match the player.
	var face_dir := Vector3.ZERO
	if _target != null:
		face_dir = _target.global_position - global_position
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		face_dir = Vector3(velocity.x, 0.0, velocity.z)
	elif order == Order.FOLLOW:
		face_dir = -player.model.global_transform.basis.z
	face_dir.y = 0.0
	if face_dir.length() > 0.05:
		var yaw := atan2(-face_dir.x, -face_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, yaw, clampf(4.0 * delta, 0.0, 1.0))

	_animate(delta)

	_cd -= delta
	if _target != null and _cd <= 0.0:
		_try_fire(_target)


func _valid_enemy(e) -> bool:
	return e != null and is_instance_valid(e) and e.is_in_group("enemy") \
			and not (e.has_method("is_dead") and e.is_dead())


func _pick_target():
	if not weapons_free:
		return null
	if order == Order.ATTACK and _valid_enemy(focus_target):
		if global_position.distance_to(focus_target.global_position) <= fire_range:
			return focus_target
		return null
	# Stick with the current target while it's valid, so the arms don't flick around.
	if _valid_enemy(_target) and global_position.distance_to(_target.global_position) <= fire_range:
		return _target
	var best = null
	var best_d := fire_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not _valid_enemy(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d and _has_line_of_sight(e):
			best_d = d
			best = e
	return best


func _has_line_of_sight(e) -> bool:
	var from := global_position + Vector3(0.0, 1.1, 0.0)
	var to: Vector3 = e.global_position + Vector3(0.0, 1.1, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _aim_point(target) -> Vector3:
	return target.global_position + Vector3(0.0, 1.1, 0.0)


## Fires the next cannon in turn, but only once that arm is actually on target.
func _try_fire(target) -> void:
	if _arms.is_empty():
		return
	for i in _arms.size():
		var arm: Dictionary = _arms[(_next_arm + i) % _arms.size()]
		var m: Node3D = arm["muzzle"]
		if m == null:
			continue
		var node: Node3D = arm["node"]
		var barrel_dir := (m.global_position - node.global_position).normalized()
		var to_t := (_aim_point(target) - m.global_position).normalized()
		if barrel_dir.angle_to(to_t) > AIM_TOLERANCE:
			continue
		_next_arm = (_next_arm + i + 1) % _arms.size()
		if _burst_left <= 0:
			_burst_left = BURST
		_burst_left -= 1
		# 0.12 s between shots, then a pause (at the base rate of fire).
		_cd = fire_interval * (0.27 if _burst_left > 0 else 1.6)
		var from := m.global_position
		var aim := _aim_point(target)
		target.take_damage(damage * BOLT_MULT, (aim - from).normalized())
		var bolt := BoltScript.new()
		get_parent().add_child(bolt)
		bolt.launch(from, aim, true, BOLT_COLOR)
		Sfx.at(from, "droid_blaster", -6.0, 0.08, 7.0)
		Sfx.at(aim, "impact", -10.0, 0.15, 6.0)
		arm["recoil"] = 1.0
		_eye.light_energy = 4.0
		return


# ------------------------------------------------------------ animation

func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	# Turning on the spot also makes the legs shuffle.
	var yaw_rate := absf(wrapf(model.rotation.y - _last_yaw, -PI, PI)) / maxf(delta, 0.0001)
	_last_yaw = model.rotation.y
	var drive := maxf(hspeed, yaw_rate * 0.8)
	var amt := clampf(drive / speed, 0.0, 1.0)
	if drive > 0.2:
		_gait_t += delta * (4.0 + drive * 1.6)

	# Body: walking bob and sway, or a slow "breathing" rise and fall when still.
	var breathe := sin(_time * 1.7) * 0.012 * (1.0 - amt)
	visual.position.y = absf(sin(_gait_t)) * 0.05 * amt + breathe
	visual.rotation.z = sin(_gait_t) * 0.025 * amt + sin(_time * 0.6) * 0.008 * (1.0 - amt)

	_animate_legs(delta, amt)
	_animate_arms(delta, amt)
	_eye.light_energy = move_toward(_eye.light_energy, 1.5, delta * 8.0)


## Each lower leg swings from its knee in the direction of travel and lifts on
## the way forward. When idle, a random leg occasionally shifts its weight.
func _animate_legs(delta: float, amt: float) -> void:
	if _legs.is_empty() or _model_root == null:
		return
	var local_v := _model_root.global_transform.basis.orthonormalized().inverse() * Vector3(velocity.x, 0.0, velocity.z)
	local_v.y = 0.0
	var dir := local_v.normalized() if local_v.length() > 0.2 else Vector3.BACK
	var swing_axis := Vector3.UP.cross(dir).normalized()

	if amt < 0.05:
		_idle_tap_timer -= delta
		if _idle_tap_timer <= 0.0:
			_idle_tap_timer = randf_range(3.0, 6.5)
			_legs[randi() % _legs.size()]["tap"] = 1.0

	for leg in _legs:
		var ph: float = _gait_t + leg["phase"]
		var swing := sin(ph) * 0.45 * amt
		var lift := maxf(0.0, cos(ph)) * 0.4 * amt
		var tap: float = leg["tap"]
		lift += sin(tap * PI) * 0.25          # idle weight shift: quick lift and set down
		leg["tap"] = move_toward(tap, 0.0, delta * 2.2)
		var b := Basis(Vector3.BACK, lift * leg["side"]) * Basis(swing_axis, -swing)
		var rest: Transform3D = leg["rest"]
		leg["node"].transform = Transform3D(b * rest.basis, rest.origin)


## Cannon arms: track the target (each fires from its own barrel), otherwise
## sway with the walk or slowly scan the area when idle. Shots kick them back.
func _animate_arms(delta: float, amt: float) -> void:
	if _arms.is_empty():
		return
	for arm in _arms:
		var node: Node3D = arm["node"]
		var parent_inv := (node.get_parent() as Node3D).global_transform.affine_inverse()
		var rest: Transform3D = arm["rest"]
		var m: Node3D = arm["muzzle"]
		var side: float = arm["side"]
		var want := Quaternion.IDENTITY
		if _target != null and m != null:
			# Barrel direction at rest, and direction to the target, in the model's space.
			var rest_dir := (rest.basis * m.position).normalized()
			var pivot := rest.origin
			var tgt_local := parent_inv * _aim_point(_target)
			var to_t := (tgt_local - pivot).normalized()
			want = Quaternion(rest_dir, to_t)
			var ang := want.get_angle()
			if ang > ARM_MAX_TURN:
				want = Quaternion.IDENTITY.slerp(want, ARM_MAX_TURN / ang)
		else:
			# Walking: arms rock with the stride. Idle: slow scanning look-around.
			var sway := sin(_gait_t + (0.0 if side > 0.0 else PI)) * 0.08 * amt
			var scan_yaw := sin(_time * 0.45 + side * 1.3) * 0.22 * (1.0 - amt)
			var scan_pitch := sin(_time * 0.7 + side) * 0.06 * (1.0 - amt)
			want = Quaternion(Vector3.UP, scan_yaw) * Quaternion(Vector3.RIGHT, sway + scan_pitch)
		var cur: Quaternion = arm["rot"]
		cur = cur.slerp(want, clampf(7.0 * delta, 0.0, 1.0))
		arm["rot"] = cur

		# Recoil: kick back along the barrel and tip up slightly.
		var recoil: float = arm["recoil"]
		arm["recoil"] = move_toward(recoil, 0.0, delta * 5.0)
		var barrel := (rest.basis * (m.position if m != null else Vector3.BACK)).normalized()
		var kick_axis := barrel.cross(Vector3.UP).normalized()
		var kick := Quaternion(kick_axis, -recoil * 0.12) if kick_axis.length() > 0.01 else Quaternion.IDENTITY
		var b := Basis(kick * cur) * rest.basis
		node.transform = Transform3D(b, rest.origin - barrel * recoil * 0.06)


func _spawn_marker(pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.7
	ring.mesh = tm
	var m := U.mat(BOLT_COLOR, 0.5, BOLT_COLOR, 3.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = pos + Vector3(0.0, 0.05, 0.0)
	var tw := ring.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 1.5)
	tw.tween_callback(ring.queue_free)
