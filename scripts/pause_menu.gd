extends CanvasLayer
## Game menu. Esc opens it on SYSTEM (pause); Tab / I opens INVENTORY,
## M the MAP, K SKILLS, J QUESTS, P PARTY. Tabs along the top.
## Also shows the victory / defeat screens (show_end).

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const PlayerScript = preload("res://scripts/player.gd")
const AllyScript = preload("res://scripts/ally.gd")
const CompanionScript = preload("res://scripts/companion.gd")
const MAIN_MENU := "res://main_menu.tscn"
const TABS := ["PARTY", "INVENTORY", "MAP", "SKILLS", "QUESTS", "SYSTEM"]

## Set by the level so menus can turn the player's controls off.
var player

var _root: Control
var _menu: Control
var _tab_buttons := {}
var _pages := {}
var _tab := "SYSTEM"
var _ended := false
var _end_box: Control
var _end_title: Label
var _end_sub: Label
var _end_stats: Label
var _retry_btn: Button
var _settings: Control
var _resume_btn: Button

# Inventory
var _selected := -1
var _slot_buttons: Array = []
var _equip_buttons := {}
var _detail_name: Label
var _detail_desc: Label
var _use_btn: Button
var _equip_btn: Button
var _drop_btn: Button
var _inv_header: Label
var _viewer: SubViewport
# Map
var _map_vp: SubViewport
var _party_vps: Array = []
var _preview   # character in the INVENTORY tab
var _map_cam: Camera3D
var _map_marker: Label
# Other pages
var _party_box: HBoxContainer
var _skills_box: HBoxContainer
var _skills_header: Label
var _quests_box: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	GS.ensure_loaded()

	_root = UI.full_rect(Control.new())
	_root.visible = false
	add_child(_root)
	_root.add_child(UI.dim())

	# Tabbed menu
	_menu = Control.new()
	UI.full_rect(_menu)
	_root.add_child(_menu)
	var margin := MarginContainer.new()
	UI.full_rect(margin)
	for k in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(k, 60)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	_menu.add_child(margin)
	var col := UI.vbox(16)
	margin.add_child(col)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	col.add_child(bar)
	for t in TABS:
		var b := UI.button(t, 190)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.toggle_mode = true
		b.pressed.connect(_show_tab.bind(t))
		bar.add_child(b)
		_tab_buttons[t] = b
	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(pages)
	for t in TABS:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.panel_style())
		UI.full_rect(p)
		p.visible = false
		pages.add_child(p)
		_pages[t] = p
	_build_party(_pages["PARTY"])
	_build_inventory(_pages["INVENTORY"])
	_build_map(_pages["MAP"])
	_build_skills(_pages["SKILLS"])
	_build_quests(_pages["QUESTS"])
	_build_system(_pages["SYSTEM"])

	# End panel (victory / defeat)
	var center := UI.full_rect(CenterContainer.new())
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_end_box = UI.panel()
	_end_box.visible = false
	center.add_child(_end_box)
	var ev := UI.vbox(12)
	_end_box.add_child(ev)
	_end_title = UI.label("", 44, UI.ACCENT)
	ev.add_child(_end_title)
	_end_sub = UI.label("", 20, UI.TEXT)
	ev.add_child(_end_sub)
	_end_stats = UI.label("", 18, UI.MUTED)
	ev.add_child(_end_stats)
	_retry_btn = UI.button("PLAY AGAIN")
	_retry_btn.pressed.connect(_restart)
	ev.add_child(_retry_btn)
	ev.add_child(_btn("MAIN MENU", _to_main_menu))
	ev.add_child(_btn("QUIT GAME", func(): get_tree().quit()))

	GS.listeners.append(_refresh)


func _exit_tree() -> void:
	GS.listeners.erase(_refresh)


func _btn(text: String, cb: Callable, width := 340.0) -> Button:
	var b := UI.button(text, width)
	b.pressed.connect(cb)
	return b


func _unhandled_input(event) -> void:
	if _ended or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.physical_keycode
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_close_settings()
		elif _root.visible:
			close()
		else:
			open("SYSTEM")
		return
	var shortcuts := {KEY_TAB: "INVENTORY", KEY_I: "INVENTORY", KEY_M: "MAP", KEY_K: "SKILLS", KEY_J: "QUESTS", KEY_P: "PARTY"}
	if shortcuts.has(key):
		get_viewport().set_input_as_handled()
		if _root.visible and _tab == shortcuts[key]:
			close()
		else:
			open(shortcuts[key])


func open(tab := "SYSTEM") -> void:
	if player != null and is_instance_valid(player) and not player.input_enabled and not _root.visible:
		return  # another panel (crafting, talk) has the controls
	get_tree().paused = true
	_root.visible = true
	_menu.visible = true
	_end_box.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_tab(tab)


