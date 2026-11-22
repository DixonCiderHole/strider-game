extends RefCounted
## Procedural rock architecture for the canyon country: cliff chunks, pillars,
## ledges you can stand on, arches and cave passages you walk through.
## Everything uses the demo's triplanar rock material (world-space, so no UVs
## and no seams), the same rock the environment rocks and terrain cliffs use.
##
##   block(size, seed, rough, flat_top)   noisy rounded box (cliff chunk / ledge)
##   cave(points, radius, seed)           walk-through passage along a path:
##                                        inner cave walls + rough outer shell
##   place(parent, mesh, xf, collide)     adds it with exact collision

const ROCK_MAT := "res://demo/assets/materials/M_rock23_tp.tres"
const ROCK_DARK_MAT := "res://demo/assets/materials/M_rock23_black_tp.tres"

static var _noise: FastNoiseLite
static var _mats := {}


static func _n() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.12
		_noise.fractal_octaves = 4
	return _noise


static func material(dark := false, tint := Color.WHITE) -> Material:
	var key := "%s%s" % [dark, tint]
	if _mats.has(key):
		return _mats[key]
	var path := ROCK_DARK_MAT if dark else ROCK_MAT
	var m: Material
	if ResourceLoader.exists(path):
		m = (load(path) as Material).duplicate()
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = (m as StandardMaterial3D).albedo_color * tint
			# Vertex colour darkens creases (set per vertex below).
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.42, 0.4, 0.38) * tint
		sm.roughness = 0.95
		m = sm
	_mats[key] = m
	return m


## A rough rock mass `size` metres across, centred on its base (y = 0 at the
## bottom). flat_top keeps the top walkable (ledges, platforms).
static func block(size: Vector3, seed_v: float, rough := 0.18, flat_top := false, seg := 10) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _n()
	var half := size * 0.5
	# Six faces of a cube, each an seg x seg grid, pushed out to a rounded box.
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid := []
		for j in seg + 1:
			var row := []
			for i in seg + 1:
				var a := -1.0 + 2.0 * i / seg
				var b := -1.0 + 2.0 * j / seg
				var c := nrm + u * a + v * b
				# Rounded box: blend the cube point towards a sphere.
				var sph := c.normalized()
				var q := c.lerp(sph * 1.25, 0.45)
				var p := Vector3(q.x * half.x, q.y * half.y + half.y, q.z * half.z)
				var top := clampf((p.y / size.y - 0.75) * 4.0, 0.0, 1.0) if flat_top else 0.0
				var d := n.get_noise_3d(p.x * 1.0 + seed_v * 17.0, p.y * 1.3, p.z * 1.0) * rough * minf(size.x, minf(size.y, size.z))
				d += n.get_noise_3d(p.x * 4.0, p.y * 4.0 + seed_v, p.z * 4.0) * rough * 0.25 * minf(size.x, size.z)
				var out := sph * d * (1.0 - top * 0.85)
				if flat_top and top > 0.0:
					p.y = lerpf(p.y, size.y, top * 0.8)
				row.append(p + out)
			grid.append(row)
		for j in seg:
			for i in seg:
				var p00: Vector3 = grid[j][i]
				var p10: Vector3 = grid[j][i + 1]
				var p01: Vector3 = grid[j + 1][i]
				var p11: Vector3 = grid[j + 1][i + 1]
				_quad(st, p00, p10, p11, p01, nrm)
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.dot(want) > 0.0:
		# Godot fronts are clockwise: flip so the face points along `want`.
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	else:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


## A cave passage you walk through, following `points` (its floor centre
## line). Cross-section: an arch `radius` wide with a flat floor; the outer
## shell is a lumpy rock mass `shell` metres thick, so from outside it reads
## as a rock spur. Open at both ends.
static func cave(points: Array, radius := 3.2, seed_v := 0.0, shell := 2.6, sides := 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _n()
	# Resample the path every ~1.5 m.
	var path := []
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 1.5))
		for k in steps:
			path.append(a.lerp(b, float(k) / steps))
	path.append(points[points.size() - 1])
	var inner := []
	var outer := []
	var fwds := []
	for i in path.size():
		var p: Vector3 = path[i]
		var fwd: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)])
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		fwds.append(fwd)
		var ri := []
		var ro := []
		for k in sides:
			var t := TAU * k / sides
			var x := cos(t)
			var y := sin(t)
			var w := radius * (1.0 + n.get_noise_3d(p.x * 0.6 + k, p.y * 0.6, p.z * 0.6 + seed_v) * 0.22)
			var hgt := radius * 1.15
			var iy := maxf(y, -0.0) * hgt
			if y < 0.0:
				iy = 0.0   # flat floor
			var ip := p + side * x * w + Vector3.UP * (iy + (0.0 if y < 0.0 else 0.0))
			if y < 0.0:
				ip = p + side * x * w * (0.95 + 0.05 * absf(y))
			ri.append(ip)
			var sw := w + shell * (1.0 + n.get_noise_3d(p.x * 0.35 + seed_v, p.y * 0.35 + k * 0.3, p.z * 0.35) * 0.6)
			var oy := (y * 0.5 + 0.5) * (hgt + shell * 1.2) - 0.6
			ro.append(p + side * x * sw + Vector3.UP * oy)
		inner.append(ri)
		outer.append(ro)
	for i in path.size() - 1:
		var cen: Vector3 = path[i] + Vector3.UP * radius * 0.5
		for k in sides:
			var k2 := (k + 1) % sides
			# Inner walls face in, towards the passage centre.
			var a: Vector3 = inner[i][k]
			var b: Vector3 = inner[i][k2]
			var c: Vector3 = inner[i + 1][k2]
			var d: Vector3 = inner[i + 1][k]
			_quad(st, a, b, c, d, cen - (a + c) * 0.5)
			# Outer shell faces out.
			var oa: Vector3 = outer[i][k]
			var ob: Vector3 = outer[i][k2]
			var oc: Vector3 = outer[i + 1][k2]
			var od: Vector3 = outer[i + 1][k]
			_quad(st, oa, ob, oc, od, (oa + oc) * 0.5 - cen)
	# Rims at both mouths, joining the inner walls to the shell.
	for end in [0, path.size() - 1]:
		var dir: Vector3 = -fwds[end] if end == 0 else fwds[end]
		for k in sides:
			var k2 := (k + 1) % sides
			_quad(st, inner[end][k], inner[end][k2], outer[end][k2], outer[end][k], dir)
	st.generate_normals()
	return st.commit()


## Adds `mesh` under `parent` at `xf` with exact (trimesh) collision.
static func place(parent: Node, mesh: ArrayMesh, xf: Transform3D, collide := true, mat: Material = null) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.transform = xf
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else material()
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
	return body
