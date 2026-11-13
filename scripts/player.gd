extends CharacterBody3D
## The player: third-person movement, over-the-shoulder camera, blaster,
## and the Mixamo skeleton + animations when they are present.

signal health_changed(current: float, maximum: float)
signal died
signal hit_landed(killed: bool)

const U = preload("res://scripts/util.gd")
const BoltScript = preload("res://scripts/bolt.gd")
const Sfx = preload("res://scripts/sfx.gd")
const GS = preload("res://scripts/game_state.gd")

const CHARACTER_PATH := "res://models/maincharacter.glb"   # textured, unrigged
const RIGGED_PATH := "res://models/trooper_rigged.fbx"      # Mixamo skeleton + idle
## The survivor as a playable character (Mixamo rig, same bone names as the
## trooper, so every animation above plays on her too).
const SURVIVOR_RIG := "res://models/female_mixamo.fbx"
const BLASTER_PATH := "res://models/blaster.glb"
## Her own rifle (the one slung on her back as a companion).
const SURVIVOR_RIFLE := "res://models/ally_rifle.glb"
## Fitted onto the blaster's grip points: 1.58x puts it at her original 0.95 m,
## and the offset lines her pistol grip (model x 0.4) up with the hand.
const SURVIVOR_RIFLE_SCALE := 1.58
const SURVIVOR_RIFLE_OFFSET := Vector3(0.218, 0.222, 0.0)
const SURVIVOR_RIFLE_MUZZLE := Vector3(-1.28, 0.38, 0.0)
const PistolModel = preload("res://scripts/pistol_model.gd")
const ANIM_FILES := {
	"run": "res://models/anim_run.fbx",
	"walk_fwd": "res://models/anim_walk_fwd.fbx",
	"walk_back": "res://models/anim_walk_back.fbx",
	"walk_left": "res://models/anim_walk_left.fbx",
	"walk_right": "res://models/anim_walk_right.fbx",
	"fire": "res://models/anim_fire.fbx",
	"hit": "res://models/anim_hit.fbx",
	"death": "res://models/anim_death.fbx",
}
const LOOPING := ["idle", "run", "fire", "walk_fwd", "walk_back", "walk_left", "walk_right"]
const NO_ROOT_MOTION := ["idle", "run", "fire", "walk_fwd", "walk_back", "walk_left", "walk_right", "hit"]
const UPPER_BODY := ["Spine", "Neck", "Head", "Shoulder", "Arm", "Hand"]

@export var walk_speed := 2.8
@export var sprint_speed := 6.5
@export var jump_velocity := 5.5
## Turn this if the character model faces the wrong way.
@export var model_yaw_offset_deg := 180.0
## Overall length of the blaster in metres.
@export var gun_length := 0.6
@export var fire_interval := 0.16
@export var damage := 20.0

var max_health := 100.0
var health := 100.0
var is_dead := false
## Turned off by the level when a menu or end screen is up.
var input_enabled := true
## Menu showcase mode: just the animated model, no camera or controls.
var display_only := false
## Who this is: "trooper" (default) or "survivor". Set before add_child.
var character := "trooper"
## Seated without the weapon raised (resting by the fire).
var seat_relaxed := false
## Editor-only free camera (F3): orbit round the character without it turning.
var free_cam := false
var _free_yaw := 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: Node3D
var visual: Node3D
var gun: Node3D
var muzzle: Node3D
var _rifle_model: Node3D
var _pistol_model: Node3D
var muzzle_light: OmniLight3D

# Rig
var anim: AnimationPlayer
var tree: AnimationTree
var _blend_pos := Vector2.ZERO
var _aim_amount := 0.0
var _aim_point := Vector3.ZERO
## Upper-body twist/tilt (radians), applied by the aim modifier.
var torso_yaw := 0.0
var torso_pitch := 0.0
var _turning := false
var _spine_bones: Array[int] = []
var _has_aim_point := false
var skeleton: Skeleton3D
var _rigged := false
var _hand_r := -1
var _hand_l := -1
var _hand_r2 := -1
var _hand_l2 := -1
var _hit_t := 0.0

var _fire_cd := 0.0
var _step_t := 0.0
var _bob_t := 0.0
var _facing_yaw := 0.0
var _want_jump := false

## Seated mode (being dragged): can't move or turn round; aims and shoots
## within an arc, legs out in front. Position is set from outside.
var seated := false
## Sleeping: lying on your back (camp wake-up). Set false to get up.
var sleeping := false
var _sleep_amount := 0.0
## Pinned mode (impaled against a tree): standing, can't move, aims in an arc.
var pinned := false
## Limited ammo when >= 0 (-1 = unlimited). Emits ammo_changed.
var ammo := -1
signal ammo_changed(left: int)
## Health never drops below this (story sections where you can't die).
var health_floor := 0.0
## Unlimited ammo, no reloading (being dragged).
var infinite_ammo := false
## "primary" (rifle, cartridges) or "sidearm" (pistol, self-charging).
var weapon := "primary"
var _reload_t := 0.0
var _base_walk := 0.0
var _base_sprint := 0.0
var _seat_amount := 0.0
var seat_arc := deg_to_rad(105.0)
var _leg_bones: Array[int] = []
var _knee_bones: Array[int] = []


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	add_to_group("player")

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	visual = Node3D.new()
	model.add_child(visual)
	_load_character()
	_load_blaster()
	if display_only:
		collision_layer = 0
		collision_mask = 0
		return

	_base_walk = walk_speed
	_base_sprint = sprint_speed
	GS.ensure_loaded()
	GS.listeners.append(_refresh_stats)
	_refresh_stats()

	cam_yaw = Node3D.new()
	cam_yaw.position.y = 1.55
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.spring_length = 3.4
	spring.position = Vector3(0.65, 0.15, 0.0)
	spring.collision_mask = 1
	spring.margin = 0.2
	cam_pitch.add_child(spring)
	spring.add_excluded_object(get_rid())
	camera = Camera3D.new()
	camera.fov = 70.0
	spring.add_child(camera)
	camera.make_current()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ character