func close() -> void:
	_root.visible = false
	_settings.visible = false
	get_tree().paused = false
	if _viewer != null:
		_viewer.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_party_rendering(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_tab(t: String) -> void:
	_tab = t
	for k in TABS:
		_pages[k].visible = k == t
		_tab_buttons[k].button_pressed = k == t
	_settings.visible = false
	_viewer.render_target_update_mode = SubViewport.UPDATE_ALWAYS if t == "INVENTORY" else SubViewport.UPDATE_DISABLED
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if t == "MAP" else SubViewport.UPDATE_DISABLED
	_set_party_rendering(t == "PARTY")
	if t == "SYSTEM":
		_resume_btn.grab_focus()
	_refresh()


func _refresh() -> void:
	if not is_inside_tree() or not _root.visible:
		return
	match _tab:
		"PARTY":
			_refresh_party()
		"INVENTORY":
			_refresh_inventory()
		"MAP":
			_refresh_map()
		"SKILLS":
			_refresh_skills()
		"QUESTS":
			_refresh_quests()


func show_end(title: String, subtitle: String, stats: String, delay := 1.5) -> void:
	_ended = true
	if player != null:
		player.input_enabled = false
	await get_tree().create_timer(delay, false).timeout
	_root.visible = true
	_menu.visible = false
	_settings.visible = false
	_end_box.visible = true
	_end_title.text = title
	_end_sub.text = subtitle
	_end_stats.text = stats
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_retry_btn.grab_focus()


# ---------------------------------------------------------------- SYSTEM

func _build_system(page: Control) -> void:
	var center := CenterContainer.new()
	page.add_child(center)
	var v := UI.vbox(12)
	center.add_child(v)
	v.add_child(UI.label("PAUSED", 40, UI.ACCENT))
	v.add_child(UI.label("The creatures can wait.", 18, UI.MUTED))
	_resume_btn = _btn("RESUME", close)
	v.add_child(_resume_btn)
	v.add_child(_btn("SAVE GAME", _save_game))
	v.add_child(_btn("RESTART AREA", _restart))
	v.add_child(_btn("SETTINGS", _open_settings))
	v.add_child(_btn("MAIN MENU", _to_main_menu))
	v.add_child(_btn("QUIT GAME", func(): GS.save(); get_tree().quit()))
	v.add_child(UI.label("Tab / I inventory   ·   M map   ·   K skills   ·   J quests   ·   P party", 15, UI.MUTED))
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)


func _open_settings() -> void:
	_settings.visible = true
	_pages["SYSTEM"].get_child(0).get_child(0).visible = false


func _close_settings() -> void:
	_settings.visible = false
	_pages["SYSTEM"].get_child(0).get_child(0).visible = true
	_resume_btn.grab_focus()


func _save_game() -> void:
	GS.save()
	GS.toast("Game saved")
	close()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_main_menu() -> void:
	GS.save()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)


# ---------------------------------------------------------------- INVENTORY

func _slot_style(color: Color, selected: bool) -> StyleBoxFlat:
	var s := UI.box(color.darkened(0.7) if color.a > 0.0 else Color(0.06, 0.06, 0.08, 0.9),
			UI.ACCENT if selected else Color(0.3, 0.3, 0.35, 0.7), 3 if selected else 2, 4)
	s.content_margin_left = 4
	s.content_margin_right = 4
	return s


