extends CanvasLayer
## On-screen info: health, wave, enemies left, crosshair and messages.

var _health_bar: ProgressBar
var _health_label: Label
var _wave_label: Label
var _enemies_label: Label
var _message: Label
var _hint: Label
var _flash: ColorRect
var _hitmarker: Label
var _kills_label: Label
var _kills := 0
var _droid_panel: PanelContainer
var _droid_order: Label
var _droid_weapons: Label
var _last_health := -1.0
var _msg_token := 0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	var crosshair := _label("+", 30)
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	root.add_child(crosshair)

	_hitmarker = _label("x", 34)
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmarker.modulate.a = 0.0
	root.add_child(_hitmarker)

	_health_label = _label("HEALTH", 18)
	_health_label.position = Vector2(28, 18)
	root.add_child(_health_label)

	_health_bar = ProgressBar.new()
	_health_bar.position = Vector2(28, 46)
	_health_bar.size = Vector2(280, 20)
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.12, 0.1)
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.add_theme_stylebox_override("fill", fill)
	root.add_child(_health_bar)

	_wave_label = _label("", 26)
	_wave_label.anchor_left = 1.0
	_wave_label.anchor_right = 1.0
	_wave_label.offset_left = -360
	_wave_label.offset_right = -28
	_wave_label.offset_top = 16
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_wave_label)

	_enemies_label = _label("", 20)
	_enemies_label.anchor_left = 1.0
	_enemies_label.anchor_right = 1.0
	_enemies_label.offset_left = -360
	_enemies_label.offset_right = -28
	_enemies_label.offset_top = 52
	_enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_enemies_label)

	_kills_label = _label("KILLS  0", 20)
	_kills_label.anchor_left = 1.0
	_kills_label.anchor_right = 1.0
	_kills_label.offset_left = -360
	_kills_label.offset_right = -28
	_kills_label.offset_top = 82
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kills_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.7))
	root.add_child(_kills_label)

	_build_droid_panel(root)

	_message = _label("", 40)
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.offset_bottom = -260
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(_message)

	_hint = _label("", 17)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_right = 1.0
	_hint.offset_top = -48
	_hint.offset_bottom = -16
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	root.add_child(_hint)


func _build_droid_panel(root: Control) -> void:
	_droid_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.06, 0.7)
	sb.border_color = Color(0.3, 0.75, 1.0, 0.8)
	sb.border_width_left = 3
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_droid_panel.add_theme_stylebox_override("panel", sb)
	_droid_panel.anchor_top = 1.0
	_droid_panel.anchor_bottom = 1.0
	_droid_panel.offset_left = 28
	_droid_panel.offset_top = -150
	_droid_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_droid_panel.visible = false
	root.add_child(_droid_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_droid_panel.add_child(v)
	var title := _label("DROID", 16)
	title.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	v.add_child(title)
	_droid_order = _label("FOLLOWING", 22)
	v.add_child(_droid_order)
	_droid_weapons = _label("WEAPONS FREE", 15)
	v.add_child(_droid_weapons)
	var keys := _label("1 Follow   2 Hold   3 Go / Attack   4 Fire on/off", 14)
	keys.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(keys)


func show_droid(on: bool) -> void:
	_droid_panel.visible = on


func set_droid_status(order_text: String, weapons_free: bool) -> void:
	_droid_order.text = order_text
	_droid_weapons.text = "WEAPONS FREE" if weapons_free else "HOLDING FIRE"
	_droid_weapons.add_theme_color_override("font_color",
			Color(0.5, 1.0, 0.6) if weapons_free else Color(1.0, 0.75, 0.3))
	var tw := create_tween()
	_droid_panel.modulate = Color(1.6, 1.6, 1.6)
	tw.tween_property(_droid_panel, "modulate", Color.WHITE, 0.3)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "HEALTH  %d" % int(round(current))
	if _last_health >= 0.0 and current < _last_health:
		_flash.color.a = 0.35
		var tw := create_tween()
		tw.tween_property(_flash, "color:a", 0.0, 0.35)
	_last_health = current


func set_wave(n: int, total: int) -> void:
	_wave_label.text = ("WAVE %d / %d" % [n, total]) if total > 0 else ("WAVE %d" % n)


## Free-form top-right text for areas without waves.
func set_objective(title: String, detail: String) -> void:
	_wave_label.text = title
	_enemies_label.text = detail


func set_enemies(n: int) -> void:
	_enemies_label.text = "Creatures left: %d" % n


func set_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = Settings.show_hints


func show_hitmarker(killed: bool) -> void:
	_hitmarker.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2) if killed else Color.WHITE)
	_hitmarker.modulate.a = 1.0
	_hitmarker.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(_hitmarker, "modulate:a", 0.0, 0.25 if not killed else 0.45)
	if killed:
		_kills += 1
		_kills_label.text = "KILLS  %d" % _kills


func kills() -> int:
	return _kills


## Shows a centred message. duration <= 0 keeps it on screen.
func show_message(text: String, duration: float) -> void:
	_msg_token += 1
	var token := _msg_token
	_message.text = text
	_message.modulate.a = 1.0
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration, false).timeout
	if token == _msg_token:
		var tw := create_tween()
		tw.tween_property(_message, "modulate:a", 0.0, 0.5)
