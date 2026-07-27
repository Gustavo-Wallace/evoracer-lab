class_name RaceHUD
extends CanvasLayer

@onready var speed_label: Label = $Layout/SpeedPanel/SpeedLabel


func set_speed(speed_kmh: float) -> void:
	speed_label.text = "%03d km/h" % roundi(speed_kmh)
