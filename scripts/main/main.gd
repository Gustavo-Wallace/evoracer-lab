extends Node2D

@onready var track: RaceTrackBase = $Track
@onready var race_manager: RaceManager = $RaceManager
@onready var race_camera: RaceCamera = $RaceCamera
@onready var hud: RaceHUD = $HUD
@onready var neural_evaluation: NeuralEvaluationManager = $NeuralEvaluationManager
@onready var evolution: EvolutionManager = $EvolutionManager
@onready var champion_replay: ChampionReplayManager = $ChampionReplayManager


func _ready() -> void:
	hud.set_track_name(track.display_name)
	race_manager.rankings_updated.connect(_on_rankings_updated)
	race_manager.race_event.connect(_on_race_event)
	race_camera.camera_state_changed.connect(_on_camera_state_changed)
	neural_evaluation.evaluation_started.connect(_on_evaluation_started)
	neural_evaluation.evaluation_finished.connect(_on_evaluation_finished)
	neural_evaluation.evaluation_cancelled.connect(_on_evaluation_cancelled)
	champion_replay.replay_started.connect(_on_replay_started)
	champion_replay.replay_restarted.connect(_on_replay_restarted)
	champion_replay.replay_finished.connect(_on_replay_finished)
	champion_replay.replay_unavailable.connect(_on_replay_unavailable)
	_update_leaderboard()


func _process(_delta: float) -> void:
	var target := race_camera.get_target()
	if not is_instance_valid(target):
		hud.set_spectator_info(
			race_camera.get_mode_label(),
			"NONE",
			0,
			race_manager.get_car_count(),
			"-"
		)
		return

	var progress := target.get_node("RaceProgress") as RaceProgressTracker
	hud.set_speed(target.get_speed_kmh())
	hud.set_race_progress(
		progress.current_lap,
		progress.current_checkpoint,
		progress.get_checkpoint_count(),
		progress.get_total_progress(),
		race_manager.get_total_laps()
	)
	var telemetry := (
		champion_replay.get_replay_telemetry()
		if champion_replay.is_replay_active()
		and target == champion_replay.get_replay_car()
		else race_manager.get_telemetry(target)
	)
	var has_finished := (
		telemetry != null
		and telemetry.state == CarRaceTelemetry.RaceState.FINISHED
	)
	hud.set_lap_timing(
		progress.get_display_lap_time(),
		progress.time_since_last_progress,
		has_finished
	)
	hud.set_spectator_info(
		(
			"REPLAY"
			if champion_replay.is_replay_active()
			else race_camera.get_mode_label()
		),
		target.vehicle_id,
		1 if champion_replay.is_replay_active() else race_manager.get_position_for_car(target),
		1 if champion_replay.is_replay_active() else race_manager.get_car_count(),
		target.get_controller_code()
	)


func _on_rankings_updated(_ranked_cars: Array[CarController]) -> void:
	_update_leaderboard()


func _on_camera_state_changed(_mode_name: String, _target: CarController) -> void:
	_update_leaderboard()


func _on_race_event(
	message: String,
	event_type: StringName,
	_event_car: CarController
) -> void:
	hud.show_race_event(message, event_type)


func _on_evaluation_started(_duration: float, _agent_count: int) -> void:
	hud.set_mode_label("NEURAL EVALUATION MODE")


func _on_evaluation_finished(_results: Array[Dictionary]) -> void:
	hud.set_mode_label("EVALUATION COMPLETE")


func _on_evaluation_cancelled() -> void:
	hud.set_mode_label("MANUAL TEST MODE")


func _on_replay_started(_car: CarController) -> void:
	hud.set_mode_label("HISTORICAL CHAMPION REPLAY")


func _on_replay_restarted(_car: CarController) -> void:
	hud.set_mode_label("CHAMPION REPLAY RESTARTED")


func _on_replay_finished() -> void:
	hud.set_mode_label(
		"NEURAL EVOLUTION MODE" if evolution.is_training_active() else "MANUAL TEST MODE"
	)


func _on_replay_unavailable(message: String) -> void:
	hud.show_race_event(message, &"RACE_END")


func _update_leaderboard() -> void:
	var target := race_camera.get_target()
	var followed_vehicle_id := target.vehicle_id if target != null else ""
	hud.set_leaderboard(
		race_manager.get_leaderboard_entries(),
		followed_vehicle_id
	)
