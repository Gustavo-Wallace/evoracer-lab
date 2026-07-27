class_name RaceHUD
extends CanvasLayer

@onready var speed_value: Label = $Layout/SpeedPanel/SpeedReadout/SpeedValue
@onready var track_label: Label = $Layout/TrackPanel/TrackContent/TrackLabel
@onready var lap_label: Label = $Layout/TrackPanel/TrackContent/RaceData/LapLabel
@onready var checkpoint_label: Label = $Layout/TrackPanel/TrackContent/RaceData/CheckpointLabel
@onready var lap_time_label: Label = $Layout/TrackPanel/TrackContent/RaceData/LapTimeLabel


func set_speed(speed_kmh: float) -> void:
	speed_value.text = "%03d" % roundi(speed_kmh)


func set_track_name(track_name: String) -> void:
	track_label.text = "TRACK 01 - %s" % track_name.to_upper()


func set_race_progress(
	current_lap: int,
	current_checkpoint: int,
	checkpoint_count: int,
	_total_progress: float
) -> void:
	lap_label.text = "LAP %02d" % current_lap
	checkpoint_label.text = "CP %02d/%02d" % [
		current_checkpoint,
		checkpoint_count - 1,
	]


func set_lap_timing(lap_time: float, _time_since_last_progress: float) -> void:
	var minutes := floori(lap_time / 60.0)
	var seconds := fmod(lap_time, 60.0)
	lap_time_label.text = "TIME %02d:%05.2f" % [minutes, seconds]