func _build_inventory(page: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	page.add_child(h)

	# Character viewer + equipment
	var left := UI.vbox(10)
	h.add_child(left)
	left.add_child(UI.label("CHARACTER", 20, UI.ACCENT))
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(300, 330)
	svc.stretch = true
	left.add_child(svc)
	_viewer = SubViewport.new()
	_viewer.own_world_3d = true
	_viewer.transparent_bg = true
	_viewer.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(_viewer)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -30, 0)
	_viewer.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	we.environment = env
	_viewer.add_child(we)
	var preview = PlayerScript.new()
	preview.display_only = true
	if GS.active_member == "survivor":
		preview.character = "survivor"   # show whoever you're playing
	_preview = preview
	_viewer.add_child(preview)
	preview.model.rotation.y = deg_to_rad(165)
	var cam := Camera3D.new()
	cam.fov = 35
	cam.position = Vector3(0.0, 1.05, 4.0)
	_viewer.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true

	var eq := GridContainer.new()
	eq.columns = 2
	eq.add_theme_constant_override("h_separation", 8)
	eq.add_theme_constant_override("v_separation", 8)
	left.add_child(eq)
	var names := {"primary": "PRIMARY", "sidearm": "SIDEARM", "utility1": "UTILITY 1", "utility2": "UTILITY 2",
			"module1": "MODULE 1", "module2": "MODULE 2", "module3": "MODULE 3"}
	for k in ["primary", "sidearm", "utility1", "utility2", "module1", "module2", "module3"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(196, 52)
		b.add_theme_font_size_override("font_size", 14)
		b.clip_text = true
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 40)
		b.set_meta("label", names[k])
		b.pressed.connect(_on_equip_slot.bind(k))
		eq.add_child(b)
		_equip_buttons[k] = b

	# Backpack + details
	var right := UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_inv_header = UI.label("", 20, UI.TEXT)
	right.add_child(_inv_header)
	right.add_child(UI.label("BACKPACK", 20, UI.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	for i in GS.BACKPACK_SLOTS:
		var b2 := Button.new()
		b2.custom_minimum_size = Vector2(86, 86)
		b2.add_theme_font_size_override("font_size", 14)
		b2.expand_icon = true
		b2.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b2.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b2.add_theme_constant_override("icon_max_width", 56)
		b2.pressed.connect(_on_slot.bind(i))
		grid.add_child(b2)
		_slot_buttons.append(b2)
	var detail := UI.vbox(6)
	right.add_child(detail)
	_detail_name = UI.label("", 24, UI.TEXT)
	detail.add_child(_detail_name)
	_detail_desc = UI.label("", 17, UI.MUTED)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(600, 0)
	detail.add_child(_detail_desc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	detail.add_child(row)
	_use_btn = _btn("USE", _on_use, 160)
	_equip_btn = _btn("EQUIP", _on_equip, 160)
	_drop_btn = _btn("DISCARD", _on_drop, 160)
	for b3 in [_use_btn, _equip_btn, _drop_btn]:
		b3.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(b3)


func _refresh_inventory() -> void:
	if _preview != null and player != null and is_instance_valid(player) and _preview.weapon != player.weapon:
		_preview.weapon = player.weapon
		_preview._show_weapon_model()
	_inv_header.text = "LEVEL %d   ·   %d / %d XP   ·   %d skill point(s)   ·   Health %d / %d" % [
		GS.player_level, GS.xp, Items.xp_for(GS.player_level), GS.skill_points,
		int(player.health) if player != null else 0, int(GS.player_max_health())]
	for i in _slot_buttons.size():
		var b: Button = _slot_buttons[i]
		var s = GS.backpack[i]
		if s == null:
			b.text = ""
			b.icon = null
			b.tooltip_text = ""
			b.add_theme_stylebox_override("normal", _slot_style(Color(0, 0, 0, 0), i == _selected))
		else:
			var it := GS.item(s["id"])
			b.icon = Items.icon(s["id"])
			b.tooltip_text = it.get("name", "")
			b.text = ("x%d" % int(s["n"])) if int(s["n"]) > 1 else " "
			if b.icon == null:
				b.text = "%s\n%s" % [it.get("tag", "?"), b.text]
			b.add_theme_stylebox_override("normal", _slot_style(it.get("color", Color.WHITE), i == _selected))
		b.add_theme_stylebox_override("hover", _slot_style(Color(0.5, 0.1, 0.08), true))
	for k in _equip_buttons:
		var eb: Button = _equip_buttons[k]
		var id: String = GS.equipment.get(k, "")
		var label: String = eb.get_meta("label")
		eb.icon = Items.icon(id) if id != "" else null
		if id == "":
			eb.text = label + "\n—"
		else:
			var extra := ""
			if GS.item(id).get("type") == "utility":
				extra = "  x%d" % GS.count(id)
			eb.text = label + "\n" + String(GS.item(id)["name"]) + extra
		eb.add_theme_stylebox_override("normal", _slot_style(GS.item(id).get("color", Color(0, 0, 0, 0)) if id != "" else Color(0, 0, 0, 0), false))
	# Details
	var sel = GS.backpack[_selected] if _selected >= 0 else null
	if sel == null:
		_detail_name.text = "Select an item"
		_detail_desc.text = "Click a backpack slot to see it. Click an equipment slot to unequip it."
		_use_btn.disabled = true
		_equip_btn.disabled = true
		_drop_btn.disabled = true
	else:
		var it2 := GS.item(sel["id"])
		_detail_name.text = "%s   x%d" % [it2["name"], int(sel["n"])]
		_detail_desc.text = it2.get("desc", "")
		_use_btn.disabled = not (it2.get("type") in ["consumable", "placeable"])
		_use_btn.text = "PLACE" if it2.get("type") == "placeable" else "USE"
		_equip_btn.disabled = it2.get("slot", "") == ""
		_drop_btn.disabled = false


func _on_slot(i: int) -> void:
	_selected = i
	_refresh_inventory()


func _on_use() -> void:
	var s = GS.backpack[_selected] if _selected >= 0 else null
	if s != null and player != null:
		var placing: bool = GS.item(s["id"]).get("type") == "placeable"
		if player.use_item(s["id"]) and placing:
			close()
			return
	_refresh_inventory()


func _on_equip() -> void:
	if _selected >= 0:
		GS.toast(GS.equip_from_slot(_selected))
	_refresh_inventory()


func _on_drop() -> void:
	if _selected >= 0 and GS.backpack[_selected] != null:
		GS.backpack[_selected] = null
		GS.changed()
	_refresh_inventory()


func _on_equip_slot(k: String) -> void:
	GS.unequip(k)
	_refresh_inventory()


# ---------------------------------------------------------------- PARTY

func _build_party(page: Control) -> void:
	var v := UI.vbox(12)
	page.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label("PARTY", 30, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.label("Highlighted: the member you are playing as", 15, UI.MUTED))
	_party_box = HBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 22)
	_party_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_party_box)


func _set_party_rendering(on: bool) -> void:
	for vp in _party_vps:
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## A small 3D stage with the member idling and slowly turning.
func _portrait(id: String) -> Control:
	var frame := PanelContainer.new()
	var fs := UI.box(Color(0.05, 0.055, 0.07, 1.0), Color(1, 1, 1, 0.08), 1, 4)
	fs.content_margin_left = 0
	fs.content_margin_right = 0
	fs.content_margin_top = 0
	fs.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", fs)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(290, 320)
	svc.stretch = true
	frame.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	_party_vps.append(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, -35, 0)
	key.light_energy = 1.2
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.45, 0.35) if id == GS.active_member else Color(0.5, 0.75, 1.0)
	vp.add_child(rim)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.46, 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	vp.add_child(we)
	# Floor disc with a glowing ring.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.75
	cm.height = 0.02
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.08, 0.09, 0.11)
	dm.emission_enabled = true
	dm.emission = UI.ACCENT if id == GS.active_member else Color(0.2, 0.5, 0.8)
	dm.emission_energy_multiplier = 0.35
	disc.material_override = dm
	vp.add_child(disc)
	var turn := Node3D.new()
	vp.add_child(turn)
	# Characters face -Z; turn them round to face the camera. (Their models
	# are only built once the viewport is in the tree, so rotate a parent.)
	var face := Node3D.new()
	face.rotation.y = PI
	turn.add_child(face)
	var cam := Camera3D.new()
	cam.fov = 30
	var look_y := 0.92
	match id:
		"trooper":
			var t = PlayerScript.new()
			t.display_only = true
			# Hold whatever weapon you have out right now.
			t.weapon = player.weapon if GS.active_member == "trooper" and player != null and is_instance_valid(player) else "primary"
			face.add_child(t)
		"survivor":
			if GS.active_member == "survivor":
				# You're playing her: show her playable model, rifle in hand.
				var su = PlayerScript.new()
				su.display_only = true
				su.character = "survivor"
				face.add_child(su)
			else:
				face.add_child(AllyScript.new())
		"droid":
			var d = CompanionScript.new()
			d.display_only = true
			face.add_child(d)
			look_y = 0.6
	var cam_pos := Vector3(0.0, look_y + 0.1, 4.4 if id != "droid" else 3.6)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, look_y, 0.0) - cam_pos), cam_pos)
	cam.current = true
	vp.add_child(cam)
	# Gentle sway so it feels alive (keeps running while the game is paused).
	_sway.call_deferred(turn)
	return frame


