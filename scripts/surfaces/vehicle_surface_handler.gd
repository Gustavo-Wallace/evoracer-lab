class_name VehicleSurfaceHandler
extends Node2D

signal surface_changed(surface: SurfaceProfile)

@export var fallback_surface: SurfaceProfile
@export var minimum_dust_speed := 55.0

var current_surface: SurfaceProfile
var _track: RaceTrackBase
var _vehicle: CarController

@onready var dust: CPUParticles2D = $GrassDust


func _ready() -> void:
	_vehicle = get_parent() as CarController
	current_surface = fallback_surface
	_find_track()
	_apply_dust_state()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_track):
		_find_track()

	var detected_surface := fallback_surface
	if _track != null and _vehicle != null:
		detected_surface = _track.get_surface_at_world_position(_vehicle.global_position)

	if detected_surface != null and detected_surface != current_surface:
		current_surface = detected_surface
		surface_changed.emit(current_surface)

	_apply_dust_state()


func get_profile() -> SurfaceProfile:
	return current_surface if current_surface != null else fallback_surface


func is_on_grass() -> bool:
	var profile := get_profile()
	return profile != null and profile.surface_id == &"grass"


func _find_track() -> void:
	for candidate in get_tree().get_nodes_in_group("race_track"):
		if candidate is RaceTrackBase:
			_track = candidate
			return


func _apply_dust_state() -> void:
	if dust == null:
		return
	var profile := get_profile()
	var speed := absf(_vehicle.current_speed) if _vehicle != null else 0.0
	dust.emitting = (
		profile != null
		and profile.emits_dust
		and speed >= minimum_dust_speed
	)
	if profile != null:
		dust.color = profile.dust_color
