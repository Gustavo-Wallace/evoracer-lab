class_name EvolutionHistoryHUD
extends CanvasLayer

@export var evolution_manager_path := NodePath("../EvolutionManager")

var _evolution: EvolutionManager

@onready var panel: PanelContainer = $Panel
@onready var header: Label = $Panel/Content/Header
@onready var record_label: Label = $Panel/Content/Record
@onready var last_label: Label = $Panel/Content/Last
@onready var progress_label: Label = $Panel/Content/Progress
@onready var recent_label: Label = $Panel/Content/Recent
@onready var graph: EvolutionGraph = $Panel/Content/Graph


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_evolution = get_node_or_null(evolution_manager_path) as EvolutionManager
	panel.visible = false
	if _evolution == null:
		push_error("EvolutionHistoryHUD requires EvolutionManager.")
		return
	_evolution.generation_started.connect(_on_generation_changed)
	_evolution.generation_updated.connect(_on_generation_updated)
	_evolution.generation_finished.connect(_on_generation_finished)
	_evolution.historical_champion_updated.connect(_on_champion_updated)
	_evolution.persistence_warning.connect(_on_persistence_warning)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_evolution_panel") and not event.is_echo():
		panel.visible = not panel.visible
		if panel.visible:
			_refresh()
		get_viewport().set_input_as_handled()


func _on_generation_changed(_generation: int, _population: int) -> void:
	_refresh()


func _on_generation_updated(_status: Dictionary) -> void:
	if panel.visible:
		_refresh_header()


func _on_generation_finished(
	_summary: Dictionary,
	_results: Array[Dictionary]
) -> void:
	_refresh()


func _on_champion_updated(_metadata: Dictionary) -> void:
	_refresh()


func _on_persistence_warning(message: String) -> void:
	if panel.visible:
		recent_label.text = "SAVE WARNING: %s" % message


func _refresh() -> void:
	if _evolution == null:
		return
	_refresh_header()
	var champion := _evolution.get_historical_champion_metadata()
	record_label.text = "RECORD  %.0f  |  %s  |  GEN %03d" % [
		float(champion.get("fitness", 0.0)),
		String(champion.get("id", "NONE")),
		int(champion.get("generation", 0)),
	]
	var history := _evolution.get_generation_history()
	var last: Dictionary = history[-1] if not history.is_empty() else {}
	last_label.text = "LAST  BEST %.0f  AVG %.0f  WORST %.0f" % [
		float(last.get("best_fitness", 0.0)),
		float(last.get("average_fitness", 0.0)),
		float(last.get("worst_fitness", 0.0)),
	]
	progress_label.text = "CHAMP  PROG %.2f  CP %d  LAPS %d  ROAD %.1f%%" % [
		float(champion.get("progress", 0.0)),
		int(champion.get("checkpoints", 0)),
		int(champion.get("laps", 0)),
		float(last.get("average_asphalt_ratio", 0.0)) * 100.0,
	]
	var recent_lines := PackedStringArray()
	for entry in _evolution.get_recent_generation_history(5):
		recent_lines.append("G%03d  B %8.0f  A %8.0f  P %.2f" % [
			int(entry.get("generation", 0)),
			float(entry.get("best_fitness", 0.0)),
			float(entry.get("average_fitness", 0.0)),
			float(entry.get("best_progress", 0.0)),
		])
	recent_label.text = "\n".join(recent_lines) if not recent_lines.is_empty() else "NO COMPLETED GENERATIONS"
	var persistence_message := String(
		_evolution.get_status_snapshot().get("persistence_warning", "")
	)
	if not persistence_message.is_empty():
		recent_label.text += "\nWARNING: %s" % persistence_message
	graph.set_history(history)


func _refresh_header() -> void:
	var status := _evolution.get_status_snapshot()
	header.text = "EVOLUTION  GEN %03d  |  [Y] HIDE" % int(
		status.get("generation", 0)
	)