func _sway(turn: Node3D) -> void:
	if not is_instance_valid(turn) or not turn.is_inside_tree():
		return
	var tw := turn.create_tween().set_loops().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(turn, "rotation:y", deg_to_rad(28.0), 3.2).from(deg_to_rad(-28.0))
	tw.tween_property(turn, "rotation:y", deg_to_rad(-28.0), 3.2)


func _stat_row(name_text: String, value: String) -> Control:
	var h := HBoxContainer.new()
	var l := UI.label(name_text, 15, UI.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UI.label(value, 16, UI.TEXT))
	return h


func _stat_bar(name_text: String, value: float, maximum: float, col: Color, text: String) -> Control:
	var v := UI.vbox(2)
	var h := HBoxContainer.new()
	var l := UI.label(name_text, 14, UI.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UI.label(text, 14, UI.TEXT))
	v.add_child(h)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 10)
	b.show_percentage = false
	b.max_value = maxf(1.0, maximum)
	b.value = value
	b.add_theme_stylebox_override("background", UI.box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.1), 1, 2))
	var f := StyleBoxFlat.new()
	f.bg_color = col
	f.set_corner_radius_all(2)
	b.add_theme_stylebox_override("fill", f)
	v.add_child(b)
	return v


func _member_column(id: String, name_text: String, role: String, level: int, xp: int, hp: float, hp_max: float, rows: Array) -> Control:
	var active := id == GS.active_member
	var p := PanelContainer.new()
	var st := UI.box(Color(0.16, 0.04, 0.03, 0.95) if active else Color(0.07, 0.07, 0.09, 0.92),
			UI.ACCENT if active else Color(0.3, 0.3, 0.35, 0.6), 3 if active else 1, 6)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	if active:
		st.shadow_color = Color(UI.ACCENT, 0.45)
		st.shadow_size = 14
	p.add_theme_stylebox_override("panel", st)
	var v := UI.vbox(6)
	v.custom_minimum_size = Vector2(290, 0)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nm := UI.label(name_text, 24, UI.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if active:
		var tag := UI.label("ACTIVE", 14, Color.WHITE)
		var tp := PanelContainer.new()
		var ts := UI.box(UI.ACCENT, UI.ACCENT, 0, 3)
		ts.content_margin_left = 8
		ts.content_margin_right = 8
		ts.content_margin_top = 2
		ts.content_margin_bottom = 2
		tp.add_theme_stylebox_override("panel", ts)
		tp.add_child(tag)
		tp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tp)
	v.add_child(UI.label(role, 15, UI.ACCENT))
	v.add_child(_portrait(id))
	var need := Items.xp_for(level)
	v.add_child(_stat_row("LEVEL", str(level)))
	v.add_child(_stat_bar("HEALTH", hp, hp_max, Color(0.86, 0.16, 0.13), "%d / %d" % [int(hp), int(hp_max)]))
	v.add_child(_stat_bar("EXPERIENCE", xp, need, Color(0.95, 0.75, 0.3), "%d / %d" % [xp, need]))
	for r in rows:
		v.add_child(_stat_row(r[0], r[1]))
	var swap := UI.button("SWAP", 290)
	swap.custom_minimum_size.y = 44
	swap.alignment = HORIZONTAL_ALIGNMENT_CENTER
	swap.disabled = true
	swap.tooltip_text = "Swapping characters is coming in a later update."
	v.add_child(swap)
	return p


