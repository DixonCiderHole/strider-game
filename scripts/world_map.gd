extends RefCounted
## The one world map every area sits on (rules: CLAUDE.md "World map / areas").
##
## Each area keeps its own local coordinates. Its place on the world map is
## worked out from the chain below: area B is shifted so its ENTRANCE lands
## exactly on area A's EXIT. So exits and entrances always line up, and
## adding an area means adding one entry here (and a link).
## North (-Z) is up on the map, east (+X) right. Distances are metres.
##
## Layout (south to north): Crash Site -> The Trail -> The Clearing ->
## The Escape -> Base Camp. Shipfall Reach branches off Base Camp to the
## east (BRANCHES). Checked: no two areas overlap.

## Story order: each area's exit leads to the next one's entrance.
const CHAIN := ["res://main.tscn", "res://path.tscn", "res://pinned.tscn", "res://drag.tscn", "res://base.tscn"]
## Side areas off the chain: [from, to]. `to`'s entrance is placed on the
## exit `from` has towards it (exit_to).
const BRANCHES := [["res://base.tscn", "res://reach.tscn"]]

## Phases of The Clearing and The Escape were solved so each one starts
## heading exactly where the previous trail ends (pinned.gd and drag.gd read
## their shape from here).
## Local shapes, entrances and exits (from main.gd, path.gd, pinned.gd,
## drag.gd and base.gd). "trail" areas follow path.gd's curve:
## x = a*sin(0.02 z) + b*sin(0.045 z + phase), walls 19 m either side.
const AREAS := {
	"res://main.tscn": {"name": "Crash Site", "shape": "circle", "radius": 60.0},
	"res://path.tscn": {"name": "The Trail", "shape": "trail", "a": 30.0, "b": 10.0, "phase": 1.3,
			"z_start": 150.0, "z_end": -160.0},
	"res://pinned.tscn": {"name": "The Clearing", "shape": "trail", "a": 26.0, "b": 8.0, "phase": 0.7144,
			"z_start": 70.0, "z_end": -80.0},
	"res://drag.tscn": {"name": "The Escape", "shape": "trail", "a": 22.0, "b": 9.0, "phase": 4.8221,
			"z_start": 140.0, "z_end": -170.0},
	"res://base.tscn": {"name": "Base Camp", "shape": "rect", "rect": Rect2(-85.0, -89.0, 170.0, 170.0)},
	"res://reach.tscn": {"name": "Shipfall Reach", "shape": "rect", "rect": Rect2(-125.0, -95.0, 250.0, 190.0)},
}

## Lead trails inside the two non-trail areas, so each one visibly runs into
## the neighbouring trail. Each starts heading straight north/south from z0
## and bends so that at the area's edge it has the neighbour trail's heading.
## Crash Site: from the clearing north to its north edge (into The Trail).
const CRASH_LEAD := {"z0": -14.0, "edge": -60.0, "joins": "res://path.tscn", "at": "start"}
## Base Camp: from the cave path south to its south edge (from The Escape).
const BASE_LEAD := {"z0": 22.0, "edge": 81.0, "joins": "res://drag.tscn", "at": "end"}
const TRAIL_WALL := 19.0

## Base Camp's east trail to Shipfall Reach: leaves the camp path at
## (x0, z0) heading north-east, and bends so it leaves the valley's east
## edge heading due east: z = z_edge + c (x - edge)^2.
const BASE_EAST := {"x0": 12.0, "z0": 2.0, "edge": 85.0, "z_edge": -20.0}
## Shipfall Reach's trail in from its west edge (heading due east) to the
## pathfinders' camp: z = z1 (1 - cos(pi (x - x0) / (x1 - x0))) / 2.
const REACH_LEAD := {"x0": -125.0, "x1": -78.0, "z1": 10.0}


static func trail_x(a: Dictionary, z: float) -> float:
	return a["a"] * sin(z * 0.02) + a["b"] * sin(z * 0.045 + a["phase"])


## dx/dz of a trail area's centre line.
static func trail_slope(a: Dictionary, z: float) -> float:
	return a["a"] * 0.02 * cos(z * 0.02) + a["b"] * 0.045 * cos(z * 0.045 + a["phase"])


