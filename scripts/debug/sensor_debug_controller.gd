class_name SensorDebugController
extends CanvasLayer

@export var toggle_action: StringName = &"toggle_sensor_debug"
@export var camera_path := NodePath("../RaceCamera")

var _debug_enabled := false
var _camera: RaceCamera
var _target: CarController
var _active_sensors: VehicleSensors

@onready var panel: PanelContainer = $Layout/SensorPanel
@onready var title_label: Label = $Layout/SensorPanel/Content/TitleLabel
@onready var values_label: Label = $Layout/SensorPanel/Content/ValuesLabel
@onready var surface_label: Label = $Layout/SensorPanel/Content/SurfaceLabel


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as RaceCamera
	panel.visible = false


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


func _set_target(candidate: CarController) -> void:
	if _target == candidate:
		return
	if _active_sensors != null:
		_active_sensors.set_debug_visible(false)

	_target = candidate
	_active_sensors = null
	if _target != null:
		_active_sensors = _target.get_node_or_null("VehicleSensors") as VehicleSensors
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
	surface_label.text = (
		"SURFACE: GRASS" if surface_value >= 0.5 else "SURFACE: ASPHALT"
	)
