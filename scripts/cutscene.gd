extends CanvasLayer
## Placeholder cutscenes: fade to black, show captions, then load the next
## section and fade back in. Call Cutscene.play("id") from any scene.
## The black overlay sits on the scene tree root, so it stays up while the
## next section is loading. Space / click: next caption. Esc: skip.

const UI = preload("res://scripts/ui.gd")

## id -> {cards: [String], next: scene path}
const CUTSCENES := {
	"leave_crash": {
		"cards": [
			"The last of them falls back into the trees.",
			"You take what you can carry from the wreck and head out along an old trail,\nlooking for the rest of your squad.",
		],
		"next": "res://path.tscn",
	},
	"ambushed": {
		"cards": [
			"Something slams into you from the treeline.",
			"You come to sitting against a tree,\na creature's spine driven through your armor.",
			"You can't move. But you can still shoot.",
		],
		"next": "res://pinned.tscn",
	},
	"rescued": {
		"cards": [
			"Everything goes dark.",
			"Footsteps. Someone is picking through the bodies of your fallen squad.",
			"She stops at you. Two fingers to your neck...\na pulse. The only two left alive.",
			"She tears the spine free, grabs you by the collar and starts to drag.",
		],
		"next": "res://drag.tscn",
	},
	"escaped": {
		"cards": [
			"She hauls you the last stretch to a cave in the cliffs.",
			"For now, you're both safe.",
		],
		"next": "res://base.tscn",
	},
}

const CARD_TIME := 4.0
const FADE := 0.8

var _cards: Array = []
var _next := ""
var _index := -1
var _black: ColorRect
var _label: Label
var _hint: Label
var _timer := 0.0
var _state := "fade_in"   # fade_in -> cards -> loading -> fade_out


static func play(id: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree.root.has_node("Cutscene"):
		return  # one at a time
	var cs = load("res://scripts/cutscene.gd").new()
	cs.name = "Cutscene"
	var data: Dictionary = CUTSCENES.get(id, {})
	cs._cards = data.get("cards", [])
	cs._next = data.get("next", "res://main_menu.tscn")
	tree.root.add_child(cs)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ResourceLoader.exists(_next):
		_next = "res://base.tscn"  # section not built yet

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_black)

	_label = UI.label("", 30, UI.TEXT)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.modulate.a = 0.0
	root.add_child(_label)

	_hint = UI.label("Space: next   ·   Esc: skip", 15, UI.MUTED)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.position = Vector2(-300, -40)
	_hint.size = Vector2(276, 26)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate.a = 0.0
	root.add_child(_hint)

	# Freeze the section underneath so nothing attacks you in the dark.
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_timer = FADE


func _process(delta: float) -> void:
	match _state:
		"fade_in":
			_timer -= delta
			_black.color.a = clampf(1.0 - _timer / FADE, 0.0, 1.0)
			if _timer <= 0.0:
				_black.color.a = 1.0
				_hint.modulate.a = 1.0
				_state = "cards"
				_show_next()
		"cards":
			_timer -= delta
			_label.modulate.a = minf(1.0, _label.modulate.a + delta * 2.0)
			if _timer <= 0.0:
				_show_next()
		"loading":
			# Give the new section a few frames to build, then fade in.
			_timer -= 1.0
			if _timer <= 0.0:
				_state = "fade_out"
				_timer = FADE
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		"fade_out":
			_timer -= delta
			_black.color.a = clampf(_timer / FADE, 0.0, 1.0)
			if _timer <= 0.0:
				queue_free()


func _input(event) -> void:
	if _state != "cards":
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	if key and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_load_next()
	elif (key and event.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]) \
			or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_show_next()


func _show_next() -> void:
	_index += 1
	if _index >= _cards.size():
		_load_next()
		return
	_timer = CARD_TIME
	_label.text = _cards[_index]
	_label.modulate.a = 0.0


func _load_next() -> void:
	_state = "loading"
	_timer = 4.0   # frames
	_label.text = ""
	_hint.modulate.a = 0.0
	get_tree().paused = false
	get_tree().change_scene_to_file(_next)
