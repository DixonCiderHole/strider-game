extends PanelContainer
## Settings box used by both the main menu and the pause menu.

signal closed

const UI = preload("res://scripts/ui.gd")


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_style())
	var v := UI.vbox(16)
	add_child(v)
	v.add_child(UI.label("SETTINGS", 34, UI.ACCENT))

	v.add_child(UI.label("Mouse sensitivity", 20, UI.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 0.0005
	slider.max_value = 0.008
	slider.step = 0.0001
	slider.value = Settings.mouse_sensitivity
	slider.custom_minimum_size = Vector2(320, 30)
	row.add_child(slider)
	var value_label := UI.label("", 20)
	value_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(value_label)
	var show_value := func(x: float): value_label.text = "%d" % roundi(x * 4000.0)
	show_value.call(slider.value)
	slider.value_changed.connect(func(x: float):
		Settings.mouse_sensitivity = x
		show_value.call(x)
		Settings.save_settings())

	v.add_child(_check("Invert mouse Y", Settings.invert_y, func(on: bool):
		Settings.invert_y = on
		Settings.save_settings()))
	v.add_child(_check("Fullscreen", Settings.fullscreen, func(on: bool):
		Settings.fullscreen = on
		Settings.apply()
		Settings.save_settings()))
	v.add_child(_check("Show control hints", Settings.show_hints, func(on: bool):
		Settings.show_hints = on
		Settings.save_settings()))

	var back := UI.button("BACK", 260)
	back.pressed.connect(func(): closed.emit())
	v.add_child(back)
	visibility_changed.connect(func():
		if visible:
			back.grab_focus())


func _check(text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 20)
	c.add_theme_color_override("font_color", UI.TEXT)
	c.toggled.connect(cb)
	return c
