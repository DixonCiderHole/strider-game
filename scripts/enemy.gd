extends CharacterBody3D
## Native creature ("Crimson Ravager"). Uses models/creature_rigged.glb, a
## skinned version of the creaturegame.glb model, and animates its bones in code:
## run cycle, idle breathing, a roar on spawn, three attacks (single blade
## slash, double cross slash, pounce), hit flinch and a death collapse.

signal died

const MODEL := preload("res://models/creature_rigged.glb")
const Sfx = preload("res://scripts/sfx.gd")
const GS = preload("res://scripts/game_state.gd")
const Pickup = preload("res://scripts/pickup.gd")
const MODEL_HEIGHT := 2.0      # metres, standing in its hunched pose
const ATTACK_HIT_RANGE := 2.6  # how far the blades reach from the creature's centre

enum State { ROAR, CHASE, ATTACK, POUNCE, DEAD }
enum Atk { SLASH_L, SLASH_R, CROSS }

var target  # the player node
var speed := 4.4
var health := 40.0
var attack_range := 2.1
var attack_damage := 12.0
var attack_cooldown := 1.1

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _state := State.ROAR
var _state_t := 0.0
var _cd := 0.6
var _pounce_cd := 0.0
var _side := 1.0
var _dead := false

var _visual: Node3D
var _skel: Skeleton3D
var _mesh: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _bones := {}

# animation state
var _gait := 0.0          # run-cycle phase (radians)
var _move_amt := 0.0      # 0 standing .. 1 full run, smoothed
var _time := 0.0
var _atk := Atk.SLASH_R
var _atk_hit_done := false
var _flinch := 0.0        # spring value, jolts back when hit
var _flinch_v := 0.0
var _flinch_side := 0.0
var _death := 0.0         # 0..1 collapse progress
var _death_side := 1.0
var _land_hit := false
var _look_yaw := 0.0
var _whoosh_done := false
var _hurt_cd := 0.0


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 2.0
	cs.shape = cap
	cs.position.y = 1.0
	add_child(cs)
	_side = 1.0 if randf() < 0.5 else -1.0
	_time = randf() * 10.0
	_pounce_cd = randf_range(2.0, 5.0)
	_build_body()
	# Not every creature roars, so a wave doesn't freeze in place.
	_set_state(State.ROAR if randf() < 0.6 else State.CHASE)


func _build_body() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var inst: Node3D = MODEL.instantiate()
	_visual.add_child(inst)
	# Model is 1.48 units tall with its feet at y = -0.73 and faces +Z;
	# the creature node faces -Z, so turn it round.
	var s := MODEL_HEIGHT / 1.48
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(0.0, 0.735 * s, 0.0)
	_visual.rotation.y = PI

	_skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_bones[_skel.get_bone_name(i)] = i
	_mesh = inst.find_children("*", "MeshInstance3D", true, false)[0]

	# Red flash when hit: an additive overlay faded in and out.
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.25, 0.15, 0.0)
	_mesh.material_overlay = _flash_mat


func _set_state(s: State) -> void:
	_state = s
	_state_t = 0.0
	if not is_inside_tree():
		return
	match s:
		State.ROAR:
			Sfx.at(global_position + Vector3.UP, "roar", -2.0, 0.12, 10.0, 0.4)
		State.ATTACK:
			_whoosh_done = false
			Sfx.at(global_position + Vector3.UP, "snarl", -6.0, 0.15, 7.0, 0.15)
		State.POUNCE:
			Sfx.at(global_position + Vector3.UP, "snarl", -3.0, 0.1, 8.0)


