extends Node2D

@onready var track: RaceTrackBase = $Track
@onready var race_manager: RaceManager = $RaceManager
@onready var race_camera: RaceCamera = $RaceCamera
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	hud.set_track_name(track.display_name)


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
		progress.get_total_progress()
	)
	hud.set_lap_timing(progress.lap_time, progress.time_since_last_progress)
	hud.set_spectator_info(
		race_camera.get_mode_label(),
		target.vehicle_id,
		race_manager.get_position_for_car(target),
		race_manager.get_car_count()
	)
