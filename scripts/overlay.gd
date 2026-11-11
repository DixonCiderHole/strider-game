extends CanvasLayer
## Shared on-screen layer for every area: quest tracker (top right),
## pickup / level-up feed (left), weapon + ammo (bottom right), XP bar,
## and the "[E] ..." prompt for the nearest interactable.

const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const UI = preload("res://scripts/ui.gd")

var player
## Push the quest tracker down when the area already uses the top right.
var tracker_top := 20.0
## Outside the camp, areas show their own objective here instead of the
## camp quest chain (which only starts once you reach the camp).
var area_title := ""
var area_goals := ""

var _root: Control
var _quest_title: Label
var _quest_goals: Label
var _feed: VBoxContainer
var _weapon: Label
var _ammo: Label
var _prompt: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _current = null


func _ready() -> void:
	layer = 5
	GS.ensure_loaded()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Quest tracker
	var qbox := VBoxContainer.new()
	qbox.add_theme_constant_override("separation", 2)
	qbox.anchor_left = 1.0
	qbox.anchor_right = 1.0
	qbox.offset_left = -420
	qbox.offset_right = -28
	qbox.offset_top = tracker_top
	qbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	qbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(qbox)
	var qhead := UI.label("QUEST", 14, UI.ACCENT)
	qhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qbox.add_child(qhead)
	_quest_title = UI.label("", 21, UI.TEXT)
	_quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qbox.add_child(_quest_title)
	_quest_goals = UI.label("", 16, UI.MUTED)
	_quest_goals.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qbox.add_child(_quest_goals)

	# Feed
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 2)
	_feed.anchor_top = 0.35
	_feed.offset_left = 28
	_feed.offset_right = 600
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)

	# Weapon + ammo
	_weapon = UI.label("", 18, UI.MUTED)
	_weapon.anchor_left = 1.0
	_weapon.anchor_right = 1.0
	_weapon.anchor_top = 1.0
	_weapon.anchor_bottom = 1.0
	_weapon.offset_left = -400
	_weapon.offset_right = -28
	_weapon.offset_top = -118
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_weapon)
	_ammo = UI.label("", 34, UI.TEXT)
	_ammo.anchor_left = 1.0
	_ammo.anchor_right = 1.0
	_ammo.anchor_top = 1.0
	_ammo.anchor_bottom = 1.0
	_ammo.offset_left = -400
	_ammo.offset_right = -28
	_ammo.offset_top = -96
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_ammo)

	# Prompt
	_prompt = UI.label("", 24, UI.TEXT)
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = -170
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)

	# XP bar
	_xp_bar = ProgressBar.new()
	_xp_bar.anchor_left = 0.35
	_xp_bar.anchor_right = 0.65
	_xp_bar.anchor_top = 1.0
	_xp_bar.anchor_bottom = 1.0
	_xp_bar.offset_top = -14
	_xp_bar.offset_bottom = -8
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.75, 0.3)
	_xp_bar.add_theme_stylebox_override("background", bg)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_root.add_child(_xp_bar)
	_xp_label = UI.label("", 13, UI.MUTED)
	_xp_label.anchor_left = 0.35
	_xp_label.anchor_right = 0.65
	_xp_label.anchor_top = 1.0
	_xp_label.anchor_bottom = 1.0
	_xp_label.offset_top = -32
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_xp_label)

	GS.listeners.append(_refresh)
	GS.check_quests()
	_refresh()


func _exit_tree() -> void:
	GS.listeners.erase(_refresh)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var q := GS.current_quest()
	if area_title != "":
		_quest_title.text = area_title
		_quest_goals.text = area_goals
	elif q.is_empty():
		_quest_title.text = "Explore"
		_quest_goals.text = "No active quest"
	else:
		_quest_title.text = q["title"]
		var lines := PackedStringArray()
		for g in q["goals"]:
			var done := GS.goal_done(g[0])
			lines.append(("✓ " if done else "• ") + String(g[1]) + GS.goal_progress(g[0]))
		_quest_goals.text = "\n".join(lines)
	var need := Items.xp_for(GS.player_level)
	_xp_bar.max_value = need
	_xp_bar.value = GS.xp
	_xp_label.text = "LEVEL %d   ·   %d / %d XP%s" % [GS.player_level, GS.xp, need, ("   ·   %d SKILL POINT%s (Esc)" % [GS.skill_points, "S" if GS.skill_points > 1 else ""]) if GS.skill_points > 0 else ""]


func _process(_delta: float) -> void:
	# Feed
	while not GS.toasts.is_empty():
		var t: String = GS.toasts.pop_front()
		var l := UI.label(t, 20, Color(1.0, 0.85, 0.5) if t.begins_with("+") else UI.TEXT)
		_feed.add_child(l)
		var tw := l.create_tween()
		tw.tween_interval(3.0)
		tw.tween_property(l, "modulate:a", 0.0, 0.8)
		tw.tween_callback(l.queue_free)
		if _feed.get_child_count() > 7:
			_feed.get_child(0).queue_free()

	if player == null or not is_instance_valid(player):
		_prompt.text = ""
		return
	# Weapon / ammo
	_weapon.text = player.weapon_name() + "   ·   " + player.ammo_hint()
	_ammo.text = player.ammo_text()

	# Nearest interactable
	_current = null
	if player.input_enabled and not player.is_dead:
		var best := 99.0
		for n in get_tree().get_nodes_in_group("interactable"):
			if not n.enabled or not n.is_visible_in_tree():
				continue
			var d: float = player.global_position.distance_to(n.global_position)
			if d < n.reach and d < best and n.get_prompt() != "":
				best = d
				_current = n
	_prompt.text = ("[E]  " + _current.get_prompt()) if _current != null else ""


func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		if _current != null and is_instance_valid(_current) and player.input_enabled:
			get_viewport().set_input_as_handled()
			_current.interact()