func _refresh_party() -> void:
	for c in _party_box.get_children():
		c.queue_free()
	_party_vps.clear()
	var scene := get_tree().current_scene
	var hp: float = player.health if player != null else GS.player_max_health()
	var hp_max: float = player.max_health if player != null else GS.player_max_health()
	if GS.active_member == "survivor":
		# Playing as her while he recovers: she's "You", he's laid up at camp.
		_party_box.add_child(_member_column("survivor", "SURVIVOR", "You  ·  Marksman", GS.player_level, GS.xp, hp, hp_max, [
			["WEAPON", "Long Rifle"],
			["DAMAGE / BOLT", str(int(GS.player_damage()))],
			["SKILL POINTS", str(GS.skill_points)],
		]))
		var pt: Dictionary = GS.profiles.get("trooper", {})
		var t_hp := GS.player_max_health()
		_party_box.add_child(_member_column("trooper", "TROOPER", "Injured  ·  Rifleman", int(pt.get("player_level", 1)), int(pt.get("xp", 0)),
				t_hp * 0.15, t_hp, [
			["WEAPON", "Blaster Rifle"],
			["STATUS", "Resting at camp"],
			["SKILL POINTS", str(int(pt.get("skill_points", 0)))],
		]))
	else:
		_party_box.add_child(_member_column("trooper", "TROOPER", "You  ·  Rifleman", GS.player_level, GS.xp, hp, hp_max, [
			["WEAPON", player.weapon_name() if player != null else "Blaster Rifle"],
			["DAMAGE / BOLT", str(int(GS.player_damage()))],
			["SKILL POINTS", str(GS.skill_points)],
		]))
	if GS.ally_joined and GS.active_member == "trooper":
		var a = scene.get_node_or_null("Ally") if scene != null else null
		var sa := GS.party_stats("survivor")
		_party_box.add_child(_member_column("survivor", "SURVIVOR", "Ally  ·  Marksman", int(sa["level"]), int(sa["xp"]),
				a.health if a != null and "health" in a else 100.0, a.max_health if a != null and "max_health" in a else 100.0, [
			["WEAPON", "Long Rifle"],
			["DAMAGE / BOLT", str(int(a.damage)) if a != null else "12"],
			["STATUS", "With you" if a != null and a.player != null else "At camp"],
		]))
	var d = scene.get_node_or_null("Droid") if scene != null else null
	var sd := GS.party_stats("droid")
	_party_box.add_child(_member_column("droid", "STRIDER DROID", "Companion  ·  Combat droid", int(sd["level"]), int(sd["xp"]),
			d.health if d != null else 100.0, d.max_health if d != null else 100.0, [
		["WEAPON", "Twin blasters"],
		["DAMAGE / BOLT", "%d  (bursts of 4)" % int(GS.droid_damage() * 0.6)],
		["ORDERS", d.order_text() if d != null else "Not deployed here"],
	]))
	_set_party_rendering(_tab == "PARTY")


# ---------------------------------------------------------------- MAP

const MapPoi = preload("res://scripts/map_poi.gd")
const MapOverlay = preload("res://scripts/map_overlay.gd")
const MAP_ZOOMS := [90.0, 160.0, 300.0]   # metres shown top to bottom
const MAP_SIZE := Vector2(660, 620)
const AREA_NAMES := {
	"res://main.tscn": "CRASH SITE",
	"res://path.tscn": "THE TRAIL",
	"res://pinned.tscn": "THE CLEARING",
	"res://drag.tscn": "THE ESCAPE",
	"res://base.tscn": "BASE CAMP",
}
var _map_zoom := 1
var _map_overlay
var _map_area: Label
var _map_list: VBoxContainer


