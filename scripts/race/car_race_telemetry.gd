class_name CarRaceTelemetry
extends RefCounted

enum RaceState {
	RACING,
	FINISHED,
	ABANDONED,
}

var vehicle_id := ""
var current_position := 0
var best_position := 0
var starting_position := 0
var positions_gained_or_lost := 0
var overtakes_completed := 0
var times_overtaken := 0
var time_in_first_place := 0.0
var completed_laps := 0
var best_lap := 0.0
var last_lap := 0.0
var total_race_time := 0.0
var state := RaceState.RACING
var finish_position := 0
var finish_time := 0.0
var continuous_progress := 0.0
var segment_progress := 0.0
var approximate_gap_to_leader := 0.0

var _position_sample_total := 0.0
var _position_sample_count := 0


func initialize(identifier: String, grid_position: int) -> void:
	vehicle_id = identifier
	starting_position = grid_position
	current_position = grid_position
	best_position = grid_position
	positions_gained_or_lost = 0
	record_position(grid_position)


func record_position(position: int, include_in_average: bool = true) -> void:
	current_position = position
	if best_position <= 0 or position < best_position:
		best_position = position
	positions_gained_or_lost = starting_position - current_position
	if include_in_average:
		_position_sample_total += position
		_position_sample_count += 1


func record_lap(lap_time: float) -> bool:
	completed_laps += 1
	last_lap = lap_time
	var is_new_best := best_lap <= 0.0 or lap_time < best_lap
	if is_new_best:
		best_lap = lap_time
	return is_new_best


func mark_finished(position: int, race_time: float) -> void:
	state = RaceState.FINISHED
	finish_position = position
	finish_time = race_time
	total_race_time = race_time


func mark_abandoned(position: int, race_time: float) -> void:
	state = RaceState.ABANDONED
	finish_position = position
	total_race_time = race_time


func is_racing() -> bool:
	return state == RaceState.RACING


func get_average_position() -> float:
	if _position_sample_count <= 0:
		return float(starting_position)
	return _position_sample_total / float(_position_sample_count)


func get_state_label() -> String:
	match state:
		RaceState.RACING:
			return "RACING"
		RaceState.FINISHED:
			return "FINISHED"
		RaceState.ABANDONED:
			return "ABANDONED"
	return "UNKNOWN"


func get_metrics_snapshot() -> Dictionary:
	return {
		"vehicle_id": vehicle_id,
		"current_position": current_position,
		"best_position": best_position,
		"average_position": get_average_position(),
		"starting_position": starting_position,
		"positions_gained_or_lost": positions_gained_or_lost,
		"overtakes_completed": overtakes_completed,
		"times_overtaken": times_overtaken,
		"time_in_first_place": time_in_first_place,
		"completed_laps": completed_laps,
		"best_lap": best_lap,
		"last_lap": last_lap,
		"total_race_time": total_race_time,
		"state": get_state_label(),
		"finish_position": finish_position,
		"finish_time": finish_time,
		"continuous_progress": continuous_progress,
		"segment_progress": segment_progress,
		"approximate_gap_to_leader": approximate_gap_to_leader,
	}
