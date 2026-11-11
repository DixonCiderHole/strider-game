extends Node3D
## Asset viewer (testing): the crashed ship on flat ground in daylight, with
## a slowly orbiting camera. Space pauses the orbit, mouse wheel zooms,
## Left/Right step around by 45 degrees.

const WreckScript = preload("res://scripts/wreck.gd")

var cam: Camera3D
var angle := 0.0
var dist := 30.0
var height := 9.0
var spin := true
var _lights: Array = []


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 140.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.27, 0.2)
	gmat.roughness = 1.0
	ground.material_override = gmat
	add_child(ground)

	WreckScript.build(self, Vector3.ZERO, 215.0, func(_p): return 0.0, _lights)

	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()


func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_SPACE:
				spin = not spin
			KEY_LEFT:
				angle -= PI * 0.25
			KEY_RIGHT:
				angle += PI * 0.25
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(dist - 2.0, 6.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(dist + 2.0, 80.0)


func _process(delta: float) -> void:
	if spin:
		angle += delta * 0.25
	cam.position = Vector3(cos(angle) * dist, height, sin(angle) * dist)
	cam.look_at(Vector3(0.0, 1.5, 0.0))
	for i in _lights.size():
		_lights[i].light_energy = 2.4 + sin(Time.get_ticks_msec() * 0.011 + i * 2.0) * 0.5
