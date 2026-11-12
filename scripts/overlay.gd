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
var _hp_bar: ProgressBar
var _hp_label: Label
var _status: VBoxContainer
var _party_box: VBoxContainer
var _party_rows := {}   # node instance id -> {bar_hp, bar_xp, label}
var _compass

## Where the gold compass marker points. Either set `objective_provider`
## (Callable returning a Vector3, or null for none) or add a Node3D to the
## "objective" group.
var objective_provider: Callable
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

	_build_compass()
	_build_status()

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
	_xp_label.text = "LV %d   %d / %d XP%s" % [GS.player_level, GS.xp, need, ("   ·   %d SKILL PT%s" % [GS.skill_points, "S" if GS.skill_points > 1 else ""]) if GS.skill_points > 0 else ""]


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

	_update_party()
	if player == null or not is_instance_valid(player):
		_prompt.text = ""
		_compass.visible = false
		return
	_update_health()
	_update_compass()
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


# ---------------------------------------------------------------- status bars

const BAR_W := 330.0
const HP_COLOR := Color(0.86, 0.16, 0.13)
const XP_COLOR := Color(0.95, 0.75, 0.3)


func _bar(w: float, h: float, fill_color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.03, 0.04, 0.72)
	bg.border_color = Color(1, 1, 1, 0.14)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _bar_text(bar: ProgressBar, size: int) -> Label:
	var l := UI.label("", size, UI.TEXT)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 8
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	bar.add_child(l)
	return l