func _build_map(page: Control) -> void:
	var v := UI.vbox(10)
	page.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(UI.label("MAP", 30, UI.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	for z in [["ZOOM IN", -1], ["ZOOM OUT", 1]]:
		var zb := UI.button(z[0], 150)
		zb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		zb.pressed.connect(func():
			_map_zoom = clampi(_map_zoom + int(z[1]), 0, MAP_ZOOMS.size() - 1)
			_refresh_map())
		top.add_child(zb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)

	# The map: a camera looking straight down, with the markers drawn on top.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.6), Color(0.3, 0.3, 0.35, 0.7), 1, 4))
	row.add_child(frame)
	var holder := Control.new()
	holder.custom_minimum_size = MAP_SIZE
	holder.clip_contents = true
	frame.add_child(holder)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	UI.full_rect(svc)
	holder.add_child(svc)
	_map_vp = SubViewport.new()
	_map_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(_map_vp)
	_map_cam = Camera3D.new()
	_map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_cam.size = MAP_ZOOMS[_map_zoom]
	_map_cam.far = 600.0
	_map_cam.rotation_degrees = Vector3(-90, 0, 0)
	# Own environment: no fog, so the ground shows from high above.
	var menv := Environment.new()
	menv.background_mode = Environment.BG_COLOR
	menv.background_color = Color(0.05, 0.06, 0.05)
	menv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	menv.ambient_light_color = Color(0.6, 0.6, 0.6)
	menv.ambient_light_energy = 1.0
	_map_cam.environment = menv
	_map_vp.add_child(_map_cam)
	_map_overlay = MapOverlay.new()
	UI.full_rect(_map_overlay)
	holder.add_child(_map_overlay)

	# Where you are and where everything is.
	var side := PanelContainer.new()
	var sst := UI.box(Color(0.04, 0.04, 0.05, 0.85), Color(0.3, 0.3, 0.35, 0.6), 1, 4)
	sst.content_margin_left = 14
	sst.content_margin_right = 14
	sst.content_margin_top = 12
	sst.content_margin_bottom = 12
	side.add_theme_stylebox_override("panel", sst)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	var sv := UI.vbox(8)
	side.add_child(sv)
	_map_area = UI.label("", 22, UI.TEXT)
	sv.add_child(_map_area)
	sv.add_child(UI.label("LOCATIONS  ·  direction and distance from you", 14, UI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	_map_list = UI.vbox(10)
	_map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_map_list)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	for k in [["camp", "Camp"], ["exit", "Way out"], ["objective", "Objective"], ["landmark", "Landmark"], ["resource", "Supplies"], ["danger", "Danger"]]:
		legend.add_child(UI.label("■ " + k[1], 13, MapPoi.colour(k[0])))
	sv.add_child(legend)
	v.add_child(UI.label("North is up   ·   ▲ You   ·   Arrows at the edge point to places off the map", 15, UI.MUTED))


## "North-east" for a direction from you, north up.
static func _bearing_name(d: Vector3) -> String:
	var deg := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var names := ["North", "North-east", "East", "South-east", "South", "South-west", "West", "North-west"]
	return names[int(round(deg / 45.0)) % 8]


func _refresh_map() -> void:
	if player == null or not is_instance_valid(player):
		return
	_map_vp.world_3d = player.get_world_3d()
	_map_cam.current = true
	_map_cam.size = MAP_ZOOMS[_map_zoom]
	_map_cam.global_position = player.global_position + Vector3(0, 250, 0)
	var scene := get_tree().current_scene
	var area_name: String = AREA_NAMES.get(scene.scene_file_path if scene != null else "", "UNKNOWN")
	_map_area.text = "YOU ARE AT:  " + area_name

	# Gather places: map markers, plus whatever the compass is pointing at.
	var places: Array = []
	for n in get_tree().get_nodes_in_group("map_poi"):
		places.append({"pos": (n as Node3D).global_position, "label": n.label, "kind": n.kind, "info": n.info})
	for n in get_tree().get_nodes_in_group("objective"):
		if n.is_in_group("map_poi"):
			continue
		var lbl: String = n.get_meta("label", "Objective")
		places.append({"pos": (n as Node3D).global_position, "label": lbl, "kind": "objective",
				"info": n.get_meta("info", "Where you need to go next.")})
	var me: Vector3 = player.global_position
	places.sort_custom(func(a, b):
		var ka: int = 0 if a["kind"] == "objective" else 1
		var kb: int = 0 if b["kind"] == "objective" else 1
		if ka != kb:
			return ka < kb
		return me.distance_to(a["pos"]) < me.distance_to(b["pos"]))

	_map_overlay.centre = me
	_map_overlay.px_per_m = MAP_SIZE.y / MAP_ZOOMS[_map_zoom]
	_map_overlay.player_yaw = player.model.global_rotation.y
	_map_overlay.pois = places
	_map_overlay.queue_redraw()

	for c in _map_list.get_children():
		c.queue_free()
	if places.is_empty():
		_map_list.add_child(UI.label("Nothing charted here yet.", 16, UI.MUTED))
	for pl in places:
		var d: Vector3 = pl["pos"] - me
		d.y = 0.0
		var dist := d.length()
		var where := "You're here" if dist < 8.0 else "%s  ·  %d m" % [_bearing_name(d), int(dist)]
		var box := UI.vbox(1)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(UI.label("■", 16, MapPoi.colour(pl["kind"])))
		var nm := UI.label(String(pl["label"]).to_upper(), 16, UI.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		head.add_child(UI.label(where, 15, MapPoi.colour(pl["kind"])))
		box.add_child(head)
		if String(pl["info"]) != "":
			var info := UI.label(pl["info"], 14, UI.MUTED)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(info)
		_map_list.add_child(box)


# ---------------------------------------------------------------- SKILLS

var _skills_view := "ATTRIBUTES"
var _skills_views := {}
var _skills_tab_btns := {}
var _attr_box: VBoxContainer
var _stat_box: VBoxContainer
var _respec_btn: Button
var _respec_armed := false

const GOLD := Color(0.95, 0.75, 0.3)


func _build_skills(page: Control) -> void:
	var v := UI.vbox(10)
	page.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	top.add_child(UI.label("CHARACTER", 30, UI.ACCENT))
	for view in ["ATTRIBUTES", "SKILL TREES"]:
		var b := UI.button(view, 210)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.toggle_mode = true
		b.pressed.connect(_show_skills_view.bind(view))
		top.add_child(b)
		_skills_tab_btns[view] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_respec_btn = UI.button("RESPEC", 200)
	_respec_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respec_btn.tooltip_text = "Refund every skill and attribute point."
	_respec_btn.pressed.connect(_respec)
	top.add_child(_respec_btn)
	_skills_header = UI.label("", 18, UI.TEXT)
	v.add_child(_skills_header)

	# Attributes + stat sheet
	var attrs := HBoxContainer.new()
	attrs.add_theme_constant_override("separation", 40)
	attrs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(attrs)
	_skills_views["ATTRIBUTES"] = attrs
	_attr_box = UI.vbox(6)
	_attr_box.custom_minimum_size = Vector2(720, 0)
	attrs.add_child(_attr_box)
	var sheet_panel := PanelContainer.new()
	sheet_panel.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.04, 0.05, 0.85), Color(0.3, 0.3, 0.35, 0.6), 1, 4))
	sheet_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attrs.add_child(sheet_panel)
	var sheet_scroll := ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_panel.add_child(sheet_scroll)
	_stat_box = UI.vbox(4)
	_stat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(_stat_box)

	# Skill trees
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_skills_views["SKILL TREES"] = scroll
	_skills_box = HBoxContainer.new()
	_skills_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_skills_box)
	_show_skills_view("ATTRIBUTES")


