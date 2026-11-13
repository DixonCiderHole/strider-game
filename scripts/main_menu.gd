extends Control
## Title screen.
## Background: the area you were last in, at night (built live, see
## menu_backdrop.gd). Circuit-trace borders along the top and bottom.
## Menu: sky-blue boxes in a column on the left, title above them.
## Right side, on top: knees-up portrait of her, hair blowing in the wind.
## Music: music/title_screen.mp3 ("Credits Title Screen").

const UI = preload("res://scripts/ui.gd")
const Sfx = preload("res://scripts/sfx.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const CircuitBorder = preload("res://scripts/circuit_border.gd")
const GS = preload("res://scripts/game_state.gd")
const GAME_SCENE := "res://main.tscn"
const BASE_SCENE := "res://base.tscn"
const PORTRAIT_MODEL := "res://models/femalelead_portrait.glb"
const MUSIC := "res://music/title_screen.mp3"

const SKY := Color(0.42, 0.8, 1.0)
const BORDER_H := 120.0

const HAIR_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);
uniform float strength = 0.085;

void vertex() {
	float w = COLOR.r;
	if (w > 0.002) {
		float ph = COLOR.g * 6.2831;
		float t = TIME;
		float gust = 0.7 + 0.3 * sin(t * 0.61) * sin(t * 0.37 + 1.3);
		float flutter = sin(t * 3.3 + ph * 2.0 + VERTEX.y * 22.0) * 0.6
			+ sin(t * 5.9 + ph * 5.0) * 0.25;
		vec3 wd = normalize(wind_dir);
		vec3 side = normalize(cross(wd, vec3(0.0, 1.0, 0.0)));
		float a = w * strength;
		VERTEX += wd * a * (gust + flutter * 0.35);
		VERTEX += side * a * 0.3 * flutter;
		VERTEX.y += a * 0.3 * (gust + flutter * 0.5);
	}
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = 0.72;
	METALLIC = 0.05;
}
"""

var _menu: Control
var _settings: Control
var _controls: Control
var _saves: Control
var _slot_rows: VBoxContainer
var _confirm_delete := 0
var _play_btn: Button
var _skel: Skeleton3D
var _bones := {}
var _time := 0.0
var _music: AudioStreamPlayer
var _footer: Label
var _backdrop: Node


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UI.full_rect(self)
	GS.ensure_loaded()

	# 2D draws over 3D, so the plain backdrop is only used if the world fails.
	if not _build_backdrop():
		var bg := ColorRect.new()
		bg.color = Color(0.01, 0.015, 0.03)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(UI.full_rect(bg))

	# Soft darkening behind the menu column so the text stays readable.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.01, 0.03, 0.62))
	grad.set_color(1, Color(0.0, 0.01, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.5, 0.5)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full_rect(shade))

	# Circuit borders, top and bottom.
	var top := CircuitBorder.new()
	top.color = SKY
	top.band = BORDER_H
	top.seed_value = 11
	top.anchor_right = 1.0
	top.offset_bottom = BORDER_H
	add_child(top)
	var bottom := CircuitBorder.new()
	bottom.color = SKY
	bottom.band = BORDER_H
	bottom.seed_value = 29
	bottom.flip = true
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -BORDER_H
	add_child(bottom)

	# Left column: title, then the menu boxes, between the two borders.
	var margin := MarginContainer.new()
	margin.anchor_bottom = 1.0
	margin.anchor_right = 0.5
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_top", int(BORDER_H) + 10)
	margin.add_theme_constant_override("margin_bottom", int(BORDER_H) + 10)
	add_child(margin)
	var col := UI.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)

	var title := UI.label("STRIDER", 96, Color(0.92, 0.97, 1.0))
	title.add_theme_color_override("font_outline_color", Color(SKY.r, SKY.g, SKY.b, 0.55))
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)
	var sub := UI.label("SURVIVE  ·  SALVAGE  ·  ESCAPE", 18, SKY)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	col.add_child(gap)

	_menu = UI.vbox(10)
	col.add_child(_menu)
	if GS.checkpoint != "" and ResourceLoader.exists(GS.checkpoint):
		var cont := _btn("CONTINUE  ·  " + _area_name(GS.checkpoint), _continue)
		_menu.add_child(cont)
		_play_btn = cont
	else:
		_play_btn = _btn("PLAY", _start_story)
		_menu.add_child(_play_btn)
	_menu.add_child(_btn("SAVE FILES", func(): _show(_saves)))
	var horde_text := "UNRELENTING HORDE"
	if GS.horde_best_wave > 0:
		horde_text += "  ·  BEST %d" % GS.horde_best_wave
	_menu.add_child(_btn(horde_text, _start_horde))
	if GS.reached_base:
		_menu.add_child(_btn("BASE CAMP", func(): get_tree().change_scene_to_file(BASE_SCENE)))
	_menu.add_child(_btn("CONTROLS", func(): _show(_controls)))
	_menu.add_child(_btn("SETTINGS", func(): _show(_settings)))
	_menu.add_child(_btn("RESET PROGRESS", _reset_progress))
	_menu.add_child(_btn("QUIT", func(): get_tree().quit()))

	# Settings / controls replace the menu column when open.
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _show(null))
	col.add_child(_settings)
	_controls = _build_controls()
	_controls.visible = false
	col.add_child(_controls)
	_saves = _build_saves()
	_saves.visible = false
	col.add_child(_saves)
	_skin_panel.call_deferred(_settings)
	_skin_panel(_controls)

	var footer := UI.label("v0.3  ·  tutorial build", 14, Color(SKY.r, SKY.g, SKY.b, 0.7))
	_footer = footer
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 96
	footer.offset_right = 400
	footer.offset_top = -BORDER_H - 6
	footer.offset_bottom = -BORDER_H + 16
	add_child(footer)

	# Top-most layer: her portrait on the right.
	_build_portrait()

	_play_music()

	# Fade in from black.
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full_rect(fade))
	var tw := fade.create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(fade, "modulate:a", 0.0, 1.4)
	tw.tween_callback(fade.queue_free)

	_play_btn.grab_focus()


# ---------------------------------------------------------------- actions

func _start_story() -> void:
	GS.horde_mode = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _continue() -> void:
	GS.horde_mode = false
	get_tree().change_scene_to_file(GS.checkpoint)


func _area_name(scene: String) -> String:
	return {"res://main.tscn": "CRASH SITE", "res://path.tscn": "THE TRAIL", "res://pinned.tscn": "PINNED",
		"res://drag.tscn": "ESCAPE", "res://base.tscn": "BASE CAMP"}.get(scene, "")


func _start_horde() -> void:
	GS.horde_mode = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _reset_progress() -> void:
	GS.reset()
	get_tree().reload_current_scene()


func _show(panel: Control) -> void:
	_settings.visible = panel == _settings
	_controls.visible = panel == _controls
	_saves.visible = panel == _saves
	if panel == _saves:
		_confirm_delete = 0
		_refresh_saves()
	_menu.visible = panel == null
	_footer.visible = panel == null
	if panel == null:
		_play_btn.grab_focus()


func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _settings.visible or _controls.visible or _saves.visible:
			_show(null)
	# Testing (editor only): F4 starts a brand-new game in save slot 5 and jumps
	# straight to the first arrival at camp, as if you'd just been rescued.
	if OS.has_feature("editor") and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		GS.horde_mode = false
		GS.use_slot(5)
		GS.reset()
		GS.wake_at_camp = true
		get_tree().change_scene_to_file("res://base.tscn")
		return
	# Testing: F2 cycles the night backdrop through every area.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		var areas := ["res://main.tscn", "res://path.tscn", "res://pinned.tscn", "res://drag.tscn", "res://base.tscn"]
		var i := areas.find(_backdrop.scene_file_path) if _backdrop != null else -1
		if _backdrop != null:
			_backdrop.queue_free()
		_spawn_backdrop.call_deferred(areas[(i + 1) % areas.size()])


# ---------------------------------------------------------------- look

func _box(alpha: float, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(SKY.r, SKY.g, SKY.b, alpha)
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(2)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(0.14, SKY))
	b.add_theme_stylebox_override("hover", _box(0.32, Color(0.85, 0.96, 1.0)))
	b.add_theme_stylebox_override("focus", _box(0.32, Color(0.85, 0.96, 1.0)))
	b.add_theme_stylebox_override("pressed", _box(0.5, Color.WHITE))
	b.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	b.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.12, 0.8))
	b.add_theme_constant_override("outline_size", 3)


func _btn(text: String, cb: Callable) -> Button:
	var b := UI.button(text, 420.0)
	b.custom_minimum_size = Vector2(420, 52)
	_style_button(b)
	b.pressed.connect(cb)
	return b


## Blue look for the settings / controls boxes (they're shared with the
## pause menu, which keeps its red look).
func _skin_panel(n: Node) -> void:
	if n is PanelContainer:
		var s := _box(0.12, SKY)
		s.bg_color = Color(0.02, 0.05, 0.1, 0.86)
		s.content_margin_left = 32
		s.content_margin_right = 32
		s.content_margin_top = 24
		s.content_margin_bottom = 24
		n.add_theme_stylebox_override("panel", s)
	if n is Button:
		_style_button(n)
	elif n is Label and (n as Label).get_theme_color("font_color") == UI.ACCENT:
		n.add_theme_color_override("font_color", SKY)
	for c in n.get_children():
		_skin_panel(c)


func _build_controls() -> Control:
	var p := PanelContainer.new()
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.label("CONTROLS", 28, SKY))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 1)
	v.add_child(grid)
	var rows := [
		["W A S D", "Walk / strafe"],
		["Shift", "Run"],
		["Mouse", "Aim"],
		["Left click", "Fire"],
		["Right click", "Aim down sights"],
		["Space", "Jump"],
		["R", "Reload (uses a blaster cartridge)"],
		["Q", "Switch rifle / pistol"],
		["H", "Quick heal"],
		["G", "Throw grenade"],
		["E", "Interact / pick up / talk"],
		["Tab or I", "Inventory"],
		["M  K  J  P", "Map · Skills · Quests · Party"],
		["Esc", "Pause menu"],
		["1  2  3  4", "Droid: follow · hold · attack target · weapons free"],
	]
	for r in rows:
		grid.add_child(UI.label(r[0], 16, Color(0.9, 0.97, 1.0)))
		grid.add_child(UI.label(r[1], 16, UI.MUTED))
	var back := UI.button("BACK", 260)
	back.pressed.connect(func(): _show(null))
	v.add_child(back)
	return p


# ---------------------------------------------------------------- backdrop

## The last area you were in, built without player or enemies, at night.
func _build_backdrop() -> bool:
	var path := GS.last_area
	if not ResourceLoader.exists(path):
		path = GAME_SCENE
	return _spawn_backdrop(path)


func _spawn_backdrop(path: String) -> bool:
	var packed = load(path)
	if packed == null:
		return false
	GS.menu_preview = true
	_backdrop = packed.instantiate()
	add_child(_backdrop)
	move_child(_backdrop, 0)
	GS.menu_preview = false
	return true


# ---------------------------------------------------------------- portrait

func _build_portrait() -> void:
	if not ResourceLoader.exists(PORTRAIT_MODEL):
		return
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.anchor_left = 0.44
	svc.anchor_right = 1.0
	svc.anchor_bottom = 1.0
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.48, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# Cool moonlight from the front-left, sky-blue rim from behind-right,
	# a little warm campfire fill from below.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-22.0, -38.0, 0.0)
	key.light_color = Color(0.8, 0.86, 1.0)
	key.light_energy = 1.05
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.45, 0.8, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 4.0
	rim.position = Vector3(0.75, 0.6, -0.9)
	vp.add_child(rim)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.55, 0.28)
	fill.light_energy = 0.7
	fill.omni_range = 3.2
	fill.position = Vector3(-0.9, -0.6, 1.0)
	vp.add_child(fill)

	# She turns slightly towards the left of the screen.
	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(-24.0)
	vp.add_child(holder)
	var inst: Node3D = load(PORTRAIT_MODEL).instantiate()
	holder.add_child(inst)

	# Wind blows from screen left to right (and a little away from camera).
	var wind_world := Vector3(1.0, 0.0, -0.3).normalized()
	var wind_local := holder.basis.inverse() * wind_world
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var src = m.get_active_material(0)
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = HAIR_SHADER
		sm.shader = sh
		if src is BaseMaterial3D:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_texture != null:
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("has_normal", true)
		sm.set_shader_parameter("wind_dir", wind_local)
		m.material_override = sm
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		_skel = found[0]
		for i in _skel.get_bone_count():
			_bones[_skel.get_bone_name(i)] = i

	# Knees up: head clear of the top border, knees at the bottom edge.
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(-0.08, 0.36, 3.2)
	vp.add_child(cam)
	cam.look_at(Vector3(-0.08, 0.36, 0.0))
	cam.make_current()


func _process(delta: float) -> void:
	_time += delta
	if _skel == null:
		return
	# Breathing and a slow, small head sway.
	var breath := sin(_time * 1.7)
	_pose("Spine1", Vector3(breath * 0.012, 0.0, 0.0))
	_pose("Spine2", Vector3(breath * 0.018, 0.0, 0.0))
	_pose("Neck", Vector3(-0.02, -0.06, 0.0))
	_pose("Head", Vector3(-0.03 + sin(_time * 0.5) * 0.015, -0.1 + sin(_time * 0.31) * 0.03, 0.03))


func _pose(bone: String, euler: Vector3) -> void:
	if _bones.has(bone):
		_skel.set_bone_pose_rotation(_bones[bone], Quaternion.from_euler(euler))


# ---------------------------------------------------------------- music

func _play_music() -> void:
	if not ResourceLoader.exists(MUSIC):
		return
	var st = load(MUSIC)
	if st is AudioStreamMP3:
		st.loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = st
	_music.volume_db = -28.0
	add_child(_music)
	_music.play()
	_music.create_tween().tween_property(_music, "volume_db", -5.0, 2.5)


# ---------------------------------------------------------------- save files

func _build_saves() -> Control:
	var v := UI.vbox(10)
	v.add_child(UI.label("SAVE FILES", 28, SKY))
	v.add_child(UI.label("Pick a save to load it, or an empty slot to start a new game.", 15, UI.MUTED))
	_slot_rows = UI.vbox(8)
	v.add_child(_slot_rows)
	var back := _btn("BACK", func(): _show(null))
	v.add_child(back)
	return v


func _refresh_saves() -> void:
	for c in _slot_rows.get_children():
		c.queue_free()
	var current := GS.current_slot()
	for n in range(1, GS.SLOTS + 1):
		var info := GS.slot_info(n)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_slot_rows.add_child(row)
		var text := ""
		if info["used"]:
			var area := _area_name(info["area"])
			var when := ""
			if int(info["saved_at"]) > 0:
				when = Time.get_datetime_string_from_unix_time(int(info["saved_at"]) + _tz_offset(), true).substr(5, 11).replace("T", "  ")
			text = "SLOT %d   ·   %s   ·   LV %d%s" % [n, area if area != "" else "NEW GAME", int(info["level"]), ("   ·   " + when) if when != "" else ""]
		else:
			text = "SLOT %d   ·   EMPTY   ·   NEW GAME" % n
		var b := _btn(("◆ " if n == current and info["used"] else "") + text, _pick_slot.bind(n, info["used"]))
		b.custom_minimum_size = Vector2(560, 50)
		b.add_theme_font_size_override("font_size", 17)
		if not info["used"]:
			b.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.75))
		row.add_child(b)
		if info["used"]:
			var del := _btn("CONFIRM?" if _confirm_delete == n else "DELETE", _delete_slot.bind(n))
			del.custom_minimum_size = Vector2(130, 50)
			del.alignment = HORIZONTAL_ALIGNMENT_CENTER
			del.add_theme_font_size_override("font_size", 15)
			if _confirm_delete == n:
				del.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
			row.add_child(del)
	if _slot_rows.get_child_count() > 0:
		(_slot_rows.get_child(0).get_child(0) as Button).grab_focus.call_deferred()


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _pick_slot(n: int, used: bool) -> void:
	GS.horde_mode = false
	GS.use_slot(n)
	if used and GS.checkpoint != "" and ResourceLoader.exists(GS.checkpoint):
		get_tree().change_scene_to_file(GS.checkpoint)
	else:
		GS.reset()   # brand new save in this slot
		get_tree().change_scene_to_file(GAME_SCENE)


func _delete_slot(n: int) -> void:
	if _confirm_delete != n:
		_confirm_delete = n   # first click asks, second click deletes
	else:
		_confirm_delete = 0
		var was_current := n == GS.current_slot()
		GS.delete_slot(n)
		if was_current:
			get_tree().reload_current_scene()   # rebuild CONTINUE for the now-empty save
			return
	_refresh_saves()
