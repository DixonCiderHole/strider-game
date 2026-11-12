extends "res://scripts/interactable.gd"
## "[E] Talk to ..." on a party member. Only offered when you're looking at
## them and nothing story-related is going on: not resting or in a cutscene,
## no dialogue open, no creatures nearby, and no story conversation pending
## (GS.flags["story_busy"]). Story talks always take priority over banter.

const GS = preload("res://scripts/game_state.gd")
const Banter = preload("res://scripts/banter.gd")
const DialogueBox = preload("res://scripts/dialogue_box.gd")

const COMBAT_RANGE := 30.0

var who := "survivor"   # "survivor" or "droid"
var member: Node3D


func _ready() -> void:
	super._ready()
	reach = 2.8
	position = Vector3(0.0, 1.2, 0.0)


func get_prompt() -> String:
	if not available():
		return ""
	if who == "droid":
		return "Talk to the droid"
	return "Talk to Ilsa" if GS.flags.get("knows_ilsa", false) else "Talk to her"


func available() -> bool:
	var tree := get_tree()
	var player = tree.get_first_node_in_group("player")
	if player == null or not player.input_enabled or player.is_dead:
		return false
	if GS.flags.get("story_busy", false) or DialogueBox.is_open(tree):
		return false
	if who == "survivor":
		if not GS.ally_joined or member == null or member.get("mode") in ["sit", "drag"]:
			return false
	# Not mid-fight.
	for e in tree.get_nodes_in_group("enemy"):
		if e.has_method("is_dead") and e.is_dead():
			continue
		if (e as Node3D).global_position.distance_to(player.global_position) < COMBAT_RANGE:
			return false
	# Only when you're actually looking at them.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to := global_position - cam.global_position
	return to.normalized().dot(-cam.global_transform.basis.z) > 0.75


func interact() -> void:
	if not available():
		return
	var player = get_tree().get_first_node_in_group("player")
	var hurt: bool = player != null and float(player.health) < float(player.max_health) * 0.5
	var area := String(get_tree().current_scene.scene_file_path)
	var lines := Banter.pick(who, area, hurt)
	DialogueBox.say(get_tree(), lines, _after)


func _after() -> void:
	if who == "survivor" and member != null and GS.flags.get("knows_ilsa", false):
		member.set("party_name", "ILSA")
	GS.changed()