func _load_character() -> void:
	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(model_yaw_offset_deg)
	visual.add_child(holder)
	var rig := SURVIVOR_RIG if character == "survivor" else RIGGED_PATH
	if ResourceLoader.exists(rig) and _load_rigged(holder, rig):
		return
	if ResourceLoader.exists(CHARACTER_PATH):
		var inst: Node3D = load(CHARACTER_PATH).instantiate()
		holder.add_child(inst)
		U.fit(inst, 1.85, 1, true)
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.8
		mi.mesh = cm
		mi.position.y = 0.9
		mi.material_override = U.mat(Color(0.12, 0.12, 0.14), 0.5)
		holder.add_child(mi)


func _load_rigged(holder: Node3D, rig_path := RIGGED_PATH) -> bool:
	var inst: Node3D = load(rig_path).instantiate()
	holder.add_child(inst)
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		inst.queue_free()
		return false
	skeleton = skels[0]

	# Guard against unit mix-ups (cm vs m). The animations place him on the ground.
	var h := U.collect_aabb(inst).size.y
	if h > 0.01 and (h > 4.0 or h < 0.8):
		inst.scale = Vector3.ONE * (1.85 / h)

	if character == "trooper":
		_apply_original_textures(inst)
	else:
		# Make sure her skinned mesh follows the skeleton the animations drive.
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).skin != null:
				mi.skeleton = mi.get_path_to(skeleton)
		skeleton.show_rest_only = false

	anim = AnimationPlayer.new()
	anim.name = "TrooperAnims"
	inst.add_child(anim)   # root_node ".." -> inst
	var skel_path := String(inst.get_path_to(skeleton))
	var lib := AnimationLibrary.new()
	# His rig file carries his idle. Hers only carries a one-frame T-pose, so
	# she borrows his idle instead (same Mixamo bone names).
	if rig_path == RIGGED_PATH:
		_add_anim(lib, "idle", inst, skel_path)
	elif ResourceLoader.exists(RIGGED_PATH):
		var idle_src: Node = load(RIGGED_PATH).instantiate()
		_add_anim(lib, "idle", idle_src, skel_path)
		idle_src.free()
		# His file stores hip height in other units; standing still, her own
		# rest hip height is right, so keep only the rotations.
		if lib.has_animation("idle"):
			var ia := lib.get_animation("idle")
			for t in range(ia.get_track_count() - 1, -1, -1):
				if ia.track_get_type(t) == Animation.TYPE_POSITION_3D:
					ia.remove_track(t)
	for anim_name in ANIM_FILES:
		var path: String = ANIM_FILES[anim_name]
		if not ResourceLoader.exists(path):
			continue
		var src_scene: Node = load(path).instantiate()
		_add_anim(lib, anim_name, src_scene, skel_path)
		src_scene.free()
	anim.add_animation_library("", lib)

	_hand_r = _find_bone("RightHand")
	_hand_l = _find_bone("LeftHand")
	_rigged = lib.has_animation("idle")
	if _rigged:
		_build_tree(inst, skel_path)
	return true


## Copies the first animation of `scene_root` into `lib`, re-pointing every
## bone track at our character's skeleton.
func _add_anim(lib: AnimationLibrary, anim_name: String, scene_root: Node, skel_path: String) -> void:
	var players := scene_root.find_children("*", "AnimationPlayer", true, false)
	for p in players:
		if p == anim:
			continue
		var ap := p as AnimationPlayer
		for n in ap.get_animation_list():
			if String(n) == "RESET":
				continue
			var a: Animation = ap.get_animation(n).duplicate(true)
			for t in a.get_track_count():
				var tp := a.track_get_path(t)
				if tp.get_subname_count() > 0:
					a.track_set_path(t, NodePath(skel_path + ":" + String(tp.get_subname(0))))
			_fit_to_body(a)
			a.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE
			if anim_name in NO_ROOT_MOTION:
				_strip_root_motion(a)
			lib.add_animation(anim_name, a)
			return


## Animations made on another body carry that body's bone lengths (and
## sometimes centimetres instead of metres). Played on our trooper, those
## position/scale keys stretch and bend his limbs. Keep only rotations, plus
## the hips' position rescaled to his own hip height.
func _fit_to_body(a: Animation) -> void:
	var hips := _find_bone("Hips")
	var ratio := 1.0
	for t in range(a.get_track_count() - 1, -1, -1):
		var tp := a.track_get_path(t)
		var bone := String(tp.get_subname(0)) if tp.get_subname_count() > 0 else ""
		var typ := a.track_get_type(t)
		if typ == Animation.TYPE_SCALE_3D:
			a.remove_track(t)
		elif typ == Animation.TYPE_POSITION_3D:
			if not bone.ends_with("Hips") or hips < 0:
				a.remove_track(t)
				continue
			if a.track_get_key_count(t) == 0:
				continue
			var rest_h := skeleton.get_bone_rest(hips).origin.length()
			var first_h := (a.track_get_key_value(t, 0) as Vector3).length()
			if rest_h > 0.0001 and first_h > 0.0001:
				ratio = rest_h / first_h
			# Her body only: the clips were made for his hip height, so scale
			# them to hers (his own keys stay exactly as animated, below).
			if character == "survivor" and absf(ratio - 1.0) > 0.001:
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * ratio)
			# The hips keys are left exactly as animated. Rescaling them here
			# (added Monday evening) dropped him about a metre into the ground.


