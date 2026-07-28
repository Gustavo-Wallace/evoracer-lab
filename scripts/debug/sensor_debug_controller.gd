class_name SensorDebugController
extends CanvasLayer

@export var toggle_action: StringName = &"toggle_sensor_debug"
@export var camera_path := NodePath("../RaceCamera")
@export var evaluation_manager_path := NodePath("../NeuralEvaluationManager")
@export var race_manager_path := NodePath("../RaceManager")
@export var replay_manager_path := NodePath("../ChampionReplayManager")

var _debug_enabled := false
var _camera: RaceCamera
var _target: CarController
var _active_sensors: VehicleSensors
var _neural_controller: NeuralCarController
var _evaluation_manager: NeuralEvaluationManager
var _race_manager: RaceManager
var _replay_manager: ChampionReplayManager

@onready var panel: PanelContainer = $Layout/SensorPanel
@onready var title_label: Label = $Layout/SensorPanel/Content/TitleLabel
@onready var values_label: Label = $Layout/SensorPanel/Content/ValuesLabel
@onready var surface_label: Label = $Layout/SensorPanel/Content/SurfaceLabel
@onready var neural_panel: PanelContainer = $Layout/NeuralPanel
@onready var neural_title: Label = $Layout/NeuralPanel/Content/TitleLabel
@onready var neural_values: Label = $Layout/NeuralPanel/Content/ValuesLabel
@onready var fitness_panel: PanelContainer = $Layout/FitnessPanel
@onready var fitness_title: Label = $Layout/FitnessPanel/Content/TitleLabel
@onready var fitness_values: Label = $Layout/FitnessPanel/Content/ValuesLabel


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as RaceCamera
	_evaluation_manager = get_node_or_null(
		evaluation_manager_path
	) as NeuralEvaluationManager
	_race_manager = get_node_or_null(race_manager_path) as RaceManager
	_replay_manager = get_node_or_null(
		replay_manager_path
	) as ChampionReplayManager
	panel.visible = false
	neural_panel.visible = false
	fitness_panel.visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = get_node_or_null(camera_path) as RaceCamera
		_set_target(null)
		return

	var followed_car := _camera.get_target()
	if _camera.view_mode == RaceCamera.ViewMode.OVERVIEW:
		followed_car = null
	_set_target(followed_car)

	panel.visible = _debug_enabled and _active_sensors != null
	if panel.visible:
		_update_panel()
	neural_panel.visible = _debug_enabled and _neural_controller != null
	if neural_panel.visible:
		_update_neural_panel()
	var fitness_breakdown := (
		_evaluation_manager.get_fitness_breakdown(_target)
		if _evaluation_manager != null and _target != null
		else {}
	)
	if fitness_breakdown.is_empty() and _replay_manager != null:
		fitness_breakdown = _replay_manager.get_fitness_breakdown(_target)
	fitness_panel.visible = (
		_debug_enabled
		and _neural_controller != null
		and not fitness_breakdown.is_empty()
	)
	if fitness_panel.visible:
		_update_fitness_panel(fitness_breakdown)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action) and not event.is_echo():
		set_debug_enabled(not _debug_enabled)
		get_viewport().set_input_as_handled()


func is_debug_enabled() -> bool:
	return _debug_enabled


func set_debug_enabled(is_enabled: bool) -> void:
	_debug_enabled = is_enabled
	if _active_sensors != null:
		_active_sensors.set_debug_visible(_debug_enabled)
	panel.visible = _debug_enabled and _active_sensors != null
	neural_panel.visible = _debug_enabled and _neural_controller != null
	fitness_panel.visible = false


func _set_target(candidate: CarController) -> void:
	if _target == candidate:
		return
	if _active_sensors != null:
		_active_sensors.set_debug_visible(false)

	_target = candidate
	_active_sensors = null
	_neural_controller = null
	if _target != null:
		_active_sensors = _target.get_node_or_null("VehicleSensors") as VehicleSensors
		_neural_controller = (
			_target.get_node_or_null("NeuralCarController") as NeuralCarController
		)
	if _active_sensors != null:
		_active_sensors.set_debug_visible(_debug_enabled)


