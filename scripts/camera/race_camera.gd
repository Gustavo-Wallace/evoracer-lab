class_name RaceCamera
extends Camera2D

signal view_mode_changed(is_overview: bool)
signal camera_state_changed(mode_name: String, target: CarController)

enum ViewMode {
	SELECTED,
	LEADER,
	RANDOM,
	OVERVIEW,
}

@export_group("Discovery")
@export var target_group: StringName = &"race_cars"
@export var track_group: StringName = &"race_track"
@export var manager_group: StringName = &"race_manager"
@export_enum("Selected", "Leader", "Random", "Overview") var initial_view_mode: int = ViewMode.SELECTED

@export_group("Follow View")
@export var follow_zoom := Vector2(1.05, 1.05)
@export_range(1.0, 12.0, 0.1) var follow_smoothing := 5.5

@export_group("Overview")
@export var overview_padding := Vector2(260.0, 220.0)
@export_range(0.1, 1.0, 0.01) var minimum_overview_zoom := 0.18
@export_range(0.1, 1.0, 0.01) var maximum_overview_zoom := 0.75
@export_range(1.0, 12.0, 0.1) var transition_smoothing := 4.0

var view_mode := ViewMode.SELECTED
var _last_tracking_mode := ViewMode.SELECTED
var _selected_index := 0
var _target: CarController
var _random_target: CarController
var _track: RaceTrackBase
var _race_manager: RaceManager
var _initialized := false


func _ready() -> void:
	view_mode = initial_view_mode
	if view_mode != ViewMode.OVERVIEW:
		_last_tracking_mode = view_mode
	_find_dependencies()
	_update_target_for_mode(true)


func _process(delta: float) -> void:
	_handle_camera_input()

	if not is_instance_valid(_race_manager) or not is_instance_valid(_track):
		_find_dependencies()
	if view_mode == ViewMode.LEADER:
		_synchronize_leader_target()
	elif not is_instance_valid(_target):
		_update_target_for_mode()

	if not _initialized:
		_snap_to_current_view()
		_initialized = true

	var desired_position := global_position
	var desired_zoom := zoom

	if view_mode == ViewMode.OVERVIEW and is_instance_valid(_track):
		desired_position = _get_overview_center()
		desired_zoom = _get_overview_zoom()
	elif is_instance_valid(_target):
		desired_position = _target.global_position
		desired_zoom = follow_zoom

	var smoothing := (
		transition_smoothing if view_mode == ViewMode.OVERVIEW else follow_smoothing
	)
	var blend := 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(desired_position, blend)
	zoom = zoom.lerp(desired_zoom, blend)


func set_target(candidate: Node2D) -> bool:
	if (
		candidate == null
		or not candidate.is_in_group(target_group)
		or not candidate is CarController
	):
		return false

	var car := candidate as CarController
	var index := _race_manager.get_car_index(car) if is_instance_valid(_race_manager) else -1
	if index >= 0:
		_selected_index = index
	_set_view_mode(ViewMode.SELECTED)
	_set_target_internal(car)
	return true


func get_target() -> CarController:
	return _target


func get_mode_label() -> String:
	match view_mode:
		ViewMode.SELECTED:
			return "SELECTED"
		ViewMode.LEADER:
			return "LEADER"
		ViewMode.RANDOM:
			return "RANDOM"
		ViewMode.OVERVIEW:
			return "OVERVIEW"
	return "UNKNOWN"


func set_view_mode(new_mode: int) -> void:
	if new_mode < ViewMode.SELECTED or new_mode > ViewMode.OVERVIEW:
		return
	_set_view_mode(new_mode)


func toggle_view_mode() -> void:
	if view_mode == ViewMode.OVERVIEW:
		_set_view_mode(_last_tracking_mode)
	else:
		_last_tracking_mode = view_mode
		_set_view_mode(ViewMode.OVERVIEW)


func select_next_car(direction: int = 1) -> void:
	if not is_instance_valid(_race_manager) or _race_manager.get_car_count() == 0:
		return
	_selected_index = posmod(
		_selected_index + direction,
		_race_manager.get_car_count()
	)
	_set_view_mode(ViewMode.SELECTED)


func select_manual_car() -> void:
	if not is_instance_valid(_race_manager):
		return
	var manual := _race_manager.get_manual_car()
	if manual != null:
		_selected_index = _race_manager.get_car_index(manual)
		_set_view_mode(ViewMode.SELECTED)


func choose_random_target() -> void:
	if not is_instance_valid(_race_manager):
		return
	var cars := _race_manager.get_cars()
	if cars.is_empty():
		return

	var previous := _random_target
	_random_target = cars.pick_random()
	if cars.size() > 1:
		while _random_target == previous:
			_random_target = cars.pick_random()
	_set_view_mode(ViewMode.RANDOM)