## Keeps the hips' height but removes forward/sideways drift, because the
## game itself moves the character.
func _strip_root_motion(a: Animation) -> void:
	var hips := _find_bone("Hips")
	if hips < 0:
		return
	var rest := skeleton.get_bone_rest(hips).origin
	var up_axis := 1
	if absf(rest.z) > absf(rest[up_axis]):
		up_axis = 2
	if absf(rest.x) > absf(rest[up_axis]):
		up_axis = 0
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var tp := a.track_get_path(t)
		if tp.get_subname_count() == 0 or not String(tp.get_subname(0)).ends_with("Hips"):
			continue
		if a.track_get_key_count(t) == 0:
			continue
		var first: Vector3 = a.track_get_key_value(t, 0)
		for k in a.track_get_key_count(t):
			var v: Vector3 = a.track_get_key_value(t, k)
			var out := first
			out[up_axis] = v[up_axis]
			a.track_set_key_value(t, k, out)


func _is_upper_body(bone: String) -> bool:
	for part in UPPER_BODY:
		if bone.contains(part):
			return true
	return false


func _anim_or_idle(n: String) -> String:
	return n if anim.has_animation(n) else "idle"


## Legs: blend between idle / walk directions / run.
## Upper body: blends in the firing animation while shooting (works while walking).
## On top: a one-shot flinch when hit.
func _build_tree(inst: Node3D, skel_path: String) -> void:
	tree = AnimationTree.new()
	tree.name = "TrooperTree"
	inst.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)

	var bt := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-1.5, -1.5)
	loco.max_space = Vector2(1.5, 2.5)
	var points := {
		"idle": Vector2.ZERO,
		"walk_fwd": Vector2(0, 1),
		"walk_back": Vector2(0, -1),
		"walk_left": Vector2(-1, 0),
		"walk_right": Vector2(1, 0),
		"run": Vector2(0, 2),
	}
	for n in points:
		if anim.has_animation(n):
			var node := AnimationNodeAnimation.new()
			node.animation = n
			loco.add_blend_point(node, points[n])
	bt.add_node("loco", loco)

	var fire := AnimationNodeAnimation.new()
	fire.animation = _anim_or_idle("fire")
	bt.add_node("fire", fire)

	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if _is_upper_body(bone):
			aim.set_filter_path(NodePath(skel_path + ":" + bone), true)
	bt.add_node("aim_blend", aim)

	var hit := AnimationNodeAnimation.new()
	hit.animation = _anim_or_idle("hit")
	bt.add_node("hit", hit)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.08
	shot.fadeout_time = 0.25
	bt.add_node("hit_shot", shot)

	bt.connect_node("aim_blend", 0, "loco")
	bt.connect_node("aim_blend", 1, "fire")
	bt.connect_node("hit_shot", 0, "aim_blend")
	bt.connect_node("hit_shot", 1, "hit")
	bt.connect_node("output", 0, "hit_shot")
	tree.tree_root = bt
	tree.active = true

	# We advance the animation ourselves each frame, then twist the spine,
	# so the twist is always applied on top of the animated pose.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for n in ["Spine", "Spine1", "Spine2"]:
		var b := _find_bone(n)
		if b >= 0:
			_spine_bones.append(b)


func _find_bone(suffix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(suffix):
			return i
	return -1


## Mixamo drops textures, so borrow the materials from the original export.
func _apply_original_textures(inst: Node3D) -> void:
	if not ResourceLoader.exists(CHARACTER_PATH):
		return
	var src: Node = load(CHARACTER_PATH).instantiate()
	var mats: Array[Material] = []
	for node in src.find_children("*", "MeshInstance3D", true, false):
		var smi := node as MeshInstance3D
		if smi.mesh == null:
			continue
		for s in smi.mesh.get_surface_count():
			var m := smi.get_active_material(s)
			if m != null:
				mats.append(m)
	src.free()
	if mats.is_empty():
		return
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var count := mi.mesh.get_surface_count()
		if count == mats.size():
			for s in count:
				mi.set_surface_override_material(s, mats[s])
		else:
			mi.material_override = mats[0]


# ------------------------------------------------------------ blaster

# Points measured on blaster.glb in its own units (long axis X, muzzle at -X, Y up).
const GUN_MODEL_LENGTH := 1.9
const GUN_GRIP := Vector3(0.85, -0.22, 0.0)     # middle of the pistol grip
const GUN_FOREGRIP := Vector3(-0.2, -0.07, 0.0) # underside, where the left hand holds
const GUN_MUZZLE := Vector3(-0.95, 0.22, 0.0)

var _rifle_muzzle := GUN_MUZZLE

func _load_blaster() -> void:
	gun = Node3D.new()
	gun.name = "Blaster"
	gun.top_level = true
	add_child(gun)
	_rifle_model = Node3D.new()
	gun.add_child(_rifle_model)
	if character == "survivor" and ResourceLoader.exists(SURVIVOR_RIFLE):
		_rifle_model.add_child(load(SURVIVOR_RIFLE).instantiate())
		_rifle_model.scale = Vector3.ONE * SURVIVOR_RIFLE_SCALE
		_rifle_model.position = SURVIVOR_RIFLE_OFFSET
		_rifle_muzzle = SURVIVOR_RIFLE_MUZZLE
	elif ResourceLoader.exists(BLASTER_PATH):
		_rifle_model.add_child(load(BLASTER_PATH).instantiate())
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.9, 0.4, 0.3)
		mi.mesh = bm
		mi.position.y = 0.2
		mi.material_override = U.mat(Color(0.2, 0.2, 0.22), 0.4)
		_rifle_model.add_child(mi)
	_pistol_model = PistolModel.build()
	_pistol_model.visible = false
	gun.add_child(_pistol_model)
	muzzle = Node3D.new()
	muzzle.position = _rifle_muzzle
	gun.add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.25, 0.2)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 4.0
	muzzle.add_child(muzzle_light)
	_hand_r2 = _find_bone("RightHandMiddle1") if skeleton != null else -1
	_hand_l2 = _find_bone("LeftHandMiddle1") if skeleton != null else -1
	_show_weapon_model()


