class_name NeuralEvaluationManager
extends Node

signal evaluation_started(maximum_duration: float, agent_count: int)
signal evaluation_updated(
	elapsed_time: float,
	maximum_duration: float,
	active_agents: int,
	total_agents: int
)
signal evaluation_finished(results: Array[Dictionary])
signal evaluation_cancelled

enum EvaluationState {
	INACTIVE,
	WAITING_FOR_SPAWN,
	RUNNING,
	FINISHED,
}

@export var fitness_config: NeuralFitnessConfig
@export var race_manager_path := NodePath("../RaceManager")
@export var track_path := NodePath("../Track")

var state := EvaluationState.INACTIVE
var elapsed_time := 0.0
var _sample_accumulator := 0.0
var _race_manager: RaceManager
var _track: RaceTrackBase
var _records_by_car: Dictionary = {}
var _records: Array[NeuralEvaluationRecord] = []
var _results: Array[Dictionary] = []


func _ready() -> void:
	_race_manager = get_node_or_null(race_manager_path) as RaceManager
	_track = get_node_or_null(track_path) as RaceTrackBase
	if _race_manager == null or _track == null:
		push_error("NeuralEvaluationManager requires RaceManager and RaceTrackBase.")
		return
	if fitness_config == null or not fitness_config.is_valid():
		push_error("NeuralEvaluationManager requires a valid NeuralFitnessConfig.")
		return
	_race_manager.cars_spawned.connect(_on_cars_spawned)


func _physics_process(delta: float) -> void:
	if state != EvaluationState.RUNNING:
		return

	elapsed_time += delta
	_sample_accumulator += delta
	if _sample_accumulator >= fitness_config.sample_interval:
		var sample_delta := _sample_accumulator
		_sample_accumulator = 0.0
		_sample_agents(sample_delta)

	if elapsed_time >= fitness_config.maximum_duration:
		for record in _records:
			if record.active:
				_end_agent(record, &"TIME_LIMIT")

	var active_count := get_active_agent_count()
	evaluation_updated.emit(
		minf(elapsed_time, fitness_config.maximum_duration),
		fitness_config.maximum_duration,
		active_count,
		_records.size()
	)
	if active_count == 0:
		_finish_evaluation()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_neural_evaluation") and not event.is_echo():
		start_evaluation()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("exit_neural_evaluation") and not event.is_echo():
		return_to_standard_mode()
		get_viewport().set_input_as_handled()


func start_evaluation() -> void:
	if _race_manager == null or fitness_config == null:
		return
	state = EvaluationState.WAITING_FOR_SPAWN
	_results.clear()
	_records.clear()
	_records_by_car.clear()
	elapsed_time = 0.0
	_sample_accumulator = 0.0
	_race_manager.start_neural_evaluation(fitness_config.agent_count)


func return_to_standard_mode() -> void:
	if _race_manager == null or not _race_manager.is_neural_evaluation_mode():
		return
	for record in _records:
		if record.active:
			_end_agent(record, &"CANCELLED")
	state = EvaluationState.INACTIVE
	_results.clear()
	_records.clear()
	_records_by_car.clear()
	_race_manager.return_to_standard_mode()
	evaluation_cancelled.emit()


func is_running() -> bool:
	return state == EvaluationState.RUNNING


func is_evaluation_mode() -> bool:
	return _race_manager != null and _race_manager.is_neural_evaluation_mode()


func get_active_agent_count() -> int:
	var count := 0
	for record in _records:
		if record.active:
			count += 1
	return count


func get_results() -> Array[Dictionary]:
	return _results.duplicate(true)


func get_fitness_breakdown(car: CarController) -> Dictionary:
	var record := _records_by_car.get(car) as NeuralEvaluationRecord
	if record == null:
		return {}
	var telemetry := _race_manager.get_telemetry(car)
	if telemetry != null:
		record.set_final_position(telemetry.current_position)
		record.calculate_fitness(fitness_config, _records.size())
	return {
		"fitness": record.fitness,
		"active": record.active,
		"reason": String(record.end_reason),
		"components": record.fitness_components.duplicate(true),
	}


func _on_cars_spawned(cars: Array[CarController]) -> void:
	if not _race_manager.is_neural_evaluation_mode():
		return
	state = EvaluationState.WAITING_FOR_SPAWN
	call_deferred("_begin_evaluation", cars)


