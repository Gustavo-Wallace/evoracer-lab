class_name RaceProgressTracker
extends Node

signal progress_changed(
	current_lap: int,
	current_checkpoint: int,
	checkpoint_count: int,
	total_progress: float
)
signal timing_updated(lap_time: float, time_since_last_progress: float)
signal lap_completed(completed_lap: int, completed_time: float)
signal checkpoint_rejected(expected_checkpoint: int, crossed_checkpoint: int)

@export var allow_manual_respawn := true

var current_checkpoint := 0
var total_checkpoints_passed := 0
var current_lap := 1
var lap_time := 0.0
var time_since_last_progress := 0.0
var total_progress := 0.0

var _checkpoint_count := 0
var _next_checkpoint := 1
var _last_valid_checkpoint_transform := Transform2D.IDENTITY
var _configured := false

@onready var vehicle: CharacterBody2D = get_parent() as CharacterBody2D


func _physics_process(delta: float) -> void:
	if not _configured:
		return

	lap_time += delta
	time_since_last_progress += delta
	timing_updated.emit(lap_time, time_since_last_progress)


func _unhandled_input(event: InputEvent) -> void:
	if not allow_manual_respawn or not _configured:
		return
	if event.is_action_pressed("respawn_car") and not event.is_echo():
		respawn_at_last_checkpoint()
		get_viewport().set_input_as_handled()


func configure(total_checkpoint_count: int, finish_transform: Transform2D) -> void:
	if _configured:
		return
	if total_checkpoint_count < 2:
		push_error("RaceProgressTracker requires a finish line and at least one checkpoint.")
		return

	_checkpoint_count = total_checkpoint_count
	_last_valid_checkpoint_transform = finish_transform
	_next_checkpoint = 1
	_configured = true
	_emit_progress()


func is_configured() -> bool:
	return _configured


func try_validate_checkpoint(
	checkpoint_index: int,
	checkpoint_transform: Transform2D
) -> bool:
	if not _configured:
		return false
	if checkpoint_index != _next_checkpoint:
		checkpoint_rejected.emit(_next_checkpoint, checkpoint_index)
		return false

	current_checkpoint = checkpoint_index
	total_checkpoints_passed += 1
	total_progress = float(total_checkpoints_passed)
	time_since_last_progress = 0.0
	_last_valid_checkpoint_transform = checkpoint_transform

	if checkpoint_index == 0:
		var completed_lap := current_lap
		var completed_time := lap_time
		current_lap += 1
		lap_time = 0.0
		_next_checkpoint = 1
		lap_completed.emit(completed_lap, completed_time)
	else:
		_next_checkpoint = (checkpoint_index + 1) % _checkpoint_count

	_emit_progress()
	return true


func respawn_at_last_checkpoint() -> void:
	if not _configured or vehicle == null:
		return

	vehicle.global_transform = _last_valid_checkpoint_transform
	if vehicle.has_method("reset_motion"):
		vehicle.reset_motion()
	else:
		vehicle.velocity = Vector2.ZERO


func get_checkpoint_count() -> int:
	return _checkpoint_count


func get_next_checkpoint() -> int:
	return _next_checkpoint


func get_total_progress() -> float:
	return total_progress


func _emit_progress() -> void:
	progress_changed.emit(
		current_lap,
		current_checkpoint,
		_checkpoint_count,
		total_progress
	)