func _palm(wrist: int, knuckle: int) -> Vector3:
	var p := skeleton.get_bone_global_pose(wrist).origin
	if knuckle >= 0:
		p = p.lerp(skeleton.get_bone_global_pose(knuckle).origin, 0.55)
	return skeleton.global_transform * p


## Grip in the right palm, barrel underside resting on the left palm.
func _update_gun() -> void:
	var s := gun_length / GUN_MODEL_LENGTH
	var fwd := -model.global_transform.basis.z
	var grip_world: Vector3
	var aim := fwd
	if _rigged and _hand_r >= 0:
		grip_world = _palm(_hand_r, _hand_r2)
		if _hand_l >= 0 and not is_dead:
			var d := _palm(_hand_l, _hand_l2) - grip_world
			if d.length() > 0.12:
				aim = d.normalized()
	else:
		grip_world = visual.global_transform * Vector3(0.25, 1.05, -0.2)
	if absf(aim.y) > 0.95:
		aim = fwd
	# While shooting or aiming, point the barrel straight at the crosshair.
	if _has_aim_point and not is_dead:
		var to_target := _aim_point - grip_world
		if to_target.length() > 1.0:
			var weight := _aim_amount if _rigged else 1.0
			aim = aim.slerp(to_target.normalized(), clampf(weight, 0.0, 1.0)).normalized()

	# Local frame: grip->foregrip direction and the gun's up.
	var a1 := (GUN_FOREGRIP - GUN_GRIP).normalized()
	var a2 := (Vector3.UP - a1 * Vector3.UP.dot(a1)).normalized()
	var local_frame := Basis(a1, a2, a1.cross(a2))
	# World frame: hand-to-hand direction and world up.
	var b2 := (Vector3.UP - aim * Vector3.UP.dot(aim)).normalized()
	var world_frame := Basis(aim, b2, aim.cross(b2))
	var rot := world_frame * local_frame.inverse()
	var gb := rot.scaled(Vector3.ONE * s)
	gun.global_transform = Transform3D(gb, grip_world - gb * GUN_GRIP)


# ------------------------------------------------------------ input & movement

