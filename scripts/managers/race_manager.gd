class_name RaceManager
extends Node2D

signal cars_spawned(cars: Array[CarController])
signal rankings_updated(ranked_cars: Array[CarController])
signal race_event(message: String, event_type: StringName, car: CarController)
signal race_started(total_laps: int)
signal car_finished(car: CarController, position: int, finish_time: float)
signal race_finished(reason: StringName, elapsed_time: float)
signal race_mode_changed(neural_evaluation_mode: bool)
signal official_leader_changed(leader: CarController)
signal leader_eligibility_changed(car: CarController, is_eligible: bool)

const CAR_SCENE := preload("res://scenes/car/Car.tscn")
const CarRaceTelemetry := preload("res://scripts/race/car_race_telemetry.gd")
const TEMPORARY_CONTROLLER_SCENE := preload(
	"res://scenes/controllers/TemporaryLineFollower.tscn"
)
const NEURAL_CONTROLLER_SCENE := preload(
	"res://scenes/controllers/NeuralCarController.tscn"
)
const CAR_COLORS: Array[Color] = [
	Color("1480b8"),
	Color("d94a3a"),
	Color("e6b82e"),
	Color("43a047"),
	Color("8e5bb7"),
	Color("e67e32"),
	Color("d96891"),
	Color("2b9c91"),
	Color("eeeeee"),
	Color("4056a1"),
	Color("8dbb3f"),
	Color("8a5a44"),
]
const SPEED_FACTORS := [
	0.92, 0.97, 1.03, 0.95, 1.06, 0.99,
	0.93, 1.04, 0.96, 1.01, 0.94, 1.02,
]

@export_category("Race Format")
@export_range(1, 99, 1) var total_laps := 3
@export_range(30.0, 3600.0, 5.0) var race_time_limit := 300.0

@export_category("Classification")
@export_range(2, 24, 1) var car_count := 12
@export_range(0, 12, 1) var neural_car_count := 3
@export_range(0.05, 1.0, 0.05) var ranking_refresh_interval := 0.1
@export_range(0.2, 3.0, 0.05) var overtake_stability_time := 0.75

@export_category("Neural Test Agents")
@export var neural_network_config: NeuralNetworkConfig

@onready var cars_container: Node2D = $Cars

var manual_car: CarController
var _track: RaceTrackBase
var _cars: Array[CarController] = []
var _ranked_cars: Array[CarController] = []
var _finish_order: Array[CarController] = []
var _telemetry_by_car: Dictionary = {}
var _progress_by_car: Dictionary = {}
var _neural_controllers_by_car: Dictionary = {}
var _previous_order_index: Dictionary = {}
var _confirmed_pair_order: Dictionary = {}
var _pair_candidates: Dictionary = {}
var _confirmed_leader: CarController
var _leader_candidate: CarController
var _leader_candidate_time := 0.0
var _ranking_timer := 0.0
var _race_elapsed_time := 0.0
var _race_best_lap := 0.0
var _race_active := false
var _restart_pending := false
var _neural_seed_batch := 0
var _neural_evaluation_mode := false
var _evaluation_agent_count := 12
var _evaluation_seed_base := -1
var _evaluation_genomes: Array[NeuralGenome] = []
var _leader_ineligible_cars: Dictionary = {}
var _official_leader: CarController


func _ready() -> void:
	_find_track()
	if _track == null:
		push_error("RaceManager requires an active RaceTrackBase.")
		return
	_start_race()


func _physics_process(delta: float) -> void:
	if not _race_active:
		return

	_race_elapsed_time += delta
	for telemetry in _telemetry_by_car.values():
		if telemetry is CarRaceTelemetry and telemetry.is_racing():
			telemetry.total_race_time = _race_elapsed_time

	var leader := get_leader()
	if leader != null:
		var leader_telemetry := get_telemetry(leader)
		if leader_telemetry != null and leader_telemetry.is_racing():
			leader_telemetry.time_in_first_place += delta

	_ranking_timer -= delta
	if _ranking_timer <= 0.0:
		_ranking_timer = ranking_refresh_interval
		_update_rankings(ranking_refresh_interval)

	if _race_elapsed_time >= race_time_limit:
		_end_race(&"TIME_LIMIT")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_race") and not event.is_echo():
		restart_race()
		get_viewport().set_input_as_handled()
	elif (
		event.is_action_pressed("randomize_neural_genomes")
		and not event.is_echo()
		and not _neural_evaluation_mode
	):
		randomize_neural_genomes()
		get_viewport().set_input_as_handled()