# ---------------------------------------------------------------- behaviour

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	_state_t += delta
	_cd -= delta
	_pounce_cd -= delta
	_hurt_cd -= delta

	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		return

	var player_alive: bool = target != null and is_instance_valid(target) and not target.is_dead
	var to_target := Vector3.ZERO
	var dist := INF
	if player_alive:
		to_target = target.global_position - global_position
		to_target.y = 0.0
		dist = to_target.length()

	var desired := Vector3.ZERO
	var turn_rate := 10.0
	match _state:
		State.ROAR:
			turn_rate = 4.0
			if _state_t > 1.3:
				_set_state(State.CHASE)
		State.CHASE:
			if player_alive:
				if dist > attack_range * 0.8:
					desired = to_target.normalized() * speed
					if is_on_wall():
						desired += to_target.normalized().cross(Vector3.UP) * _side * speed
				if dist <= attack_range and _cd <= 0.0:
					_start_attack()
				elif dist > 4.5 and dist < 9.0 and _pounce_cd <= 0.0 and is_on_floor():
					if randf() < 0.45:
						_set_state(State.POUNCE)
						_land_hit = false
					_pounce_cd = randf_range(4.0, 7.0)
		State.ATTACK:
			turn_rate = 5.0
			# Small step into the swing.
			var lunge := 1.8 if _state_t > _atk_windup() and _state_t < _atk_windup() + 0.15 else 0.0
			desired = -global_transform.basis.z * lunge
			if not _whoosh_done and _state_t >= _atk_windup() - 0.05:
				_whoosh_done = true
				Sfx.at(global_position + Vector3.UP, "whoosh", -4.0, 0.15, 6.0)
			if not _atk_hit_done and _state_t >= _atk_windup() + 0.08:
				_atk_hit_done = true
				_deal_damage(attack_damage * (1.35 if _atk == Atk.CROSS else 1.0), ATTACK_HIT_RANGE)
			if _state_t >= _atk_length():
				_cd = attack_cooldown * randf_range(0.8, 1.3)
				_set_state(State.CHASE)
		State.POUNCE:
			turn_rate = 8.0 if _state_t < 0.4 else 0.0
			if _state_t < 0.4:
				pass  # crouch, coiling up
			elif _state_t < 0.45 and is_on_floor():
				var dir := to_target.normalized() if player_alive else -global_transform.basis.z
				var leap := clampf(dist * 1.5, 7.0, 12.0)
				velocity = dir * leap + Vector3.UP * 4.8
				_state_t = 0.45
			elif _state_t > 0.6 and is_on_floor():
				if not _land_hit:
					_land_hit = true
					Sfx.at(global_position, "slam", -2.0, 0.1, 9.0)
					_deal_damage(attack_damage * 1.4, ATTACK_HIT_RANGE)
					_state_t = 0.6
				if _state_t > 1.15:
					_cd = 0.6
					_set_state(State.CHASE)

	var leaping := _state == State.POUNCE and _state_t >= 0.4 and not _land_hit
	if not leaping:
		var t := clampf(6.0 * delta, 0.0, 1.0)
		if _state == State.POUNCE and _land_hit:
			t = clampf(12.0 * delta, 0.0, 1.0)
		velocity.x = lerpf(velocity.x, desired.x, t)
		velocity.z = lerpf(velocity.z, desired.z, t)
	move_and_slide()

	if to_target.length() > 0.1 and turn_rate > 0.0:
		var yaw := atan2(-to_target.x, -to_target.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_rate * delta, 0.0, 1.0))


func _start_attack() -> void:
	var r := randf()
	if r < 0.3:
		_atk = Atk.CROSS
	elif r < 0.65:
		_atk = Atk.SLASH_R
	else:
		_atk = Atk.SLASH_L
	_atk_hit_done = false
	_set_state(State.ATTACK)


func _atk_windup() -> float:
	return 0.38 if _atk == Atk.CROSS else 0.3


func _atk_length() -> float:
	return 1.0 if _atk == Atk.CROSS else 0.8


func _deal_damage(amount: float, reach: float) -> void:
	if _dead or target == null or not is_instance_valid(target) or target.is_dead:
		return
	var d: Vector3 = target.global_position - global_position
	d.y = 0.0
	if d.length() > reach:
		return
	# Blades only hit what's in front.
	var fwd := -global_transform.basis.z
	if d.length() > 0.8 and fwd.dot(d.normalized()) < 0.3:
		return
	target.take_damage(amount, d.normalized())


var max_health := 0.0   # set from health the first time it's hurt (for Executioner)

