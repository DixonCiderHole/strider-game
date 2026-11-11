extends RefCounted
## Sound helper. All sounds live in res://sounds/ (made for this game).
## Files ending in "_loop" loop automatically.

const DIR := "res://sounds/"

static var _cache := {}
static var _last_played := {}


static func stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var path := DIR + sound + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if s is AudioStreamWAV and sound.ends_with("_loop"):
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	_cache[sound] = s
	return s


static func _scene() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


## Stops the same sound stacking up when many things trigger it at once.
static func _too_soon(sound: String, gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -100.0)) < gap:
		return true
	_last_played[sound] = now
	return false


## One-shot 3D sound at a world position.
static func at(pos: Vector3, sound: String, volume_db := 0.0, pitch_var := 0.08, unit_size := 8.0, min_gap := 0.0) -> void:
	if min_gap > 0.0 and _too_soon(sound, min_gap):
		return
	var s := stream(sound)
	var parent := _scene()
	if s == null or parent == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.unit_size = unit_size
	p.max_distance = 90.0
	p.attenuation_filter_cutoff_hz = 9000.0
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## One-shot non-positional sound (UI, the player's own hits).
static func ui(sound: String, volume_db := 0.0, pitch_var := 0.0) -> void:
	var s := stream(sound)
	var tree := Engine.get_main_loop() as SceneTree
	if s == null or tree == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## A looping sound attached to `parent` (3D if parent is a Node3D).
static func loop(parent: Node, sound: String, volume_db := 0.0, unit_size := 6.0, positional := true) -> Node:
	var s := stream(sound)
	if s == null:
		return null
	if positional and parent is Node3D:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = volume_db
		p.unit_size = unit_size
		p.max_distance = 60.0
		p.autoplay = true
		parent.add_child(p)
		return p
	var q := AudioStreamPlayer.new()
	q.stream = s
	q.volume_db = volume_db
	q.autoplay = true
	parent.add_child(q)
	return q
