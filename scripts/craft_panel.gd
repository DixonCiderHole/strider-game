extends CanvasLayer
## Crafting bench screen, laid out like a fabricator terminal:
## category tabs on the left, a grid of recipe tiles in the middle and the
## selected item on the right (big picture, required items with what you
## have, amount and CRAFT). Bench upgrades run along the bottom.

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const Sfx = preload("res://scripts/sfx.gd")

const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.38, 0.32)
const FRAME := Color(0.3, 0.31, 0.35, 0.8)
const TILE_BG := Color(0.07, 0.075, 0.09, 0.95)

var player
var _root: Control
var _title: Label
var _cat := "ALL"
var _cat_buttons := {}
var _grid: GridContainer
var _selected := 0
var _amount := 1
# Detail pane
var _big: TextureRect
var _big_count: Label
var _name: Label
var _type: Label
var _desc: Label
var _reqs: VBoxContainer
var _lock: Label
var _amount_label: Label
var _craft_btn: Button
# Bench strip
var _bench_title: Label
var _bench_reqs: HBoxContainer
var _upgrade_btn: Button


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

	# Header
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UI.label("FABRICATION BENCH", 30, UI.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := UI.button("CLOSE  (Esc)", 200)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.custom_minimum_size.y = 42
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	v.add_child(_rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	v.add_child(body)

	# Categories
	var cats := UI.vbox(6)
	cats.custom_minimum_size = Vector2(190, 0)
	body.add_child(cats)
	for c in ["ALL"] + Items.CRAFT_CATS:
		var b := Button.new()
		b.text = c
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(190, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_stylebox_override("normal", UI.box(Color(0.08, 0.08, 0.1, 0.9), Color(0.25, 0.25, 0.3, 0.6), 1, 3))
		b.add_theme_stylebox_override("hover", UI.box(Color(0.2, 0.06, 0.05, 0.95), UI.ACCENT, 1, 3))
		b.add_theme_stylebox_override("pressed", UI.box(Color(0.42, 0.06, 0.04, 0.95), UI.ACCENT, 2, 3))
		b.pressed.connect(_set_cat.bind(c))
		cats.add_child(b)
		_cat_buttons[c] = b

	# Recipe grid
	var mid := UI.vbox(6)
	body.add_child(mid)
	mid.add_child(UI.label("RECIPES", 15, UI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(4 * 122 + 16, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	# Detail
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UI.box(Color(0.045, 0.05, 0.06, 0.95), FRAME, 1, 4))
	detail.custom_minimum_size = Vector2(430, 0)
	body.add_child(detail)
	var dv := UI.vbox(8)
	detail.add_child(dv)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.11, 0.13, 1.0), Color(0.4, 0.4, 0.45, 0.6), 1, 4))
	frame.custom_minimum_size = Vector2(0, 190)
	dv.add_child(frame)
	var fc := Control.new()
	frame.add_child(fc)
	_big = TextureRect.new()
	_big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	UI.full_rect(_big)
	fc.add_child(_big)
	_big_count = UI.label("", 22, UI.TEXT)
	_big_count.anchor_left = 1.0
	_big_count.anchor_right = 1.0
	_big_count.anchor_top = 1.0
	_big_count.anchor_bottom = 1.0
	_big_count.offset_left = -80
	_big_count.offset_top = -36
	_big_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fc.add_child(_big_count)
	_name = UI.label("", 26, UI.TEXT)
	dv.add_child(_name)
	_type = UI.label("", 14, UI.ACCENT)
	dv.add_child(_type)
	_desc = UI.label("", 16, UI.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(390, 0)
	dv.add_child(_desc)
	dv.add_child(_rule())
	dv.add_child(UI.label("REQUIRED ITEMS", 15, UI.MUTED))
	_reqs = UI.vbox(4)
	dv.add_child(_reqs)
	_lock = UI.label("", 15, BAD)
	_lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock.custom_minimum_size = Vector2(390, 0)
	dv.add_child(_lock)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(spacer)
	var amt := HBoxContainer.new()
	amt.add_theme_constant_override("separation", 8)
	dv.add_child(amt)
	amt.add_child(UI.label("AMOUNT", 15, UI.MUTED))
	var minus := _small_btn("−", _change_amount.bind(-1))
	amt.add_child(minus)
	_amount_label = UI.label("1", 22, UI.TEXT)
	_amount_label.custom_minimum_size = Vector2(36, 0)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amt.add_child(_amount_label)
	amt.add_child(_small_btn("+", _change_amount.bind(1)))
	amt.add_child(_small_btn("MAX", _max_amount))
	_craft_btn = UI.button("CRAFT", 390)
	_craft_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_btn.add_theme_font_size_override("font_size", 24)
	_craft_btn.add_theme_stylebox_override("normal", UI.box(Color(0.5, 0.08, 0.05, 0.95), UI.ACCENT, 2, 4))
	_craft_btn.pressed.connect(_craft)
	dv.add_child(_craft_btn)

	# Bench upgrade strip
	v.add_child(_rule())
	var bench := HBoxContainer.new()
	bench.add_theme_constant_override("separation", 14)
	v.add_child(bench)
	_bench_title = UI.label("", 17, UI.TEXT)
	bench.add_child(_bench_title)
	_bench_reqs = HBoxContainer.new()
	_bench_reqs.add_theme_constant_override("separation", 14)
	_bench_reqs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench.add_child(_bench_reqs)
	_upgrade_btn = UI.button("UPGRADE BENCH", 240)
	_upgrade_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_btn.custom_minimum_size.y = 44
	_upgrade_btn.pressed.connect(_upgrade)
	bench.add_child(_upgrade_btn)
	GS.listeners.append(_refresh)


func _exit_tree() -> void:
	GS.listeners.erase(_refresh)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.08)
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _small_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46 if text.length() < 3 else 64, 36)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", UI.box(Color(0.1, 0.1, 0.12, 0.95), FRAME, 1, 3))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.25, 0.07, 0.05, 0.95), UI.ACCENT, 1, 3))
	b.pressed.connect(cb)
	return b


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
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if not _craft_btn.disabled:
			_craft()


func _visible_recipes() -> Array:
	var out := []
	for i in Items.RECIPES.size():
		if _cat == "ALL" or Items.RECIPES[i].get("cat", "") == _cat:
			out.append(i)
	return out


## How many times the recipe could be made from what's in the backpack.
func _max_crafts(r: Dictionary) -> int:
	var m := 99
	for k in r["in"]:
		m = mini(m, GS.count(k) / maxi(1, int(r["in"][k])))
	return m


func _tile(i: int) -> Control:
	var r: Dictionary = Items.RECIPES[i]
	var unlocked := GS.recipe_unlocked(r)
	var can := unlocked and GS.has_all(r["in"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(114, 122)
	b.tooltip_text = GS.item(r["out"]).get("name", "")
	var border := UI.ACCENT if i == _selected else (Color(0.4, 0.75, 0.45, 0.8) if can else Color(0.25, 0.25, 0.3, 0.7))
	var bg := Color(0.3, 0.05, 0.04, 0.95) if i == _selected else TILE_BG
	b.add_theme_stylebox_override("normal", UI.box(bg, border, 3 if i == _selected else 1, 4))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.2, 0.06, 0.05, 0.95), UI.ACCENT, 2, 4))
	b.add_theme_stylebox_override("pressed", UI.box(Color(0.3, 0.05, 0.04, 0.95), UI.ACCENT, 3, 4))
	b.pressed.connect(_select.bind(i))
	var pic := TextureRect.new()
	pic.texture = Items.icon(r["out"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(17, 8)
	pic.size = Vector2(80, 80)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		pic.modulate = Color(0.35, 0.35, 0.38, 0.8)
	elif not can:
		pic.modulate = Color(0.75, 0.75, 0.78, 0.9)
	b.add_child(pic)
	var nm := UI.label(String(GS.item(r["out"])["name"]), 12, UI.TEXT if unlocked else UI.MUTED)
	nm.position = Vector2(4, 92)
	nm.size = Vector2(106, 24)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	if int(r["count"]) > 1:
		var cnt := UI.label("x%d" % int(r["count"]), 13, UI.TEXT)
		cnt.position = Vector2(80, 70)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cnt)
	if not unlocked:
		var lk := UI.label("LOCKED", 12, BAD)
		lk.position = Vector2(6, 4)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lk)
	elif can:
		var dot := ColorRect.new()
		dot.color = GOOD
		dot.position = Vector2(98, 8)
		dot.size = Vector2(8, 8)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
	return b