func _unhandled_input(event) -> void:
	if display_only or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Settings.mouse_sensitivity
		var invert := -1.0 if Settings.invert_y else 1.0
		cam_yaw.rotation.y -= event.relative.x * sens
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - event.relative.y * sens * invert,
				deg_to_rad(-60.0), deg_to_rad(45.0))
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif free_cam and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		spring.spring_length = clampf(spring.spring_length + (-0.4 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.4), 1.2, 9.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F3:
				if OS.has_feature("editor"):
					free_cam = not free_cam
					_free_yaw = _facing_yaw
					GS.toast("Free camera ON  (mouse orbits, wheel zooms, F3 to exit)" if free_cam else "Free camera OFF")
			KEY_SPACE:
				_want_jump = true
			KEY_R:
				_start_reload()
			KEY_Q:
				_switch_weapon()
			KEY_H:
				_quick_heal()
			KEY_G:
				_throw_grenade()


# ------------------------------------------------------------ weapons & items

func _exit_tree() -> void:
	GS.listeners.erase(_refresh_stats)


## Re-reads damage, max health and speed from upgrades, skills and modules.
func _refresh_stats() -> void:
	if display_only or not is_inside_tree():
		return
	if weapon == "sidearm" and GS.equipment.get("sidearm", "") == "":
		weapon = "primary"   # pistol unequipped while in hand
	_show_weapon_model()
	var w := GS.item(GS.equipment.get(weapon, ""))
	damage = GS.player_damage() * float(w.get("damage", 1.0))
	fire_interval = float(w.get("rate", 0.16)) / GS.fire_rate_mult()
	var old_max := max_health
	max_health = GS.player_max_health()
	if max_health > old_max and old_max > 0.0:
		health += max_health - old_max
	health = minf(health, max_health)
	health_changed.emit(health, max_health)
	var sp := 1.0 + GS.module_bonus("speed")
	walk_speed = _base_walk * sp
	sprint_speed = _base_sprint * sp


func weapon_name() -> String:
	return GS.item(GS.equipment.get(weapon, "")).get("name", "Unarmed")


func ammo_text() -> String:
	if ammo >= 0:
		return "%d" % ammo
	if infinite_ammo or weapon == "sidearm":
		return "∞"
	if _reload_t > 0.0:
		return "RELOADING"
	return "%d / %d" % [GS.mag, GS.mag_size()]


func ammo_hint() -> String:
	if ammo >= 0 or infinite_ammo:
		return ""
	if weapon == "sidearm":
		return "Q: rifle"
	return "%d cartridges   ·   R reload%s" % [GS.count("cartridge"), "   ·   Q: pistol" if GS.equipment.get("sidearm", "") != "" else ""]


func _switch_weapon() -> void:
	var other := "sidearm" if weapon == "primary" else "primary"
	if GS.equipment.get(other, "") == "":
		return
	weapon = other
	_reload_t = 0.0
	_refresh_stats()
	_show_weapon_model()


## Shows the rifle or the pistol in your hands to match the selected weapon.
func _show_weapon_model() -> void:
	if _rifle_model == null or _pistol_model == null:
		return
	var pistol := weapon == "sidearm"
	_rifle_model.visible = not pistol
	_pistol_model.visible = pistol
	muzzle.position = PistolModel.MUZZLE if pistol else _rifle_muzzle
	Sfx.ui("ui_click", -6.0)


func _start_reload() -> void:
	if ammo >= 0 or infinite_ammo or weapon != "primary" or _reload_t > 0.0:
		return
	if GS.mag >= GS.mag_size():
		return
	if GS.count("cartridge") <= 0:
		GS.toast("No blaster cartridges. Craft some at the bench.")
		return
	_reload_t = 1.4 * GS.reload_time_mult()
	Sfx.ui("crate_open", -10.0, 0.1)


func _finish_reload() -> void:
	if GS.remove_item("cartridge", 1):
		GS.mag = GS.mag_size()
		GS.changed()


func _quick_heal() -> void:
	if health >= max_health:
		return
	for id in ["bandage", "ration", "stim"]:
		if GS.count(id) > 0:
			use_item(id)
			return
	GS.toast("Nothing to heal with.")


## Uses a consumable from the backpack.
func use_item(id: String) -> bool:
	var it := GS.item(id)
	if it.get("type") == "placeable" and GS.count(id) > 0:
		var sc := get_tree().current_scene
		if sc == null or not sc.has_method("place_crate"):
			GS.toast("Storage crates can only be placed at camp.")
			return false
		if not sc.place_crate(id):
			return false
		GS.remove_item(id, 1)
		GS.toast("Placed %s" % it["name"])
		Sfx.ui("crate_open", -6.0, 0.05)
		return true
	if it.get("type") != "consumable" or GS.count(id) <= 0:
		return false
	GS.remove_item(id, 1)
	heal(GS.heal_amount(id))
	GS.toast("Used %s" % it["name"])
	Sfx.ui("upgrade", -12.0, 0.1)
	return true


func _throw_grenade() -> void:
	var slot := ""
	for k in ["utility1", "utility2"]:
		var id: String = GS.equipment.get(k, "")
		if id != "" and GS.count(id) > 0:
			slot = id
			break
	if slot == "":
		GS.toast("No grenade equipped (Esc → INVENTORY, equip to a utility slot).")
		return
	GS.remove_item(slot, 1)
	var it := GS.item(slot)
	var from := global_position + Vector3.UP * 1.5
	var to := _aim_point if _has_aim_point else from - cam_yaw.global_transform.basis.z * 15.0
	if from.distance_to(to) > 22.0:
		to = from + (to - from).normalized() * 22.0
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	g.mesh = sm
	g.material_override = U.mat(Color(0.25, 0.3, 0.2), 0.6, Color(1.0, 0.3, 0.1), 1.5)
	get_parent().add_child(g)
	g.global_position = from
	var tw := g.create_tween()
	var dur := 0.25 + from.distance_to(to) * 0.04
	tw.tween_method(_grenade_arc.bind(g, from, to), 0.0, 1.0, dur)
	tw.tween_interval(0.6)
	tw.tween_callback(_grenade_boom.bind(g, float(it.get("damage", 60.0)) * GS.grenade_mult(), float(it.get("radius", 4.0)) + GS.grenade_radius_bonus()))


func _grenade_arc(t: float, g: Node3D, from: Vector3, to: Vector3) -> void:
	g.global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 2.5


func _grenade_boom(g: Node3D, dmg: float, radius: float) -> void:
	_explode(g.global_position, dmg, radius)
	g.queue_free()


func _explode(at: Vector3, dmg: float, radius: float) -> void:
	Sfx.at(at, "slam", 4.0, 0.1, 14.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: float = e.global_position.distance_to(at)
		if d < radius:
			e.take_damage(dmg * (1.0 - d / radius * 0.5), (e.global_position - at).normalized())
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.light_energy = 12.0
	flash.omni_range = radius * 2.5
	get_parent().add_child(flash)
	flash.global_position = at + Vector3.UP
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.5
	bs.height = 1.0
	ball.mesh = bs
	ball.material_override = U.mat(Color(1, 0.6, 0.2), 0.5, Color(1.0, 0.5, 0.1), 6.0)
	get_parent().add_child(ball)
	ball.global_position = at
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 1.2, 0.3)
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(ball.queue_free)
	tw.chain().tween_callback(flash.queue_free)


func _process(delta: float) -> void:
	_since_hit += delta
	_invuln_t = maxf(_invuln_t - delta, 0.0)
	if not is_dead and not display_only and _since_hit > 5.0 and health < max_health:
		var rr := GS.regen_rate()
		if rr > 0.0:
			health = minf(health + rr * delta, max_health)
			health_changed.emit(health, max_health)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()
	_seat_amount = move_toward(_seat_amount, 1.0 if seated else 0.0, delta * 2.5)
	if _rigged and tree != null and tree.active:
		tree.advance(delta)
		_twist_spine()
		_seat_legs()
	_sleep_amount = move_toward(_sleep_amount, 1.0 if sleeping else 0.0, delta * (4.0 if sleeping else 0.9))
	if model != null:
		model.position.y = -0.82 * _seat_amount + 0.16 * _sleep_amount
		# Lying on your back: tip the whole body over backwards.
		model.rotation.x = deg_to_rad(90.0) * _sleep_amount
	if gun != null:
		gun.visible = _sleep_amount < 0.4
	if cam_yaw != null:
		# Seated: camera up over her shoulder, looking down past you.
		cam_yaw.position.y = 1.55 + (-0.45 if pinned else 0.45) * _seat_amount
	_update_gun()


## Turns the legs forward so the trooper sits with legs out in front.
func _seat_legs() -> void:
	if _seat_amount <= 0.001:
		return
	if _leg_bones.is_empty():
		for i in skeleton.get_bone_count():
			var n := skeleton.get_bone_name(i)
			if n.ends_with("UpLeg"):
				_leg_bones.append(i)
			elif n.ends_with("Leg"):
				_knee_bones.append(i)
	var sb := skeleton.global_transform.basis.orthonormalized()
	var right := model.global_transform.basis.x.normalized()
	var fwd := -model.global_transform.basis.z.normalized()
	for i in _leg_bones.size():
		var b := _leg_bones[i]
		var side := 1.0 if skeleton.get_bone_name(b).begins_with("Left") else -1.0
		var w := Basis(right, deg_to_rad(84.0) * _seat_amount) * Basis(fwd, deg_to_rad(9.0) * side * _seat_amount)
		var pose := skeleton.get_bone_global_pose(b)
		pose.basis = (sb.inverse() * w * sb) * pose.basis
		skeleton.set_bone_global_pose(b, pose)
	for b in _knee_bones:
		var pose := skeleton.get_bone_global_pose(b)
		pose.basis = (sb.inverse() * Basis(right, deg_to_rad(-12.0) * _seat_amount) * sb) * pose.basis
		skeleton.set_bone_global_pose(b, pose)


## Turns the spine so the upper body follows the camera while the legs stay put.
func _twist_spine() -> void:
	if _spine_bones.is_empty() or (absf(torso_yaw) < 0.001 and absf(torso_pitch) < 0.001):
		return
	var sb := skeleton.global_transform.basis.orthonormalized()
	var right := model.global_transform.basis.x.normalized()
	var n := float(_spine_bones.size())
	var step_world := Basis(Vector3.UP, torso_yaw / n) * Basis(right, torso_pitch / n)
	var step := sb.inverse() * step_world * sb
	for b in _spine_bones:
		var pose := skeleton.get_bone_global_pose(b)
		pose.basis = step * pose.basis
		skeleton.set_bone_global_pose(b, pose)


func _physics_process(delta: float) -> void:
	if display_only:
		if _rigged:
			_update_anim(delta, false)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	if (sleeping or _sleep_amount > 0.0) and not is_dead:
		velocity = Vector3.ZERO
		model.rotation.y = _facing_yaw
		if _rigged:
			_update_anim(delta, false)
		return
	if (seated or pinned) and not is_dead:
		_seated_physics(delta)
		return

	if is_dead:
		torso_yaw = lerpf(torso_yaw, 0.0, clampf(8.0 * delta, 0.0, 1.0))
		torso_pitch = lerpf(torso_pitch, 0.0, clampf(8.0 * delta, 0.0, 1.0))
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	var input := Vector2.ZERO
	if input_enabled:
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0
	input = input.normalized()

	# Free camera: steer relative to the body, not the camera.
	var ctrl_yaw: float = _free_yaw if free_cam else cam_yaw.rotation.y
	var dir := Basis(Vector3.UP, ctrl_yaw) * Vector3(input.x, 0.0, input.y)
	var captured := input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var shooting := captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var aiming := captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	# Sprint only forwards and not while shooting or aiming.
	var sprinting := input_enabled and Input.is_physical_key_pressed(KEY_SHIFT) and input.y < -0.5 \
			and not shooting and not aiming
	var speed := sprint_speed if sprinting else walk_speed
	if aiming:
		speed *= 0.75
	var accel := 12.0 if is_on_floor() else 3.0
	var t := clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, dir.x * speed, t)
	velocity.z = lerpf(velocity.z, dir.z * speed, t)

	if _want_jump and is_on_floor():
		velocity.y = jump_velocity
	var climbing := _climb(dir, delta)
	_want_jump = false

	move_and_slide()

	# Footsteps.
	var hs := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hs > 0.6:
		_step_t -= delta * hs
		if _step_t <= 0.0:
			_step_t = 1.45
			Sfx.at(global_position, "step%d" % (randi() % 3), -10.0 if hs < 4.0 else -6.0, 0.12, 4.0)
	else:
		_step_t = 0.2

	_update_aim_point()

	# Moving: the whole body faces the camera direction.
	# Standing: the feet stay put and the torso twists to follow the aim;
	# past ~70 degrees the feet turn to catch up.
	var twist := wrapf(ctrl_yaw - _facing_yaw, -PI, PI)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.4
	if moving:
		_turning = false
		_facing_yaw = lerp_angle(_facing_yaw, ctrl_yaw, clampf(12.0 * delta, 0.0, 1.0))
	else:
		if absf(twist) > deg_to_rad(70.0):
			_turning = true
		if _turning:
			_facing_yaw = lerp_angle(_facing_yaw, ctrl_yaw, clampf(7.0 * delta, 0.0, 1.0))
			if absf(twist) < deg_to_rad(4.0):
				_turning = false
	if climbing:
		_facing_yaw = lerp_angle(_facing_yaw, _climb_yaw, clampf(12.0 * delta, 0.0, 1.0))
	model.rotation.y = _facing_yaw
	twist = wrapf(ctrl_yaw - _facing_yaw, -PI, PI)
	torso_yaw = lerpf(torso_yaw, twist, clampf(20.0 * delta, 0.0, 1.0))
	torso_pitch = lerpf(torso_pitch, 0.0 if free_cam else cam_pitch.rotation.x * 0.85, clampf(20.0 * delta, 0.0, 1.0))

	# Aim zoom (the free camera keeps whatever zoom the wheel set).
	if not free_cam:
		spring.spring_length = lerpf(spring.spring_length, 2.0 if aiming else 3.4, clampf(10.0 * delta, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, 55.0 if aiming else 70.0, clampf(10.0 * delta, 0.0, 1.0))

	if _rigged:
		_update_anim(delta, shooting or aiming)
	else:
		_animate_fake(delta)

	_fire_cd -= delta
	if shooting and _fire_cd <= 0.0:
		_fire_cd = fire_interval
		_shoot()
	muzzle_light.light_energy = move_toward(muzzle_light.light_energy, 0.0, 60.0 * delta)


## Ladders: nodes in the "ladder" group carry metas "centre"/"half" (the
## climb zone, in the ladder's own space; local +X points away from the wall)
## and "roof" (height of the roof the ladder leads to).
## Push towards the ladder to climb, pull away to climb down, Space to let go.
var _climb_yaw := 0.0

func _ladder_here():
	for l in get_tree().get_nodes_in_group("ladder"):
		var lp: Vector3 = (l as Node3D).global_transform.affine_inverse() * global_position
		var d: Vector3 = (lp - (l.get_meta("centre") as Vector3)).abs()
		var h: Vector3 = l.get_meta("half")
		if d.x <= h.x and d.y <= h.y and d.z <= h.z:
			return l
	return null


func _climb(dir: Vector3, delta: float) -> bool:
	if not input_enabled:
		return false
	var l = _ladder_here()
	if l == null:
		return false
	var xf: Transform3D = l.global_transform
	var out := xf.basis.x.normalized()
	var into := -out
	var f := dir.dot(into)
	if is_on_floor() and f < 0.3:
		return false   # just walking past it, or stepping away from it
	if _want_jump:
		velocity = out * 3.5 + Vector3.UP * 3.0
		return false
	var lp: Vector3 = xf.affine_inverse() * global_position
	var roof: float = l.get_meta("roof")
	velocity.y = clampf(f * 2.0, -1.0, 1.0) * 2.8
	var lateral := xf.basis.z.normalized()
	var v_out: float
	if lp.y > roof + 0.05 and f > 0.2:
		v_out = -walk_speed * 0.8                       # over the top and onto the roof
		velocity.y = maxf(velocity.y, 0.5)
	else:
		v_out = clampf((0.42 - lp.x) * 6.0, -2.5, 2.5)  # hug the rungs
	velocity.x = out.x * v_out - lateral.x * lp.z * 4.0
	velocity.z = out.z * v_out - lateral.z * lp.z * 4.0
	_climb_yaw = atan2(-into.x, -into.z)
	if absf(velocity.y) > 0.5:
		_step_t -= delta * 2.0
		if _step_t <= 0.0:
			_step_t = 0.9
			Sfx.at(global_position, "step%d" % (randi() % 3), -12.0, 0.2, 4.0)
	return true


## Aim and shoot only; the body faces _facing_yaw and the camera is kept
## within SEAT_ARC of it.
func _seated_physics(delta: float) -> void:
	velocity = Vector3.ZERO
	var captured := input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var shooting := captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var aiming := captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var rel := clampf(wrapf(cam_yaw.rotation.y - _facing_yaw, -PI, PI), -seat_arc, seat_arc)
	cam_yaw.rotation.y = _facing_yaw + rel
	model.rotation.y = _facing_yaw
	torso_yaw = lerpf(torso_yaw, rel, clampf(20.0 * delta, 0.0, 1.0))
	torso_pitch = lerpf(torso_pitch, cam_pitch.rotation.x * 0.85, clampf(20.0 * delta, 0.0, 1.0))
	_update_aim_point()
	var arm := 0.7 if pinned else 2.3
	spring.spring_length = lerpf(spring.spring_length, arm * 0.62 if aiming else arm, clampf(10.0 * delta, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, 55.0 if aiming else 70.0, clampf(10.0 * delta, 0.0, 1.0))
	if _rigged:
		_update_anim(delta, not seat_relaxed)
	if seat_relaxed:
		return
	_fire_cd -= delta
	if shooting and _fire_cd <= 0.0:
		_fire_cd = fire_interval
		_shoot()
	muzzle_light.light_energy = move_toward(muzzle_light.light_energy, 0.0, 60.0 * delta)


## Faces the seated trooper towards `yaw` (world radians).
func set_seat_facing(yaw: float) -> void:
	var rel := wrapf(cam_yaw.rotation.y - _facing_yaw, -PI, PI)
	_facing_yaw = yaw
	cam_yaw.rotation.y = yaw + rel


func _update_anim(delta: float, weapon_up: bool) -> void:
	# Movement relative to where the trooper faces (model faces -Z).
	var local := model.global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var target := Vector2(local.x, -local.z) / walk_speed
	if target.y > 1.0:
		# Between walk (1) and run (2) as speed rises towards sprint speed.
		target.y = 1.0 + clampf((-local.z - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)
	if not is_on_floor():
		target *= 0.3
	_blend_pos = _blend_pos.lerp(target, clampf(10.0 * delta, 0.0, 1.0))
	tree.set("parameters/loco/blend_position", _blend_pos)
	_aim_amount = lerpf(_aim_amount, 1.0 if weapon_up else 0.0, clampf(12.0 * delta, 0.0, 1.0))
	tree.set("parameters/aim_blend/blend_amount", _aim_amount)


## Used only if the rigged model is missing: a simple bob and sway.
func _animate_fake(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob_t += delta * hspeed * 1.8
		visual.position.y = absf(sin(_bob_t)) * 0.07
		visual.rotation.z = sin(_bob_t) * 0.05
	else:
		var k := clampf(10.0 * delta, 0.0, 1.0)
		visual.position.y = lerpf(visual.position.y, 0.0, k)
		visual.rotation.z = lerpf(visual.rotation.z, 0.0, k)


## Raycast through the crosshair; used for giving the droid orders.
func aim_hit() -> Dictionary:
	if camera == null:
		return {}
	var centre := get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(centre)
	var to := from + _view_dir() * 120.0
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 1 | 4))


## What the crosshair is on (or a point far away along it).
## Straight out of the middle of the screen.
func _view_dir() -> Vector3:
	var d := -camera.global_transform.basis.z
	return d.normalized() if d.is_finite() and d.length_squared() > 1e-8 else -global_transform.basis.z


func _update_aim_point() -> void:
	if not camera.global_position.is_finite():
		return
	if free_cam:
		var fwd := -model.global_transform.basis.z
		_aim_point = global_position + Vector3.UP * 1.4 + fwd * 60.0
		_has_aim_point = true
		return
	var space := get_world_3d().direct_space_state
	var centre := get_viewport().get_visible_rect().size * 0.5
	if centre.x < 1.0 or centre.y < 1.0:
		return   # window minimised / hidden: no valid view to aim from
	var from := camera.project_ray_origin(centre)
	if not from.is_finite():
		return
	var to := from + _view_dir() * 250.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 4))
	_aim_point = hit["position"] if not hit.is_empty() else to
	_has_aim_point = true


