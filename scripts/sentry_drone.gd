extends Node3D
## A Vaari sentry drone, asleep mid-air over the trail.
##
## Asleep it drifts and its eye glows dimly. It wakes if you come near
## without crouching, or fire a shot within earshot. Once awake it turns,
## locks on and fires a single lethal beam. Bolts don't hurt it.
## Call reset() to put it back to sleep (after you respawn).

const U = preload("res://scripts/util.gd")
const Sfx = preload("res://scripts/sfx.gd")

const MODEL_PATH := "res://models/sentry_drone/Meshy_AI_Spotter_Drone_20261110_texture.fbx"
const TEX := "res://models/sentry_drone/Meshy_AI_Spotter_Drone_20261110_texture"
const SIZE := 1.3                 # metres across
## Walking or running this close wakes it.
const WAKE_RADIUS := 11.0
## Even crouched, bumping right into it wakes it.
const TOUCH_RADIUS := 1.6
## Gunfire this close wakes it.
const HEAR_SHOT_RADIUS := 30.0
const LOCK_TIME := 0.9            # from waking to firing

signal woke

var player: Node3D
var state := "asleep"             # "asleep", "locking", "fired"

var _body: Node3D
var _eye: OmniLight3D
var _eye_mat: StandardMaterial3D
var _t := 0.0
var _lock_t := 0.0
var _home := Vector3.ZERO


func _ready() -> void:
	add_to_group("sentry_drone")
	_home = position
	_body = Node3D.new()
	add_child(_body)
	if ResourceLoader.exists(MODEL_PATH):
		var inst: Node3D = load(MODEL_PATH).instantiate()
		_body.add_child(inst)
		var box := U.collect_aabb(inst)
		var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if size > 0.0001:
			inst.scale = Vector3.ONE * (SIZE / size)
			inst.position = -(box.get_center()) * (SIZE / size)
		_apply_textures(inst)
	# Its eye: a glow that is dim and slow while it sleeps.
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1.0, 0.2, 0.12)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.15, 0.08)
	_eye_mat.emission_energy_multiplier = 1.0
	_eye = OmniLight3D.new()
	_eye.light_color = Color(1.0, 0.2, 0.1)
	_eye.omni_range = 4.0
	_eye.light_energy = 0.4
	_eye.position = Vector3(0.0, 0.0, -SIZE * 0.45)
	_body.add_child(_eye)
	var glint := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	glint.mesh = sm
	glint.material_override = _eye_mat
	glint.position = _eye.position
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(glint)
	if player != null and player.has_signal("shot_fired"):
		player.shot_fired.connect(_on_shot)
	reset()


## Meshy's PBR maps, in case the importer didn't pick them up.
func _apply_textures(inst: Node3D) -> void:
	if not ResourceLoader.exists(TEX + ".png"):
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + ".png")
	if ResourceLoader.exists(TEX + "_normal.png"):
		m.normal_enabled = true
		m.normal_texture = load(TEX + "_normal.png")
	if ResourceLoader.exists(TEX + "_metallic.png"):
		m.metallic = 1.0
		m.metallic_texture = load(TEX + "_metallic.png")
	if ResourceLoader.exists(TEX + "_roughness.png"):
		m.roughness = 1.0
		m.roughness_texture = load(TEX + "_roughness.png")
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m


func reset() -> void:
	state = "asleep"
	_lock_t = 0.0
	position = _home
	# Dozing: nose tipped down a little.
	_body.rotation = Vector3(deg_to_rad(-18.0), rotation.y, 0.0)
	_body.rotation.y = 0.0


func is_asleep() -> bool:
	return state == "asleep"


func _process(delta: float) -> void:
	_t += delta
	match state:
		"asleep":
			# Slow drift and a slow "breathing" glow.
			position = _home + Vector3(sin(_t * 0.4) * 0.12, sin(_t * 0.9) * 0.15, 0.0)
			_body.rotation.z = sin(_t * 0.5) * 0.05
			var breathe := 0.5 + 0.5 * sin(_t * 1.3)
			_eye.light_energy = 0.15 + 0.35 * breathe
			_eye_mat.emission_energy_multiplier = 0.4 + 1.2 * breathe
			_check_wake()
		"locking":
			_face_player(delta, 10.0)
			_lock_t += delta
			# Eye flares as it locks on.
			var k := clampf(_lock_t / LOCK_TIME, 0.0, 1.0)
			_eye.light_energy = 2.0 + 10.0 * k + sin(_t * 40.0) * 2.0
			_eye_mat.emission_energy_multiplier = 3.0 + 12.0 * k
			if _lock_t >= LOCK_TIME:
				_fire()
		"fired":
			_face_player(delta, 4.0)
			_eye.light_energy = 3.0
			_eye_mat.emission_energy_multiplier = 4.0


func _target() -> Vector3:
	return player.global_position + Vector3.UP * 1.1


func _check_wake() -> void:
	if player == null or player.get("is_dead"):
		return
	var d := global_position.distance_to(_target())
	var sneaking: bool = player.has_method("is_sneaking") and player.is_sneaking()
	if d < TOUCH_RADIUS or (not sneaking and d < WAKE_RADIUS):
		wake()


func _on_shot() -> void:
	if state == "asleep" and player != null and global_position.distance_to(_target()) < HEAR_SHOT_RADIUS:
		wake()


func wake() -> void:
	if state != "asleep":
		return
	state = "locking"
	_lock_t = 0.0
	Sfx.at(global_position, "droid_power", 4.0, 0.0, 14.0)
	woke.emit()


func _face_player(delta: float, speed: float) -> void:
	if player == null:
		return
	var to := _target() - global_position
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	_body.rotation.y = lerp_angle(_body.rotation.y, yaw, clampf(speed * delta, 0.0, 1.0))
	_body.rotation.x = lerp_angle(_body.rotation.x, pitch, clampf(speed * delta, 0.0, 1.0))
	_body.rotation.z = lerpf(_body.rotation.z, 0.0, clampf(speed * delta, 0.0, 1.0))


func _fire() -> void:
	state = "fired"
	if player == null or player.get("is_dead"):
		return
	var from := _eye.global_position
	var to := _target()
	_beam(from, to)
	Sfx.at(global_position, "droid_blaster", 8.0, 0.0, 20.0)
	Sfx.at(to, "impact", 4.0, 0.05, 10.0)
	if player.has_method("kill"):
		player.kill()


## A searing red beam that fades out.
func _beam(from: Vector3, to: Vector3) -> void:
	var beam_len := from.distance_to(to)
	if beam_len < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = beam_len
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.3, 0.2, 1.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.15, 0.08)
	m.emission_energy_multiplier = 16.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	var mid := (from + to) * 0.5
	var up := (to - from).normalized()
	var side := up.cross(Vector3.UP)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	mi.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), mid)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.25, 0.15)
	flash.light_energy = 12.0
	flash.omni_range = 8.0
	get_tree().current_scene.add_child(flash)
	flash.global_position = to
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5).set_delay(0.12)
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(func():
		mi.queue_free()
		flash.queue_free())
