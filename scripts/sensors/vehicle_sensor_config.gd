class_name VehicleSensorConfig
extends Resource

@export_group("Ray Layout")
@export var sensor_names := PackedStringArray([
	"front",
	"front_short_left",
	"front_short_right",
	"front_open_left",
	"front_open_right",
	"left",
	"right",
])
@export var sensor_angles_degrees := PackedFloat32Array([
	0.0,
	-25.0,
	25.0,
	-55.0,
	55.0,
	-90.0,
	90.0,
])
@export var sensor_ranges := PackedFloat32Array([
	420.0,
	320.0,
	320.0,
	270.0,
	270.0,
	220.0,
	220.0,
])
@export var ray_origin := Vector2(0.0, -20.0)

@export_group("Detection")
@export_flags_2d_physics var navigable_limit_mask := 1
@export_flags_2d_physics var car_mask := 2
@export var detect_other_cars := false

@export_group("State Normalization")
@export_range(100.0, 4000.0, 25.0) var checkpoint_distance_reference := 1600.0


func get_sensor_count() -> int:
	return mini(
		sensor_names.size(),
		mini(sensor_angles_degrees.size(), sensor_ranges.size())
	)


func has_valid_layout() -> bool:
	return (
		not sensor_names.is_empty()
		and sensor_names.size() == sensor_angles_degrees.size()
		and sensor_names.size() == sensor_ranges.size()
	)


func get_collision_mask() -> int:
	var result := navigable_limit_mask
	if detect_other_cars:
		result |= car_mask
	return result
