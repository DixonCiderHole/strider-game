extends CanvasLayer
## Reading screen for datapads, journals and radio logs (see lore.gd).
## First read of each one gives a little XP.

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Lore = preload("res://scripts/lore.gd")
const Sfx = preload("res://scripts/sfx.gd")

const FIRST_READ_XP := 10

var player
var _root: Control
var _title: Label
var _source: Label
var _body: Label


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("lore_panel")
	_root = UI.full_rect(Control.new())
	_root.visible = false
	add_child(_root)
	_root.add_child(UI.dim())
	var center := UI.full_rect(CenterContainer.new())
	_root.add_child(center)
	var p := UI.panel()
	center.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	_title = UI.label("", 30, UI.ACCENT)
	v.add_child(_title)
	_source = UI.label("", 16, UI.MUTED)
	v.add_child(_source)
	var line := ColorRect.new()
	line.color = Color(UI.ACCENT, 0.5)
	line.custom_minimum_size = Vector2(0, 2)
	v.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = UI.label("", 19)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(740, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var close_btn := UI.button("CLOSE  (E / Esc)", 260)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(close)
	v.add_child(close_btn)


func open(id: String) -> void:
	if player != null and is_instance_valid(player) and not player.input_enabled:
		return
	var e := Lore.entry(id)
	if e.is_empty():
		return
	_title.text = String(e["title"]).to_upper()
	_source.text = String(e.get("source", ""))
	_body.text = String(e["text"])
	_root.visible = true
	get_tree().paused = true
	if player != null:
		player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ui("ui_click", -6.0, 0.05)
	if not GS.flags.get("read:" + id, false):
		GS.flags["read:" + id] = true
		GS.add_xp(FIRST_READ_XP)
		GS.toast("New log: %s  (+%d XP)" % [e["title"], FIRST_READ_XP])
		GS.save()


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


static func read(tree: SceneTree, id: String) -> void:
	for p in tree.get_nodes_in_group("lore_panel"):
		p.open(id)
		return