func get_cars() -> Array[CarController]:
	return _cars.duplicate()


func get_ranked_cars() -> Array[CarController]:
	return _ranked_cars.duplicate()


func get_manual_car() -> CarController:
	return manual_car


func get_leader() -> CarController:
	return _ranked_cars[0] if not _ranked_cars.is_empty() else null


func get_official_leader() -> CarController:
	var first_valid: CarController
	for car in _ranked_cars:
		if not is_instance_valid(car) or car.is_queued_for_deletion():
			continue
		if first_valid == null:
			first_valid = car
		if not _leader_ineligible_cars.has(car):
			return car
	# When every competitor has ended, retain the official final-order leader.
	return first_valid


func set_car_leader_eligible(car: CarController, is_eligible: bool) -> void:
	if car == null:
		return
	var was_eligible := not _leader_ineligible_cars.has(car)
	if is_eligible:
		_leader_ineligible_cars.erase(car)
	else:
		_leader_ineligible_cars[car] = true
	if was_eligible == is_eligible:
		return
	leader_eligibility_changed.emit(car, is_eligible)
	_refresh_official_leader()


func get_car(index: int) -> CarController:
	if _cars.is_empty():
		return null
	return _cars[posmod(index, _cars.size())]


func get_car_index(car: CarController) -> int:
	return _cars.find(car)


func get_car_count() -> int:
	return _cars.size()


func get_neural_cars() -> Array[CarController]:
	var result: Array[CarController] = []
	for car in _cars:
		if _neural_controllers_by_car.has(car):
			result.append(car)
	return result


func get_neural_genome_copies() -> Array[NeuralGenome]:
	var result: Array[NeuralGenome] = []
	for car in _cars:
		var controller := _neural_controllers_by_car.get(car) as NeuralCarController
		if controller != null and controller.genome != null:
			result.append(controller.genome.copy_genome())
	return result


func is_neural_evaluation_mode() -> bool:
	return _neural_evaluation_mode


func get_progress_tracker(car: CarController) -> RaceProgressTracker:
	return _progress_by_car.get(car) as RaceProgressTracker


func get_position_for_car(car: CarController) -> int:
	var telemetry := get_telemetry(car)
	return telemetry.current_position if telemetry != null else 0


func get_total_laps() -> int:
	return total_laps


func get_race_elapsed_time() -> float:
	return _race_elapsed_time


func is_race_active() -> bool:
	return _race_active


func get_telemetry(car: CarController) -> CarRaceTelemetry:
	return _telemetry_by_car.get(car) as CarRaceTelemetry


func get_telemetry_by_vehicle_id(vehicle_id: String) -> CarRaceTelemetry:
	for telemetry in _telemetry_by_car.values():
		if telemetry is CarRaceTelemetry and telemetry.vehicle_id == vehicle_id:
			return telemetry
	return null


func get_all_telemetry() -> Array[CarRaceTelemetry]:
	var result: Array[CarRaceTelemetry] = []
	for car in _cars:
		var telemetry := get_telemetry(car)
		if telemetry != null:
			result.append(telemetry)
	return result


func get_metrics_for_car(car: CarController) -> Dictionary:
	var telemetry := get_telemetry(car)
	return telemetry.get_metrics_snapshot() if telemetry != null else {}


func get_leaderboard_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for car in _ranked_cars:
		var telemetry := get_telemetry(car)
		if telemetry == null:
			continue
		entries.append({
			"position": telemetry.current_position,
			"vehicle_id": telemetry.vehicle_id,
			"lap": mini(telemetry.completed_laps + 1, total_laps),
			"total_laps": total_laps,
			"gap_seconds": telemetry.approximate_gap_to_leader,
			"state": telemetry.get_state_label(),
			"controller": car.get_controller_code(),
		})
	return entries


