extends CanvasLayer
## The camp job board: three repeatable jobs at a time that pay salvage.
##   hunt     kill N creatures (anywhere, counted from when the job is posted)
##   elite    kill N elite creatures
##   supply   hand over N of a material
## Turning a job in pays it out and posts a new one. Jobs live in
## GS.flags["jobs"] so they carry between areas and saves.

const UI = preload("res://scripts/ui.gd")
const GS = preload("res://scripts/game_state.gd")
const Items = preload("res://scripts/items.gd")
const Sfx = preload("res://scripts/sfx.gd")

const JOB_COUNT := 3
const SUPPLY := {"scrap": [6, 10], "ore": [3, 6], "fiber": [6, 10], "glowcap": [3, 5], "crystal": [2, 4], "tech": [2, 4], "plastic": [3, 6]}

var player
var _root: Control
var _list: VBoxContainer
var _head: Label


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
	v.custom_minimum_size = Vector2(760, 0)
	p.add_child(v)
	v.add_child(UI.label("JOB BOARD", 32, UI.ACCENT))
	v.add_child(UI.label("Camp work that pays in salvage. Finish a job, turn it in here, and a new one goes up.", 16, UI.MUTED))
	_head = UI.label("", 18, Color(1.0, 0.8, 0.45))
	v.add_child(_head)
	_list = UI.vbox(10)
	v.add_child(_list)
	var close_btn := UI.button("CLOSE  (Esc)", 220)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(close)
	v.add_child(close_btn)


# ------------------------------------------------------------ jobs

static func jobs() -> Array:
	GS.ensure_loaded()
	var js: Array = GS.flags.get("jobs", [])
	while js.size() < JOB_COUNT:
		js.append(_new_job(js))
	GS.flags["jobs"] = js
	return js


static func _new_job(existing: Array) -> Dictionary:
	var kinds := ["hunt", "supply", "hunt", "elite", "supply"]
	var kind: String = kinds[randi() % kinds.size()]
	# Don't post two of the same kind at once if we can help it.
	for _i in 4:
		var dup := false
		for j in existing:
			if j["kind"] == kind:
				dup = true
		if not dup:
			break
		kind = kinds[randi() % kinds.size()]
	match kind:
		"hunt":
			var n := randi_range(8, 16)
			return {"kind": "hunt", "need": n, "start": int(GS.flags.get("kills", 0)), "pay": 3 * n + 10}
		"elite":
			var n2 := randi_range(1, 2)
			return {"kind": "elite", "need": n2, "start": int(GS.flags.get("elite_kills", 0)), "pay": 55 * n2}
		_:
			var ids := SUPPLY.keys()
			var id: String = ids[randi() % ids.size()]
			var r: Array = SUPPLY[id]
			var n3 := randi_range(int(r[0]), int(r[1]))
			return {"kind": "supply", "item": id, "need": n3, "pay": 5 * n3 + 10}


static func progress(j: Dictionary) -> int:
	match String(j["kind"]):
		"hunt":
			return int(GS.flags.get("kills", 0)) - int(j["start"])
		"elite":
			return int(GS.flags.get("elite_kills", 0)) - int(j["start"])
		_:
			return GS.count(String(j["item"]))


static func describe(j: Dictionary) -> String:
	match String(j["kind"]):
		"hunt":
			return "Cull the packs: kill %d creatures" % int(j["need"])
		"elite":
			return "Big game: kill %d elite creature%s (the ones with the molten glow)" % [int(j["need"]), "" if int(j["need"]) == 1 else "s"]
		_:
			return "Supply run: hand over %d %s" % [int(j["need"]), String(GS.item(String(j["item"])).get("name", j["item"]))]


func _turn_in(i: int) -> void:
	var js := jobs()
	var j: Dictionary = js[i]
	if progress(j) < int(j["need"]):
		return
	if j["kind"] == "supply":
		GS.remove_item(String(j["item"]), int(j["need"]))
	GS.add_salvage(int(j["pay"]))
	GS.add_xp(10)
	GS.toast("Job done  ·  +%d salvage" % int(j["pay"]))
	js.remove_at(i)
	js.append(_new_job(js))
	GS.flags["jobs"] = js
	Sfx.ui("upgrade", -4.0)
	GS.changed()
	_refresh()


# ------------------------------------------------------------ panel

func open() -> void:
	if player != null and is_instance_valid(player) and not player.input_enabled:
		return
	_root.visible = true
	get_tree().paused = true
	if player != null:
		player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ui("ui_click", -6.0)
	_refresh()


func close() -> void:
	_root.visible = false
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


func _refresh() -> void:
	if not _root.visible:
		return
	_head.text = "SALVAGE  %d" % GS.salvage
	for c in _list.get_children():
		c.queue_free()
	var js := jobs()
	for i in js.size():
		var j: Dictionary = js[i]
		var have := mini(progress(j), int(j["need"]))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.box(Color(0.07, 0.07, 0.09, 0.92), Color(0.3, 0.3, 0.35, 0.6), 1, 6))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(describe(j), 18, UI.TEXT))
		info.add_child(UI.label("Progress  %d / %d      Pays  %d salvage" % [have, int(j["need"]), int(j["pay"])], 15, UI.MUTED))
		h.add_child(info)
		var b := UI.button("TURN IN", 160)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.disabled = have < int(j["need"])
		b.pressed.connect(_turn_in.bind(i))
		h.add_child(b)
		_list.add_child(row)
