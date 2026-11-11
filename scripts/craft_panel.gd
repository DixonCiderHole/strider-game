extends CanvasLayer
## Crafting bench screen: recipe list, ingredients, CRAFT, and bench upgrades.

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const Sfx = preload("res://scripts/sfx.gd")

var player
var _root: Control
var _list: VBoxContainer
var _title: Label
var _name: Label
var _desc: Label
var _needs: Label
var _craft_btn: Button
var _bench_label: Label
var _upgrade_btn: Button
var _selected := 0


func _ready() -> void:
	layer = 15
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
	p.add_child(v)
	_title = UI.label("CRAFTING BENCH", 32, UI.ACCENT)
	v.add_child(_title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	v.add_child(h)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_list = UI.vbox(6)
	scroll.add_child(_list)

	var right := UI.vbox(10)
	right.custom_minimum_size = Vector2(520, 0)
	h.add_child(right)
	_name = UI.label("", 28, UI.TEXT)
	right.add_child(_name)
	_desc = UI.label("", 17, UI.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(520, 0)
	right.add_child(_desc)
	right.add_child(UI.label("NEEDS", 16, UI.ACCENT))
	_needs = UI.label("", 20, UI.TEXT)
	right.add_child(_needs)
	_craft_btn = UI.button("CRAFT", 260)
	_craft_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_btn.pressed.connect(_craft)
	right.add_child(_craft_btn)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	right.add_child(gap)
	_bench_label = UI.label("", 17, UI.MUTED)
	_bench_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bench_label.custom_minimum_size = Vector2(520, 0)
	right.add_child(_bench_label)
	_upgrade_btn = UI.button("UPGRADE BENCH", 300)
	_upgrade_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_btn.pressed.connect(_upgrade)
	right.add_child(_upgrade_btn)
	var close_btn := UI.button("CLOSE  (Esc)", 260)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(close)
	v.add_child(close_btn)
	GS.listeners.append(_refresh)


func _exit_tree() -> void:
	GS.listeners.erase(_refresh)


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	if player != null:
		player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false
	if player != null:
		player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_E]:
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	if not is_inside_tree() or not _root.visible:
		return
	_title.text = "CRAFTING BENCH   ·   LEVEL %d" % GS.bench_level
	for c in _list.get_children():
		c.queue_free()
	for i in Items.RECIPES.size():
		var r: Dictionary = Items.RECIPES[i]
		var it := GS.item(r["out"])
		var unlocked := GS.recipe_unlocked(r)
		var mark := ""
		if not unlocked:
			mark = "  (locked)"
		elif GS.has_all(r["in"]):
			mark = "  ●"
		var b := UI.button(String(it["name"]) + mark, 340)
		b.custom_minimum_size.y = 44
		b.add_theme_font_size_override("font_size", 18)
		if i == _selected:
			b.add_theme_stylebox_override("normal", UI.box(Color(0.42, 0.05, 0.04, 0.92), UI.ACCENT))
		if not unlocked:
			b.add_theme_color_override("font_color", UI.MUTED)
		b.pressed.connect(_select.bind(i))
		_list.add_child(b)

	var rr: Dictionary = Items.RECIPES[_selected]
	var it2 := GS.item(rr["out"])
	_name.text = "%s%s" % [it2["name"], ("  x%d" % rr["count"]) if int(rr["count"]) > 1 else ""]
	_desc.text = it2.get("desc", "")
	var lines := PackedStringArray()
	for k in rr["in"]:
		var have := GS.count(k)
		var need: int = rr["in"][k]
		lines.append("%s %s   %d / %d" % ["✓" if have >= need else "✗", GS.item(k)["name"], have, need])
	var lock := ""
	if GS.bench_level < int(rr.get("bench", 1)):
		lock = "\nNeeds crafting bench level %d." % int(rr["bench"])
	var sk: String = rr.get("skill", "")
	if sk != "" and GS.rank(sk) <= 0:
		lock += "\nNeeds the skill \"%s\"." % GS.skill_def(sk)["name"]
	_needs.text = "\n".join(lines) + lock
	_craft_btn.disabled = not (GS.recipe_unlocked(rr) and GS.has_all(rr["in"]))

	var next := GS.bench_level + 1
	if Items.BENCH_LEVELS.has(next):
		var cost: Dictionary = Items.BENCH_LEVELS[next]["in"]
		var parts := PackedStringArray()
		for k in cost:
			parts.append("%s %d/%d" % [GS.item(k)["name"], GS.count(k), int(cost[k])])
		_bench_label.text = "Upgrade to level %d (unlocks grenades, pistol, stims and modules):\n%s" % [next, ",  ".join(parts)]
		_upgrade_btn.visible = true
		_upgrade_btn.disabled = not GS.has_all(cost)
	else:
		_bench_label.text = "Bench fully upgraded."
		_upgrade_btn.visible = false


func _select(i: int) -> void:
	_selected = i
	_refresh()


func _craft() -> void:
	if GS.craft(Items.RECIPES[_selected]):
		Sfx.ui("upgrade", -5.0, 0.05)
	_refresh()


func _upgrade() -> void:
	if GS.upgrade_bench():
		Sfx.ui("upgrade", -3.0)
	_refresh()
