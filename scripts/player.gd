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
## New rigs (Nov 2026, see RIGGING.md): each character is rigged once in Mixamo
## and every animation was downloaded from that same rig, so the clips fit the
## body exactly. If a file is missing the old rig below is used instead.
const V2_RIGS := {
	"trooper": {"rig": "res://models/player_v2/mainman.fbx", "anims": "res://models/player_v2/mainman_anims/"},
	"survivor": {"rig": "res://models/player_v2/mainlady.fbx", "anims": "res://models/player_v2/mainlady_anims/"},
}
## Game animation name -> file name in the folders above.
const V2_ANIMS := {
	"idle": "idle", "run": "run", "fire": "fire", "hit": "hit", "death": "death",
	"walk_fwd": "walk_forward", "walk_back": "walk_back", "walk_left": "walk_left", "walk_right": "walk_right",
	"crouch_idle": "crouch_idle", "crouch_fwd": "crouch_forward", "crouch_back": "crouch_back", "crouch_left": "crouch_left",
	"prone_idle": "prone_idle", "prone_fwd": "prone_forward", "prone_back": "prone_back",
	"prone_turn_left": "prone_turn_left", "prone_turn_right": "prone_turn_right", "prone_fire": "prone_fire",
	"swim_idle": "swim_idle", "swim_fwd": "swim_fwd",
}
const ANIM_FILES := {
	"run": "res://models/anim_run.fbx",
	"walk_fwd": "res://models/anim_walk_fwd.fbx",
	"walk_back": "res://models/anim_walk_back.fbx",
	"walk_left": "res://models/anim_walk_left.fbx",
	"walk_right": "res://models/anim_walk_right.fbx",
	"fire": "res://models/anim_fire.fbx",
	"hit": "res://models/anim_hit.fbx",
	"death": "res://models/anim_death.fbx",
	"crouch_idle": "res://models/anim_crouch_idle.fbx",
	"crouch_fwd": "res://models/anim_crouch_fwd.fbx",
	"crouch_back": "res://models/anim_crouch_back.fbx",
	"crouch_left": "res://models/anim_crouch_left.fbx",
}
const LOOPING := ["idle", "run", "fire", "walk_fwd", "walk_back", "walk_left", "walk_right",
		"crouch_idle", "crouch_fwd", "crouch_back", "crouch_left",
		"prone_idle", "prone_fwd", "prone_back", "prone_turn_left", "prone_turn_right", "prone_fire",
		"swim_idle", "swim_fwd"]
const NO_ROOT_MOTION := ["idle", "run", "fire", "walk_fwd", "walk_back", "walk_left", "walk_right", "hit",
		"crouch_idle", "crouch_fwd", "crouch_back", "crouch_left",
		"prone_idle", "prone_fwd", "prone_back", "prone_turn_left", "prone_turn_right", "prone_fire",
		"swim_idle", "swim_fwd"]
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
## Crouched (C toggles): slower and quieter; sleeping drones don't hear you.
var crouched := false
var _crouch_amount := 0.0
const CROUCH_SPEED_MULT := 0.5
## Fires when you crouch or stand (for tutorials).
signal crouch_changed(on: bool)
## Lying prone (Z toggles): very slow, lowest profile. Needs the new rigs'
## prone animations (both characters have them).
## Set by the area each frame while you wade (1 = dry land, lower = slower).
var wade_mult := 1.0

## Swimming. The area sets water_at: a Callable(Vector3) -> float giving the
## water surface height there (-INF where there's no water). Water deeper
## than SWIM_DEPTH at your feet and you swim: Space rises, C dives, look
## down and swim forwards to dive too. No shooting in the water.
var water_at: Callable
var swimming := false
var breath := BREATH_MAX
var _swim_amount := 0.0
var _swim_move := 0.0
var _has_swim := false
var _water_y := -INF
var _wet := false
var _drown_t := 0.0
var _swim_ui: CanvasLayer
var _breath_bar: ColorRect
var _breath_back: ColorRect
var _underwater_tint: ColorRect
const BREATH_MAX := 20.0
const SWIM_SPEED := 2.4
const SWIM_SPRINT := 3.9
const SWIM_DEPTH := 1.35    # water this deep at your feet and you float
const FLOAT_DEPTH := 1.5    # feet this far under the surface while treading water
const SWIM_LIFT := 0.62     # raises the body for the flat-out swim stroke
signal swimming_changed(on: bool)

