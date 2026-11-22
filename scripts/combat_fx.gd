extends Node3D
## Shared combat effects for an area (one per scene, made on demand with
## CombatFX.get_for(node)):
##  - flamethrower fire: burning globs that fly in an arc, hurt what they
##    touch and leave burning patches on the ground for a few seconds;
##  - the special grenades: flashbang, smoke, stun and thermal detonator.

const Sfx = preload("res://scripts/sfx.gd")
const U = preload("res://scripts/util.gd")

const GRAVITY := 7.0
const GLOB_LIFE := 1.6
const PATCH_LIFE := 4.0
const PATCH_R := 1.7
const MAX_PATCHES := 16

var _globs: Array = []     # {pos, vel, life, dmg}
var _patches: Array = []   # {pos, t, dmg, tick, node}
var _clouds: Array = []    # {pos, t, r, tick}
var _patch_pm: ParticleProcessMaterial
var _patch_mesh: QuadMesh


static func get_for(n: Node) -> Node3D:
	var scene := n.get_tree().current_scene
	if scene == null:
		scene = n.get_parent()
	var fx = scene.get_node_or_null("CombatFX")
	if fx == null:
		fx = load("res://scripts/combat_fx.gd").new()
		fx.name = "CombatFX"
		scene.add_child(fx)
	return fx as Node3D


# ---------------------------------------------------------------- fire

func fire_glob(from: Vector3, vel: Vector3, dmg: float) -> void:
	_globs.append({"pos": from, "vel": vel, "life": GLOB_LIFE, "dmg": dmg})


func _physics_process(delta: float) -> void:
	if _globs.is_empty() and _patches.is_empty() and _clouds.is_empty():
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var space := get_world_3d().direct_space_state
	for i in range(_globs.size() - 1, -1, -1):
		var g: Dictionary = _globs[i]
		var p0: Vector3 = g["pos"]
		var v: Vector3 = g["vel"]
		v.y -= GRAVITY * delta
		var p1 := p0 + v * delta
		g["vel"] = v
		g["life"] = float(g["life"]) - delta
		var done := false
		for e in enemies:
			if e.has_method("is_dead") and e.is_dead():
				continue
			if (e.global_position + Vector3.UP * 0.8).distance_to(p1) < 1.2:
				e.take_damage(float(g["dmg"]), v.normalized())
				_add_patch(Vector3(e.global_position.x, e.global_position.y + 0.05, e.global_position.z), float(g["dmg"]))
				done = true
				break
		if not done:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p1, 1))
			if not hit.is_empty():
				_add_patch(hit["position"], float(g["dmg"]))
				done = true
		if done or float(g["life"]) <= 0.0:
			_globs.remove_at(i)
		else:
			g["pos"] = p1
	for i in range(_patches.size() - 1, -1, -1):
		var pt: Dictionary = _patches[i]
		pt["t"] = float(pt["t"]) - delta
		pt["tick"] = float(pt["tick"]) - delta
		if float(pt["tick"]) <= 0.0:
			pt["tick"] = 0.3
			var pp: Vector3 = pt["pos"]
			for e in enemies:
				if e.has_method("is_dead") and e.is_dead():
					continue
				if e.global_position.distance_to(pp) < PATCH_R:
					e.take_damage(float(pt["dmg"]) * 0.5, Vector3.ZERO)
		var light := (pt["node"] as Node3D).get_node_or_null("Light") as OmniLight3D
		if light != null:
			light.light_energy = clampf(float(pt["t"]), 0.0, 1.0) * randf_range(1.6, 2.4)
		if float(pt["t"]) <= 0.0:
			var gp := (pt["node"] as Node3D).get_node_or_null("Flames") as GPUParticles3D
			if gp != null:
				gp.emitting = false
			var n: Node = pt["node"]
			get_tree().create_timer(0.8).timeout.connect(n.queue_free)
			_patches.remove_at(i)
	for i in range(_clouds.size() - 1, -1, -1):
		var c: Dictionary = _clouds[i]
		c["t"] = float(c["t"]) - delta
		c["tick"] = float(c["tick"]) - delta
		if float(c["tick"]) <= 0.0:
			c["tick"] = 0.3
			var cp: Vector3 = c["pos"]
			var r: float = c["r"]
			for e in enemies:
				var inside: bool = e.global_position.distance_to(cp) < r
				var tgt = e.get("target")
				var prey_inside: bool = tgt != null and is_instance_valid(tgt) and tgt.global_position.distance_to(cp) < r
				if (inside or prey_inside) and e.has_method("confuse"):
					e.confuse(0.7)
		if float(c["t"]) <= 0.0:
			_clouds.remove_at(i)


func _add_patch(at: Vector3, dmg: float) -> void:
	for pt in _patches:
		if (pt["pos"] as Vector3).distance_to(at) < 1.2:
			pt["t"] = PATCH_LIFE   # keep the existing fire going
			pt["dmg"] = maxf(float(pt["dmg"]), dmg)
			return
	if _patches.size() >= MAX_PATCHES:
		var old: Dictionary = _patches.pop_front()
		(old["node"] as Node).queue_free()
	var node := Node3D.new()
	add_child(node)
	node.global_position = at
	node.add_child(_flames(0.9, 120, 0.7))
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.5, 0.15)
	light.omni_range = 4.0
	light.light_energy = 2.0
	light.position.y = 0.6
	node.add_child(light)
	_patches.append({"pos": at, "t": PATCH_LIFE, "dmg": dmg, "tick": 0.0, "node": node})