func randomize_neural_genomes() -> void:
	if neural_network_config == null:
		return
	_neural_seed_batch += 1
	for car in get_neural_cars():
		var controller := _neural_controllers_by_car.get(car) as NeuralCarController
		if controller == null:
			continue
		var car_index := _cars.find(car)
		controller.assign_genome(_create_neural_genome(car, car_index))
		var progress := _progress_by_car.get(car) as RaceProgressTracker
		if progress != null:
			progress.respawn_at_last_checkpoint()
	race_event.emit("NEURAL WEIGHTS RESET", &"NEURAL_RESET", null)


func start_neural_evaluation(agent_count: int) -> void:
	_evaluation_agent_count = clampi(agent_count, 2, 24)
	_evaluation_seed_base = -1
	_evaluation_genomes.clear()
	_neural_evaluation_mode = true
	race_mode_changed.emit(true)
	restart_race()


func start_seeded_neural_evaluation(agent_count: int, seed_base: int) -> void:
	_evaluation_agent_count = clampi(agent_count, 2, 24)
	_evaluation_seed_base = seed_base
	_evaluation_genomes.clear()
	_neural_evaluation_mode = true
	race_mode_changed.emit(true)
	restart_race()


func start_neural_evaluation_with_genomes(
	genomes: Array[NeuralGenome]
) -> void:
	if genomes.size() < 2:
		push_error("A neural evaluation requires at least two genomes.")
		return
	_evaluation_genomes.clear()
	for genome in genomes:
		if genome == null or not genome.is_valid():
			push_error("Invalid genome supplied to RaceManager.")
			_evaluation_genomes.clear()
			return
		_evaluation_genomes.append(genome.copy_genome())
	_evaluation_agent_count = clampi(_evaluation_genomes.size(), 2, 24)
	_evaluation_seed_base = -1
	_neural_evaluation_mode = true
	race_mode_changed.emit(true)
	restart_race()


func return_to_standard_mode() -> void:
	if not _neural_evaluation_mode:
		return
	_neural_evaluation_mode = false
	_evaluation_seed_base = -1
	_evaluation_genomes.clear()
	race_mode_changed.emit(false)
	restart_race()


func finish_neural_evaluation_race() -> void:
	if _neural_evaluation_mode and _race_active:
		_end_race(&"EVALUATION_COMPLETE")


func restart_race() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	call_deferred("_perform_restart")


func _perform_restart() -> void:
	for child in cars_container.get_children():
		child.free()
	_start_race()
	_restart_pending = false


func _start_race() -> void:
	manual_car = null
	_cars.clear()
	_ranked_cars.clear()
	_finish_order.clear()
	_telemetry_by_car.clear()
	_progress_by_car.clear()
	_neural_controllers_by_car.clear()
	_previous_order_index.clear()
	_confirmed_pair_order.clear()
	_pair_candidates.clear()
	_leader_ineligible_cars.clear()
	_official_leader = null
	_confirmed_leader = null
	_leader_candidate = null
	_leader_candidate_time = 0.0
	_ranking_timer = 0.0
	_race_elapsed_time = 0.0
	_race_best_lap = 0.0
	_race_active = true

	_spawn_cars()
	_ranked_cars = _cars.duplicate()
	_rebuild_previous_order_indices()
	_initialize_pair_order()
	_confirmed_leader = get_leader()
	_update_rankings(0.0)
	race_started.emit(total_laps)
	var start_message := (
		"NEURAL EVALUATION · %d AGENTS" % _cars.size()
		if _neural_evaluation_mode
		else "NEW RACE · %d LAPS" % total_laps
	)
	race_event.emit(start_message, &"RACE_START", null)


func _find_track() -> void:
	for candidate in get_tree().get_nodes_in_group("race_track"):
		if candidate is RaceTrackBase:
			_track = candidate
			return


