class_name CarController
extends CharacterBody2D

signal speed_changed(speed_kmh: float)

@export_category("Engine")
@export var acceleration := 260.0
@export var reverse_acceleration := 190.0
@export var brake_force := 480.0
@export var coast_deceleration := 115.0
@export var maximum_forward_speed := 440.0
@export var maximum_reverse_speed := 160.0

@export_category("Steering")
@export var maximum_steer_rate := 2.25
@export var steering_response := 5.5
@export var minimum_steering_speed := 22.0

@export_category("Collision")
@export_range(0.0, 1.0) var collision_rebound := 0.12
@export var pixels_per_second_to_kmh := 0.36

@export_category("Vehicle")
@export var dimensions: VehicleDimensions

var current_speed := 0.0
var current_steer_rate := 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if dimensions == null:
		push_error("CarController requires a VehicleDimensions resource.")
		return

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = Vector2(dimensions.body_width, dimensions.body_length)


func _physics_process(delta: float) -> void:
	_update_speed(delta)
	_update_steering(delta)

	velocity = Vector2.UP.rotated(rotation) * current_speed
	move_and_slide()

	if get_slide_collision_count() > 0:
		current_speed = -current_speed * collision_rebound

	speed_changed.emit(get_speed_kmh())


func get_speed_kmh() -> float:
	return absf(current_speed) * pixels_per_second_to_kmh


func reset_motion() -> void:
	current_speed = 0.0
	current_steer_rate = 0.0
	velocity = Vector2.ZERO
	speed_changed.emit(0.0)


func _update_speed(delta: float) -> void:
	var throttle := Input.get_axis("brake_reverse", "accelerate")
	var target_speed := 0.0
	var change_rate := coast_deceleration

	if throttle > 0.0:
		target_speed = maximum_forward_speed
		change_rate = brake_force if current_speed < 0.0 else acceleration
	elif throttle < 0.0:
		target_speed = -maximum_reverse_speed
		change_rate = brake_force if current_speed > 0.0 else reverse_acceleration

	current_speed = move_toward(current_speed, target_speed, change_rate * delta)


func _update_steering(delta: float) -> void:
	var steering_input := Input.get_axis("steer_left", "steer_right")
	var speed_ratio := clampf(absf(current_speed) / maximum_forward_speed, 0.0, 1.0)
	var target_steer_rate := steering_input * maximum_steer_rate * speed_ratio
	current_steer_rate = move_toward(
		current_steer_rate,
		target_steer_rate,
		steering_response * delta
	)

	if absf(current_speed) >= minimum_steering_speed:
		var movement_direction := signf(current_speed)
		rotation += current_steer_rate * movement_direction * delta