func _shoot() -> void:
	if _reload_t > 0.0:
		return
	if ammo == 0:
		Sfx.ui("ui_click", -4.0)
		_fire_cd = 0.35
		return
	if ammo > 0:
		ammo -= 1
		ammo_changed.emit(ammo)
	elif not infinite_ammo and weapon == "primary":
		if GS.mag <= 0:
			Sfx.ui("ui_click", -4.0)
			_fire_cd = 0.35
			_start_reload()
			return
		GS.mag -= 1
	var space := get_world_3d().direct_space_state
	var centre := get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(centre)
	var to := from + _view_dir() * 250.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	var hit := space.intersect_ray(query)
	var target_point := to
	if not hit.is_empty():
		target_point = hit["position"]
		var col = hit["collider"]
		if col != null and col.has_method("take_damage"):
			var dmg := damage
			var hp = col.get("health")
			var hp_max = col.get("max_health")
			if GS.rank("executioner") > 0 and hp != null and hp_max != null and float(hp_max) > 0.0 and float(hp) / float(hp_max) < 0.3:
				dmg *= 1.4
			var crit := randf() < GS.crit_chance()
			if crit:
				dmg *= GS.crit_mult()
				_crit_popup(target_point, dmg)
			col.take_damage(dmg, (target_point - global_position).normalized())
			var killed: bool = col.has_method("is_dead") and col.is_dead()
			hit_landed.emit(killed)
			if killed and GS.rank("adrenaline") > 0:
				heal(6.0 * GS.rank("adrenaline"))
			Sfx.at(target_point, "impact", -8.0, 0.15, 6.0)

	var bolt := BoltScript.new()
	get_parent().add_child(bolt)
	bolt.launch(muzzle.global_position, target_point, not hit.is_empty())
	Sfx.ui("blaster", -9.0, 0.06)

	muzzle_light.light_energy = 6.0
	cam_pitch.rotation.x = minf(cam_pitch.rotation.x + 0.006, deg_to_rad(45.0))


