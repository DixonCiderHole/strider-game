extends Node
## Autoload "Settings": player options, saved between sessions.

const PATH := "user://settings.cfg"

# ---- controls
var mouse_sensitivity := 0.0025
var aim_sensitivity := 0.7        # mouse speed while aiming (x normal)
var invert_y := false
var crouch_toggle := true         # false = hold C
var camera_recoil := true

# ---- display
var fullscreen := false
var fov := 70.0
var vsync := true
var max_fps := 0                  # 0 = no cap
var render_scale := 1.0
var msaa := 0                     # 0 off, 1 = 2x, 2 = 4x
var shadow_quality := 2           # 0 low, 1 medium, 2 high

# ---- gameplay / interface
var show_hints := true
var show_tutorials := true
var damage_numbers := true
var objective_marker := true
var cutscene_auto := true         # cutscene lines move on by themselves
var subtitle_size := 1            # 0 small, 1 medium, 2 large

# ---- audio (0..1)
var master_volume := 1.0
var sfx_volume := 1.0
var ambience_volume := 0.8

const KEYS := {
	"controls": ["mouse_sensitivity", "aim_sensitivity", "invert_y", "crouch_toggle", "camera_recoil"],
	"display": ["fullscreen", "fov", "vsync", "max_fps", "render_scale", "msaa", "shadow_quality"],
	"gameplay": ["show_hints", "show_tutorials", "damage_numbers", "objective_marker", "cutscene_auto", "subtitle_size"],
	"audio": ["master_volume", "sfx_volume", "ambience_volume"],
}


func _ready() -> void:
	_make_buses()
	load_settings()
	apply()


## Sound effects and looping ambience get their own buses so they have
## separate volume sliders (see sfx.gd).
func _make_buses() -> void:
	for bus in ["SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for section in KEYS:
		for k in KEYS[section]:
			# Older settings files kept show_hints under "display".
			var sec: String = section
			if k == "show_hints" and not cf.has_section_key(section, k):
				sec = "display"
			set(k, cf.get_value(sec, k, get(k)))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for section in KEYS:
		for k in KEYS[section]:
			cf.set_value(section, k, get(k))
	cf.save(PATH)


func apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	var vp := get_tree().root
	vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(msaa, 0, 2)]
	var sizes := [1024, 2048, 4096]
	var q := clampi(shadow_quality, 0, 2)
	RenderingServer.directional_shadow_atlas_set_size(sizes[q], true)
	vp.positional_shadow_atlas_size = sizes[q]
	_set_volume("Master", master_volume)
	_set_volume("SFX", sfx_volume)
	_set_volume("Ambience", ambience_volume)


func _set_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


## Dialogue / subtitle text size for the chosen setting.
func subtitle_px(base: int) -> int:
	return int(base * [0.85, 1.0, 1.3][clampi(subtitle_size, 0, 2)])