func _show_skills_view(view: String) -> void:
	_skills_view = view
	for k in _skills_views:
		_skills_views[k].visible = k == view
		_skills_tab_btns[k].button_pressed = k == view
	_refresh_skills()


func _refresh_skills() -> void:
	_skills_header.text = "Level %d   ·   %d / %d XP   ·   Attribute points: %d   ·   Skill points: %d" % [
		GS.player_level, GS.xp, Items.xp_for(GS.player_level), GS.attr_points, GS.skill_points]
	_respec_btn.text = "CONFIRM RESPEC?" if _respec_armed else "RESPEC"
	if _skills_view == "ATTRIBUTES":
		_refresh_attributes()
	else:
		_refresh_trees()


func _refresh_attributes() -> void:
	for c in _attr_box.get_children():
		c.queue_free()
	_attr_box.add_child(UI.label("ATTRIBUTES   ·   +%d points every level" % Items.ATTR_PER_LEVEL, 20, UI.ACCENT))
	for a in Items.ATTRIBUTES:
		var id: String = a["id"]
		var spent := int(GS.attributes.get(id, 0))
		var total := GS.attr(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_attr_box.add_child(row)
		var name_col := UI.vbox(0)
		name_col.custom_minimum_size = Vector2(300, 0)
		row.add_child(name_col)
		name_col.add_child(UI.label(String(a["name"]).to_upper(), 19, GOLD if total > 0 else UI.TEXT))
		var per := UI.label("Per point: " + String(a["per"]), 13, UI.MUTED)
		per.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		per.custom_minimum_size = Vector2(300, 0)
		name_col.add_child(per)
		var bar_col := UI.vbox(2)
		bar_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar_col)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(250, 14)
		bar.max_value = Items.ATTR_CAP
		bar.value = spent
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", UI.box(Color(0.08, 0.08, 0.1), Color(0.3, 0.3, 0.35), 1, 2))
		bar.add_theme_stylebox_override("fill", UI.box(Color(0.8, 0.2, 0.12), Color(0.95, 0.4, 0.2), 1, 2))
		bar_col.add_child(bar)
		var bonus := total - spent
		bar_col.add_child(UI.label("%d / %d%s" % [spent, Items.ATTR_CAP, ("   (+%d from skills)" % bonus) if bonus > 0 else ""], 14, UI.MUTED))
		var plus := UI.button("+", 56)
		plus.alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.custom_minimum_size.y = 44
		plus.add_theme_font_size_override("font_size", 24)
		plus.disabled = not GS.can_raise(id)
		plus.pressed.connect(_raise.bind(id))
		row.add_child(plus)
	_refresh_stat_sheet()