var prone := false
var _prone_amount := 0.0
var _has_prone := false
const PRONE_SPEED_MULT := 0.3
signal prone_changed(on: bool)
## Every shot you fire (sleeping drones hear it).
signal shot_fired
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
var _has_crouch := false

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
	# The mini drone from the freighter flies with you once it's fixed.
	if not display_only and GS.flags.get("drone_installed", false):
		_spawn_mini_drone.call_deferred()
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
	if V2_RIGS.has(character) and _load_rigged_v2(holder, V2_RIGS[character]):
		return
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


## New rigs: the model and its own 13 animations (all made on this exact body).
## Returns false (and leaves nothing behind) if the rig or its idle is missing,
## so the old rig loads instead.
func _load_rigged_v2(holder: Node3D, cfg: Dictionary) -> bool:
	var rig_path: String = cfg["rig"]
	var dir: String = cfg["anims"]
	if not ResourceLoader.exists(rig_path) or not ResourceLoader.exists(dir + "idle.fbx"):
		return false
	var inst: Node3D = load(rig_path).instantiate()
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		inst.free()
		return false
	holder.add_child(inst)
	skeleton = skels[0]
	# Mixamo writes metres but labels them centimetres, so the import comes in
	# 100x too small. Scale by exactly 100 to keep each character's real height.
	var h := U.collect_aabb(inst).size.y
	if h > 0.0001 and h < 0.1:
		inst.scale = Vector3.ONE * 100.0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			mi.skeleton = mi.get_path_to(skeleton)
	skeleton.show_rest_only = false

	anim = AnimationPlayer.new()
	anim.name = "TrooperAnims"
	inst.add_child(anim)   # root_node ".." -> inst
	var skel_path := String(inst.get_path_to(skeleton))
	var lib := AnimationLibrary.new()
	for anim_name in V2_ANIMS:
		var path := dir + String(V2_ANIMS[anim_name]) + ".fbx"
		if not ResourceLoader.exists(path):
			continue
		var src_scene: Node = load(path).instantiate()
		_add_anim(lib, anim_name, src_scene, skel_path, true)
		src_scene.free()
	anim.add_animation_library("", lib)

	_hand_r = _find_bone("RightHand")
	_hand_l = _find_bone("LeftHand")
	_rigged = lib.has_animation("idle")
	if _rigged:
		_build_tree(inst, skel_path)
	return true


## Copies the first animation of `scene_root` into `lib`, re-pointing every
## bone track at our character's skeleton. `same_body`: the clip was made on
## this exact rig, so every track (position and scale too) is kept as is.
func _add_anim(lib: AnimationLibrary, anim_name: String, scene_root: Node, skel_path: String, same_body := false) -> void:
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
			if not same_body:
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

	# Crouched locomotion; strafing right plays the left strafe backwards.
	var crouch := AnimationNodeBlendSpace2D.new()
	crouch.min_space = Vector2(-1.5, -1.5)
	crouch.max_space = Vector2(1.5, 1.5)
	var cpoints := [["crouch_idle", Vector2.ZERO, false], ["crouch_fwd", Vector2(0, 1), false],
			["crouch_back", Vector2(0, -1), false], ["crouch_left", Vector2(-1, 0), false],
			["crouch_left", Vector2(1, 0), true]]
	_has_crouch = anim.has_animation("crouch_idle")
	if _has_crouch:
		for cp in cpoints:
			if anim.has_animation(cp[0]):
				var cn := AnimationNodeAnimation.new()
				cn.animation = cp[0]
				if cp[2]:
					cn.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
				crouch.add_blend_point(cn, cp[1])
		bt.add_node("crouch", crouch)
		var cmix := AnimationNodeBlend2.new()
		bt.add_node("crouch_mix", cmix)
		bt.connect_node("crouch_mix", 0, "loco")
		bt.connect_node("crouch_mix", 1, "crouch")

	# Prone: crawl forward/back, turn on the spot for left/right (Mixamo has
	# no sideways crawl), and its own firing pose blended in while shooting.
	_has_prone = anim.has_animation("prone_idle")
	var base_out := "crouch_mix" if _has_crouch else "loco"
	if _has_prone:
		var pspace := AnimationNodeBlendSpace2D.new()
		pspace.min_space = Vector2(-1.5, -1.5)
		pspace.max_space = Vector2(1.5, 1.5)
		for pp in [["prone_idle", Vector2.ZERO], ["prone_fwd", Vector2(0, 1)], ["prone_back", Vector2(0, -1)],
				["prone_turn_left", Vector2(-1, 0)], ["prone_turn_right", Vector2(1, 0)]]:
			if anim.has_animation(pp[0]):
				var pn := AnimationNodeAnimation.new()
				pn.animation = pp[0]
				pspace.add_blend_point(pn, pp[1])
		bt.add_node("prone", pspace)
		var pfire := AnimationNodeAnimation.new()
		pfire.animation = "prone_fire" if anim.has_animation("prone_fire") else "prone_idle"
		bt.add_node("prone_fire", pfire)
		var pfmix := AnimationNodeBlend2.new()
		bt.add_node("prone_fire_mix", pfmix)
		bt.connect_node("prone_fire_mix", 0, "prone")
		bt.connect_node("prone_fire_mix", 1, "prone_fire")
		var pmix := AnimationNodeBlend2.new()
		bt.add_node("prone_mix", pmix)
		bt.connect_node("prone_mix", 0, base_out)
		bt.connect_node("prone_mix", 1, "prone_fire_mix")
		base_out = "prone_mix"

	# Swimming: tread water when still, front crawl when moving.
	_has_swim = anim.has_animation("swim_idle")
	if _has_swim:
		var sspace := AnimationNodeBlendSpace1D.new()
		sspace.min_space = 0.0
		sspace.max_space = 1.0
		var si := AnimationNodeAnimation.new()
		si.animation = "swim_idle"
		sspace.add_blend_point(si, 0.0)
		var sf := AnimationNodeAnimation.new()
		sf.animation = "swim_fwd" if anim.has_animation("swim_fwd") else "swim_idle"
		sspace.add_blend_point(sf, 1.0)
		bt.add_node("swim", sspace)
		var smix := AnimationNodeBlend2.new()
		bt.add_node("swim_mix", smix)
		bt.connect_node("swim_mix", 0, base_out)
		bt.connect_node("swim_mix", 1, "swim")
		base_out = "swim_mix"

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

	bt.connect_node("aim_blend", 0, base_out)
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


