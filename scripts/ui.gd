extends RefCounted
## Shared look for menus: dark panels, red accent, chunky buttons.

const Sfx = preload("res://scripts/sfx.gd")
const ACCENT := Color(0.86, 0.13, 0.1)
const TEXT := Color(0.92, 0.92, 0.94)
const MUTED := Color(0.62, 0.64, 0.68)


static func box(bg: Color, border: Color, border_w := 2, radius := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func button(text: String, width := 340.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", box(Color(0.07, 0.07, 0.09, 0.88), Color(0.3, 0.3, 0.35, 0.7)))
	b.add_theme_stylebox_override("hover", box(Color(0.42, 0.05, 0.04, 0.92), ACCENT))
	b.add_theme_stylebox_override("focus", box(Color(0.42, 0.05, 0.04, 0.92), ACCENT))
	b.add_theme_stylebox_override("pressed", box(Color(0.25, 0.03, 0.02, 0.96), ACCENT))
	b.pressed.connect(func(): Sfx.ui("ui_click", -8.0))
	return b


static func label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel_style() -> StyleBoxFlat:
	var s := box(Color(0.035, 0.035, 0.045, 0.94), Color(0.3, 0.06, 0.05), 2, 6)
	s.content_margin_left = 36
	s.content_margin_right = 36
	s.content_margin_top = 28
	s.content_margin_bottom = 28
	return s


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p


static func vbox(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


static func dim() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.6)
	full_rect(r)
	return r
