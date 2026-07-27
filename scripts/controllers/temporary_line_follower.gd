class_name TemporaryLineFollower
extends Node

@export var target_speed := 300.0
@export_range(0.75, 1.25, 0.01) var speed_factor := 1.0
@export_range(2, 12, 1) var lookahead_points := 5
@export_range(0.5, 4.0, 0.1) var steering_gain := 2.2

var _vehicle: CarController
var _track: RaceTrackBase
var _progress: RaceProgressTracker
var _surface_handler: VehicleSurfaceHandler
var _recovery_cooldown := 0.0
var _recovery_timer := 0.0
var _stuck_time := 0.0
var _recovery_attempts := 0
var _recovery_steering := 1.0


func _ready() -> void:
	_vehicle = get_parent() as CarController
	if _vehicle == null:
		push_error("TemporaryLineFollower must be a child of CarController.")
		return
	_progress = _vehicle.get_node("RaceProgress") as RaceProgressTracker
	_surface_handler = _vehicle.get_node("VehicleSurface") as VehicleSurfaceHandler
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
	if _update_recovery(delta):
		return

	var closest_index := _track.get_closest_racing_line_index(_vehicle.global_position)
	var is_on_grass := _surface_handler != null and _surface_handler.is_on_grass()
	var dynamic_lookahead := lookahead_points + floori(absf(_vehicle.current_speed) / 120.0)
	if is_on_grass:
		dynamic_lookahead = maxi(2, lookahead_points / 2)
	var target_index := (closest_index + dynamic_lookahead) % racing_points.size()
	var target_position := _track.to_global(racing_points[target_index])
	var desired_direction := _vehicle.global_position.direction_to(target_position)
	var forward := Vector2.UP.rotated(_vehicle.global_rotation)
	var return_gain := 1.3 if is_on_grass else 1.0
	var steering := clampf(
		forward.cross(desired_direction) * steering_gain * return_gain,
		-1.0,
		1.0
	)

	var alignment := clampf(forward.dot(desired_direction), 0.0, 1.0)
	var corner_speed_factor := lerpf(0.68, 1.0, alignment)
	var desired_speed := target_speed * speed_factor * corner_speed_factor
	var throttle := 0.32
	if _vehicle.current_speed < desired_speed - 12.0:
		throttle = 1.0
	elif _vehicle.current_speed > desired_speed + 12.0:
		throttle = -0.35

	_vehicle.set_control_inputs(throttle, steering)


func _find_track() -> void:
	for candidate in get_tree().get_nodes_in_group("race_track"):
		if candidate is RaceTrackBase:
			_track = candidate
			return


func _update_recovery(delta: float) -> bool:
	_recovery_cooldown = maxf(_recovery_cooldown - delta, 0.0)

	if _recovery_timer > 0.0:
		_recovery_timer = maxf(_recovery_timer - delta, 0.0)
		_vehicle.set_control_inputs(-0.8, _recovery_steering)
		return true

	var nearly_stopped := absf(_vehicle.current_speed) < 26.0
	var pressing_barrier := _vehicle.barrier_contact_time > 0.65
	if nearly_stopped or pressing_barrier:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)

	var stalled_progress := (
		_progress != null
		and _progress.time_since_last_progress > 10.0 + _recovery_attempts * 4.0
	)
	if (
		_progress != null
		and _progress.time_since_last_progress > 28.0
		and _recovery_attempts >= 2
		and _recovery_cooldown <= 0.0
	):
		_progress.respawn_at_last_checkpoint()
		_recovery_cooldown = 12.0
		_recovery_attempts = 0
		return true

	if (
		_recovery_cooldown <= 0.0
		and (_stuck_time > 2.2 or stalled_progress)
	):
		_recovery_timer = 1.6
		_recovery_cooldown = 4.0
		_stuck_time = 0.0
		_recovery_attempts += 1
		_recovery_steering = -1.0 if _recovery_attempts % 2 == 0 else 1.0
		_vehicle.set_control_inputs(-0.8, _recovery_steering)
		return true

	if _progress != null and _progress.time_since_last_progress < 2.0:
		_recovery_attempts = 0
	return false
