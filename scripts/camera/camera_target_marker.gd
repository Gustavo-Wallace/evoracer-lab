class_name CameraTargetMarker
extends Node2D

@export var camera_path := NodePath("../RaceCamera")
@export var marker_color := Color("ffd45e")
@export_range(16.0, 48.0, 1.0) var ring_radius := 27.0

var _camera: RaceCamera


func _ready() -> void:
	z_index = 100
	_camera = get_node_or_null(camera_path) as RaceCamera
	visible = false
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = get_node_or_null(camera_path) as RaceCamera
	var target := _camera.get_target() if is_instance_valid(_camera) else null
	var should_show := (
		is_instance_valid(target)
		and _camera.view_mode != RaceCamera.ViewMode.OVERVIEW
	)
	visible = should_show
	if should_show:
		global_position = target.global_position


func _draw() -> void:
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		32,
		Color(marker_color, 0.86),
		2.0,
		true
	)
	var arrow := PackedVector2Array([
		Vector2(0.0, -ring_radius - 5.0),
		Vector2(-7.0, -ring_radius - 15.0),
		Vector2(7.0, -ring_radius - 15.0),
	])
	draw_colored_polygon(arrow, Color(marker_color, 0.92))
	draw_polyline(arrow, Color("5a241c"), 1.5, true)