func take_damage(amount: float, from_dir := Vector3.ZERO) -> void:
	if _dead:
		return
	if max_health <= 0.0:
		max_health = health
	health -= amount
	if health > 0.0 and _hurt_cd <= 0.0:
		_hurt_cd = 0.35
		Sfx.at(global_position + Vector3.UP, "creature_hurt", -6.0, 0.15, 7.0, 0.08)
	if _state != State.POUNCE:
		velocity += Vector3(from_dir.x, 0.0, from_dir.z) * 2.0
	_flinch_v -= 9.0
	_flinch_side = randf_range(-1.0, 1.0)
	_flash_mat.albedo_color.a = 0.55
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	_set_state(State.DEAD)
	Sfx.at(global_position + Vector3.UP, "creature_death", -2.0, 0.12, 9.0)
	GS.add_xp(8)
	_drop_loot.call_deferred()
	_death_side = 1.0 if randf() < 0.5 else -1.0
	collision_layer = 0
	collision_mask = 1
	remove_from_group("enemy")
	died.emit()
	var tw := create_tween()
	tw.tween_property(self, "_death", 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(2.5)
	tw.tween_property(_visual, "position:y", -1.2, 1.4)
	tw.tween_callback(queue_free)


func is_dead() -> bool:
	return _dead


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if _skel == null:
		return
	_time += delta
	_flash_mat.albedo_color.a = move_toward(_flash_mat.albedo_color.a, 0.0, delta * 3.5)
	# Flinch spring.
	_flinch_v += (-_flinch * 120.0 - _flinch_v * 14.0) * delta
	_flinch += _flinch_v * delta

	var hspeed := Vector2(velocity.x, velocity.z).length()
	var airborne := _state == State.POUNCE and _state_t >= 0.45 and not _land_hit
	var moving := 0.0 if airborne else clampf(hspeed / 4.5, 0.0, 1.0)
	_move_amt = lerpf(_move_amt, moving, clampf(8.0 * delta, 0.0, 1.0))
	_gait += delta * (3.0 + hspeed * 1.7) * (1.0 if _move_amt > 0.05 else 0.0)

	var p := {}  # bone -> Vector3 euler degrees
	for n in _bones:
		p[n] = Vector3.ZERO
	var root_off := Vector3.ZERO

	_pose_idle(p)
	_pose_run(p, _move_amt)
	match _state:
		State.ROAR:
			_pose_roar(p)
		State.ATTACK:
			_pose_attack(p)
		State.POUNCE:
			root_off.y += _pose_pounce(p)
	# Flinch: rock the upper body back.
	p["Chest"] += Vector3(_flinch * 3.0, _flinch_side * _flinch * 2.0, 0.0)
	p["Head"] += Vector3(_flinch * 3.5, 0.0, _flinch_side * _flinch * 2.0)
	p["Spine"] += Vector3(_flinch * 1.5, 0.0, 0.0)
	if _death > 0.0:
		root_off += _pose_death(p, _death)
	root_off.y += -absf(sin(_gait)) * 0.05 * _move_amt

	for n in p:
		var e: Vector3 = p[n] * (PI / 180.0)
		_skel.set_bone_pose_rotation(_bones[n], Quaternion.from_euler(e))
	# Whole-body offset (hips are the root bone), in model units.
	var hips: int = _bones["Hips"]
	_skel.set_bone_pose_position(hips, _skel.get_bone_rest(hips).origin + root_off / (MODEL_HEIGHT / 1.48))


func _pose_idle(p: Dictionary) -> void:
	var breathe := sin(_time * 2.2)
	p["Chest"] += Vector3(breathe * 3.0, 0.0, 0.0)
	p["Spine"] += Vector3(breathe * 1.5, 0.0, 0.0)
	p["ArmL"] += Vector3(breathe * -3.0, 0.0, breathe * 2.0)
	p["ArmR"] += Vector3(breathe * -3.0, 0.0, -breathe * 2.0)
	# Twitchy head and blade fidgets.
	_look_yaw = lerpf(_look_yaw, sin(_time * 0.7) * 20.0 + sin(_time * 3.1) * 4.0, 0.1)
	p["Head"] += Vector3(sin(_time * 1.3) * 5.0, _look_yaw * (1.0 - _move_amt), sin(_time * 0.9) * 6.0)
	p["BladeL"] += Vector3(sin(_time * 1.7) * 4.0, 0.0, 0.0)
	p["BladeR"] += Vector3(sin(_time * 1.9 + 1.0) * 4.0, 0.0, 0.0)


func _leg(p: Dictionary, thigh: String, shin: String, foot: String, phase: float, amt: float, swing: float) -> void:
	var s := sin(phase)
	var lift := maxf(0.0, cos(phase))  # knee bends while the leg swings forward
	p[thigh] += Vector3(-s * swing * amt, 0.0, 0.0)
	p[shin] += Vector3(lift * 45.0 * amt, 0.0, 0.0)
	p[foot] += Vector3((s * swing - lift * 30.0) * amt, 0.0, 0.0)


func _pose_run(p: Dictionary, amt: float) -> void:
	if amt < 0.01:
		return
	var g := _gait
	_leg(p, "ThighR", "ShinR", "FootR", g, amt, 38.0)
	_leg(p, "ThighF", "ShinF", "FootF", g + PI, amt, 38.0)
	_leg(p, "ThighB", "ShinB", "FootB", g + PI * 0.5, amt, 30.0)
	# Lean into the run, rock the hips and swing the blades.
	p["Hips"] += Vector3(8.0 * amt, sin(g) * 6.0 * amt, sin(g) * 4.0 * amt)
	p["Spine"] += Vector3(6.0 * amt, -sin(g) * 4.0 * amt, 0.0)
	p["Chest"] += Vector3(4.0 * amt, -sin(g) * 6.0 * amt, 0.0)
	p["Head"] += Vector3(-12.0 * amt, sin(g) * 3.0 * amt, 0.0)
	p["ArmL"] += Vector3(-sin(g) * 22.0 * amt - 10.0 * amt, 0.0, 0.0)
	p["ArmR"] += Vector3(sin(g) * 22.0 * amt - 10.0 * amt, 0.0, 0.0)
	p["BladeL"] += Vector3(-15.0 * amt, 0.0, 0.0)
	p["BladeR"] += Vector3(-15.0 * amt, 0.0, 0.0)


func _pose_roar(p: Dictionary) -> void:
	var t := _state_t
	# Rear up, spread the blades, shake the head; ease out at the end.
	var w := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(1.0, 1.3, t))
	var shake := sin(t * 40.0) * 4.0 * smoothstep(0.3, 0.45, t)
	p["Spine"] += Vector3(-14.0 * w, 0.0, 0.0)
	p["Chest"] += Vector3(-16.0 * w, 0.0, 0.0)
	p["Head"] += Vector3(-30.0 * w + shake, shake * 0.5, 0.0)
	p["ArmL"] += Vector3(-55.0 * w, 0.0, -35.0 * w)
	p["ArmR"] += Vector3(-55.0 * w, 0.0, 35.0 * w)
	p["BladeL"] += Vector3(-30.0 * w, 0.0, 0.0)
	p["BladeR"] += Vector3(-30.0 * w, 0.0, 0.0)
	p["ShinR"] += Vector3(12.0 * w, 0.0, 0.0)
	p["ShinF"] += Vector3(12.0 * w, 0.0, 0.0)


