extends Node2D

@onready var track: RaceTrackBase = $Track
@onready var race_manager: RaceManager = $RaceManager
@onready var race_camera: RaceCamera = $RaceCamera
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	hud.set_track_name(track.display_name)
	race_manager.rankings_updated.connect(_on_rankings_updated)
	race_manager.race_event.connect(_on_race_event)
	race_camera.camera_state_changed.connect(_on_camera_state_changed)
	_update_leaderboard()


func _process(_delta: float) -> void:
	var target := race_camera.get_target()
	if target == null:
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
	hud.set_lap_timing(progress.lap_time, progress.time_since_last_progress)
	hud.set_spectator_info(
		race_camera.get_mode_label(),
		target.vehicle_id,
		race_manager.get_position_for_car(target),
		race_manager.get_car_count()
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


func _update_leaderboard() -> void:
	var target := race_camera.get_target()
	var followed_vehicle_id := target.vehicle_id if target != null else ""
	hud.set_leaderboard(
		race_manager.get_leaderboard_entries(),
		followed_vehicle_id
	)
