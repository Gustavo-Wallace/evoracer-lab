extends Node2D

@onready var track: RaceTrackBase = $Track
@onready var car: CarController = $Car
@onready var progress: RaceProgressTracker = $Car/RaceProgress
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	car.global_transform = track.get_start_transform()
	track.register_car(car)
	car.speed_changed.connect(hud.set_speed)
	progress.progress_changed.connect(hud.set_race_progress)
	progress.timing_updated.connect(hud.set_lap_timing)
	hud.set_speed(car.get_speed_kmh())
	hud.set_track_name(track.display_name)
	hud.set_race_progress(
		progress.current_lap,
		progress.current_checkpoint,
		progress.get_checkpoint_count(),
		progress.get_total_progress()
	)
	hud.set_lap_timing(progress.lap_time, progress.time_since_last_progress)
