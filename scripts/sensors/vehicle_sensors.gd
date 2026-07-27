class_name VehicleSensors
extends Node2D

const STATE_INPUT_NAMES := [
	"speed",
	"checkpoint_direction",
	"checkpoint_distance",
	"surface_grass",
]

@export var config: VehicleSensorConfig

var _vehicle: CarController
var _progress: RaceProgressTracker
var _surface_handler: VehicleSurfaceHandler
var _track: RaceTrackBase
var _rays: Array[RayCast2D] = []
var _distance_inputs := PackedFloat32Array()
var _speed_input := 0.0
var _checkpoint_direction_input := 0.0
var _checkpoint_distance_input := 1.0
var _surface_input := 0.0
var _debug_visible := false
var _detect_other_cars := false


func _ready() -> void:
	_vehicle = get_parent() as CarController
	if _vehicle == null:
		push_error("VehicleSensors must be a child of CarController.")
		return
	if config == null or not config.has_valid_layout():
		push_error("VehicleSensors requires matching sensor names, angles and ranges.")
		return

	_progress = _vehicle.get_node("RaceProgress") as RaceProgressTracker
	_surface_handler = _vehicle.get_node("VehicleSurface") as VehicleSurfaceHandler
	_detect_other_cars = config.detect_other_cars
	_find_track()
	_create_raycasts()
	_update_inputs()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_track):
		_find_track()
	_update_inputs()
	if _debug_visible:
		queue_redraw()


func get_neural_inputs() -> PackedFloat32Array:
	var inputs := _distance_inputs.duplicate()
	inputs.append(_speed_input)
	inputs.append(_checkpoint_direction_input)
	inputs.append(_checkpoint_distance_input)
	inputs.append(_surface_input)
	return inputs


func get_input_names() -> PackedStringArray:
	var names := config.sensor_names.duplicate()
	for state_name in STATE_INPUT_NAMES:
		names.append(state_name)
	return names


func get_distance_inputs() -> PackedFloat32Array:
	return _distance_inputs.duplicate()


func set_debug_visible(is_visible: bool) -> void:
	if _debug_visible == is_visible:
		return
	_debug_visible = is_visible
	queue_redraw()


func is_debug_visible() -> bool:
	return _debug_visible


func set_detect_other_cars(is_enabled: bool) -> void:
	_detect_other_cars = is_enabled
	var collision_mask := _get_collision_mask()
	for ray in _rays:
		ray.collision_mask = collision_mask


func _create_raycasts() -> void:
	_distance_inputs.resize(config.get_sensor_count())
	_distance_inputs.fill(1.0)

	for index in range(config.get_sensor_count()):
		var ray := RayCast2D.new()
		ray.name = "Ray%02d_%s" % [index, config.sensor_names[index]]
		ray.position = config.ray_origin
		ray.target_position = (
			Vector2.UP.rotated(deg_to_rad(config.sensor_angles_degrees[index]))
			* config.sensor_ranges[index]
		)
		ray.collision_mask = _get_collision_mask()
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		ray.enabled = true
		ray.add_exception(_vehicle)
		add_child(ray)
		_rays.append(ray)
		ray.force_raycast_update()


func _update_inputs() -> void:
	for index in range(_rays.size()):
		var ray := _rays[index]
		var normalized_distance := 1.0
		if ray.is_colliding():
			normalized_distance = clampf(
				ray.global_position.distance_to(ray.get_collision_point())
				/ config.sensor_ranges[index],
				0.0,
				1.0
			)
		_distance_inputs[index] = normalized_distance

	if _vehicle == null:
		return
	_speed_input = clampf(
		_vehicle.current_speed / _vehicle.maximum_forward_speed,
		-1.0,
		1.0
	)
	_surface_input = 1.0 if (
		_surface_handler != null and _surface_handler.is_on_grass()
	) else 0.0
	_update_checkpoint_inputs()


func _update_checkpoint_inputs() -> void:
	if _track == null or _progress == null or not _progress.is_configured():
		_checkpoint_direction_input = 0.0
		_checkpoint_distance_input = 1.0
		return

	var checkpoint_position := _track.get_checkpoint_global_position(
		_progress.get_next_checkpoint()
	)
	var checkpoint_offset := checkpoint_position - _vehicle.global_position
	var forward_angle := Vector2.UP.rotated(_vehicle.global_rotation).angle()
	var relative_angle := wrapf(
		checkpoint_offset.angle() - forward_angle,
		-PI,
		PI
	)
	_checkpoint_direction_input = clampf(relative_angle / PI, -1.0, 1.0)
	_checkpoint_distance_input = clampf(
		checkpoint_offset.length() / config.checkpoint_distance_reference,
		0.0,
		1.0
	)


func _find_track() -> void:
	for candidate in get_tree().get_nodes_in_group("race_track"):
		if candidate is RaceTrackBase:
			_track = candidate
			return


func _get_collision_mask() -> int:
	var result := config.navigable_limit_mask
	if _detect_other_cars:
		result |= config.car_mask
	return result


func _draw() -> void:
	if not _debug_visible:
		return

	for index in range(_rays.size()):
		var ray := _rays[index]
		var ray_start := ray.position
		var maximum_end := ray_start + ray.target_position
		var visible_end := maximum_end
		if ray.is_colliding():
			visible_end = to_local(ray.get_collision_point())

		var value := _distance_inputs[index]
		var ray_color := Color(0.34, 0.92, 0.42, 0.88)
		if value <= 0.35:
			ray_color = Color(0.94, 0.2, 0.14, 0.95)
		elif value <= 0.68:
			ray_color = Color(0.98, 0.72, 0.18, 0.92)

		draw_line(ray_start, maximum_end, Color(0.95, 0.9, 0.7, 0.16), 1.0)
		draw_line(ray_start, visible_end, ray_color, 2.5, true)
		draw_circle(visible_end, 4.0 if ray.is_colliding() else 2.5, ray_color)
