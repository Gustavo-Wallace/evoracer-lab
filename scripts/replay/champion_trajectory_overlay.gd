class_name ChampionTrajectoryOverlay
extends Node2D

var trajectory := PackedVector2Array()
var offroad_points := PackedVector2Array()
var checkpoint_points := PackedVector2Array()
var end_position := Vector2.ZERO


func configure(metadata: Dictionary) -> void:
	trajectory = _copy_points(metadata.get("trajectory", PackedVector2Array()))
	offroad_points = _copy_points(
		metadata.get("offroad_points", PackedVector2Array())
	)
	checkpoint_points = _copy_points(
		metadata.get("checkpoint_points", PackedVector2Array())
	)
	end_position = metadata.get("end_position", Vector2.ZERO) as Vector2
	queue_redraw()


func _draw() -> void:
	if trajectory.size() >= 2:
		draw_polyline(trajectory, Color(1.0, 0.79, 0.25, 0.62), 4.0, true)
		draw_polyline(trajectory, Color(0.22, 0.12, 0.07, 0.6), 1.0, true)
	for point in offroad_points:
		draw_circle(point, 6.0, Color(0.82, 0.19, 0.13, 0.82))
	for point in checkpoint_points:
		draw_circle(point, 7.0, Color(0.35, 0.84, 0.3, 0.9), false, 2.0)
	if end_position != Vector2.ZERO:
		draw_line(
			end_position + Vector2(-8.0, -8.0),
			end_position + Vector2(8.0, 8.0),
			Color(1.0, 0.94, 0.72, 0.95),
			3.0
		)
		draw_line(
			end_position + Vector2(-8.0, 8.0),
			end_position + Vector2(8.0, -8.0),
			Color(1.0, 0.94, 0.72, 0.95),
			3.0
		)


func _copy_points(value: Variant) -> PackedVector2Array:
	return (
		(value as PackedVector2Array).duplicate()
		if value is PackedVector2Array
		else PackedVector2Array()
	)
