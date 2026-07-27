class_name TemporaryLineFollower
extends Node

@export var target_speed := 300.0
@export_range(0.75, 1.25, 0.01) var speed_factor := 1.0
@export_range(2, 12, 1) var lookahead_points := 5
@export_range(0.5, 4.0, 0.1) var steering_gain := 2.2

var _vehicle: CarController
var _track: RaceTrackBase
var _progress: RaceProgressTracker
var _recovery_cooldown := 0.0


func _ready() -> void:
	_vehicle = get_parent() as CarController
	if _vehicle == null:
		push_error("TemporaryLineFollower must be a child of CarController.")
		return
	_progress = _vehicle.get_node("RaceProgress") as RaceProgressTracker
	_find_track()


func _physics_process(delta: float) -> void:
	if _vehicle == null:
		return
	if not is_instance_valid(_track):
		_find_track()
		return

	var racing_points := _track.get_racing_line_points()
	if racing_points.is_empty():
		return

	var closest_index := _track.get_closest_racing_line_index(_vehicle.global_position)
	var dynamic_lookahead := lookahead_points + floori(absf(_vehicle.current_speed) / 120.0)
	var target_index := (closest_index + dynamic_lookahead) % racing_points.size()
	var target_position := _track.to_global(racing_points[target_index])
	var desired_direction := _vehicle.global_position.direction_to(target_position)
	var forward := Vector2.UP.rotated(_vehicle.global_rotation)
	var steering := clampf(forward.cross(desired_direction) * steering_gain, -1.0, 1.0)

	var alignment := clampf(forward.dot(desired_direction), 0.0, 1.0)
	var corner_speed_factor := lerpf(0.68, 1.0, alignment)
	var desired_speed := target_speed * speed_factor * corner_speed_factor
	var throttle := 0.32
	if _vehicle.current_speed < desired_speed - 12.0:
		throttle = 1.0
	elif _vehicle.current_speed > desired_speed + 12.0:
		throttle = -0.35

	_vehicle.set_control_inputs(throttle, steering)
	_update_recovery(delta)


func _find_track() -> void:
	for candidate in get_tree().get_nodes_in_group("race_track"):
		if candidate is RaceTrackBase:
			_track = candidate
			return


func _update_recovery(delta: float) -> void:
	_recovery_cooldown = maxf(_recovery_cooldown - delta, 0.0)
	if (
		_progress != null
		and _progress.time_since_last_progress > 18.0
		and _recovery_cooldown <= 0.0
	):
		_progress.respawn_at_last_checkpoint()
		_recovery_cooldown = 12.0