func _spawn_cars() -> void:
	var spawn_count := _evaluation_agent_count if _neural_evaluation_mode else car_count
	var grid_transforms := _track.get_start_grid_transforms(spawn_count)
	var neural_start_index := maxi(spawn_count - neural_car_count, 1)

	for index in range(spawn_count):
		var car := CAR_SCENE.instantiate() as CarController
		car.manual_control_enabled = not _neural_evaluation_mode and index == 0
		car.transform = (
			_track.get_start_transform()
			if _neural_evaluation_mode
			else grid_transforms[index]
		)
		cars_container.add_child(car)
		car.set_vehicle_identity(
			(
				"AGENT-%02d" % (index + 1)
				if _neural_evaluation_mode
				else "CAR-%02d" % (index + 1)
			),
			CAR_COLORS[index % CAR_COLORS.size()]
		)

		var progress := car.get_node("RaceProgress") as RaceProgressTracker
		progress.allow_manual_respawn = not _neural_evaluation_mode and index == 0
		_track.register_car(car)
		progress.lap_completed.connect(_on_lap_completed.bind(car))
		_progress_by_car[car] = progress

		var telemetry := CarRaceTelemetry.new()
		telemetry.initialize(car.vehicle_id, index + 1)
		_telemetry_by_car[car] = telemetry

		if not _neural_evaluation_mode and index == 0:
			manual_car = car
			car.set_controller_kind(&"MANUAL")
		elif _neural_evaluation_mode or index >= neural_start_index:
			car.set_controller_kind(&"NEURAL")
			var neural_controller := (
				NEURAL_CONTROLLER_SCENE.instantiate() as NeuralCarController
			)
			neural_controller.genome = (
				_evaluation_genomes[index].copy_genome()
				if _neural_evaluation_mode and index < _evaluation_genomes.size()
				else _create_neural_genome(car, index)
			)
			car.add_child(neural_controller)
			_neural_controllers_by_car[car] = neural_controller
		else:
			car.set_controller_kind(&"TEMPORARY")
			var temporary_controller := (
				TEMPORARY_CONTROLLER_SCENE.instantiate() as TemporaryLineFollower
			)
			temporary_controller.speed_factor = SPEED_FACTORS[index % SPEED_FACTORS.size()]
			car.add_child(temporary_controller)

		_cars.append(car)

	cars_spawned.emit(get_cars())


func _create_neural_genome(car: CarController, car_index: int) -> NeuralGenome:
	var genome := NeuralGenome.new()
	if neural_network_config == null:
		push_error("RaceManager requires a NeuralNetworkConfig resource.")
		return genome
	var input_count := car.get_neural_inputs().size()
	if not neural_network_config.is_valid_for(input_count):
		push_error("Invalid neural network configuration.")
		return genome
	var seed_base := (
		_evaluation_seed_base
		if _neural_evaluation_mode and _evaluation_seed_base >= 0
		else neural_network_config.random_seed_base
	)
	var genome_seed := seed_base + car_index
	if not (_neural_evaluation_mode and _evaluation_seed_base >= 0):
		genome_seed += (
			_neural_seed_batch * neural_network_config.reroll_seed_stride
		)
	genome.configure_random(
		input_count,
		neural_network_config.hidden_neuron_count,
		neural_network_config.output_neuron_count,
		genome_seed,
		neural_network_config.random_weight_scale,
		"G001-I%02d-S%d" % [car_index + 1, genome_seed]
	)
	return genome


func _update_rankings(stability_delta: float) -> void:
	_update_continuous_progress()
	_ranked_cars = _cars.duplicate()
	_ranked_cars.sort_custom(_is_car_ahead)

	for index in range(_ranked_cars.size()):
		var telemetry := get_telemetry(_ranked_cars[index])
		if telemetry != null:
			telemetry.record_position(index + 1, telemetry.is_racing())

	_refresh_official_leader()

	_update_approximate_gaps()
	if stability_delta > 0.0:
		_update_overtake_candidates(stability_delta)
		_update_leader_candidate(stability_delta)
	_rebuild_previous_order_indices()
	rankings_updated.emit(get_ranked_cars())


func _refresh_official_leader() -> void:
	var next_leader := get_official_leader()
	if _official_leader == next_leader:
		return
	_official_leader = next_leader
	official_leader_changed.emit(_official_leader)


func _update_continuous_progress() -> void:
	var checkpoint_count := _track.get_checkpoint_count()
	for car in _cars:
		var telemetry := get_telemetry(car)
		var progress := _progress_by_car.get(car) as RaceProgressTracker
		if telemetry == null or progress == null:
			continue
		if telemetry.state == CarRaceTelemetry.RaceState.FINISHED:
			telemetry.segment_progress = 1.0
			telemetry.continuous_progress = float(total_laps * checkpoint_count)
			continue
		if telemetry.state == CarRaceTelemetry.RaceState.ABANDONED:
			continue

		telemetry.segment_progress = progress.get_intermediate_progress()
		telemetry.continuous_progress = (
			float(telemetry.completed_laps * checkpoint_count)
			+ float(progress.current_checkpoint)
			+ telemetry.segment_progress
		)


