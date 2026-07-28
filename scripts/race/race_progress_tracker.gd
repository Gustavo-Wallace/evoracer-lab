class_name RaceProgressTracker
extends Node

signal progress_changed(
	current_lap: int,
	current_checkpoint: int,
	checkpoint_count: int,
	total_progress: float
)
signal timing_updated(lap_time: float, time_since_last_progress: float)
signal lap_completed(completed_lap: int, completed_time: float)
signal checkpoint_rejected(
	expected_checkpoint: int,
	crossed_checkpoint: int,
	reason: StringName
)
signal abnormal_progress_jump(
	attempted_jump: float,
	allowed_jump: float,
	lateral_distance: float
)

@export_category("Manual Recovery")
@export var allow_manual_respawn := true

@export_category("Checkpoint Validation")
@export var minimum_forward_crossing_speed := 18.0
@export_range(0.1, 2.0, 0.05) var minimum_checkpoint_interval := 0.35
@export_range(1.0, 3.0, 0.05) var physical_speed_tolerance := 1.5
@export_range(0.5, 1.0, 0.01) var minimum_segment_progress := 0.78

@export_category("Projected Progress")
@export_range(1.0, 2.0, 0.05) var distance_budget_multiplier := 1.15
@export_range(0.0, 1.0, 0.05) var grass_progress_multiplier := 0.35
@export_range(0.05, 0.75, 0.05) var abnormal_jump_threshold := 0.2
@export var debug_progress_alerts := true

var current_checkpoint := 0
var total_checkpoints_passed := 0
var current_lap := 1
var lap_time := 0.0
var last_completed_lap_time := 0.0
var total_elapsed_time := 0.0
var time_since_last_progress := 0.0
var total_progress := 0.0
var completed_lap_times := PackedFloat32Array()

var rejected_by_order := 0
var rejected_by_direction := 0
var rejected_by_timing := 0
var rejected_by_route := 0
var maximum_progress_jump := 0.0
var invalid_course_warning := false

var _checkpoint_count := 0
var _next_checkpoint := 1
var _last_valid_checkpoint_transform := Transform2D.IDENTITY
var _configured := false
var _timing_frozen := false
var _track: RaceTrackBase
var _intermediate_progress := 0.0
var _raw_projected_progress := 0.0
var _maximum_raw_projected_progress := 0.0
var _projected_lateral_distance := 0.0
var _current_segment_length := 0.0
var _time_since_checkpoint := 0.0
var _last_validation_physics_frame := -1
var _finish_line_armed := false
var _last_vehicle_position := Vector2.ZERO
var _debug_alert_cooldown := 0.0

@onready var vehicle: CharacterBody2D = get_parent() as CharacterBody2D


func _physics_process(delta: float) -> void:
	if not _configured or _timing_frozen:
		return

	lap_time += delta
	total_elapsed_time += delta
	time_since_last_progress += delta
	_time_since_checkpoint += delta
	_debug_alert_cooldown = maxf(_debug_alert_cooldown - delta, 0.0)
	_update_projected_progress()
	timing_updated.emit(lap_time, time_since_last_progress)


func _unhandled_input(event: InputEvent) -> void:
	if not allow_manual_respawn or not _configured:
		return
	if event.is_action_pressed("respawn_car") and not event.is_echo():
		respawn_at_last_checkpoint()
		get_viewport().set_input_as_handled()


func configure(
	total_checkpoint_count: int,
	finish_transform: Transform2D,
	track: RaceTrackBase = null
) -> void:
	if _configured:
		return
	if total_checkpoint_count < 2:
		push_error("RaceProgressTracker requires a finish line and at least one checkpoint.")
		return

	_checkpoint_count = total_checkpoint_count
	_last_valid_checkpoint_transform = finish_transform
	_next_checkpoint = 1
	_track = track
	_last_vehicle_position = vehicle.global_position if vehicle != null else finish_transform.origin
	_configured = true
	_emit_progress()


func is_configured() -> bool:
	return _configured


func try_validate_checkpoint(
	checkpoint_index: int,
	checkpoint_transform: Transform2D,
	forward_crossing_speed: float = 0.0,
	entered_from_correct_side: bool = false
) -> bool:
	if not _configured or _timing_frozen:
		return false
	if checkpoint_index == 0 and not _finish_line_armed:
		return false
	if checkpoint_index != _next_checkpoint:
		rejected_by_order += 1
		_reject_checkpoint(checkpoint_index, &"ORDER")
		return false
	if (
		not entered_from_correct_side
		or forward_crossing_speed < minimum_forward_crossing_speed
	):
		rejected_by_direction += 1
		_reject_checkpoint(checkpoint_index, &"DIRECTION")
		return false

	var physics_frame := Engine.get_physics_frames()
	var maximum_plausible_speed := 1.0
	if vehicle is CarController:
		maximum_plausible_speed = (
			(vehicle as CarController).maximum_forward_speed
			* physical_speed_tolerance
		)
	var physical_interval := _current_segment_length / maximum_plausible_speed
	var required_interval := maxf(minimum_checkpoint_interval, physical_interval)
	if (
		physics_frame == _last_validation_physics_frame
		or _time_since_checkpoint < required_interval
	):
		rejected_by_timing += 1
		_reject_checkpoint(checkpoint_index, &"TIMING")
		return false
	if _intermediate_progress < minimum_segment_progress:
		rejected_by_route += 1
		_reject_checkpoint(checkpoint_index, &"ROUTE")
		return false

	current_checkpoint = checkpoint_index
	total_checkpoints_passed += 1
	total_progress = float(total_checkpoints_passed)
	time_since_last_progress = 0.0
	_last_valid_checkpoint_transform = checkpoint_transform
	_last_validation_physics_frame = physics_frame
	_time_since_checkpoint = 0.0
	_intermediate_progress = 0.0
	_raw_projected_progress = 0.0
	_maximum_raw_projected_progress = 0.0
	_current_segment_length = 0.0
	_last_vehicle_position = vehicle.global_position if vehicle != null else checkpoint_transform.origin

	if checkpoint_index == 0:
		_finish_line_armed = false
		var completed_lap := current_lap
		var completed_time := lap_time
		last_completed_lap_time = completed_time
		completed_lap_times.append(completed_time)
		current_lap += 1
		lap_time = 0.0
		_next_checkpoint = 1
		lap_completed.emit(completed_lap, completed_time)
	else:
		_next_checkpoint = (checkpoint_index + 1) % _checkpoint_count

	_emit_progress()
	return true


