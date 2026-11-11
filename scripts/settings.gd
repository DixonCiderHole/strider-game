extends Node
## Autoload "Settings": player options, saved between sessions.

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var invert_y := false
var fullscreen := false
var show_hints := true


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sensitivity = cf.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cf.get_value("controls", "invert_y", invert_y)
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	show_hints = cf.get_value("display", "show_hints", show_hints)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "show_hints", show_hints)
	cf.save(PATH)


func apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