func _is_car_ahead(first: CarController, second: CarController) -> bool:
	var first_telemetry := get_telemetry(first)
	var second_telemetry := get_telemetry(second)
	if first_telemetry == null or second_telemetry == null:
		return first.vehicle_id < second.vehicle_id

	if first_telemetry.state == CarRaceTelemetry.RaceState.FINISHED:
		if second_telemetry.state == CarRaceTelemetry.RaceState.FINISHED:
			return first_telemetry.finish_position < second_telemetry.finish_position
		return true
	if second_telemetry.state == CarRaceTelemetry.RaceState.FINISHED:
		return false
	if first_telemetry.state == CarRaceTelemetry.RaceState.ABANDONED:
		if second_telemetry.state == CarRaceTelemetry.RaceState.ABANDONED:
			return first_telemetry.finish_position < second_telemetry.finish_position
		return false
	if second_telemetry.state == CarRaceTelemetry.RaceState.ABANDONED:
		return true

	if not is_equal_approx(
		first_telemetry.continuous_progress,
		second_telemetry.continuous_progress
	):
		return first_telemetry.continuous_progress > second_telemetry.continuous_progress

	var first_previous := int(_previous_order_index.get(first, first_telemetry.starting_position))
	var second_previous := int(_previous_order_index.get(second, second_telemetry.starting_position))
	if first_previous != second_previous:
		return first_previous < second_previous
	return first.vehicle_id < second.vehicle_id


func _update_approximate_gaps() -> void:
	if _ranked_cars.is_empty():
		return
	var leader := _ranked_cars[0]
	var leader_telemetry := get_telemetry(leader)
	if leader_telemetry == null:
		return

	var checkpoint_count := maxi(_track.get_checkpoint_count(), 1)
	var average_sector_length := _track.get_circuit_length() / float(checkpoint_count)
	var reference_speed := maxf(absf(leader.current_speed), 180.0)
	var first_finish_time := leader_telemetry.finish_time

	for car in _ranked_cars:
		var telemetry := get_telemetry(car)
		if telemetry == null:
			continue
		if car == leader:
			telemetry.approximate_gap_to_leader = 0.0
		elif (
			telemetry.state == CarRaceTelemetry.RaceState.FINISHED
			and first_finish_time > 0.0
		):
			telemetry.approximate_gap_to_leader = maxf(
				telemetry.finish_time - first_finish_time,
				0.0
			)
		else:
			var progress_gap := maxf(
				leader_telemetry.continuous_progress - telemetry.continuous_progress,
				0.0
			)
			telemetry.approximate_gap_to_leader = (
				progress_gap * average_sector_length / reference_speed
			)


func _initialize_pair_order() -> void:
	for first_index in range(_ranked_cars.size()):
		for second_index in range(first_index + 1, _ranked_cars.size()):
			var first := _ranked_cars[first_index]
			var second := _ranked_cars[second_index]
			_confirmed_pair_order[_get_pair_key(first, second)] = first


func _update_overtake_candidates(delta: float) -> void:
	var order_indices: Dictionary = {}
	for index in range(_ranked_cars.size()):
		order_indices[_ranked_cars[index]] = index

	for first_index in range(_cars.size()):
		for second_index in range(first_index + 1, _cars.size()):
			var first := _cars[first_index]
			var second := _cars[second_index]
			var key := _get_pair_key(first, second)
			var ahead := (
				first if int(order_indices[first]) < int(order_indices[second]) else second
			)
			var confirmed := _confirmed_pair_order.get(key, ahead) as CarController
			if ahead == confirmed:
				_pair_candidates.erase(key)
				continue

			var candidate: Dictionary = _pair_candidates.get(key, {})
			if candidate.get("ahead") == ahead:
				candidate["time"] = float(candidate.get("time", 0.0)) + delta
			else:
				candidate = {"ahead": ahead, "time": delta}
			_pair_candidates[key] = candidate

			if float(candidate["time"]) >= overtake_stability_time:
				_confirmed_pair_order[key] = ahead
				_pair_candidates.erase(key)
				_record_overtake(ahead, confirmed)


