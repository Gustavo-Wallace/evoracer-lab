class_name ChampionReplayManager
extends Node2D

signal replay_started(car: CarController)
signal replay_restarted(car: CarController)
signal replay_finished
signal replay_unavailable(message: String)
signal trajectory_visibility_changed(is_visible: bool)

const CAR_SCENE := preload("res://scenes/car/Car.tscn")
const NEURAL_CONTROLLER_SCENE := preload(
	"res://scenes/controllers/NeuralCarController.tscn"
)

@export var evolution_manager_path := NodePath("../EvolutionManager")
@export var race_manager_path := NodePath("../RaceManager")
@export var evaluation_manager_path := NodePath("../NeuralEvaluationManager")
@export var track_path := NodePath("../Track")
@export var camera_path := NodePath("../RaceCamera")

var _evolution: EvolutionManager
var _race_manager: RaceManager
var _evaluation: NeuralEvaluationManager
var _track: RaceTrackBase
var _camera: RaceCamera
var _replay_car: CarController
var _controller: NeuralCarController
var _record: NeuralEvaluationRecord
var _telemetry: CarRaceTelemetry
var _trajectory_overlay: ChampionTrajectoryOverlay
var _elapsed_time := 0.0
var _sample_accumulator := 0.0
var _is_replaying := false
var _trajectory_visible := true
var _saved_camera_mode := RaceCamera.ViewMode.SELECTED
var _saved_camera_target: CarController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_evolution = get_node_or_null(evolution_manager_path) as EvolutionManager
	_race_manager = get_node_or_null(race_manager_path) as RaceManager
	_evaluation = get_node_or_null(
		evaluation_manager_path
	) as NeuralEvaluationManager
	_track = get_node_or_null(track_path) as RaceTrackBase
	_camera = get_node_or_null(camera_path) as RaceCamera
	if (
		_evolution == null
		or _race_manager == null
		or _evaluation == null
		or _track == null
		or _camera == null
	):
		push_error("ChampionReplayManager dependencies are incomplete.")


