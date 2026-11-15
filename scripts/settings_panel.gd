extends PanelContainer
## Settings box used by both the main menu and the pause menu.
## Four tabs (GAMEPLAY, CONTROLS, DISPLAY, AUDIO); every option has a short
## line saying what it does. Changes apply and save straight away.

signal closed

const UI = preload("res://scripts/ui.gd")

const TABS := ["GAMEPLAY", "CONTROLS", "DISPLAY", "AUDIO"]
var _pages := {}
var _tab_btns := {}
var _back: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_style())
	var v := UI.vbox(12)
	add_child(v)
	v.add_child(UI.label("SETTINGS", 34, UI.ACCENT))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in TABS:
		var b := UI.button(t, 170)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.toggle_mode = true
		b.pressed.connect(_show.bind(t))
		tabs.add_child(b)
		_tab_btns[t] = b

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for t in TABS:
		var page := UI.vbox(14)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(page)
		_pages[t] = page
	_build_gameplay(_pages["GAMEPLAY"])
	_build_controls(_pages["CONTROLS"])
	_build_display(_pages["DISPLAY"])
	_build_audio(_pages["AUDIO"])

	_back = UI.button("BACK", 260)
	_back.pressed.connect(func(): closed.emit())
	v.add_child(_back)
	_show("GAMEPLAY")
	visibility_changed.connect(func():
		if visible:
			_back.grab_focus())


func _show(t: String) -> void:
	for k in TABS:
		_pages[k].visible = k == t
		_tab_btns[k].button_pressed = k == t


func _changed() -> void:
	Settings.apply()
	Settings.save_settings()


# ---------------------------------------------------------------- pages

func _build_gameplay(p: VBoxContainer) -> void:
	_toggle(p, "Show control hints", "The line of controls along the bottom of the screen.", "show_hints")
	_toggle(p, "Tutorial pop-ups", "Control tips the first time you need them (move, sprint, jump, crouch...).", "show_tutorials")
	_toggle(p, "Objective marker", "A marker on screen over your current objective, with the distance to it.", "objective_marker")
	_toggle(p, "Damage numbers", "CRIT, EVADED, BLOCKED and similar pop-ups during fights.", "damage_numbers")
	_toggle(p, "Cutscene lines move on by themselves", "On: each line holds for its reading time, Space skips ahead. Off: press Space or click for every line.", "cutscene_auto")
	_choice(p, "Subtitle size", "Size of conversation and cutscene text.", "subtitle_size", ["Small", "Medium", "Large"])


func _build_controls(p: VBoxContainer) -> void:
	_slider(p, "Mouse sensitivity", "How fast the camera turns with the mouse.", "mouse_sensitivity", 0.0005, 0.008, 0.0001,
			func(x): return "%d" % roundi(x * 4000.0))
	_slider(p, "Aim sensitivity", "Camera speed while aiming (right mouse), as a share of normal.", "aim_sensitivity", 0.3, 1.0, 0.05,
			func(x): return "%d%%" % roundi(x * 100.0))
	_toggle(p, "Invert mouse Y", "Push the mouse forward to look down.", "invert_y")
	_choice(p, "Crouch", "Toggle: press C to crouch, C again to stand. Hold: crouch while holding C.", "crouch_toggle", ["Hold", "Toggle"], true)
	_toggle(p, "Camera recoil", "The camera kicks up a little with each shot.", "camera_recoil")


func _build_display(p: VBoxContainer) -> void:
	_toggle(p, "Fullscreen", "Fill the whole screen instead of a window.", "fullscreen")
	_slider(p, "Field of view", "How wide the camera sees. Aiming zooms in from this.", "fov", 60.0, 100.0, 1.0,
			func(x): return "%d°" % roundi(x))
	_toggle(p, "VSync", "Sync frames to your monitor to stop screen tearing. Turn off for lower input lag.", "vsync")
	_choice(p, "Frame rate cap", "Limit frames per second to keep fans and heat down.", "max_fps", ["Off", "30", "60", "120", "144"], false,
			[0, 30, 60, 120, 144])
	_slider(p, "Render scale", "Draw the 3D world at a lower resolution for more speed. 100% is sharpest.", "render_scale", 0.5, 1.0, 0.05,
			func(x): return "%d%%" % roundi(x * 100.0))
	_choice(p, "Anti-aliasing", "Smooths jagged edges. Higher costs more performance.", "msaa", ["Off", "2x", "4x"])
	_choice(p, "Shadow quality", "Sharpness of shadows. Lower is faster.", "shadow_quality", ["Low", "Medium", "High"])


func _build_audio(p: VBoxContainer) -> void:
	var pct := func(x): return "%d%%" % roundi(x * 100.0)
	_slider(p, "Master volume", "Everything.", "master_volume", 0.0, 1.0, 0.05, pct)
	_slider(p, "Effects volume", "Blasters, creatures, footsteps, menus.", "sfx_volume", 0.0, 1.0, 0.05, pct)
	_slider(p, "Ambience volume", "Forest, fire and other background loops.", "ambience_volume", 0.0, 1.0, 0.05, pct)


# ---------------------------------------------------------------- rows

func _row(p: VBoxContainer, title: String, desc: String) -> HBoxContainer:
	var box := UI.vbox(2)
	p.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	box.add_child(top)
	var l := UI.label(title, 20, UI.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var d := UI.label(desc, 15, UI.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(700, 0)
	box.add_child(d)
	return top


func _toggle(p: VBoxContainer, title: String, desc: String, key: String) -> void:
	var top := _row(p, title, desc)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get(key))
	c.toggled.connect(func(on: bool):
		Settings.set(key, on)
		_changed())
	top.add_child(c)


func _slider(p: VBoxContainer, title: String, desc: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var top := _row(p, title, desc)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get(key))
	s.custom_minimum_size = Vector2(260, 28)
	top.add_child(s)
	var val := UI.label(fmt.call(s.value), 18)
	val.custom_minimum_size = Vector2(64, 0)
	top.add_child(val)
	s.value_changed.connect(func(x: float):
		Settings.set(key, x)
		val.text = fmt.call(x)
		_changed())


## A row of buttons. `as_bool`: the setting is a bool (index 1 = true).
## `values`: what each button stores (defaults to its index).
func _choice(p: VBoxContainer, title: String, desc: String, key: String, names: Array, as_bool := false, values: Array = []) -> void:
	var top := _row(p, title, desc)
	var btns: Array = []
	var current = Settings.get(key)
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(78, 34)
		b.add_theme_font_size_override("font_size", 16)
		var v = (i == 1) if as_bool else (values[i] if not values.is_empty() else i)
		b.button_pressed = v == current
		btns.append(b)
		top.add_child(b)
		b.pressed.connect(func():
			Settings.set(key, v)
			for o in btns:
				o.button_pressed = o == b
			_changed())
