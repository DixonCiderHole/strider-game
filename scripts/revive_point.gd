extends Node3D
## Downed party members (Ilsa, the droid). Added as a child of the member,
## which provides: health, max_health, is_dead (true while down) and revive(frac).
##  - Walk up and hold E for a few seconds to get them back on their feet.
##  - If nobody does, they get up by themselves once no creatures are awake nearby.

const GS = preload("res://scripts/game_state.gd")

const HOLD_TIME := 2.5      # seconds of holding E
const AUTO_TIME := 8.0      # seconds of calm before they get up alone
const REACH := 2.4
const CALM_RANGE := 30.0

var member: Node3D
var _hold := 0.0
var _calm := 0.0
var _label: Label3D


func _ready() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 36
	_label.outline_size = 10
	_label.pixel_size = 0.004
	_label.position = Vector3(0.0, 1.3, 0.0)
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	if member == null or not is_instance_valid(member) or not member.is_dead:
		_hold = 0.0
		_calm = 0.0
		_label.visible = false
		return
	var player = get_tree().get_first_node_in_group("player")
	var near: bool = player != null and not player.is_dead \
			and player.global_position.distance_to(member.global_position) < REACH
	var holding: bool = near and player.input_enabled and Input.is_physical_key_pressed(KEY_E)
	_hold = _hold + delta if holding else maxf(_hold - delta * 2.0, 0.0)
	_label.visible = true
	if near:
		_label.modulate = Color(0.6, 1.0, 0.7)
		_label.text = "REVIVING  %d%%" % int(_hold / HOLD_TIME * 100.0) if _hold > 0.0 else "Hold E to revive"
	else:
		_label.modulate = Color(1.0, 0.4, 0.35)
		_label.text = "DOWN"
	if _hold >= HOLD_TIME:
		member.revive(0.45)
		GS.toast("%s is back on their feet." % String(member.party_name).capitalize())
		return
	# Nobody came: they pick themselves up once the fight's over.
	var calm := true
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.is_dead() or ("dormant" in e and e.dormant):
			continue
		if e.global_position.distance_to(member.global_position) < CALM_RANGE:
			calm = false
			break
	_calm = _calm + delta if calm else 0.0
	if _calm >= AUTO_TIME:
		member.revive(0.3)
		GS.toast("%s picks themselves up." % String(member.party_name).capitalize())
