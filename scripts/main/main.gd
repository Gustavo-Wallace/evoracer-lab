extends Node2D

@onready var car: CarController = $Car
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	car.speed_changed.connect(hud.set_speed)
	hud.set_speed(car.get_speed_kmh())
