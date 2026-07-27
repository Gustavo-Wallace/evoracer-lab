class_name SurfaceProfile
extends Resource

@export var surface_id: StringName = &"asphalt"
@export_range(0.0, 2.0, 0.05) var acceleration_multiplier := 1.0
@export_range(0.0, 2.0, 0.05) var maximum_speed_multiplier := 1.0
@export_range(0.0, 4.0, 0.05) var coast_deceleration_multiplier := 1.0
@export_range(0.0, 2.0, 0.05) var steering_rate_multiplier := 1.0
@export_range(0.0, 2.0, 0.05) var steering_response_multiplier := 1.0
@export var emits_dust := false
@export var dust_color := Color("c6a96b99")