## Wind-up -> strike -> recover, shaped as a 0..1 raise and a 0..1 strike.
func _swing_curve(t: float, windup: float, strike: float, length: float) -> Vector2:
	var raise := 0.0
	var hit := 0.0
	if t < windup:
		raise = ease(t / windup, 0.5)
	elif t < windup + strike:
		var k := (t - windup) / strike
		raise = 1.0 - k
		hit = k
	else:
		var k := clampf((t - windup - strike) / (length - windup - strike), 0.0, 1.0)
		hit = 1.0 - smoothstep(0.0, 1.0, k)
	return Vector2(raise, hit)


func _pose_attack(p: Dictionary) -> void:
	var c := _swing_curve(_state_t, _atk_windup(), 0.12, _atk_length())
	var raise := c.x
	var hit := c.y
	var arms: Array = []
	match _atk:
		Atk.SLASH_L:
			arms = ["L"]
		Atk.SLASH_R:
			arms = ["R"]
		Atk.CROSS:
			arms = ["L", "R"]
	for a in arms:
		var inward := 1.0 if a == "L" else -1.0
		p["Arm" + a] += Vector3(-110.0 * raise + 40.0 * hit, -inward * 25.0 * raise + inward * 30.0 * hit, -inward * 20.0 * raise)
		p["Blade" + a] += Vector3(-45.0 * raise + 25.0 * hit, 0.0, 0.0)
	# Body twists away during the wind-up and whips through on the strike.
	var twist := 0.0
	if _atk == Atk.SLASH_L:
		twist = -1.0
	elif _atk == Atk.SLASH_R:
		twist = 1.0
	p["Chest"] += Vector3(-12.0 * raise + 14.0 * hit, twist * (15.0 * raise - 22.0 * hit), 0.0)
	p["Spine"] += Vector3(-6.0 * raise + 10.0 * hit, twist * (8.0 * raise - 10.0 * hit), 0.0)
	p["Head"] += Vector3(-10.0 * raise + 8.0 * hit, 0.0, 0.0)
	# Brace the legs on the strike.
	p["ShinR"] += Vector3(15.0 * hit, 0.0, 0.0)
	p["ShinF"] += Vector3(15.0 * hit, 0.0, 0.0)
	p["ThighR"] += Vector3(-10.0 * hit, 0.0, 0.0)
	p["ThighF"] += Vector3(-10.0 * hit, 0.0, 0.0)


