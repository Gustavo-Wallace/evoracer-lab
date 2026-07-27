class_name RaceHUD
extends CanvasLayer

@onready var speed_value: Label = $Layout/SpeedPanel/SpeedReadout/SpeedValue
@onready var track_label: Label = $Layout/TrackPanel/TrackLabel


func set_speed(speed_kmh: float) -> void:
	speed_value.text = "%03d" % roundi(speed_kmh)


func set_track_name(track_name: String) -> void:
	track_label.text = "TRACK 01 - %s" % track_name.to_upper()
