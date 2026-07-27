class_name RaceCamera
extends Camera2D

signal view_mode_changed(is_overview: bool)

enum ViewMode {
	FOLLOW,
	OVERVIEW,
}

@export_group("Target Discovery")
@export var target_group: StringName = &"race_cars"
@export var track_group: StringName = &"race_track"
@export_enum("Follow", "Overview") var initial_view_mode: int = ViewMode.FOLLOW

@export_group("Follow View")
@export var follow_zoom := Vector2(1.05, 1.05)
@export_range(1.0, 12.0, 0.1) var follow_smoothing := 5.5

@export_group("Overview")
@export var overview_padding := Vector2(260.0, 220.0)
@export_range(0.1, 1.0, 0.01) var minimum_overview_zoom := 0.18
@export_range(0.1, 1.0, 0.01) var maximum_overview_zoom := 0.75
@export_range(1.0, 12.0, 0.1) var transition_smoothing := 4.0

var view_mode := ViewMode.FOLLOW
var _target: Node2D
var _track: RaceTrackBase
var _initialized := false


func _ready() -> void:
	view_mode = initial_view_mode
	_select_first_available_target()
	_find_active_track()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_camera"):
		toggle_view_mode()

	if not is_instance_valid(_target):
		_select_first_available_target()
	if not is_instance_valid(_track):
		_find_active_track()

	if not _initialized:
		_snap_to_current_view()
		_initialized = true

	var desired_position := global_position
	var desired_zoom := zoom

	if view_mode == ViewMode.FOLLOW and is_instance_valid(_target):
		desired_position = _target.global_position
		desired_zoom = follow_zoom
	elif view_mode == ViewMode.OVERVIEW and is_instance_valid(_track):
		desired_position = _get_overview_center()
		desired_zoom = _get_overview_zoom()

	var smoothing := (
		follow_smoothing if view_mode == ViewMode.FOLLOW else transition_smoothing
	)
	var blend := 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(desired_position, blend)
	zoom = zoom.lerp(desired_zoom, blend)


func set_target(candidate: Node2D) -> bool:
	if candidate == null or not candidate.is_in_group(target_group):
		return false
	_target = candidate
	return true


func get_target() -> Node2D:
	return _target


func toggle_view_mode() -> void:
	view_mode = (
		ViewMode.OVERVIEW if view_mode == ViewMode.FOLLOW else ViewMode.FOLLOW
	)
	view_mode_changed.emit(view_mode == ViewMode.OVERVIEW)


func _select_first_available_target() -> void:
	for candidate in get_tree().get_nodes_in_group(target_group):
		if candidate is Node2D:
			_target = candidate
			return
	_target = null


func _find_active_track() -> void:
	for candidate in get_tree().get_nodes_in_group(track_group):
		if candidate is RaceTrackBase:
			_track = candidate
			return
	_track = null


func _snap_to_current_view() -> void:
	if view_mode == ViewMode.FOLLOW and is_instance_valid(_target):
		global_position = _target.global_position
		zoom = follow_zoom
	elif view_mode == ViewMode.OVERVIEW and is_instance_valid(_track):
		global_position = _get_overview_center()
		zoom = _get_overview_zoom()


func _get_overview_center() -> Vector2:
	var bounds := _track.get_local_bounds()
	return _track.to_global(bounds.get_center())


func _get_overview_zoom() -> Vector2:
	var bounds := _track.get_local_bounds()
	var track_scale := _track.global_scale.abs()
	var world_size := bounds.size * track_scale + overview_padding * 2.0
	var viewport_size := get_viewport_rect().size
	var fit_zoom := minf(
		viewport_size.x / world_size.x,
		viewport_size.y / world_size.y
	)
	fit_zoom = clampf(fit_zoom, minimum_overview_zoom, maximum_overview_zoom)
	return Vector2.ONE * fit_zoom