## Returns a vertical body offset (metres).
func _pose_pounce(p: Dictionary) -> float:
	var t := _state_t
	var crouch := 0.0
	var air := 0.0
	var land := 0.0
	if t < 0.4:
		crouch = smoothstep(0.0, 0.4, t)
	elif not _land_hit:
		air = 1.0
	else:
		land = 1.0 - smoothstep(0.6, 1.15, t)
		crouch = land * 0.7
	# Coil: legs fold, blades pulled back.
	for leg in [["ThighR", "ShinR", "FootR"], ["ThighF", "ShinF", "FootF"], ["ThighB", "ShinB", "FootB"]]:
		p[leg[0]] += Vector3(-30.0 * crouch + 25.0 * air, 0.0, 0.0)
		p[leg[1]] += Vector3(55.0 * crouch + 20.0 * air, 0.0, 0.0)
		p[leg[2]] += Vector3(-25.0 * crouch - 30.0 * air, 0.0, 0.0)
	p["Spine"] += Vector3(10.0 * crouch - 10.0 * air, 0.0, 0.0)
	p["Chest"] += Vector3(8.0 * crouch - 12.0 * air + 18.0 * land, 0.0, 0.0)
	p["Head"] += Vector3(-15.0 * crouch - 10.0 * air, 0.0, 0.0)
	# In the air both blades go high, then slam down on landing.
	for a in ["L", "R"]:
		var out := -1.0 if a == "L" else 1.0
		p["Arm" + a] += Vector3(30.0 * crouch - 120.0 * air + 35.0 * land, 0.0, out * 30.0 * air)
		p["Blade" + a] += Vector3(-40.0 * air + 20.0 * land, 0.0, 0.0)
	return -0.35 * crouch


## Collapse onto one side with the legs buckling. Returns body offset.
func _pose_death(p: Dictionary, d: float) -> Vector3:
	var s := _death_side
	for n in p:
		p[n] *= (1.0 - d)
	p["Hips"] += Vector3(10.0 * d, 0.0, 80.0 * s * d)
	p["Spine"] += Vector3(15.0 * d, 0.0, 10.0 * s * d)
	p["Chest"] += Vector3(20.0 * d, 0.0, 5.0 * s * d)
	p["Head"] += Vector3(25.0 * d, 20.0 * s * d, 15.0 * s * d)
	p["ArmL"] += Vector3(30.0 * d, 0.0, -25.0 * d)
	p["ArmR"] += Vector3(30.0 * d, 0.0, 25.0 * d)
	p["BladeL"] += Vector3(-20.0 * d, 0.0, 0.0)
	p["BladeR"] += Vector3(-20.0 * d, 0.0, 0.0)
	for leg in [["ThighR", "ShinR"], ["ThighF", "ShinF"], ["ThighB", "ShinB"]]:
		p[leg[0]] += Vector3(-40.0 * d, 0.0, 0.0)
		p[leg[1]] += Vector3(70.0 * d, 0.0, 0.0)
	return Vector3(0.0, -0.75 * d, 0.0)



## Sometimes leaves something behind: cartridges, scrap or tech.
func _drop_loot() -> void:
	var r := randf()
	var id := ""
	if r < 0.22:
		id = "cartridge"
	elif r < 0.34:
		id = "scrap"
	elif r < 0.40:
		id = "tech"
	if id == "":
		return
	var p := global_position
	p.y += 0.05
	Pickup.spawn(get_parent(), "resource", id, p, Vector2i(1, 1))