func _stat_line(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	var l := UI.label(label, 16, UI.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UI.label(value, 16, UI.TEXT))
	_stat_box.add_child(row)


func _refresh_stat_sheet() -> void:
	for c in _stat_box.get_children():
		c.queue_free()
	var w := GS.item(GS.equipment.get("primary", ""))
	var rate := float(w.get("rate", 0.16))
	var dmg := GS.player_damage() * float(w.get("damage", 1.0))
	var pct := func(x: float) -> String: return "%.1f%%" % (x * 100.0)
	_stat_box.add_child(UI.label("OFFENSE", 18, UI.ACCENT))
	_stat_line("Damage per bolt (%s)" % w.get("name", "rifle"), "%.1f" % dmg)
	_stat_line("Critical chance", pct.call(GS.crit_chance()))
	_stat_line("Critical damage", "x%.2f" % GS.crit_mult())
	_stat_line("Fire rate", "%.1f shots/s" % (GS.fire_rate_mult() / rate))
	_stat_line("Reload time", "%.2f s" % (1.4 * GS.reload_time_mult()))
	_stat_line("Magazine", "%d" % GS.mag_size())
	_stat_line("Grenade damage", "x%.2f   (+%.2f m radius)" % [GS.grenade_mult(), GS.grenade_radius_bonus()])
	_stat_line("Execute bonus (<30% health)", "+40%" if GS.rank("executioner") > 0 else "—")
	_stat_box.add_child(UI.label("DEFENSE", 18, UI.ACCENT))
	_stat_line("Max health", "%d" % int(GS.player_max_health()))
	_stat_line("Damage reduction", pct.call(1.0 - GS.damage_taken_mult()))
	_stat_line("Evade chance", pct.call(GS.evade_chance()))
	_stat_line("Block chance", "%s   (absorbs %d%%)" % [pct.call(GS.block_chance()), int(GS.BLOCK_ABSORB * 100)])
	_stat_line("Health regeneration", "%.2f /s after 5 s" % GS.regen_rate())
	_stat_line("Healing items", "+50%" if GS.rank("field_medic") > 0 else "normal")
	_stat_line("Last Stand", "ready every 2 min" if GS.rank("last_stand") > 0 else "—")
	_stat_box.add_child(UI.label("SQUAD", 18, UI.ACCENT))
	_stat_line("Droid damage per bolt", "%.1f" % GS.droid_damage())
	_stat_line("Ally damage", "x%.2f" % GS.ally_damage_mult())
	_stat_line("Health per kill", "%d" % (6 * GS.rank("adrenaline")))
	_stat_box.add_child(UI.label("SURVIVAL", 18, UI.ACCENT))
	_stat_line("Experience gain", "x%.2f" % GS.xp_mult())
	_stat_line("Salvage gain", "x%.2f" % GS.salvage_mult())
	_stat_line("Extra resources per pickup", "+%d" % GS.rank("scavenger"))
	_stat_line("Module strength", "x%.2f" % (1.0 + 0.25 * GS.rank("overclock")))


func _refresh_trees() -> void:
	for c in _skills_box.get_children():
		c.queue_free()
	for br in Items.BRANCHES:
		var col := UI.vbox(6)
		col.custom_minimum_size = Vector2(286, 0)
		_skills_box.add_child(col)
		col.add_child(UI.label(br, 22, UI.ACCENT))
		var blurb := UI.label("%s\n%d points spent" % [Items.BRANCH_BLURB[br], GS.branch_points(br)], 13, UI.MUTED)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(286, 0)
		col.add_child(blurb)
		for tier in Items.TIERS.size():
			var req: Array = Items.TIERS[tier]
			var open := GS.tier_open(br, tier)
			var head := "TIER %s" % ["I", "II", "III", "IV"][tier]
			if tier > 0:
				head += "   ·   Lv %d, %d pts" % [int(req[0]), int(req[1])]
			col.add_child(UI.label(head + ("" if open else "   (locked)"), 14, GOLD if open else Color(0.45, 0.45, 0.5)))
			for sk in Items.SKILLS:
				if sk["branch"] != br or int(sk.get("tier", 0)) != tier:
					continue
				col.add_child(_skill_tile(sk, open))


func _skill_tile(sk: Dictionary, open: bool) -> Control:
	var r := GS.rank(sk["id"])
	var maxed := r >= int(sk["ranks"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(286, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.text = "%s   %d/%d\n%s" % [sk["name"], r, int(sk["ranks"]), sk["desc"]]
	b.add_theme_font_size_override("font_size", 14)
	var bg := Color(0.07, 0.07, 0.09, 0.95)
	var border := Color(0.25, 0.25, 0.3)
	if r > 0:
		bg = Color(0.2, 0.12, 0.05, 0.95)
		border = GOLD
	elif GS.can_learn(sk["id"]):
		border = UI.ACCENT
	b.add_theme_stylebox_override("normal", UI.box(bg, border, 2, 4))
	b.add_theme_stylebox_override("hover", UI.box(bg.lightened(0.08), UI.ACCENT if not maxed else GOLD, 2, 4))
	b.add_theme_stylebox_override("pressed", UI.box(bg.lightened(0.12), GOLD, 2, 4))
	b.add_theme_stylebox_override("disabled", UI.box(bg, border, 2, 4))
	b.add_theme_color_override("font_color", UI.TEXT if open else Color(0.5, 0.5, 0.55))
	b.add_theme_color_override("font_disabled_color", (GOLD if r > 0 else (UI.TEXT if open else Color(0.45, 0.45, 0.5))))
	b.disabled = not GS.can_learn(sk["id"])
	b.pressed.connect(_learn.bind(sk["id"]))
	return b


func _raise(id: String) -> void:
	GS.raise_attr(id)
	_respec_armed = false
	_refresh_skills()


func _learn(id: String) -> void:
	GS.learn(id)
	_respec_armed = false
	_refresh_skills()


func _respec() -> void:
	if not _respec_armed:
		_respec_armed = true
		_refresh_skills()
		return
	_respec_armed = false
	GS.respec()
	_refresh_skills()


# ---------------------------------------------------------------- QUESTS

func _build_quests(page: Control) -> void:
	var v := UI.vbox(10)
	page.add_child(v)
	v.add_child(UI.label("QUESTS", 30, UI.ACCENT))
	_quests_box = UI.vbox(8)
	v.add_child(_quests_box)


func _refresh_quests() -> void:
	for c in _quests_box.get_children():
		c.queue_free()
	for i in Items.QUESTS.size():
		var q: Dictionary = Items.QUESTS[i]
		if i < GS.quest_stage:
			_quests_box.add_child(UI.label("✓  " + String(q["title"]), 20, UI.MUTED))
		elif i == GS.quest_stage:
			_quests_box.add_child(UI.label("▶  " + String(q["title"]), 24, UI.TEXT))
			for g in q["goals"]:
				var done := GS.goal_done(g[0])
				_quests_box.add_child(UI.label("        %s %s%s" % ["✓" if done else "•", g[1], GS.goal_progress(g[0])], 18, UI.ACCENT if not done else UI.MUTED))
		else:
			_quests_box.add_child(UI.label("•  ???", 20, Color(0.4, 0.4, 0.45)))
	if GS.quest_stage >= Items.QUESTS.size():
		_quests_box.add_child(UI.label("All camp quests done. Explore and survive.", 20, UI.TEXT))