func set_crouched(on: bool) -> void:
	if on == crouched:
		return
	if on:
		set_prone(false)
	crouched = on
	crouch_changed.emit(on)


func set_prone(on: bool) -> void:
	if on == prone or (on and not _has_prone):
		return
	if on:
		set_crouched(false)
	prone = on
	prone_changed.emit(on)


## True when you're crouched and moving slowly enough to stay quiet.
func is_sneaking() -> bool:
	return (crouched and _crouch_amount > 0.6) or (prone and _prone_amount > 0.6)


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
	_pistol_model = Node3D.new()
	_pistol_model.visible = false
	gun.add_child(_pistol_model)
	_mount_weapons()
	muzzle = Node3D.new()
	muzzle.position = _rifle_muzzle
	gun.add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.25, 0.2)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 4.0
	muzzle.add_child(muzzle_light)
	# Knuckle for the palm: middle finger if the rig has one, else the index
	# chain (the new rigs have only a single finger chain, named Index).
	if skeleton != null:
		_hand_r2 = _find_bone("RightHandMiddle1")
		if _hand_r2 < 0:
			_hand_r2 = _find_bone("RightHandIndex1")
		_hand_l2 = _find_bone("LeftHandMiddle1")
		if _hand_l2 < 0:
			_hand_l2 = _find_bone("LeftHandIndex1")
	_show_weapon_model()


## Puts the equipped weapons' models in the gun mount. Weapons with a
## "model" in Items.ITEMS (the Meshy guns: long axis X, muzzle at -X, 1.9
## units long) are scaled to their real length ("len", metres) and moved so
## their grip sits on the mount's grip; others use the built-in rifle/pistol.
var _mounted := {"primary": "-", "sidearm": "-"}
var _muzzles := {"primary": GUN_MUZZLE, "sidearm": PistolModel.MUZZLE}