func _record_overtake(overtaker: CarController, overtaken: CarController) -> void:
	var overtaker_telemetry := get_telemetry(overtaker)
	var overtaken_telemetry := get_telemetry(overtaken)
	if (
		overtaker_telemetry == null
		or overtaken_telemetry == null
		or not overtaker_telemetry.is_racing()
		or not overtaken_telemetry.is_racing()
	):
		return
	overtaker_telemetry.overtakes_completed += 1
	overtaken_telemetry.times_overtaken += 1
	race_event.emit(
		"OVERTAKE · %s > %s" % [overtaker.vehicle_id, overtaken.vehicle_id],
		&"OVERTAKE",
		overtaker
	)


func _update_leader_candidate(delta: float) -> void:
	var current_leader := get_leader()
	if current_leader == null or current_leader == _confirmed_leader:
		_leader_candidate = null
		_leader_candidate_time = 0.0
		return
	if current_leader == _leader_candidate:
		_leader_candidate_time += delta
	else:
		_leader_candidate = current_leader
		_leader_candidate_time = delta

	if _leader_candidate_time >= overtake_stability_time:
		_confirmed_leader = current_leader
		_leader_candidate = null
		_leader_candidate_time = 0.0
		race_event.emit(
			"NEW LEADER · %s" % current_leader.vehicle_id,
			&"NEW_LEADER",
			current_leader
		)


func _on_lap_completed(
	completed_lap: int,
	lap_time: float,
	car: CarController
) -> void:
	if not _race_active:
		return
	var telemetry := get_telemetry(car)
	if telemetry == null or not telemetry.is_racing():
		return

	telemetry.record_lap(lap_time)
	if _race_best_lap <= 0.0 or lap_time < _race_best_lap:
		_race_best_lap = lap_time
		race_event.emit(
			"BEST LAP · %s · %s" % [car.vehicle_id, _format_time(lap_time)],
			&"BEST_LAP",
			car
		)

	if completed_lap >= total_laps:
		var progress := get_progress_tracker(car)
		if progress != null:
			progress.freeze_timing()
		_finish_order.append(car)
		var finish_position := _finish_order.size()
		telemetry.mark_finished(finish_position, _race_elapsed_time)
		telemetry.record_position(finish_position, false)
		car_finished.emit(car, finish_position, _race_elapsed_time)
		race_event.emit(
			"FINISH P%02d · %s · %s" % [
				finish_position,
				car.vehicle_id,
				_format_time(_race_elapsed_time),
			],
			&"FINISH",
			car
		)
		_update_rankings(0.0)
		if _finish_order.size() == _cars.size():
			_end_race(&"ALL_FINISHED")


func _end_race(reason: StringName) -> void:
	if not _race_active:
		return
	for car in _cars:
		var progress := get_progress_tracker(car)
		if progress != null:
			progress.freeze_timing()
	if reason == &"TIME_LIMIT" or reason == &"EVALUATION_COMPLETE":
		_update_rankings(0.0)
		var next_position := _finish_order.size() + 1
		for car in _ranked_cars:
			var telemetry := get_telemetry(car)
			if telemetry != null and telemetry.is_racing():
				telemetry.mark_abandoned(next_position, _race_elapsed_time)
				telemetry.record_position(next_position, false)
				next_position += 1

	_race_active = false
	_update_rankings(0.0)
	race_finished.emit(reason, _race_elapsed_time)
	var message := "RACE COMPLETE"
	if reason == &"TIME_LIMIT":
		message = "TIME LIMIT"
	elif reason == &"EVALUATION_COMPLETE":
		message = "EVALUATION COMPLETE"
	race_event.emit(message, &"RACE_END", get_leader())


func _rebuild_previous_order_indices() -> void:
	_previous_order_index.clear()
	for index in range(_ranked_cars.size()):
		_previous_order_index[_ranked_cars[index]] = index


func _get_pair_key(first: CarController, second: CarController) -> String:
	var first_id := first.get_instance_id()
	var second_id := second.get_instance_id()
	return (
		"%d:%d" % [first_id, second_id]
		if first_id < second_id
		else "%d:%d" % [second_id, first_id]
	)


func _format_time(value: float) -> String:
	var minutes := floori(value / 60.0)
	var seconds := fmod(value, 60.0)
	return "%02d:%05.2f" % [minutes, seconds]
