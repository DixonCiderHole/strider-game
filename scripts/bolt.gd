extends Node3D
## A blaster bolt tracer. The hit itself is decided instantly by a ray;
## this is just the glowing streak that flies to the impact point.

const U = preload("res://scripts/util.gd")
const SPEED := 140.0

var _dir := Vector3.ZERO
var _remaining := 0.0
var _hit := false
var _end := Vector3.ZERO
var _color := Color(1.0, 0.35, 0.15)


func launch(from: Vector3, to: Vector3, hit_something: bool, color := Color(1.0, 0.2, 0.15)) -> void:
	global_position = from
	_end = to
	_hit = hit_something
	_remaining = from.distance_to(to)
	if _remaining < 0.1:
		queue_free()
		return
	_dir = (to - from) / _remaining
	look_at(to, Vector3.UP if absf(_dir.y) < 0.99 else Vector3.RIGHT)

	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 0.9
	mi.mesh = cm
	mi.rotation.x = deg_to_rad(90.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = U.mat(color, 0.5, color, 6.0)
	_color = color
	add_child(mi)


func _process(delta: float) -> void:
	var step := SPEED * delta
	if step >= _remaining:
		global_position = _end
		if _hit:
			_spawn_impact()
		queue_free()
		return
	global_position += _dir * step
	_remaining -= step


func _spawn_impact() -> void:
	var spark := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	spark.mesh = sm
	var m := U.mat(_color.lightened(0.3), 0.5, _color, 8.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.material_override = m
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(spark)
	spark.global_position = _end
	var tw := spark.create_tween()
	tw.set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ONE * 2.5, 0.15)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.15)
	tw.chain().tween_callback(spark.queue_free)