func _begin_evaluation(cars: Array[CarController]) -> void:
	if not _race_manager.is_neural_evaluation_mode():
		return
	_records.clear()
	_records_by_car.clear()
	_results.clear()
	elapsed_time = 0.0
	_sample_accumulator = 0.0

	for car in cars:
		var controller := car.get_node_or_null(
			"NeuralCarController"
		) as NeuralCarController
		if controller == null:
			continue
		var record := NeuralEvaluationRecord.new()
		record.initialize(car, controller)
		_records.append(record)
		_records_by_car[car] = record
		var progress := _race_manager.get_progress_tracker(car)
		if progress != null:
			progress.allow_manual_respawn = false
			progress.lap_completed.connect(_on_agent_lap_completed.bind(car))

	if _records.is_empty():
		push_error("Neural evaluation started without neural agents.")
		state = EvaluationState.INACTIVE
		return
	state = EvaluationState.RUNNING
	evaluation_started.emit(fitness_config.maximum_duration, _records.size())


func _sample_agents(delta: float) -> void:
	for record in _records:
		if not record.active or not is_instance_valid(record.car):
			continue
		var car := record.car
		var progress := _race_manager.get_progress_tracker(car)
		var telemetry := _race_manager.get_telemetry(car)
		if progress == null or telemetry == null:
			_end_agent(record, &"INVALID_STATE")
			continue

		var surface_handler := car.get_node_or_null(
			"VehicleSurface"
		) as VehicleSurfaceHandler
		var is_on_asphalt := surface_handler == null or not surface_handler.is_on_grass()
		record.sample(
			delta,
			elapsed_time,
			progress,
			telemetry,
			is_on_asphalt,
			_get_forward_alignment(car),
			fitness_config
		)

		if telemetry.state == CarRaceTelemetry.RaceState.FINISHED:
			_end_agent(record, &"FINISHED")
		elif progress.time_since_last_progress >= fitness_config.no_progress_time_limit:
			_end_agent(record, &"NO_PROGRESS")
		elif record.stationary_streak >= fitness_config.stationary_time_limit:
			_end_agent(record, &"STATIONARY")
		elif record.wrong_direction_streak >= fitness_config.wrong_direction_time_limit:
			_end_agent(record, &"WRONG_DIRECTION")

		record.set_final_position(telemetry.current_position)
		record.calculate_fitness(fitness_config, _records.size())


func _end_agent(record: NeuralEvaluationRecord, reason: StringName) -> void:
	if not record.active:
		return
	record.terminate(reason, elapsed_time)
	if is_instance_valid(record.car):
		record.car.set_control_inputs(0.0, 0.0)
		record.car.reset_motion()
		record.car.process_mode = Node.PROCESS_MODE_DISABLED


func _finish_evaluation() -> void:
	if state != EvaluationState.RUNNING:
		return
	_race_manager.finish_neural_evaluation_race()

	for record in _records:
		var telemetry := _race_manager.get_telemetry(record.car)
		if telemetry != null:
			record.set_final_position(telemetry.current_position)
		record.calculate_fitness(fitness_config, _records.size())

	_records.sort_custom(_is_record_fitter)
	_results.clear()
	for index in range(_records.size()):
		_results.append(_records[index].get_result_snapshot(index + 1))
	state = EvaluationState.FINISHED
	evaluation_finished.emit(get_results())


func _is_record_fitter(first: NeuralEvaluationRecord, second: NeuralEvaluationRecord) -> bool:
	if not is_equal_approx(first.fitness, second.fitness):
		return first.fitness > second.fitness
	if not is_equal_approx(first.max_continuous_progress, second.max_continuous_progress):
		return first.max_continuous_progress > second.max_continuous_progress
	if not is_equal_approx(first.end_time, second.end_time):
		return first.end_time < second.end_time
	return first.agent_id < second.agent_id


func _on_agent_lap_completed(
	_completed_lap: int,
	lap_time: float,
	car: CarController
) -> void:
	var record := _records_by_car.get(car) as NeuralEvaluationRecord
	if record != null and record.active:
		record.record_lap(lap_time)


func _get_forward_alignment(car: CarController) -> float:
	var points := _track.get_racing_line_points()
	if points.size() < 2:
		return 0.0
	var closest_index := _track.get_closest_racing_line_index(car.global_position)
	var next_index := (closest_index + 2) % points.size()
	var path_direction := _track.to_global(points[closest_index]).direction_to(
		_track.to_global(points[next_index])
	)
	var movement_direction := car.velocity.normalized()
	if movement_direction == Vector2.ZERO:
		movement_direction = Vector2.UP.rotated(car.global_rotation)
	return clampf(movement_direction.dot(path_direction), -1.0, 1.0)
