extends RefCounted
## Title-screen backdrop: an area scene built with GameState.menu_preview set
## calls make() after building its world (no player, enemies or HUD). This
## turns the lighting to night and adds a slowly drifting camera.

const NIGHT_SKY := """
shader_type sky;
uniform vec3 moon_dir = vec3(-0.4, 0.5, -0.6);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 top = vec3(0.012, 0.020, 0.055);
	vec3 hor = vec3(0.070, 0.100, 0.170);
	vec3 col = mix(hor, top, pow(up, 0.45));
	if (d.y < 0.0) {
		col = mix(hor, vec3(0.008, 0.010, 0.014), clamp(-d.y * 4.0, 0.0, 1.0));
	}
	// Stars
	vec3 p = d * 260.0;
	vec3 cell = floor(p);
	float h = hash(cell);
	float s = step(0.975, h) * smoothstep(0.45, 0.0, length(fract(p) - 0.5));
	s *= smoothstep(0.0, 0.15, d.y) * (0.4 + 0.6 * hash(cell + 7.0));
	col += vec3(0.8, 0.88, 1.0) * s * 4.0;
	// Faint band of the galaxy
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.2, 1.0))) * 4.0, 2.0)) * up;
	col += vec3(0.06, 0.08, 0.14) * band;
	// Moon and its halo
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.99955, 0.99975, md) * 3.0;
	col += vec3(0.25, 0.32, 0.5) * pow(max(md, 0.0), 220.0) * 0.6;
	col += vec3(0.05, 0.07, 0.12) * pow(max(md, 0.0), 12.0);
	COLOR = col;
}
"""


## root: the area node. cam_pos / look_at: where the backdrop camera sits.
static func make(root: Node3D, cam_pos: Vector3, look: Vector3) -> void:
	var moon_dir := Vector3(-0.4, 0.5, -0.6)
	for c in root.get_children():
		if c is DirectionalLight3D:
			var l := c as DirectionalLight3D
			l.light_color = Color(0.62, 0.72, 1.0)
			l.light_energy = 0.5
			l.shadow_enabled = true
			moon_dir = l.global_transform.basis.z.normalized()
			if moon_dir.y < 0.25:
				moon_dir.y = 0.25
				moon_dir = moon_dir.normalized()
	for c in root.get_children():
		if c is WorldEnvironment:
			var env: Environment = (c as WorldEnvironment).environment
			var sh := Shader.new()
			sh.code = NIGHT_SKY
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("moon_dir", moon_dir)
			var sky := Sky.new()
			sky.sky_material = sm
			env.sky = sky
			env.background_mode = Environment.BG_SKY
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.36, 0.44, 0.7)
			env.ambient_light_energy = 0.42
			env.fog_enabled = true
			env.fog_light_color = Color(0.05, 0.07, 0.13)
			env.fog_density = maxf(env.fog_density, 0.014)
			env.fog_sky_affect = 0.0   # keep the stars clear of the fog
			env.glow_enabled = true
			env.glow_intensity = 1.0
			env.glow_bloom = 0.05
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.tonemap_exposure = 1.2
	root.set_process_input(false)
	root.set_process_unhandled_input(false)
	root.set_physics_process(false)

	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.far = 400.0
	root.add_child(cam)
	cam.global_position = cam_pos
	look.y += cam_pos.distance_to(look) * 0.32
	cam.look_at(look)
	cam.make_current()
	# Slow drift so the world feels alive behind the menu.
	var side := cam.global_transform.basis.x
	var tw := cam.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "global_position", cam_pos + side * 1.6 + Vector3(0, 0.25, 0), 14.0)
	tw.tween_property(cam, "global_position", cam_pos - side * 1.6, 14.0)
