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
			t.weapon = player.weapon if player != null and is_instance_valid(player) else "primary"
			face.add_child(t)
		"survivor":
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
	_party_box.add_child(_member_column("trooper", "TROOPER", "You  ·  Rifleman", GS.player_level, GS.xp, hp, hp_max, [
		["WEAPON", player.weapon_name() if player != null else "Blaster Rifle"],
		["DAMAGE / BOLT", str(int(GS.player_damage()))],
		["SKILL POINTS", str(GS.skill_points)],
	]))
	if GS.ally_joined:
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
		["DAMAGE / BOLT", str(int(GS.droid_damage()))],
		["ORDERS", d.order_text() if d != null else "Not deployed here"],
	]))
	_set_party_rendering(_tab == "PARTY")


# ---------------------------------------------------------------- MAP

func _build_map(page: Control) -> void:
	var v := UI.vbox(10)
	page.add_child(v)
	v.add_child(UI.label("MAP", 30, UI.ACCENT))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(700, 620)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(holder)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	UI.full_rect(svc)
	holder.add_child(svc)
	_map_vp = SubViewport.new()
	_map_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(_map_vp)
	_map_cam = Camera3D.new()
	_map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_cam.size = 150.0
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
	_map_marker = UI.label("▲", 30, Color(1.0, 0.3, 0.2))
	_map_marker.position = Vector2(338, 290)
	_map_marker.pivot_offset = Vector2(12, 18)
	holder.add_child(_map_marker)
	v.add_child(UI.label("▲ You   ·   North is up", 15, UI.MUTED))


func _refresh_map() -> void:
	if player == null or not is_instance_valid(player):
		return
	_map_vp.world_3d = player.get_world_3d()
	_map_cam.current = true
	_map_cam.global_position = player.global_position + Vector3(0, 250, 0)
	_map_marker.rotation = -player.model.global_rotation.y


# ---------------------------------------------------------------- SKILLS

func _build_skills(page: Control) -> void:
	var v := UI.vbox(14)
	page.add_child(v)
	v.add_child(UI.label("SKILL TREE", 30, UI.ACCENT))
	_skills_header = UI.label("", 20, UI.TEXT)
	v.add_child(_skills_header)
	_skills_box = HBoxContainer.new()
	_skills_box.add_theme_constant_override("separation", 30)
	v.add_child(_skills_box)


func _refresh_skills() -> void:
	_skills_header.text = "Skill points: %d   ·   Level %d   ·   %d / %d XP   ·   Earn XP from kills, crafting, scavenging and quests." % [
		GS.skill_points, GS.player_level, GS.xp, Items.xp_for(GS.player_level)]
	for c in _skills_box.get_children():
		c.queue_free()
	for br in Items.BRANCHES:
		var col := UI.vbox(10)
		col.custom_minimum_size = Vector2(330, 0)
		_skills_box.add_child(col)
		col.add_child(UI.label(br, 22, UI.ACCENT))
		for sk in Items.SKILLS:
			if sk["branch"] != br:
				continue
			var r := GS.rank(sk["id"])
			var b := UI.button("%s   %d/%d" % [sk["name"], r, sk["ranks"]], 330)
			b.custom_minimum_size.y = 46
			b.add_theme_font_size_override("font_size", 18)
			b.disabled = not GS.can_learn(sk["id"])
			if r > 0:
				b.add_theme_stylebox_override("disabled", UI.box(Color(0.2, 0.12, 0.05, 0.9), Color(0.95, 0.75, 0.3), 2, 4))
			b.pressed.connect(_learn.bind(sk["id"]))
			col.add_child(b)
			var req: String = sk.get("req", "")
			var d := UI.label(sk["desc"] + ("   (needs %s)" % GS.skill_def(req)["name"] if req != "" else ""), 14, UI.MUTED)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(330, 0)
			col.add_child(d)


func _learn(id: String) -> void:
	GS.learn(id)
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