## x of a lead trail (CRASH_LEAD / BASE_LEAD) at z. Before z0 it is 0.
static func lead_x(lead: Dictionary, z: float) -> float:
	var z0: float = lead["z0"]
	var edge: float = lead["edge"]
	var a: Dictionary = AREAS[lead["joins"]]
	var slope := trail_slope(a, a["z_start"] if lead["at"] == "start" else a["z_end"])
	var c := slope / (2.0 * (edge - z0))
	var dir := signf(edge - z0)
	var t := (z - z0) * dir   # distance along, from z0 towards the edge
	if t <= 0.0:
		return 0.0
	if t <= absf(edge - z0):
		return c * (z - z0) * (z - z0)
	return c * (edge - z0) * (edge - z0) + slope * (z - edge)


## dx/dz of a lead trail at z.
static func lead_slope(lead: Dictionary, z: float) -> float:
	return (lead_x(lead, z + 0.05) - lead_x(lead, z - 0.05)) / 0.1


## Horizontal distance from (x, z) to a lead trail (INF before it starts).
static func lead_dist(lead: Dictionary, x: float, z: float) -> float:
	if (z - float(lead["z0"])) * signf(float(lead["edge"]) - float(lead["z0"])) < 0.0:
		return INF
	var s := lead_slope(lead, z)
	return absf(x - lead_x(lead, z)) / sqrt(1.0 + s * s)


static func east_z(x: float) -> float:
	var c: float = (BASE_EAST["z0"] - BASE_EAST["z_edge"]) / pow(BASE_EAST["x0"] - BASE_EAST["edge"], 2.0)
	return BASE_EAST["z_edge"] + c * pow(x - BASE_EAST["edge"], 2.0)


## Horizontal distance from (x, z) to Base Camp's east trail (INF off its ends).
static func east_dist(x: float, z: float) -> float:
	if x < float(BASE_EAST["x0"]) - 2.0:
		return INF
	var c: float = (BASE_EAST["z0"] - BASE_EAST["z_edge"]) / pow(BASE_EAST["x0"] - BASE_EAST["edge"], 2.0)
	var s: float = 2.0 * c * (x - BASE_EAST["edge"]) if x < float(BASE_EAST["edge"]) else 0.0
	var zz: float = east_z(minf(x, BASE_EAST["edge"]))
	return absf(z - zz) / sqrt(1.0 + s * s)


static func reach_lead_z(x: float) -> float:
	var t := clampf((x - float(REACH_LEAD["x0"])) / (float(REACH_LEAD["x1"]) - float(REACH_LEAD["x0"])), 0.0, 1.0)
	return float(REACH_LEAD["z1"]) * (1.0 - cos(PI * t)) * 0.5


## Horizontal distance from (x, z) to Shipfall Reach's entry trail.
static func reach_lead_dist(x: float, z: float) -> float:
	if x > float(REACH_LEAD["x1"]) + 2.0:
		return INF
	var k := PI / (float(REACH_LEAD["x1"]) - float(REACH_LEAD["x0"]))
	var t := clampf((x - float(REACH_LEAD["x0"])) * k, 0.0, PI)
	var s := float(REACH_LEAD["z1"]) * 0.5 * sin(t) * k
	return absf(z - reach_lead_z(x)) / sqrt(1.0 + s * s)


## Every area on the map: the story chain, then its side branches.
static func areas() -> Array:
	var out := CHAIN.duplicate()
	for b in BRANCHES:
		out.append(b[1])
	return out


## Every [from, to] pair whose exit and entrance meet.
static func links() -> Array:
	var out := []
	for i in range(CHAIN.size() - 1):
		out.append([CHAIN[i], CHAIN[i + 1]])
	for b in BRANCHES:
		out.append(b)
	return out


## Local exit in `from` that leads to `to`.
static func exit_to(from: String, to: String) -> Vector2:
	if from == "res://base.tscn" and to == "res://reach.tscn":
		return Vector2(BASE_EAST["edge"], BASE_EAST["z_edge"])
	return exit(from)