# ------------------------------------------------------------ health

## Small "CRIT" number that floats up off the target.
func _crit_popup(at: Vector3, dmg: float) -> void:
	var l := Label3D.new()
	l.text = "CRIT %d" % int(round(dmg))
	l.font_size = 44
	l.pixel_size = 0.004
	l.outline_size = 10
	l.modulate = Color(1.0, 0.75, 0.25)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	get_parent().add_child(l)
	l.global_position = at + Vector3.UP * 0.3
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", at + Vector3.UP * 1.3, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


var _since_hit := 99.0
var _invuln_t := 0.0

func take_damage(amount: float, _from_dir := Vector3.ZERO) -> void:
	if is_dead or _invuln_t > 0.0:
		return
	if randf() < GS.evade_chance():
		_combat_text("EVADED", Color(0.6, 0.85, 1.0))
		return
	amount *= GS.damage_taken_mult()
	if randf() < GS.block_chance():
		amount *= 1.0 - GS.BLOCK_ABSORB
		_combat_text("BLOCKED", Color(0.75, 0.8, 0.9))
	_since_hit = 0.0
	if health - amount <= 0.0 and health_floor <= 0.0 and GS.try_last_stand():
		health = 1.0
		_invuln_t = 3.0
		health_changed.emit(health, max_health)
		_combat_text("LAST STAND", Color(1.0, 0.35, 0.25))
		return
	health = maxf(health - amount, health_floor)
	health_changed.emit(health, max_health)
	Sfx.ui("player_hit", -3.0, 0.1)
	if health <= 0.0:
		_die()
	elif tree != null and anim.has_animation("hit"):
		tree.set("parameters/hit_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _combat_text(text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.004
	l.outline_size = 10
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.position = Vector3(0.0, 2.2, 0.0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 2.9, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func _die() -> void:
	is_dead = true
	died.emit()
	if _rigged and anim.has_animation("death"):
		tree.active = false
		anim.play("death", 0.15)
	else:
		var tw := create_tween()
		tw.tween_property(visual, "rotation:x", deg_to_rad(80.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