func _req_row(id: String, need: int) -> Control:
	var have := GS.count(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bgp := PanelContainer.new()
	var st := UI.box(Color(0.1, 0.11, 0.13, 1.0), (GOOD if have >= need else BAD) * Color(1, 1, 1, 0.7), 1, 3)
	st.content_margin_left = 2
	st.content_margin_right = 2
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	bgp.add_theme_stylebox_override("panel", st)
	row.add_child(bgp)
	var pic := TextureRect.new()
	pic.texture = Items.icon(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(42, 42)
	bgp.add_child(pic)
	var nm := UI.label(String(GS.item(id).get("name", id)), 17, UI.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)
	var n := UI.label("%d / %d" % [have, need * _amount], 18, GOOD if have >= need * _amount else BAD)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(n)
	return row


func _refresh() -> void:
	if not is_inside_tree() or not _root.visible:
		return
	_title.text = "FABRICATION BENCH   ·   LEVEL %d" % GS.bench_level
	for c in _cat_buttons:
		_cat_buttons[c].button_pressed = c == _cat
	var vis := _visible_recipes()
	if not (_selected in vis) and not vis.is_empty():
		_selected = vis[0]
	for c in _grid.get_children():
		c.queue_free()
	for i in vis:
		_grid.add_child(_tile(i))

	var r: Dictionary = Items.RECIPES[_selected]
	var it := GS.item(r["out"])
	_big.texture = Items.icon(r["out"])
	_big_count.text = ("x%d" % (int(r["count"]) * _amount)) if int(r["count"]) * _amount > 1 else ""
	_name.text = it["name"]
	_type.text = String(it.get("type", "")).to_upper() + ("   ·   %d SLOTS" % int(it["slots"]) if it.has("slots") else "")
	_desc.text = it.get("desc", "")
	for c in _reqs.get_children():
		c.queue_free()
	for k in r["in"]:
		_reqs.add_child(_req_row(k, int(r["in"][k])))
	var lock := PackedStringArray()
	if GS.bench_level < int(r.get("bench", 1)):
		lock.append("Needs crafting bench level %d." % int(r["bench"]))
	var sk: String = r.get("skill", "")
	if sk != "" and GS.rank(sk) <= 0:
		lock.append("Needs the skill \"%s\"." % GS.skill_def(sk)["name"])
	_lock.text = "\n".join(lock)
	_amount_label.text = str(_amount)
	var can := GS.recipe_unlocked(r) and _max_crafts(r) >= _amount
	_craft_btn.disabled = not can
	_craft_btn.text = ("CRAFT" if _amount == 1 else "CRAFT  x%d" % _amount) + "   [Enter]"

	var next := GS.bench_level + 1
	for c in _bench_reqs.get_children():
		c.queue_free()
	if Items.BENCH_LEVELS.has(next):
		_bench_title.text = "UPGRADE TO LEVEL %d" % next
		var cost: Dictionary = Items.BENCH_LEVELS[next]["in"]
		for k in cost:
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 4)
			var pic := TextureRect.new()
			pic.texture = Items.icon(k)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = Vector2(34, 34)
			chip.add_child(pic)
			var have := GS.count(k)
			var lab := UI.label("%d/%d" % [have, int(cost[k])], 16, GOOD if have >= int(cost[k]) else BAD)
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			chip.add_child(lab)
			_bench_reqs.add_child(chip)
		_upgrade_btn.visible = true
		_upgrade_btn.disabled = not GS.has_all(cost)
	else:
		_bench_title.text = "BENCH FULLY UPGRADED"
		_upgrade_btn.visible = false


func _set_cat(c: String) -> void:
	_cat = c
	_amount = 1
	_refresh()


func _select(i: int) -> void:
	if i != _selected:
		_amount = 1
	_selected = i
	_refresh()


func _change_amount(d: int) -> void:
	_amount = clampi(_amount + d, 1, 20)
	_refresh()


func _max_amount() -> void:
	_amount = clampi(_max_crafts(Items.RECIPES[_selected]), 1, 20)
	_refresh()


func _craft() -> void:
	var made := 0
	for k in _amount:
		if not GS.craft(Items.RECIPES[_selected]):
			break
		made += 1
	if made > 0:
		Sfx.ui("upgrade", -5.0, 0.05)
	_amount = 1
	_refresh()


func _upgrade() -> void:
	if GS.upgrade_bench():
		Sfx.ui("upgrade", -3.0)
	_refresh()