func _update_panel() -> void:
	var inputs := _active_sensors.get_neural_inputs()
	var names := _active_sensors.get_input_names()
	var lines := PackedStringArray()
	for index in range(0, inputs.size(), 2):
		var line := "%-21s %+.2f" % [names[index].to_upper(), inputs[index]]
		if index + 1 < inputs.size():
			line += "   %-21s %+.2f" % [
				names[index + 1].to_upper(),
				inputs[index + 1],
			]
		lines.append(line)

	title_label.text = "SENSOR DEBUG  |  %s  |  [V]" % _target.vehicle_id
	values_label.text = "\n".join(lines)
	var surface_value := inputs[inputs.size() - 1]
	var surface_text := (
		"SURFACE: GRASS" if surface_value >= 0.5 else "SURFACE: ASPHALT"
	)
	var official_leader := (
		_race_manager.get_official_leader()
		if is_instance_valid(_race_manager)
		else null
	)
	var camera_target := _camera.get_target() if is_instance_valid(_camera) else null
	var leader_id := (
		official_leader.vehicle_id if is_instance_valid(official_leader) else "NONE"
	)
	var target_id := (
		camera_target.vehicle_id if is_instance_valid(camera_target) else "NONE"
	)
	var sync_state := "N/A"
	if _camera.view_mode == RaceCamera.ViewMode.LEADER:
		sync_state = "SYNC" if official_leader == camera_target else "DIVERGED"
	surface_label.text = "%s   LEADER: %s   CAMERA: %s   %s" % [
		surface_text,
		leader_id,
		target_id,
		sync_state,
	]


func _update_neural_panel() -> void:
	var snapshot := _neural_controller.get_debug_snapshot()
	var outputs := snapshot["outputs"] as PackedFloat32Array
	var output_text := "WAITING FOR OUTPUT"
	if outputs.size() == 3:
		output_text = "RAW  STEER %+.2f   ACCEL %+.2f   BRAKE %+.2f" % [
			outputs[0],
			outputs[1],
			outputs[2],
		]
	neural_title.text = "NEURAL  |  %s  |  SEED %d" % [
		String(snapshot["genome_id"]),
		int(snapshot["seed"]),
	]
	neural_values.text = "%s\nAPPLIED  STEER %+.2f   ACCEL %.2f   BRAKE %.2f\nTHROTTLE %+.2f" % [
		output_text,
		float(snapshot["steering"]),
		float(snapshot["acceleration"]),
		float(snapshot["brake_reverse"]),
		float(snapshot["throttle"]),
	]


func _update_fitness_panel(breakdown: Dictionary) -> void:
	var components: Dictionary = breakdown["components"]
	var primary := (
		float(components.get("valid_progress", 0.0))
		+ float(components.get("checkpoints", 0.0))
		+ float(components.get("finish_crossings", 0.0))
		+ float(components.get("fast_laps", 0.0))
	)
	var secondary := (
		float(components.get("useful_speed", 0.0))
		+ float(components.get("asphalt", 0.0))
		+ float(components.get("best_position", 0.0))
		+ float(components.get("final_position", 0.0))
		+ float(components.get("leader_time", 0.0))
		+ float(components.get("overtakes", 0.0))
	)
	var penalties := (
		float(components.get("stationary_penalty", 0.0))
		+ float(components.get("wrong_way_penalty", 0.0))
		+ float(components.get("grass_penalty", 0.0))
		+ float(components.get("barrier_penalty", 0.0))
		+ float(components.get("no_progress_penalty", 0.0))
		+ float(components.get("spinning_penalty", 0.0))
	)
	fitness_title.text = "FITNESS BREAKDOWN  |  %s" % String(breakdown["reason"])
	fitness_values.text = "TOTAL %+.0f   LAP TIER %+.0f\nPROGRESS %+.0f   SECONDARY %+.0f   PENALTIES %+.0f\nRAW %+.0f   BOUNDED %+.0f" % [
		float(breakdown["fitness"]),
		float(components.get("lap_tier", 0.0)),
		primary,
		secondary,
		penalties,
		float(components.get("non_lap_raw", 0.0)),
		float(components.get("non_lap_bounded", 0.0)),
	]
