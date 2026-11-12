extends RefCounted
## The crashed dropship: models/crashed_ship.glb set nose-down at the end of
## its furrow, right wing torn off and lying back along the furrow, with a
## panelled / grimy / scorched hull material, fires, smoke, sparks, debris
## and a scorch mark.

const U = preload("res://scripts/util.gd")
const SHIP := "res://models/crashed_ship.glb"
const SCALE := 0.78

## Hull detail: panel seams, per-panel tint, grime and burn, all procedural
## in the model's own space, so the plating sticks to the ship.
const HULL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_color : source_color = vec3(0.56, 0.58, 0.6);
uniform float metal = 0.55;
uniform float rough = 0.42;
uniform float burn_amount = 0.55;
uniform vec3 hot_spot = vec3(4.0, 1.0, -2.0);
varying vec3 opos;
varying vec3 onrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i), n100 = hash3(i + vec3(1,0,0)), n010 = hash3(i + vec3(0,1,0)), n110 = hash3(i + vec3(1,1,0));
	float n001 = hash3(i + vec3(0,0,1)), n101 = hash3(i + vec3(1,0,1)), n011 = hash3(i + vec3(0,1,1)), n111 = hash3(i + vec3(1,1,1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm(vec3 p) { return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.15; }

// Large hull plates with thin seams; some plates are subdivided into
// smaller access panels. Returns seam (0 on a seam) and a per-plate id.
vec2 plates(vec2 uv) {
	vec2 sz = vec2(3.2, 1.6);
	vec2 g = uv / sz;
	float row = floor(g.y);
	g.x += step(0.5, hash(vec2(row, 7.3))) * 0.5;
	vec2 c = floor(g);
	vec2 f = fract(g);
	vec2 e = min(f, 1.0 - f) * sz;
	float seam = mix(0.45, 1.0, smoothstep(0.008, 0.022, min(e.x, e.y)));
	float h = hash(c + 3.1);
	if (h > 0.55) {
		// Access panel: an inset rectangle inside the plate.
		vec2 q = abs(f - vec2(0.5)) * sz;
		vec2 hs = vec2(0.25 + 0.2 * hash(c + 9.0), 0.2 + 0.15 * hash(c + 4.0)) * sz;
		float edge = min(abs(q.x - hs.x), abs(q.y - hs.y));
		float inside = step(q.x, hs.x) * step(q.y, hs.y);
		seam *= mix(1.0, mix(0.6, 1.0, smoothstep(0.006, 0.018, edge)), step(edge, 0.05) * (inside + (1.0 - inside)));
	}
	if (h < 0.2) {
		// Rivet line along the plate's lower edge.
		float r = length(vec2(fract(f.x * sz.x / 0.18) - 0.5, (f.y * sz.y - 0.08) / 0.18));
		seam *= mix(0.7, 1.0, smoothstep(0.18, 0.3, r));
	}
	return vec2(seam, hash(c));
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(onrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 a = plates(opos.zy);
	vec2 b = plates(opos.xz);
	vec2 c = plates(opos.xy);
	float seam = a.x * w.x + b.x * w.y + c.x * w.z;
	float id = a.y * w.x + b.y * w.y + c.y * w.z;
	vec3 col = base_color * (0.93 + 0.1 * id);
	col *= seam;
	// Grime: streaks running down, heavier low on the hull.
	float streak = vnoise(vec3(opos.x * 3.0, opos.y * 0.35, opos.z * 3.0));
	float grime = smoothstep(0.35, 0.9, fbm(opos * 0.7)) * 0.45 + streak * 0.2 + smoothstep(1.0, -1.5, opos.y) * 0.25;
	col *= 1.0 - clamp(grime, 0.0, 0.7);
	// Scorching: patchy, strongest near the torn side and the engines.
	float near = 1.0 - smoothstep(2.0, 9.0, distance(opos, hot_spot));
	float burn = smoothstep(0.62, 0.42, fbm(opos * 0.45) - near * 0.35) * burn_amount;
	burn = clamp(burn + near * 0.5, 0.0, 1.0);
	col = mix(col, vec3(0.035, 0.03, 0.028), burn * 0.9);
	// Heat-tinted metal at the edge of burns.
	col += vec3(0.25, 0.12, 0.04) * burn * (1.0 - burn) * 0.6;
	ALBEDO = col;
	METALLIC = metal * (1.0 - burn * 0.8);
	ROUGHNESS = clamp(rough + (1.0 - seam) * 0.25 + burn * 0.45 + grime * 0.2, 0.0, 1.0);
}
"""


## Builds the wreck. ground_y: Callable(Vector3) -> float. Returns the node.
## yaw_deg: direction of travel (the furrow lies behind it).
static func build(parent: Node3D, pos: Vector3, yaw_deg: float, ground_y: Callable, fire_lights: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Wreck"
	parent.add_child(root)
	root.global_position = pos

	if not ResourceLoader.exists(SHIP):
		return root
	var ship_scene: Node3D = load(SHIP).instantiate()

	# Ship body: nose dug in and down, rolled onto the torn side.
	var body := StaticBody3D.new()
	body.name = "Ship"
	root.add_child(body)
	body.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(9.0, 0.0, -13.0)   # nose down, roll towards the missing wing
	body.add_child(tilt)
	tilt.position = Vector3(0.0, 1.0, 0.0)   # hull origin is mid-body; belly sits just below the ground, nose dug in
	tilt.scale = Vector3.ONE * SCALE

	var hull_mat := _hull_material(Color(0.56, 0.58, 0.6), 0.55, 0.42)
	var panel_mat := _hull_material(Color(0.44, 0.46, 0.49), 0.6, 0.5)
	var wing_r: Node3D = null
	for child in ship_scene.get_children():
		var n := child as Node3D
		if n == null:
			continue
		ship_scene.remove_child(n)
		if n.name == "WingR":
			wing_r = n
			continue
		tilt.add_child(n)
	ship_scene.free()
	# The model carries its own PBR materials (panels, grime and scorching).

	# Collision from the hull mesh itself.
	for mi in tilt.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var cs := CollisionShape3D.new()
		cs.shape = m.mesh.create_trimesh_shape()
		body.add_child(cs)
		cs.transform = body.global_transform.affine_inverse() * m.global_transform

	# Torn-off right wing, back along the furrow, half buried and upside down-ish.
	# The model's nose is +Z: fwd is where the nose points, the furrow lies behind.
	var fwd := Vector3(sin(deg_to_rad(yaw_deg)), 0.0, cos(deg_to_rad(yaw_deg)))
	var back := -fwd
	var side := Vector3(fwd.z, 0.0, -fwd.x)   # the ship's right (+X), the torn side
	if wing_r != null:
		var wb := StaticBody3D.new()
		wb.name = "TornWing"
		root.add_child(wb)
		var wp := pos + back * 13.0 + side * 3.5
		wb.global_position = Vector3(wp.x, ground_y.call(wp) - 0.35, wp.z)
		wb.rotation_degrees = Vector3(0.0, yaw_deg + 160.0, 0.0)
		var wt := Node3D.new()
		wt.rotation_degrees = Vector3(-8.0, 0.0, 168.0)
		wt.scale = Vector3.ONE * SCALE
		wb.add_child(wt)
		wing_r.position = Vector3.ZERO   # the model centres the torn wing on its own origin
		wt.add_child(wing_r)
		for mi in wt.find_children("*", "MeshInstance3D", true, false):
			var cs := CollisionShape3D.new()
			cs.shape = (mi as MeshInstance3D).mesh.create_convex_shape()
			wb.add_child(cs)
			cs.transform = wb.global_transform.affine_inverse() * (mi as Node3D).global_transform
		_fire(root, wb.global_position + Vector3(0.0, 0.6, 0.0), 0.6, fire_lights)

	# Fires and smoke: torn wing root, engine block, nose.
	var fp := [
		pos + side * 2.9 + Vector3(0.0, 1.0, 0.0),
		pos + back * 9.5 + Vector3(0.0, 1.8, 0.0),
		pos + back * 4.0 + side * 2.2 + Vector3(0.0, 2.2, 0.0),
		pos + fwd * 9.0 + Vector3(0.0, 0.2, 0.0),
	]
	for i in fp.size():
		_fire(root, fp[i], 1.2 if i < 2 else 0.8, fire_lights)
	_smoke(root, pos + side * 2.5 + back * 1.0 + Vector3(0.0, 2.5, 0.0), 1.0)
	_smoke(root, pos + back * 9.5 + Vector3(0.0, 3.0, 0.0), 0.8)
	_sparks(root, pos + side * 3.0 + Vector3(0.0, 1.6, 0.6))

	# Debris strewn along the furrow.
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for k in 26:
		var t := rng.randf_range(-2.0, 24.0)
		var p: Vector3 = pos + back * t + side * rng.randf_range(-5.0, 5.0)
		p.y = ground_y.call(p) + 0.05
		var d := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(0.3, 1.6), rng.randf_range(0.04, 0.2), rng.randf_range(0.3, 1.2))
		d.mesh = bm
		d.material_override = hull_mat if rng.randf() < 0.6 else panel_mat
		root.add_child(d)
		d.global_position = p
		d.rotation_degrees = Vector3(rng.randf_range(-35, 35), rng.randf() * 360.0, rng.randf_range(-35, 35))
	# Scorch mark under and behind the ship.
	var dec := Decal.new()
	dec.texture_albedo = _scorch_texture()
	dec.size = Vector3(16.0, 6.0, 26.0)
	dec.modulate = Color(1, 1, 1, 0.9)
	root.add_child(dec)
	dec.global_position = pos + back * 4.0 + Vector3(0.0, 0.5, 0.0)
	dec.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	return root


static func _hull_material(col: Color, metal: float, rough: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = HULL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", col)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough", rough)
	return m


## Hull and panel surfaces get the detailed material; trim, glass, lights keep theirs.
static func _apply_materials(n: Node, hull_mat: Material, panel_mat: Material) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			var nm := src.resource_name if src != null else ""
			if nm == "hull":
				m.set_surface_override_material(s, hull_mat)
			elif nm == "panel":
				m.set_surface_override_material(s, panel_mat)
			elif src is BaseMaterial3D:
				var d := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
				if nm == "glow":
					d.emission_enabled = true
					d.emission = Color(1.0, 0.38, 0.1)
					d.emission_energy_multiplier = 3.0
				m.set_surface_override_material(s, d)


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


static func _scorch_texture() -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.03
	for y in 256:
		for x in 256:
			var d := Vector2(x - 128, (y - 128) * 0.7).length() / 128.0
			var edge := 1.0 - smoothstep(0.75, 1.0, maxf(absf(x - 128.0), absf(y - 128.0)) / 128.0)
			var a := clampf((1.0 - d) * 1.4 + n.get_noise_2d(x, y) * 0.6, 0.0, 1.0) * edge
			img.set_pixel(x, y, Color(0.03, 0.025, 0.02, a * 0.85))
	return ImageTexture.create_from_image(img)


static func _billboard_mat(col: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.albedo_color = col
	return m


static func _fire(root: Node3D, at: Vector3, size: float, fire_lights: Array) -> void:
	var p := GPUParticles3D.new()
	p.amount = int(60 * size)
	p.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45 * size
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2 * size
	pm.initial_velocity_max = 2.4 * size
	pm.gravity = Vector3(0.0, 1.5, 0.0)
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	grad.add_point(0.4, Color(1.0, 0.4, 0.08, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.05, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9) * size
	q.material = _billboard_mat(Color(1.0, 0.6, 0.25), true)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = at
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 7.0 * size + 2.0
	light.shadow_enabled = size > 1.0
	root.add_child(light)
	light.global_position = at + Vector3(0.0, 0.8, 0.0)
	fire_lights.append(light)


static func _smoke(root: Node3D, at: Vector3, size: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 7.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.6, 0.25, 0.2)   # drifts with the wind
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	pm.scale_min = 1.0 * size
	pm.scale_max = 1.6 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(1.0, 4.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	sct.texture_mode = CurveTexture.TEXTURE_MODE_RED
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.1, 0.09, 0.08, 0.0))
	grad.add_point(0.12, Color(0.12, 0.11, 0.1, 0.7))
	grad.set_color(grad.get_point_count() - 1, Color(0.35, 0.34, 0.33, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	var m := _billboard_mat(Color(1, 1, 1), false)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 40, 30))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = at


static func _sparks(root: Node3D, at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.8
	p.explosiveness = 0.85
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.3, 1.0, 0.0)
	pm.spread = 50.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.05
	pm.scale_max = 0.1
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	q.material = _billboard_mat(Color(1.0, 0.8, 0.4), true)
	p.draw_pass_1 = q
	root.add_child(p)
	p.global_position = at
	# Irregular bursts.
	var tw := p.create_tween().set_loops()
	tw.tween_callback(func(): p.restart())
	tw.tween_interval(1.7)
	tw.tween_callback(func(): p.restart())
	tw.tween_interval(0.6)
	tw.tween_callback(func(): p.restart())
	tw.tween_interval(3.1)