func _mount_weapons() -> void:
	if _rifle_model == null or _pistol_model == null:
		return
	for slot in ["primary", "sidearm"]:
		# Menu previews show that character's own equipped weapons too.
		var eq: Dictionary = GS.equipment_of(character) if display_only else GS.equipment
		var id := String(eq.get(slot, ""))
		if _mounted[slot] == id:
			continue
		_mounted[slot] = id
		var holder: Node3D = _rifle_model if slot == "primary" else _pistol_model
		for c in holder.get_children():
			c.queue_free()
		var it := GS.item(id)
		if it.has("model") and ResourceLoader.exists(String(it["model"])):
			var k := float(it["len"]) / gun_length
			var grip: Vector2 = it["grip"]
			var mz: Vector2 = it["muzzle"]
			var m: Node3D = load(String(it["model"])).instantiate()
			m.scale = Vector3.ONE * k
			m.position = GUN_GRIP - Vector3(grip.x, grip.y, 0.0) * k
			holder.add_child(m)
			_muzzles[slot] = GUN_GRIP + Vector3(mz.x - grip.x, mz.y - grip.y, 0.0) * k
		elif slot == "primary":
			var r := Node3D.new()
			holder.add_child(r)
			_muzzles[slot] = GUN_MUZZLE
			if character == "survivor" and ResourceLoader.exists(SURVIVOR_RIFLE):
				r.add_child(load(SURVIVOR_RIFLE).instantiate())
				r.scale = Vector3.ONE * SURVIVOR_RIFLE_SCALE
				r.position = SURVIVOR_RIFLE_OFFSET
				_muzzles[slot] = SURVIVOR_RIFLE_MUZZLE
			elif ResourceLoader.exists(BLASTER_PATH):
				r.add_child(load(BLASTER_PATH).instantiate())
			_rifle_muzzle = _muzzles[slot]
		else:
			holder.add_child(PistolModel.build())
			_muzzles[slot] = PistolModel.MUZZLE


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
	# Hold-to-crouch: stand when C is let go.
	if event is InputEventKey and not event.pressed and event.physical_keycode == KEY_C and not Settings.crouch_toggle:
		set_crouched(false)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Settings.mouse_sensitivity
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			sens *= Settings.aim_sensitivity
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
				if swimming:
					pass                  # held to rise (see _swim_vertical)
				elif prone:
					set_prone(false)      # get up first
				elif crouched:
					set_crouched(false)   # stand up first
				else:
					_want_jump = true
			KEY_C:
				if input_enabled and not swimming and not seated and not sleeping and not pinned and not is_dead:
					set_crouched(not crouched if Settings.crouch_toggle else true)
			KEY_Z:
				if input_enabled and not swimming and not seated and not sleeping and not pinned and not is_dead:
					set_prone(not prone)
			KEY_R:
				_start_reload()
			KEY_Q:
				_switch_weapon()
			KEY_H:
				_quick_heal()
			KEY_G:
				if not swimming:
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
	var aid := GS.ammo_item()
	var aname: String = "fuel canisters" if aid == "fuel" else ("heavy cells" if aid == "heavy_cell" else "cartridges")
	return "%d %s   ·   R reload%s" % [GS.count(aid), aname, "   ·   Q: sidearm" if GS.equipment.get("sidearm", "") != "" else ""]


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
	_mount_weapons()
	var pistol := weapon == "sidearm"
	_rifle_model.visible = not pistol
	_pistol_model.visible = pistol
	if muzzle != null:
		muzzle.position = _muzzles[weapon]
	Sfx.ui("ui_click", -6.0)


func _start_reload() -> void:
	if ammo >= 0 or infinite_ammo or weapon != "primary" or _reload_t > 0.0:
		return
	if GS.mag >= GS.mag_size():
		return
	var ammo_id := GS.ammo_item()
	if GS.count(ammo_id) <= 0:
		GS.toast("No %s. Craft some at the bench, or search wrecks." % String(GS.item(ammo_id).get("name", ammo_id)))
		return
	_reload_t = 1.4 * GS.reload_time_mult()
	Sfx.ui("crate_open", -10.0, 0.1)


func _finish_reload() -> void:
	if GS.remove_item(GS.ammo_item(), 1):
		GS.mag = GS.mag_size()
		GS.changed()


func _quick_heal() -> void:
	if health >= max_health:
		return
	for id in ["bandage", "ration", "coagulant", "antivenom", "stim", "trauma_kit"]:
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
	tw.tween_callback(_grenade_boom.bind(g, float(it.get("damage", 60.0)) * GS.grenade_mult(), float(it.get("radius", 4.0)) + GS.grenade_radius_bonus(),
			String(it.get("effect", "frag"))))


func _grenade_arc(t: float, g: Node3D, from: Vector3, to: Vector3) -> void:
	g.global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 2.5


func _grenade_boom(g: Node3D, dmg: float, radius: float, effect := "frag") -> void:
	if effect == "frag":
		_explode(g.global_position, dmg, radius)
	else:
		CombatFX.get_for(self).grenade(effect, g.global_position, dmg, radius)
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
	_flame_tick(delta)
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
	_crouch_amount = move_toward(_crouch_amount, 1.0 if crouched else 0.0, delta * 5.0)
	_prone_amount = move_toward(_prone_amount, 1.0 if prone else 0.0, delta * 2.5)
	if _rigged and tree != null and tree.active:
		tree.advance(delta)
		_twist_spine()
		_seat_legs()
	_sleep_amount = move_toward(_sleep_amount, 1.0 if sleeping else 0.0, delta * (4.0 if sleeping else 0.9))
	if model != null:
		model.position.y = -0.82 * _seat_amount + 0.16 * _sleep_amount + (SWIM_LIFT * _swim_amount * _swim_move if _has_swim else 0.0)
		# Lying on your back: tip the whole body over backwards.
		model.rotation.x = deg_to_rad(90.0) * _sleep_amount
	if gun != null:
		gun.visible = _sleep_amount < 0.4 and _swim_amount < 0.4
	if cam_yaw != null:
		# Seated: camera up over her shoulder, looking down past you.
		cam_yaw.position.y = 1.55 + (-0.45 if pinned else 0.45) * _seat_amount - 0.5 * _crouch_amount - 0.95 * _prone_amount
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
		_rotate_bone(b, sb.inverse() * w * sb)
	for b in _knee_bones:
		_rotate_bone(b, sb.inverse() * Basis(right, deg_to_rad(-12.0) * _seat_amount) * sb)


