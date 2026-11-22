extends CanvasLayer
## Scrapping at the bench: break down spare weapons, modules and grenades
## from your backpack for salvage and some of the parts they were made from.
## (Equipped gear isn't in the backpack, so it can't be scrapped by mistake.)

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const Sfx = preload("res://scripts/sfx.gd")

const SCRAP_TYPES := ["weapon", "module", "utility"]

var player
var _root: Control
var _list: VBoxContainer
var _head: Label
var _back_to: Node


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = UI.full_rect(Control.new())
	_root.visible = false
	add_child(_root)
	_root.add_child(UI.dim())
	var center := UI.full_rect(CenterContainer.new())
	_root.add_child(center)
	var p := UI.panel()
	center.add_child(p)
	var v := UI.vbox(12)
	v.custom_minimum_size = Vector2(760, 0)
	p.add_child(v)
	v.add_child(UI.label("SCRAP GEAR", 32, UI.ACCENT))
	v.add_child(UI.label("Break spare gear down for salvage and some of its parts back. Equipped gear is safe.", 16, UI.MUTED))
	_head = UI.label("", 18, Color(1.0, 0.8, 0.45))
	v.add_child(_head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = UI.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var close_btn := UI.button("BACK  (Esc)", 220)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(close)
	v.add_child(close_btn)


## What one of `id` breaks down into: {"salvage": n, "<material>": n, ...}.
static func yield_of(id: String) -> Dictionary:
	var out := {"salvage": 8}
	for r in Items.RECIPES:
		if r["out"] != id:
			continue
		var per := maxf(1.0, float(r["count"]))
		var total := 0
		for k in r["in"]:
			total += int(r["in"][k])
			var back := int(floor(int(r["in"][k]) / per * 0.5))
			if back > 0:
				out[k] = back
		out["salvage"] = int(round(total * 4.0 / per)) + 6 * int(r.get("bench", 1))
		return out
	# Not craftable (found or a reward): worth more salvage, no parts back.
	match String(GS.item(id).get("type", "")):
		"weapon":
			out["salvage"] = 30
		"module":
			out["salvage"] = 35
	return out


static func _yield_text(y: Dictionary) -> String:
	var parts := PackedStringArray(["%d salvage" % int(y["salvage"])])
	for k in y:
		if k != "salvage":
			parts.append("%d %s" % [int(y[k]), String(GS.item(k).get("name", k))])
	return ", ".join(parts)


func _scrap(id: String, n: int) -> void:
	n = mini(n, GS.count(id))
	if n <= 0:
		return
	GS.remove_item(id, n)
	var y := yield_of(id)
	GS.add_salvage(int(y["salvage"]) * n)
	for k in y:
		if k != "salvage":
			GS.add_item(k, int(y[k]) * n, false)
	GS.toast("Scrapped %d x %s" % [n, String(GS.item(id).get("name", id))])
	Sfx.ui("crate_open", -6.0, 0.1)
	GS.changed()
	_refresh()


func open(back_to: Node = null) -> void:
	_back_to = back_to
	_root.visible = true
	_refresh()


func close() -> void:
	_root.visible = false
	if _back_to != null and is_instance_valid(_back_to) and _back_to.has_method("open"):
		_back_to.open()


func _input(event) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_TAB]:
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	if not _root.visible:
		return
	_head.text = "SALVAGE  %d" % GS.salvage
	for c in _list.get_children():
		c.queue_free()
	var seen := {}
	for s in GS.backpack:
		if s == null:
			continue
		var id: String = s["id"]
		if seen.has(id) or not (String(GS.item(id).get("type", "")) in SCRAP_TYPES):
			continue
		seen[id] = true
		var have := GS.count(id)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.box(Color(0.07, 0.07, 0.09, 0.92), Color(0.3, 0.3, 0.35, 0.6), 1, 6))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var pic := TextureRect.new()
		pic.texture = Items.icon(id)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(56, 56)
		h.add_child(pic)
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s   x%d" % [String(GS.item(id).get("name", id)), have], 18, UI.TEXT))
		info.add_child(UI.label("Each gives: " + _yield_text(yield_of(id)), 14, UI.MUTED))
		h.add_child(info)
		var one := UI.button("SCRAP 1", 130)
		one.alignment = HORIZONTAL_ALIGNMENT_CENTER
		one.pressed.connect(_scrap.bind(id, 1))
		h.add_child(one)
		if have > 1:
			var all := UI.button("SCRAP ALL", 140)
			all.alignment = HORIZONTAL_ALIGNMENT_CENTER
			all.pressed.connect(_scrap.bind(id, have))
			h.add_child(all)
		_list.add_child(row)
	if _list.get_child_count() == 0:
		_list.add_child(UI.label("Nothing to scrap. Spare weapons, modules and grenades in your backpack show up here.", 16, UI.MUTED))