## Bottom left: allies (if any) above your own health and XP bars.
func _build_status() -> void:
	_status = VBoxContainer.new()
	_status.add_theme_constant_override("separation", 4)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 28
	_status.offset_right = 28 + BAR_W
	_status.offset_top = -22
	_status.offset_bottom = -22
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 8)
	_status.add_child(_party_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_status.add_child(gap)
	_hp_bar = _bar(BAR_W, 22, HP_COLOR)
	_status.add_child(_hp_bar)
	_hp_label = _bar_text(_hp_bar, 15)
	_xp_bar = _bar(BAR_W, 22, XP_COLOR)
	_status.add_child(_xp_bar)
	_xp_label = _bar_text(_xp_bar, 15)


func _update_health() -> void:
	var mx: float = maxf(1.0, player.max_health)
	_hp_bar.max_value = mx
	_hp_bar.value = clampf(player.health, 0.0, mx)
	_hp_label.text = "HP   %d / %d" % [int(round(maxf(player.health, 0.0))), int(round(mx))]


func _update_party() -> void:
	var members := get_tree().get_nodes_in_group("party_member")
	var seen := {}
	for m in members:
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var key: int = m.get_instance_id()
		seen[key] = true
		if not _party_rows.has(key):
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			var name_l := UI.label("", 14, UI.MUTED)
			row.add_child(name_l)
			var hp := _bar(BAR_W * 0.75, 12, HP_COLOR.lerp(Color(0.2, 0.8, 0.9), 0.0))
			row.add_child(hp)
			var xp := _bar(BAR_W * 0.75, 12, XP_COLOR)
			row.add_child(xp)
			_party_box.add_child(row)
			_party_rows[key] = {"row": row, "name": name_l, "hp": hp, "xp": xp}
		var r: Dictionary = _party_rows[key]
		var st := GS.party_stats(m.party_id)
		var need := Items.xp_for(int(st["level"]))
		r["name"].text = "%s   ·   LV %d" % [m.party_name, int(st["level"])]
		r["hp"].max_value = maxf(1.0, m.max_health)
		r["hp"].value = m.health
		r["xp"].max_value = need
		r["xp"].value = int(st["xp"])
	for key in _party_rows.keys():
		if not seen.has(key):
			_party_rows[key]["row"].queue_free()
			_party_rows.erase(key)


# ---------------------------------------------------------------- compass

class CompassBar extends Control:
	const SPAN := 180.0          # degrees visible across the bar
	const GOLD := Color(1.0, 0.78, 0.25)
	var heading := 0.0           # degrees, 0 = north (-Z), 90 = east (+X)
	var has_obj := false
	var obj_bearing := 0.0       # degrees, absolute
	var obj_dist := 0.0
	var accent := Color(0.95, 0.35, 0.25)

	func _x_for(deg: float) -> float:
		var rel := wrapf(deg - heading, -180.0, 180.0)
		return size.x * 0.5 + rel / SPAN * size.x

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := size.x
		var h := size.y
		# Frame
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.02, 0.03, 0.05, 0.62)
		bg.border_color = Color(1, 1, 1, 0.16)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(3)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		draw_line(Vector2(6, h - 1), Vector2(w - 6, h - 1), Color(accent, 0.55), 2.0)
		# Hash marks every 5 degrees, labels every 45.
		var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
		var first := int(floor((heading - SPAN * 0.5) / 5.0)) * 5
		var d := first
		while d <= heading + SPAN * 0.5 + 5.0:
			var x := _x_for(float(d))
			var edge := 1.0 - clampf(absf(x - w * 0.5) / (w * 0.5), 0.0, 1.0)
			var a := clampf(edge * 1.6, 0.0, 1.0)
			if x >= 2.0 and x <= w - 2.0:
				var dd := posmod(d, 360)
				if names.has(dd):
					var txt: String = names[dd]
					var cardinal := txt.length() == 1
					var fs := 20 if cardinal else 14
					var col := Color(accent, a) if txt == "N" else Color(1, 1, 1, a * (1.0 if cardinal else 0.8))
					var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string_outline(font, Vector2(x - tw * 0.5, h * 0.5 + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, a * 0.8))
					draw_string(font, Vector2(x - tw * 0.5, h * 0.5 + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				elif dd % 15 == 0:
					draw_line(Vector2(x, h - 13), Vector2(x, h - 3), Color(1, 1, 1, a * 0.75), 2.0)
				else:
					draw_line(Vector2(x, h - 8), Vector2(x, h - 3), Color(1, 1, 1, a * 0.45), 1.0)
			d += 5
		# Centre pointer
		var c := w * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(c - 6, 0), Vector2(c + 6, 0), Vector2(c, 7)]), Color(1, 1, 1, 0.9))
		# Objective
		if has_obj:
			var rel := wrapf(obj_bearing - heading, -180.0, 180.0)
			var off := absf(rel) > SPAN * 0.5
			var x2 := clampf(_x_for(obj_bearing), 10.0, w - 10.0)
			var cy := h * 0.5 + 2.0
			var col2 := Color(GOLD, 0.55 if off else 1.0)
			var r := 7.0
			var dia := PackedVector2Array([Vector2(x2, cy - r), Vector2(x2 + r, cy), Vector2(x2, cy + r), Vector2(x2 - r, cy)])
			draw_colored_polygon(dia, Color(0, 0, 0, 0.6) if not off else Color(0, 0, 0, 0.3))
			var inner := PackedVector2Array([Vector2(x2, cy - r + 2), Vector2(x2 + r - 2, cy), Vector2(x2, cy + r - 2), Vector2(x2 - r + 2, cy)])
			draw_colored_polygon(inner, col2)
			if off:
				var s := signf(rel)
				draw_colored_polygon(PackedVector2Array([Vector2(x2 + s * 10, cy - 5), Vector2(x2 + s * 16, cy), Vector2(x2 + s * 10, cy + 5)]), col2)
			var txt2 := "%d m" % int(round(obj_dist))
			var fs2 := 13
			var tw2 := font.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			var tp := Vector2(clampf(x2 - tw2 * 0.5, 0.0, w - tw2), -4.0)
			draw_string_outline(font, tp, txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 4, Color(0, 0, 0, 0.85))
			draw_string(font, tp, txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, col2)


func _build_compass() -> void:
	_compass = CompassBar.new()
	_compass.accent = UI.ACCENT
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -330
	_compass.offset_right = 330
	_compass.offset_top = 30
	_compass.offset_bottom = 66
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_compass)


func _objective_point():
	if objective_provider.is_valid():
		return objective_provider.call()
	for n in get_tree().get_nodes_in_group("objective"):
		if n is Node3D and n.is_visible_in_tree():
			return n.global_position
	return null


func _update_compass() -> void:
	_compass.visible = true
	var cam := get_viewport().get_camera_3d()
	var fwd: Vector3 = -cam.global_transform.basis.z if cam != null else -player.global_transform.basis.z
	_compass.heading = wrapf(rad_to_deg(atan2(fwd.x, -fwd.z)), 0.0, 360.0)
	var o = _objective_point()
	_compass.has_obj = o != null
	if o != null:
		var op: Vector3 = o
		var to: Vector3 = op - player.global_position
		_compass.obj_bearing = rad_to_deg(atan2(to.x, -to.z))
		_compass.obj_dist = Vector2(to.x, to.z).length()
	_compass.queue_redraw()