func notify_checkpoint_exit(checkpoint_index: int) -> void:
	if checkpoint_index == 0:
		_finish_line_armed = true


func respawn_at_last_checkpoint() -> void:
	if not _configured or vehicle == null or _timing_frozen:
		return

	vehicle.global_transform = _last_valid_checkpoint_transform
	_intermediate_progress = 0.0
	_raw_projected_progress = 0.0
	_maximum_raw_projected_progress = 0.0
	_current_segment_length = 0.0
	_last_vehicle_position = vehicle.global_position
	time_since_last_progress = 0.0
	_time_since_checkpoint = 0.0
	if vehicle.has_method("reset_motion"):
		vehicle.reset_motion()
	else:
		vehicle.velocity = Vector2.ZERO


func freeze_timing() -> void:
	_timing_frozen = true


func is_timing_frozen() -> bool:
	return _timing_frozen


func get_checkpoint_count() -> int:
	return _checkpoint_count


func get_next_checkpoint() -> int:
	return _next_checkpoint


func get_total_progress() -> float:
	return total_progress


func get_intermediate_progress() -> float:
	return _intermediate_progress


func get_raw_projected_progress() -> float:
	return _raw_projected_progress


func get_projected_lateral_distance() -> float:
	return _projected_lateral_distance


func get_display_lap_time() -> float:
	return last_completed_lap_time if _timing_frozen else lap_time


func get_lap_times() -> PackedFloat32Array:
	return completed_lap_times.duplicate()


func get_diagnostics() -> Dictionary:
	return {
		"maximum_progress_jump": maximum_progress_jump,
		"invalid_course_warning": invalid_course_warning,
		"rejected_by_order": rejected_by_order,
		"rejected_by_direction": rejected_by_direction,
		"rejected_by_timing": rejected_by_timing,
		"rejected_by_route": rejected_by_route,
	}


func _update_projected_progress() -> void:
	if _track == null or vehicle == null:
		return
	var projection := _track.get_checkpoint_segment_projection(
		vehicle.global_position,
		current_checkpoint,
		_next_checkpoint
	)
	_raw_projected_progress = float(projection["progress"])
	_projected_lateral_distance = float(projection["lateral_distance"])
	_current_segment_length = float(projection["segment_length"])
	var movement_distance := vehicle.global_position.distance_to(_last_vehicle_position)
	_last_vehicle_position = vehicle.global_position
	if _current_segment_length <= 0.001:
		return

	var surface_multiplier := (
		1.0
		if _track.is_world_position_on_asphalt(vehicle.global_position)
		else grass_progress_multiplier
	)
	var allowed_jump := (
		movement_distance
		/ _current_segment_length
		* distance_budget_multiplier
		* surface_multiplier
	)
	var attempted_jump := maxf(
		_raw_projected_progress - _maximum_raw_projected_progress,
		0.0
	)
	if attempted_jump > allowed_jump + abnormal_jump_threshold:
		maximum_progress_jump = maxf(maximum_progress_jump, attempted_jump)
		invalid_course_warning = true
		abnormal_progress_jump.emit(
			attempted_jump,
			allowed_jump,
			_projected_lateral_distance
		)
		if debug_progress_alerts and _debug_alert_cooldown <= 0.0:
			push_warning(
				"%s abnormal progress jump: %.3f (allowed %.3f, lateral %.1f px)" % [
					vehicle.name,
					attempted_jump,
					allowed_jump,
					_projected_lateral_distance,
				]
			)
			_debug_alert_cooldown = 1.0
	var credited_progress := minf(attempted_jump, allowed_jump)
	_intermediate_progress = clampf(
		_intermediate_progress + credited_progress,
		0.0,
		1.0
	)
	_maximum_raw_projected_progress = maxf(
		_maximum_raw_projected_progress,
		_raw_projected_progress
	)


func _reject_checkpoint(checkpoint_index: int, reason: StringName) -> void:
	invalid_course_warning = true
	checkpoint_rejected.emit(_next_checkpoint, checkpoint_index, reason)


func _emit_progress() -> void:
	progress_changed.emit(
		current_lap,
		current_checkpoint,
		_checkpoint_count,
		total_progress
	)