## A flickering fire on the ground (radius r).
func _flames(r: float, amount: int, life: float) -> GPUParticles3D:
	if _patch_pm == null:
		_patch_pm = ParticleProcessMaterial.new()
		_patch_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_patch_pm.emission_box_extents = Vector3(0.9, 0.05, 0.9)
		_patch_pm.direction = Vector3(0, 1, 0)
		_patch_pm.spread = 12.0
		_patch_pm.initial_velocity_min = 1.0
		_patch_pm.initial_velocity_max = 2.4
		_patch_pm.gravity = Vector3(0, 1.0, 0)
		_patch_pm.scale_min = 0.5
		_patch_pm.scale_max = 1.0
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 0.4))
		sc.add_point(Vector2(0.4, 1.0))
		sc.add_point(Vector2(1.0, 0.1))
		var sct := CurveTexture.new()
		sct.curve = sc
		_patch_pm.scale_curve = sct
		var gt := GradientTexture1D.new()
		gt.gradient = fire_gradient()
		_patch_pm.color_ramp = gt
		_patch_mesh = QuadMesh.new()
		_patch_mesh.size = Vector2(0.55, 0.7)
		_patch_mesh.material = additive_material()
	var p := GPUParticles3D.new()
	p.name = "Flames"
	p.amount = amount
	p.lifetime = life
	p.process_material = _patch_pm
	p.draw_pass_1 = _patch_mesh
	p.local_coords = false
	return p


static func fire_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.set_color(1, Color(0.12, 0.08, 0.06, 0.0))
	g.add_point(0.25, Color(1.0, 0.55, 0.12, 0.95))
	g.add_point(0.6, Color(0.85, 0.22, 0.05, 0.6))
	return g


static func soft_dot() -> GradientTexture2D:
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	return dot


static func additive_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_dot()
	return mat


# ---------------------------------------------------------------- grenades

## Special grenade effects. kind: flash | smoke | stun | thermal.
func grenade(kind: String, at: Vector3, dmg: float, radius: float) -> void:
	match kind:
		"flash":
			_light(at, Color(1, 1, 1), 30.0, radius * 3.0, 0.6)
			_burst(at, Color(1, 1, 1), radius * 0.5, 0.25)
			Sfx.at(at, "slam", 6.0, 0.05, 18.0)
			for e in get_tree().get_nodes_in_group("enemy"):
				if e.global_position.distance_to(at) < radius and e.has_method("stun"):
					e.stun(3.0)
		"stun":
			_light(at, Color(0.4, 0.7, 1.0), 14.0, radius * 2.5, 0.8)
			_burst(at, Color(0.4, 0.75, 1.0), radius, 0.35)
			_sparks(at, radius)
			Sfx.at(at, "impact", 4.0, 0.3, 14.0)
			for e in get_tree().get_nodes_in_group("enemy"):
				var d: float = e.global_position.distance_to(at)
				if d < radius:
					e.take_damage(dmg, (e.global_position - at).normalized())
					if e.has_method("stun"):
						e.stun(2.5)
		"smoke":
			Sfx.at(at, "impact", -2.0, 0.2, 10.0)
			_smoke(at, radius, 8.0)
			_clouds.append({"pos": at, "t": 8.0, "r": radius, "tick": 0.0})
		"thermal":
			Sfx.at(at, "slam", 10.0, 0.05, 24.0)
			for e in get_tree().get_nodes_in_group("enemy"):
				var d2: float = e.global_position.distance_to(at)
				if d2 < radius:
					e.take_damage(dmg * (1.0 - d2 / radius * 0.5), (e.global_position - at).normalized())
			_light(at, Color(1.0, 0.55, 0.2), 24.0, radius * 3.0, 1.0)
			_burst(at, Color(1.0, 0.55, 0.15), radius * 1.1, 0.4)
			_add_patch(at, dmg * 0.08)
			for k in 7:
				var a := TAU * k / 7.0
				var p := at + Vector3(cos(a), 0.0, sin(a)) * radius * 0.55
				var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p - Vector3.UP * 6.0, 1))
				if not hit.is_empty():
					_add_patch(hit["position"], dmg * 0.08)


func _light(at: Vector3, col: Color, energy: float, rng: float, time: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	add_child(l)
	l.global_position = at + Vector3.UP
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


func _burst(at: Vector3, col: Color, r: float, time: float) -> void:
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.5
	bs.height = 1.0
	ball.mesh = bs
	var m := U.mat(col, 0.5, col, 6.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = m
	add_child(ball)
	ball.global_position = at
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * r * 1.6, time)
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(ball.queue_free)


func _sparks(at: Vector3, r: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = r * 1.5
	pm.initial_velocity_max = r * 3.0
	pm.gravity = Vector3(0, -6, 0)
	pm.color = Color(0.5, 0.8, 1.0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = additive_material()
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = at + Vector3.UP * 0.5
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _smoke(at: Vector3, r: float, time: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 3.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r * 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 3.0
	pm.scale_max = 5.0
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.77, 0.75, 0.0))
	g.set_color(1, Color(0.6, 0.62, 0.6, 0.0))
	g.add_point(0.2, Color(0.72, 0.74, 0.72, 0.85))
	g.add_point(0.75, Color(0.65, 0.67, 0.65, 0.7))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_dot()
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = at + Vector3.UP * 0.8
	p.emitting = true
	get_tree().create_timer(time).timeout.connect(_stop_emit.bind(p))
	get_tree().create_timer(time + 3.5).timeout.connect(p.queue_free)


func _stop_emit(p: GPUParticles3D) -> void:
	if is_instance_valid(p):
		p.emitting = false