## Turns bone `b` by `step` (in skeleton space) by changing ONLY its rotation.
## set_bone_global_pose() also rewrote position and scale, which the
## animations never reset, so tiny errors built up until limbs stretched
## (fixed only by a reload). Rotation is re-set by the animation every frame,
## so nothing can build up now.
func _rotate_bone(b: int, step: Basis) -> void:
	var target := step * skeleton.get_bone_global_pose(b).basis
	var p := skeleton.get_bone_parent(b)
	var parent_basis := skeleton.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(b, (parent_basis.inverse() * target).get_rotation_quaternion())


## Turns the spine so the upper body follows the camera while the legs stay put.
func _twist_spine() -> void:
	if _spine_bones.is_empty() or (absf(torso_yaw) < 0.001 and absf(torso_pitch) < 0.001):
		return
	var sb := skeleton.global_transform.basis.orthonormalized()
	var right := model.global_transform.basis.x.normalized()
	var n := float(_spine_bones.size())
	# Lying down you can't twist far: the body turns instead.
	var k := 1.0 - 0.7 * _prone_amount
	var step_world := Basis(Vector3.UP, torso_yaw * k / n) * Basis(right, torso_pitch * k / n)
	var step := sb.inverse() * step_world * sb
	for b in _spine_bones:
		_rotate_bone(b, step)


