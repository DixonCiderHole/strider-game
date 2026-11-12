extends CanvasLayer
## Storage crate screen: your backpack on the left, the crate on the right.
## Click a stack to move it across.

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const Sfx = preload("res://scripts/sfx.gd")

var player
var _crate = null
var _root: Control
var _title: Label
var _cap: Label
var _pack_grid: GridContainer
var _crate_grid: GridContainer
var _pickup_btn: Button
var _hint: Label


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("storage_panel")
	_root = UI.full_rect(Control.new())
	_root.visible = false
	add_child(_root)
	_root.add_child(UI.dim())
	var center := UI.full_rect(CenterContainer.new())
	_root.add_child(center)
	var p := UI.panel()
	center.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	_title = UI.label("STORAGE", 32, UI.ACCENT)
	v.add_child(_title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	v.add_child(h)

	var left := UI.vbox(8)
	h.add_child(left)
	left.add_child(UI.label("BACKPACK", 18, UI.ACCENT))
	_pack_grid = GridContainer.new()
	_pack_grid.columns = 6
	_pack_grid.add_theme_constant_override("h_separation", 6)
	_pack_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(_pack_grid)

	var right := UI.vbox(8)
	h.add_child(right)
	_cap = UI.label("CRATE", 18, UI.ACCENT)
	right.add_child(_cap)
	_crate_grid = GridContainer.new()
	_crate_grid.columns = 5
	_crate_grid.add_theme_constant_override("h_separation", 6)
	_crate_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_crate_grid)

	_hint = UI.label("Click a stack to move it across.", 16, UI.MUTED)
	v.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for spec in [["STORE ALL", _store_all], ["TAKE ALL", _take_all]]:
		var b := UI.button(spec[0], 200)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(spec[1])
		row.add_child(b)
	_pickup_btn = UI.button("PICK UP CRATE", 240)
	_pickup_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_btn.pressed.connect(_pick_up)
	row.add_child(_pickup_btn)
	var close_btn := UI.button("CLOSE  (Esc)", 220)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	GS.listeners.append(_refresh)


func _exit_tree() -> void:
	GS.listeners.erase(_refresh)


func open_crate(c) -> void:
	if player != null and is_instance_valid(player) and not player.input_enabled:
		return
	_crate = c
	_root.visible = true
	get_tree().paused = true
	if player != null:
		player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ui("crate_open", -8.0, 0.05)
	_refresh()


func close() -> void:
	_root.visible = false
	_crate = null
	get_tree().paused = false
	if player != null:
		player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GS.save()


func _input(event) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_E, KEY_TAB]:
		get_viewport().set_input_as_handled()
		close()


func _tile(s, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(84, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", 56)
	b.add_theme_font_size_override("font_size", 14)
	var col := Color(0.06, 0.06, 0.08, 0.92)
	if s != null:
		var it := GS.item(s["id"])
		b.icon = Items.icon(s["id"])
		b.text = ("x%d" % int(s["n"])) if int(s["n"]) > 1 else " "
		b.tooltip_text = it.get("name", "")
		col = (it.get("color", Color.GRAY) as Color).darkened(0.72)
	b.add_theme_stylebox_override("normal", UI.box(col, Color(0.3, 0.3, 0.35, 0.7), 2, 4))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.5, 0.1, 0.08), UI.ACCENT, 3, 4))
	b.add_theme_stylebox_override("pressed", UI.box(Color(0.5, 0.1, 0.08), UI.ACCENT, 3, 4))
	b.pressed.connect(cb)
	return b


func _refresh() -> void:
	if not is_inside_tree() or not _root.visible or _crate == null or not is_instance_valid(_crate):
		return
	var d: Dictionary = _crate.data
	var used := 0
	for s in d["items"]:
		if s != null:
			used += 1
	_title.text = String(GS.item(d["type"])["name"]).to_upper()
	_cap.text = "CRATE   %d / %d" % [used, d["items"].size()]
	for c in _pack_grid.get_children():
		c.queue_free()
	for c in _crate_grid.get_children():
		c.queue_free()
	for i in GS.backpack.size():
		_pack_grid.add_child(_tile(GS.backpack[i], _store.bind(i)))
	for j in d["items"].size():
		_crate_grid.add_child(_tile(d["items"][j], _take.bind(j)))
	_pickup_btn.disabled = used > 0
	_pickup_btn.tooltip_text = "Empty the crate first." if used > 0 else ""


func _store(i: int) -> void:
	if GS.store(_crate.data, i):
		Sfx.ui("ui_click", -10.0, 0.1)
	else:
		GS.toast("The crate is full.")
	_refresh()


func _take(i: int) -> void:
	if GS.take(_crate.data, i):
		Sfx.ui("ui_click", -10.0, 0.1)
	else:
		GS.toast("Your backpack is full.")
	_refresh()


func _store_all() -> void:
	for i in GS.backpack.size():
		var s = GS.backpack[i]
		if s != null and GS.item(s["id"]).get("type") in ["resource", "consumable", "ammo", "placeable"]:
			GS.store(_crate.data, i)
	_refresh()


func _take_all() -> void:
	for j in _crate.data["items"].size():
		GS.take(_crate.data, j)
	_refresh()


func _pick_up() -> void:
	var c = _crate
	if GS.add_item(c.data["type"], 1, false) > 0:
		GS.toast("Your backpack is full.")
		return
	GS.storage.erase(c.data)
	close()
	c.queue_free()
	GS.toast("Picked up %s" % GS.item(c.data["type"])["name"])
	GS.save()
