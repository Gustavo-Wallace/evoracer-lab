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
@export_range(0.0, 1.0) var scrape_speed_retention_per_second := 0.78
@export_range(0.0, 1.0) var frontal_impact_threshold := 0.72
@export_range(0.0, 1.0) var frontal_speed_retention := 0.16
@export_range(0.0, 1.0) var frontal_tangent_retention := 0.42
@export var wall_alignment_speed := 7.0
@export var wall_separation_distance := 0.8
@export var pixels_per_second_to_kmh := 0.36

@export_category("Vehicle")
@export var dimensions: VehicleDimensions
@export var vehicle_id := "CAR-01"
@export var manual_control_enabled := true

var controller_kind: StringName = &"MANUAL"

var current_speed := 0.0
var current_steer_rate := 0.0
var barrier_contact_time := 0.0
var _requested_throttle := 0.0
var _requested_steering := 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var body_visual: Polygon2D = $Body
@onready var center_stripe: Polygon2D = $CenterStripe
@onready var surface_handler: VehicleSurfaceHandler = $VehicleSurface
@onready var vehicle_sensors: VehicleSensors = $VehicleSensors


func _ready() -> void:
	if dimensions == null:
		push_error("CarController requires a VehicleDimensions resource.")
		return

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = Vector2(dimensions.body_width, dimensions.body_length)
	_update_controller_marker()


func _physics_process(delta: float) -> void:
	var throttle := _requested_throttle
	var steering := _requested_steering
	if manual_control_enabled:
		throttle = Input.get_axis("brake_reverse", "accelerate")
		steering = Input.get_axis("steer_left", "steer_right")

	var surface := surface_handler.get_profile()
	_update_speed(throttle, surface, delta)
	_update_steering(steering, surface, delta)

	velocity = Vector2.UP.rotated(rotation) * current_speed
	var pre_collision_velocity := velocity
	move_and_slide()

	if get_slide_collision_count() > 0:
		barrier_contact_time += delta
		_resolve_barrier_contact(pre_collision_velocity, delta)
	else:
		barrier_contact_time = 0.0

	speed_changed.emit(get_speed_kmh())


func get_speed_kmh() -> float:
	return absf(current_speed) * pixels_per_second_to_kmh


func get_neural_inputs() -> PackedFloat32Array:
	return vehicle_sensors.get_neural_inputs()


func get_neural_input_names() -> PackedStringArray:
	return vehicle_sensors.get_input_names()


func set_control_inputs(throttle: float, steering: float) -> void:
	_requested_throttle = clampf(throttle, -1.0, 1.0)
	_requested_steering = clampf(steering, -1.0, 1.0)


func set_vehicle_identity(identifier: String, body_color: Color) -> void:
	vehicle_id = identifier
	body_visual.color = body_color


func set_controller_kind(kind: StringName) -> void:
	controller_kind = kind
	if is_node_ready():
		_update_controller_marker()


func get_controller_code() -> String:
	match controller_kind:
		&"NEURAL":
			return "N"
		&"TEMPORARY":
			return "T"
		_:
			return "M"


func reset_motion() -> void:
	current_speed = 0.0
	current_steer_rate = 0.0
	barrier_contact_time = 0.0
	velocity = Vector2.ZERO
	speed_changed.emit(0.0)


func _update_controller_marker() -> void:
	match controller_kind:
		&"NEURAL":
			center_stripe.color = Color("b889e8")
		&"TEMPORARY":
			center_stripe.color = Color("79c9d4")
		_:
			center_stripe.color = Color("ffbd33")


func _update_speed(throttle: float, surface: SurfaceProfile, delta: float) -> void:
	var acceleration_scale := surface.acceleration_multiplier if surface != null else 1.0
	var maximum_speed_scale := surface.maximum_speed_multiplier if surface != null else 1.0
	var coast_scale := surface.coast_deceleration_multiplier if surface != null else 1.0
	var surface_forward_max := maximum_forward_speed * maximum_speed_scale
	var surface_reverse_max := maximum_reverse_speed * maximum_speed_scale
	var target_speed := 0.0
	var change_rate := coast_deceleration * coast_scale

	if throttle > 0.0:
		target_speed = surface_forward_max
		if current_speed < 0.0:
			change_rate = brake_force
		elif current_speed > target_speed:
			change_rate = coast_deceleration * coast_scale
		else:
			change_rate = acceleration * acceleration_scale
	elif throttle < 0.0:
		target_speed = -surface_reverse_max
		if current_speed > 0.0:
			change_rate = brake_force
		elif current_speed < target_speed:
			change_rate = coast_deceleration * coast_scale
		else:
			change_rate = reverse_acceleration * acceleration_scale

	current_speed = move_toward(current_speed, target_speed, change_rate * delta)


