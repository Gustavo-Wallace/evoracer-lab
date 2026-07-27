extends Node2D

@onready var track: RaceTrackBase = $Track
@onready var car: CarController = $Car
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	car.global_transform = track.get_start_transform()
	car.speed_changed.connect(hud.set_speed)
	hud.set_speed(car.get_speed_kmh())
	hud.set_track_name(track.display_name)