## Local entrance (where you arrive from the previous area).
static func entrance(scene: String) -> Vector2:
	var a: Dictionary = AREAS[scene]
	if scene == "res://reach.tscn":
		return Vector2(REACH_LEAD["x0"], 0.0)
	if scene == "res://base.tscn":
		return Vector2(lead_x(BASE_LEAD, BASE_LEAD["edge"]), BASE_LEAD["edge"])
	if a["shape"] == "trail":
		return Vector2(trail_x(a, a["z_start"]), a["z_start"])
	return Vector2.ZERO


## Local exit (where the path to the next area leaves).
static func exit(scene: String) -> Vector2:
	var a: Dictionary = AREAS[scene]
	if scene == "res://main.tscn":
		return Vector2(lead_x(CRASH_LEAD, CRASH_LEAD["edge"]), CRASH_LEAD["edge"])
	if a["shape"] == "trail":
		return Vector2(trail_x(a, a["z_end"]), a["z_end"])
	return Vector2.ZERO


## Where each area's local origin sits on the world map.
static func offsets() -> Dictionary:
	var out := {CHAIN[0]: Vector2.ZERO}
	for i in range(1, CHAIN.size()):
		var prev: String = CHAIN[i - 1]
		var cur: String = CHAIN[i]
		out[cur] = out[prev] + exit(prev) - entrance(cur)
	for b in BRANCHES:
		out[b[1]] = out[b[0]] + exit_to(b[0], b[1]) - entrance(b[1])
	return out


## A local position in `scene` -> world-map position (x, z).
static func to_world(scene: String, local: Vector3) -> Vector2:
	var o: Dictionary = offsets()
	return o.get(scene, Vector2.ZERO) + Vector2(local.x, local.z)


## Outline of an area on the world map (closed polygon, world x/z).
static func outline(scene: String) -> PackedVector2Array:
	var a: Dictionary = AREAS[scene]
	var o: Vector2 = offsets()[scene]
	var pts := PackedVector2Array()
	match a["shape"]:
		"circle":
			for i in 32:
				var t := TAU * i / 32.0
				pts.append(o + Vector2(cos(t), sin(t)) * float(a["radius"]))
		"rect":
			var r: Rect2 = a["rect"]
			for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				pts.append(o + c)
		"trail":
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			var z: float = a["z_start"]
			while z >= float(a["z_end"]) - 0.01:
				var x := trail_x(a, z)
				left.append(o + Vector2(x - TRAIL_WALL, z))
				right.append(o + Vector2(x + TRAIL_WALL, z))
				z -= 10.0
			pts.append_array(left)
			right.reverse()
			pts.append_array(right)
	return pts


## Every path drawn for an area (world polylines): its centre line plus
## Base Camp's east trail.
static func lines(scene: String) -> Array:
	var out := [centre_line(scene)]
	var o: Vector2 = offsets()[scene]
	if scene == "res://base.tscn":
		var east := PackedVector2Array()
		var n := 24
		for i in n + 1:
			var x: float = lerpf(BASE_EAST["x0"], BASE_EAST["edge"], float(i) / n)
			east.append(o + Vector2(x, east_z(x)))
		out.append(east)
	return out


## Centre line of a trail (world), for drawing the path itself. For the
## Crash Site, Base Camp and Shipfall Reach it is their lead trail.
static func centre_line(scene: String) -> PackedVector2Array:
	var a: Dictionary = AREAS[scene]
	var o: Vector2 = offsets()[scene]
	var pts := PackedVector2Array()
	if scene == "res://reach.tscn":
		for i in 25:
			var x: float = lerpf(REACH_LEAD["x0"], REACH_LEAD["x1"], i / 24.0)
			pts.append(o + Vector2(x, reach_lead_z(x)))
		return pts
	for pair in [["res://main.tscn", CRASH_LEAD], ["res://base.tscn", BASE_LEAD]]:
		if scene == pair[0]:
			var lead: Dictionary = pair[1]
			var n := 24
			for i in n + 1:
				var lz: float = lerpf(lead["z0"], lead["edge"], float(i) / n)
				pts.append(o + Vector2(lead_x(lead, lz), lz))
			return pts
	if a["shape"] != "trail":
		return pts
	var z: float = a["z_start"]
	while z >= float(a["z_end"]) - 0.01:
		pts.append(o + Vector2(trail_x(a, z), z))
		z -= 5.0
	return pts