func _update_steering(
	steering_input: float,
	surface: SurfaceProfile,
	delta: float
) -> void:
	var maximum_speed_scale := surface.maximum_speed_multiplier if surface != null else 1.0
	var steering_rate_scale := surface.steering_rate_multiplier if surface != null else 1.0
	var steering_response_scale := (
		surface.steering_response_multiplier if surface != null else 1.0
	)
	var surface_forward_max := maxf(maximum_forward_speed * maximum_speed_scale, 1.0)
	var speed_ratio := clampf(absf(current_speed) / surface_forward_max, 0.0, 1.0)
	var target_steer_rate := (
		steering_input * maximum_steer_rate * steering_rate_scale * speed_ratio
	)
	current_steer_rate = move_toward(
		current_steer_rate,
		target_steer_rate,
		steering_response * steering_response_scale * delta
	)

	if absf(current_speed) >= minimum_steering_speed:
		var movement_direction := signf(current_speed)
		rotation += current_steer_rate * movement_direction * delta


func _resolve_barrier_contact(pre_collision_velocity: Vector2, delta: float) -> void:
	var speed_before := pre_collision_velocity.length()
	if speed_before <= 0.001:
		return

	var strongest_normal := Vector2.ZERO
	var strongest_inward_speed := 0.0
	var combined_normal := Vector2.ZERO
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		var normal := collision.get_normal()
		var inward_speed := maxf(-pre_collision_velocity.dot(normal), 0.0)
		combined_normal += normal
		if inward_speed > strongest_inward_speed:
			strongest_inward_speed = inward_speed
			strongest_normal = normal

	if strongest_normal == Vector2.ZERO:
		return

	var tangent_velocity := pre_collision_velocity.slide(strongest_normal)
	var impact_ratio := strongest_inward_speed / speed_before
	var previous_direction := signf(current_speed)
	if is_zero_approx(previous_direction):
		previous_direction = 1.0

	if impact_ratio >= frontal_impact_threshold:
		_resolve_frontal_impact(
			tangent_velocity,
			strongest_normal,
			speed_before,
			previous_direction,
			delta
		)
	else:
		var retention := pow(scrape_speed_retention_per_second, delta)
		var preserved_speed := tangent_velocity.length() * retention
		current_speed = preserved_speed * previous_direction
		velocity = tangent_velocity * retention
		_align_forward_with_velocity(tangent_velocity, previous_direction, delta)

	if combined_normal != Vector2.ZERO:
		position += combined_normal.normalized() * wall_separation_distance


func _resolve_frontal_impact(
	tangent_velocity: Vector2,
	collision_normal: Vector2,
	speed_before: float,
	previous_direction: float,
	delta: float
) -> void:
	var retained_tangent_speed := tangent_velocity.length() * frontal_tangent_retention
	var rebound_speed := speed_before * frontal_speed_retention
	current_steer_rate *= 0.25

	if retained_tangent_speed > minimum_steering_speed:
		current_speed = retained_tangent_speed * previous_direction
		velocity = tangent_velocity.normalized() * retained_tangent_speed
		_align_forward_with_velocity(tangent_velocity, previous_direction, delta)
	else:
		current_speed = -rebound_speed * previous_direction
		velocity = collision_normal * rebound_speed


func _align_forward_with_velocity(
	movement_velocity: Vector2,
	movement_direction: float,
	delta: float
) -> void:
	if movement_velocity.length_squared() <= 0.001:
		return
	var desired_forward := movement_velocity.normalized() * movement_direction
	var desired_rotation := desired_forward.angle() + PI * 0.5
	var blend := 1.0 - exp(-wall_alignment_speed * delta)
	rotation = lerp_angle(rotation, desired_rotation, blend)