func _physics_process(delta: float) -> void:
	if not _is_replaying or not is_instance_valid(_replay_car):
		return
	_elapsed_time += delta
	_sample_accumulator += delta
	_update_telemetry_progress()
	if _sample_accumulator >= _evaluation.fitness_config.sample_interval:
		var sample_delta := _sample_accumulator
		_sample_accumulator = 0.0
		_sample_replay(sample_delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _is_replaying and event.is_action_pressed("exit_neural_evaluation"):
		exit_replay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_champion_replay"):
		if _is_replaying:
			exit_replay()
		else:
			start_replay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart_champion_replay") and _is_replaying:
		restart_replay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_replay_trajectory") and _is_replaying:
		_trajectory_visible = not _trajectory_visible
		if _trajectory_overlay != null:
			_trajectory_overlay.visible = _trajectory_visible
		trajectory_visibility_changed.emit(_trajectory_visible)
		get_viewport().set_input_as_handled()


func start_replay() -> bool:
	if _is_replaying:
		return true
	if _evolution == null or not _evolution.has_historical_champion():
		var message := "NO HISTORICAL CHAMPION AVAILABLE"
		replay_unavailable.emit(message)
		push_warning(message)
		return false
	_saved_camera_mode = _camera.view_mode
	_saved_camera_target = _camera.get_target()
	_evolution.begin_replay_pause()
	_set_training_cars_visible(false)
	_is_replaying = true
	_spawn_replay_car()
	replay_started.emit(_replay_car)
	return true


func restart_replay() -> void:
	if not _is_replaying:
		return
	_destroy_replay_car()
	_spawn_replay_car()
	replay_restarted.emit(_replay_car)


func exit_replay() -> void:
	if not _is_replaying:
		return
	_destroy_replay_car()
	_is_replaying = false
	_set_training_cars_visible(true)
	_restore_camera()
	_evolution.end_replay_pause()
	replay_finished.emit()


func is_replay_active() -> bool:
	return _is_replaying


func get_replay_car() -> CarController:
	return _replay_car


func get_replay_telemetry() -> CarRaceTelemetry:
	return _telemetry


func get_fitness_breakdown(car: CarController) -> Dictionary:
	if car != _replay_car or _record == null:
		return {}
	_record.calculate_fitness(_evaluation.fitness_config, 1)
	return {
		"fitness": _record.fitness,
		"active": true,
		"reason": "REPLAY",
		"components": _record.fitness_components.duplicate(true),
	}


func _spawn_replay_car() -> void:
	var genome := _evolution.get_historical_champion_genome()
	if genome == null:
		return
	_elapsed_time = 0.0
	_sample_accumulator = 0.0
	_replay_car = CAR_SCENE.instantiate() as CarController
	_replay_car.manual_control_enabled = false
	_replay_car.transform = _track.get_start_transform()
	add_child(_replay_car)
	_replay_car.set_vehicle_identity("CHAMPION", Color("e7a92f"))
	_replay_car.set_controller_kind(&"NEURAL")
	_track.register_car(_replay_car)
	var progress := _replay_car.get_node("RaceProgress") as RaceProgressTracker
	progress.allow_manual_respawn = false
	progress.lap_completed.connect(_on_replay_lap_completed)

	_controller = NEURAL_CONTROLLER_SCENE.instantiate() as NeuralCarController
	_controller.genome = genome.copy_genome()
	_replay_car.add_child(_controller)
	_telemetry = CarRaceTelemetry.new()
	_telemetry.initialize(_replay_car.vehicle_id, 1)
	_record = NeuralEvaluationRecord.new()
	_record.initialize(_replay_car, _controller)

	_trajectory_overlay = ChampionTrajectoryOverlay.new()
	_trajectory_overlay.z_index = 5
	_trajectory_overlay.configure(
		_evolution.get_historical_champion_metadata()
	)
	_trajectory_overlay.visible = _trajectory_visible
	add_child(_trajectory_overlay)
	_camera.set_target(_replay_car)


func _destroy_replay_car() -> void:
	if is_instance_valid(_replay_car):
		_replay_car.free()
	if is_instance_valid(_trajectory_overlay):
		_trajectory_overlay.free()
	_replay_car = null
	_controller = null
	_record = null
	_telemetry = null
	_trajectory_overlay = null


func _sample_replay(delta: float) -> void:
	var progress := _replay_car.get_node("RaceProgress") as RaceProgressTracker
	var surface_handler := _replay_car.get_node_or_null(
		"VehicleSurface"
	) as VehicleSurfaceHandler
	_record.sample(
		delta,
		_elapsed_time,
		progress,
		_telemetry,
		surface_handler == null or not surface_handler.is_on_grass(),
		_get_forward_alignment(_replay_car),
		_evaluation.fitness_config
	)
	_record.set_final_position(1)
	_record.calculate_fitness(_evaluation.fitness_config, 1)


func _update_telemetry_progress() -> void:
	var progress := _replay_car.get_node("RaceProgress") as RaceProgressTracker
	_telemetry.total_race_time = _elapsed_time
	_telemetry.current_position = 1
	_telemetry.segment_progress = progress.get_intermediate_progress()
	_telemetry.continuous_progress = (
		float(_telemetry.completed_laps * _track.get_checkpoint_count())
		+ float(progress.current_checkpoint)
		+ telemetry_segment_progress()
	)


func telemetry_segment_progress() -> float:
	return _telemetry.segment_progress if _telemetry != null else 0.0


func _on_replay_lap_completed(_lap: int, lap_time: float) -> void:
	_telemetry.record_lap(lap_time)
	_record.record_lap(lap_time)


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


func _set_training_cars_visible(is_visible: bool) -> void:
	for car in _race_manager.get_cars():
		if is_instance_valid(car):
			car.visible = is_visible


func _restore_camera() -> void:
	if (
		_saved_camera_mode == RaceCamera.ViewMode.SELECTED
		and is_instance_valid(_saved_camera_target)
	):
		_camera.set_target(_saved_camera_target)
	else:
		_camera.set_view_mode(_saved_camera_mode)