func _handle_camera_input() -> void:
	if Input.is_action_just_pressed("camera_selected"):
		_set_view_mode(ViewMode.SELECTED)
	if Input.is_action_just_pressed("camera_leader"):
		_set_view_mode(ViewMode.LEADER)
	if Input.is_action_just_pressed("camera_random"):
		choose_random_target()
	if Input.is_action_just_pressed("camera_overview"):
		_set_view_mode(ViewMode.OVERVIEW)
	if Input.is_action_just_pressed("camera_next"):
		select_next_car(1)
	if Input.is_action_just_pressed("camera_previous"):
		select_next_car(-1)
	if Input.is_action_just_pressed("camera_randomize"):
		choose_random_target()
	if Input.is_action_just_pressed("camera_manual"):
		select_manual_car()
	if Input.is_action_just_pressed("toggle_camera"):
		toggle_view_mode()


func _set_view_mode(new_mode: int) -> void:
	if new_mode != ViewMode.OVERVIEW:
		_last_tracking_mode = new_mode
	var changed := view_mode != new_mode
	view_mode = new_mode
	_update_target_for_mode(true)
	if changed:
		view_mode_changed.emit(view_mode == ViewMode.OVERVIEW)


func _update_target_for_mode(force_signal: bool = false) -> void:
	if not is_instance_valid(_race_manager):
		return

	var desired_target := _target
	match view_mode:
		ViewMode.SELECTED:
			desired_target = _race_manager.get_car(_selected_index)
		ViewMode.LEADER:
			desired_target = _race_manager.get_official_leader()
		ViewMode.RANDOM:
			if not is_instance_valid(_random_target):
				choose_random_target()
			desired_target = _random_target
		ViewMode.OVERVIEW:
			if not is_instance_valid(desired_target):
				desired_target = _race_manager.get_manual_car()

	_set_target_internal(desired_target, force_signal)


func _set_target_internal(candidate: CarController, force_signal: bool = false) -> void:
	if candidate != null and not is_instance_valid(candidate):
		candidate = null
	var changed := _target != candidate
	_target = candidate
	if changed or force_signal:
		camera_state_changed.emit(get_mode_label(), _target)


func _find_dependencies() -> void:
	for candidate in get_tree().get_nodes_in_group(manager_group):
		if candidate is RaceManager:
			_bind_race_manager(candidate as RaceManager)
			break
	for candidate in get_tree().get_nodes_in_group(track_group):
		if candidate is RaceTrackBase:
			_track = candidate
			break


func _bind_race_manager(manager: RaceManager) -> void:
	if _race_manager == manager:
		return
	_race_manager = manager
	if not _race_manager.rankings_updated.is_connected(_on_rankings_updated):
		_race_manager.rankings_updated.connect(_on_rankings_updated)
	if not _race_manager.official_leader_changed.is_connected(
		_on_official_leader_changed
	):
		_race_manager.official_leader_changed.connect(
			_on_official_leader_changed
		)
	if not _race_manager.leader_eligibility_changed.is_connected(
		_on_leader_eligibility_changed
	):
		_race_manager.leader_eligibility_changed.connect(
			_on_leader_eligibility_changed
		)
	if not _race_manager.cars_spawned.is_connected(_on_cars_spawned):
		_race_manager.cars_spawned.connect(_on_cars_spawned)
	if not _race_manager.car_finished.is_connected(_on_car_finished):
		_race_manager.car_finished.connect(_on_car_finished)
	if not _race_manager.race_started.is_connected(_on_race_started):
		_race_manager.race_started.connect(_on_race_started)


func _synchronize_leader_target(force_signal: bool = false) -> void:
	if view_mode != ViewMode.LEADER or not is_instance_valid(_race_manager):
		return
	# Always take the live object reference from the authoritative manager.
	_set_target_internal(
		_race_manager.get_official_leader(),
		force_signal
	)


func _on_rankings_updated(_ranked_cars: Array[CarController]) -> void:
	_synchronize_leader_target()


func _on_official_leader_changed(_leader: CarController) -> void:
	_synchronize_leader_target()


func _on_leader_eligibility_changed(
	_car: CarController,
	_is_eligible: bool
) -> void:
	_synchronize_leader_target()


func _on_cars_spawned(_cars: Array[CarController]) -> void:
	_random_target = null
	_selected_index = 0
	if view_mode == ViewMode.LEADER:
		_synchronize_leader_target(true)
	else:
		_update_target_for_mode(true)


func _on_car_finished(
	_car: CarController,
	_position: int,
	_finish_time: float
) -> void:
	_synchronize_leader_target()


func _on_race_started(_total_laps: int) -> void:
	if view_mode == ViewMode.LEADER:
		_synchronize_leader_target(true)


func _snap_to_current_view() -> void:
	if view_mode == ViewMode.OVERVIEW and is_instance_valid(_track):
		global_position = _get_overview_center()
		zoom = _get_overview_zoom()
	elif is_instance_valid(_target):
		global_position = _target.global_position
		zoom = follow_zoom


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
