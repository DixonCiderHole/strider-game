extends CanvasLayer
## Conversation box along the bottom of the screen, usable in any area.
## DialogueBox.say(tree, lines, on_done) plays an Array of [speaker, text]:
## E / Space for the next line, Esc to skip. The player can't move meanwhile.

const UI = preload("res://scripts/ui.gd")
const Banter = preload("res://scripts/banter.gd")

var player
var _panel: PanelContainer
var _name: Label
var _text: Label
var _lines: Array = []
var _i := 0
var _on_done: Callable


static func say(tree: SceneTree, lines: Array, on_done := Callable()) -> void:
	var box = tree.get_first_node_in_group("dialogue_box")
	if box == null:
		box = load("res://scripts/dialogue_box.gd").new()
		tree.current_scene.add_child(box)
	box.play(lines, on_done)


static func is_open(tree: SceneTree) -> bool:
	var box = tree.get_first_node_in_group("dialogue_box")
	return box != null and box._panel.visible


func _ready() -> void:
	layer = 14
	add_to_group("dialogue_box")
	_panel = UI.panel()
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -230
	_panel.offset_bottom = -60
	_panel.visible = false
	add_child(_panel)
	var v := UI.vbox(8)
	_panel.add_child(v)
	_name = UI.label("", 22, UI.ACCENT)
	v.add_child(_name)
	_text = UI.label("", 22, UI.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(600, 0)
	v.add_child(_text)
	v.add_child(UI.label("E / Space: continue   ·   Esc: skip", 14, UI.MUTED))


func play(lines: Array, on_done := Callable()) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_on_done = on_done
	_i = 0
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player != null:
		player.input_enabled = false
	_panel.visible = true
	_show()


func _show() -> void:
	var line: Array = _lines[_i]
	_name.text = Banter.speaker_name(String(line[0]))
	_name.add_theme_color_override("font_color", UI.ACCENT if line[0] != "YOU" else Color(0.95, 0.75, 0.3))
	_text.text = String(line[1])


func _finish() -> void:
	_panel.visible = false
	if player != null and is_instance_valid(player):
		player.input_enabled = true
	if _on_done.is_valid():
		_on_done.call()


func _input(event) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
			get_viewport().set_input_as_handled()
			_i += 1
			if _i >= _lines.size():
				_finish()
			else:
				_show()
		elif event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_finish()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_i += 1
		if _i >= _lines.size():
			_finish()
		else:
			_show()