func _physics_process(delta: float) -> void:
	if display_only:
		if _rigged:
			_update_anim(delta, false)
		return
	_update_water(delta)
	if not is_on_floor() and not swimming:
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
	var shooting := captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not swimming
	var aiming := captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not swimming
	# Sprint only forwards and not while shooting or aiming.
	var sprinting := input_enabled and Input.is_physical_key_pressed(KEY_SHIFT) and input.y < -0.5 \
			and not shooting and not aiming
	if sprinting and crouched:
		set_crouched(false)   # sprinting stands you up
	if sprinting and prone:
		set_prone(false)
	var speed := sprint_speed if sprinting else walk_speed
	if crouched:
		speed = walk_speed * CROUCH_SPEED_MULT
	if prone:
		speed = walk_speed * PRONE_SPEED_MULT
	if aiming:
		speed *= 0.75
	speed *= wade_mult
	if swimming:
		speed = SWIM_SPRINT if (input_enabled and Input.is_physical_key_pressed(KEY_SHIFT) and input.y < -0.5) else SWIM_SPEED
	var accel := 12.0 if is_on_floor() else 3.0
	if swimming:
		accel = 3.5
	var t := clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, dir.x * speed, t)
	velocity.z = lerpf(velocity.z, dir.z * speed, t)

	if swimming:
		_swim_vertical(input, speed, delta)
	elif _want_jump and is_on_floor():
		velocity.y = jump_velocity
	var climbing := _climb(dir, delta)
	_want_jump = false

	move_and_slide()

	# Footsteps.
	var hs := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hs > 0.6 and not swimming:
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
	if moving and swimming:
		# Swimming: the body turns to face the way you're swimming.
		_turning = false
		_facing_yaw = lerp_angle(_facing_yaw, atan2(-velocity.x, -velocity.z), clampf(5.0 * delta, 0.0, 1.0))
	elif moving:
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
	camera.fov = lerpf(camera.fov, Settings.fov - 15.0 if aiming else Settings.fov, clampf(10.0 * delta, 0.0, 1.0))

	if _rigged:
		_update_anim(delta, shooting or aiming or crouched)
		if _has_prone:
			tree.set("parameters/prone_fire_mix/blend_amount", 1.0 if (shooting or aiming) and prone else 0.0)
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
	camera.fov = lerpf(camera.fov, Settings.fov - 15.0 if aiming else Settings.fov, clampf(10.0 * delta, 0.0, 1.0))
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
	if prone:
		target = Vector2(local.x, -local.z) / (walk_speed * PRONE_SPEED_MULT)
	elif crouched:
		target = Vector2(local.x, -local.z) / (walk_speed * CROUCH_SPEED_MULT)
	elif target.y > 1.0:
		# Between walk (1) and run (2) as speed rises towards sprint speed.
		target.y = 1.0 + clampf((-local.z - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)
	if not is_on_floor():
		target *= 0.3
	_blend_pos = _blend_pos.lerp(target, clampf(10.0 * delta, 0.0, 1.0))
	tree.set("parameters/loco/blend_position", _blend_pos)
	if _has_crouch:
		tree.set("parameters/crouch/blend_position", _blend_pos.limit_length(1.0))
		tree.set("parameters/crouch_mix/blend_amount", _crouch_amount)
	if _has_prone:
		tree.set("parameters/prone/blend_position", _blend_pos.limit_length(1.0))
		tree.set("parameters/prone_mix/blend_amount", _prone_amount)
	_aim_amount = lerpf(_aim_amount, 1.0 if weapon_up else 0.0, clampf(12.0 * delta, 0.0, 1.0))
	if _has_swim:
		tree.set("parameters/swim/blend_position", _swim_move)
		tree.set("parameters/swim_mix/blend_amount", _swim_amount)
	# Prone has its own firing pose, so the standing upper-body aim fades out.
	tree.set("parameters/aim_blend/blend_amount", _aim_amount * (1.0 - _prone_amount) * (1.0 - _swim_amount))


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
	if GS.item(GS.equipment.get(weapon, "")).get("flame", false):
		_shoot_flame()
		return
	if ammo == 0:
		Sfx.ui("ui_click", -4.0)
		_fire_cd = 0.35
		return
	shot_fired.emit()
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
	# The pistol has its own snappier shot.
	Sfx.ui("pistol_shot" if weapon == "sidearm" else "blaster", -9.0, 0.06)

	muzzle_light.light_energy = 6.0
	if Settings.camera_recoil:
		cam_pitch.rotation.x = minf(cam_pitch.rotation.x + 0.006, deg_to_rad(45.0))


func _spawn_mini_drone() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var d = load("res://scripts/mini_drone.gd").new()
	d.name = "MiniDrone"
	d.player = self
	get_parent().add_child(d)


# ------------------------------------------------------------ flamethrower

const FLAME_SPEED := 22.0
const CombatFX = preload("res://scripts/combat_fx.gd")
var _flame: GPUParticles3D
var _flame_light: OmniLight3D
var _flame_sound: AudioStreamPlayer3D
var _flame_t := 0.0

## A short-range stream of fire: hurts every creature in a narrow cone in
## front of the nozzle (they hate fire, LORE.md). No ammo for now (testing).
func _shoot_flame() -> void:
	if not infinite_ammo and ammo < 0:
		if GS.mag <= 0:
			Sfx.ui("ui_click", -4.0)
			_fire_cd = 0.35
			_start_reload()
			return
		GS.mag -= 1
	shot_fired.emit()
	var dir := _view_dir()
	var origin := muzzle.global_position
	# Burning gel flies in an arc (about 20 m on the flat), hurts what it
	# touches and keeps burning where it lands (combat_fx.gd).
	var jitter := Vector3(randf_range(-0.5, 0.5), randf_range(-0.2, 0.5), randf_range(-0.5, 0.5))
	CombatFX.get_for(self).fire_glob(origin + dir * 0.3, dir * FLAME_SPEED + jitter, damage)
	if _flame == null:
		_build_flame()
	_flame.global_position = origin
	_flame.look_at(origin + dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	_flame.emitting = true
	_flame_light.global_position = origin + dir * 1.5
	_flame_light.light_energy = randf_range(3.0, 5.0)
	if not _flame_sound.playing:
		_flame_sound.play()
	_flame_sound.global_position = origin
	_flame_t = 0.15


func _build_flame() -> void:
	_flame = GPUParticles3D.new()
	_flame.top_level = true
	_flame.amount = 260
	_flame.lifetime = 1.1
	_flame.local_coords = false
	_flame.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 4.0
	pm.initial_velocity_min = FLAME_SPEED - 2.0
	pm.initial_velocity_max = FLAME_SPEED + 1.0
	pm.gravity = Vector3(0, -CombatFX.GRAVITY, 0)   # same arc as the burning gel
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(0.5, 1.0))
	sc.add_point(Vector2(1.0, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.set_color(1, Color(0.15, 0.1, 0.08, 0.0))
	g.add_point(0.25, Color(1.0, 0.55, 0.12, 0.95))
	g.add_point(0.6, Color(0.8, 0.2, 0.05, 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_flame.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	mat.albedo_texture = dot
	quad.material = mat
	_flame.draw_pass_1 = quad
	add_child(_flame)
	_flame_light = OmniLight3D.new()
	_flame_light.top_level = true
	_flame_light.light_color = Color(1.0, 0.55, 0.2)
	_flame_light.omni_range = 7.0
	_flame_light.light_energy = 0.0
	add_child(_flame_light)
	_flame_sound = AudioStreamPlayer3D.new()
	_flame_sound.top_level = true
	_flame_sound.stream = Sfx.stream("fire_loop")
	_flame_sound.pitch_scale = 1.6
	_flame_sound.volume_db = -2.0
	add_child(_flame_sound)


func _flame_tick(delta: float) -> void:
	if _flame == null or _flame_t <= 0.0:
		return
	_flame_t -= delta
	if _flame_t <= 0.0:
		_flame.emitting = false
		_flame_light.light_energy = 0.0
		_flame_sound.stop()


# ------------------------------------------------------------ health

## Small "CRIT" number that floats up off the target.
func _crit_popup(at: Vector3, dmg: float) -> void:
	if not Settings.damage_numbers:
		return
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
	if health - amount <= 0.0 and health_floor <= 0.0 and GS.try_second_chance():
		health = max_health * 0.4
		_invuln_t = 1.5
		health_changed.emit(health, max_health)
		_combat_text("SECOND CHANCE", Color(0.5, 1.0, 0.6))
		return
	health = maxf(health - amount, health_floor)
	health_changed.emit(health, max_health)
	if health > 0.0 and health < max_health * 0.25:
		var inj := GS.auto_injector_item()
		if inj != "":
			use_item(inj)
			_combat_text("AUTO-INJECTOR", Color(0.5, 1.0, 0.6))
	Sfx.ui("player_hit", -3.0, 0.1)
	if health <= 0.0:
		_die()
	elif tree != null and anim.has_animation("hit"):
		tree.set("parameters/hit_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _combat_text(text: String, col: Color) -> void:
	if not Settings.damage_numbers:
		return
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


## Dies outright: no evade, block or last stand (e.g. the sentry drone).
func kill() -> void:
	if is_dead:
		return
	health = 0.0
	health_changed.emit(health, max_health)
	_die()


## Back on your feet at `pos` with full health (checkpoint respawn).
func revive(pos: Vector3, yaw: float) -> void:
	is_dead = false
	set_crouched(false)
	_crouch_amount = 0.0
	set_prone(false)
	_prone_amount = 0.0
	velocity = Vector3.ZERO
	global_position = pos
	health = max_health
	health_changed.emit(health, max_health)
	_invuln_t = 2.0
	_facing_yaw = yaw
	model.rotation.y = yaw
	if cam_yaw != null:
		cam_yaw.rotation.y = yaw
	visual.rotation.x = 0.0
	if _rigged:
		anim.stop()
		tree.active = true
	torso_yaw = 0.0
	torso_pitch = 0.0


func _die() -> void:
	is_dead = true
	set_crouched(false)
	set_prone(false)
	died.emit()
	if _rigged and anim.has_animation("death"):
		tree.active = false
		anim.play("death", 0.15)
	else:
		var tw := create_tween()
		tw.tween_property(visual, "rotation:x", deg_to_rad(80.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ------------------------------------------------------------ swimming

## Water depth at your feet, getting in and out, breath and drowning.
func _update_water(delta: float) -> void:
	_water_y = float(water_at.call(global_position)) if water_at.is_valid() else -INF
	var depth := _water_y - global_position.y
	if not swimming and depth > SWIM_DEPTH and not is_dead and not seated and not sleeping:
		_set_swimming(true)
	elif swimming and (is_dead or (depth < SWIM_DEPTH - 0.3 and is_on_floor()) or depth < 0.5):
		_set_swimming(false)
	# Wading slows you the deeper it gets, with a splash on the way in.
	wade_mult = 1.0 if swimming else lerpf(1.0, 0.5, clampf((depth - 0.1) / 0.7, 0.0, 1.0))
	var wet := depth > 0.2
	if wet and not _wet:
		Sfx.at(global_position + Vector3.UP * 0.3, "splash", -5.0, 0.15, 7.0, 0.3)
	_wet = wet
	_swim_amount = move_toward(_swim_amount, 1.0 if swimming else 0.0, delta * 3.0)
	var hs := Vector2(velocity.x, velocity.z).length()
	_swim_move = move_toward(_swim_move, clampf(hs / SWIM_SPEED, 0.0, 1.0) if swimming else 0.0, delta * 2.5)
	# Lean into dives and climbs (the stroke swims flat, so tip the body).
	var tilt := 0.0
	if swimming and hs > 0.4:
		tilt = clampf(atan2(velocity.y, hs), -1.0, 0.8) * 0.9
	visual.rotation.x = lerp_angle(visual.rotation.x, tilt, clampf(delta * 4.0, 0.0, 1.0))
	# Breath: runs down with your head under, back up as soon as it's clear.
	var head_under := global_position.y + 1.62 + (SWIM_LIFT * _swim_move if _has_swim else 0.0) < _water_y
	if head_under and not is_dead:
		breath = maxf(breath - delta, 0.0)
		if breath <= 0.0:
			_drown_t -= delta
			if _drown_t <= 0.0:
				_drown_t = 1.0
				_drown_hurt(max_health * 0.08)
	else:
		breath = minf(breath + delta * 5.0, BREATH_MAX)
		_drown_t = 0.0
	_update_swim_ui()


func _set_swimming(on: bool) -> void:
	if on == swimming:
		return
	swimming = on
	if on:
		set_crouched(false)
		set_prone(false)
		velocity.y *= 0.25    # the water breaks your fall
		if not GS.flags.get("swim_tip", false):
			GS.flags["swim_tip"] = true
			GS.toast("Swimming: Space rises, hold C to dive (or look down and swim). Watch your breath. No shooting in the water.")
	swimming_changed.emit(on)


## Up and down in the water: float at the surface, Space rises, C dives,
## and swimming forwards follows where you look.
func _swim_vertical(input: Vector2, speed: float, delta: float) -> void:
	var float_y := _water_y - FLOAT_DEPTH
	var want := 0.7    # you drift back up when you stop diving
	var diving := input_enabled and Input.is_physical_key_pressed(KEY_C)
	var rising := input_enabled and Input.is_physical_key_pressed(KEY_SPACE)
	if diving:
		want = -2.4
	elif rising:
		want = 2.4
	# Swim where you look: forwards with the camera tipped down takes you down.
	var pitch: float = cam_pitch.rotation.x
	if input.y < -0.3 and absf(pitch) > 0.3:
		want += sin(pitch) * speed * -input.y
	if global_position.y > float_y - 0.15 and not diving and want > -0.5:
		# At the surface: bob there.
		want = (float_y - global_position.y) * 5.0 + sin(Time.get_ticks_msec() * 0.003) * 0.08
	velocity.y = lerpf(velocity.y, want, clampf(5.0 * delta, 0.0, 1.0))


## Drowning damage: skips dodge/block, which can't save you from water.
func _drown_hurt(amount: float) -> void:
	health = maxf(health - amount, health_floor)
	health_changed.emit(health, max_health)
	_combat_text("DROWNING", Color(0.5, 0.75, 1.0))
	Sfx.ui("player_hit", -6.0, 0.1)
	if health <= 0.0:
		_die()


## Breath bar under the crosshair, and a blue-green tint with the camera under.
func _update_swim_ui() -> void:
	if _swim_ui == null:
		if display_only or not is_inside_tree():
			return
		_swim_ui = CanvasLayer.new()
		_swim_ui.layer = 2
		add_child(_swim_ui)
		_underwater_tint = ColorRect.new()
		_underwater_tint.color = Color(0.05, 0.22, 0.26, 0.45)
		_underwater_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_underwater_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		_swim_ui.add_child(_underwater_tint)
		_breath_back = ColorRect.new()
		_breath_back.color = Color(0.02, 0.05, 0.08, 0.7)
		_breath_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_breath_back.anchor_left = 0.5
		_breath_back.anchor_right = 0.5
		_breath_back.anchor_top = 0.5
		_breath_back.anchor_bottom = 0.5
		_breath_back.offset_left = -110.0
		_breath_back.offset_right = 110.0
		_breath_back.offset_top = 70.0
		_breath_back.offset_bottom = 80.0
		_swim_ui.add_child(_breath_back)
		_breath_bar = ColorRect.new()
		_breath_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_breath_bar.position = Vector2(2.0, 2.0)
		_breath_bar.size = Vector2(216.0, 6.0)
		_breath_back.add_child(_breath_bar)
		var lbl := Label.new()
		lbl.text = "BREATH"
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		lbl.position = Vector2(0.0, -18.0)
		_breath_back.add_child(lbl)
	var frac := breath / BREATH_MAX
	_breath_back.visible = frac < 0.999 and not is_dead
	_breath_bar.size.x = 216.0 * frac
	_breath_bar.color = Color(0.45, 0.85, 1.0) if frac > 0.3 else Color(1.0, 0.4, 0.3)
	_underwater_tint.visible = camera != null and camera.global_position.y < _water_y
