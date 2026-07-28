class_name NeuralEvaluationHUD
extends CanvasLayer

@export var evaluation_manager_path := NodePath("../NeuralEvaluationManager")
@export var evolution_manager_path := NodePath("../EvolutionManager")
@export var camera_path := NodePath("../RaceCamera")

var _manager: NeuralEvaluationManager
var _camera: RaceCamera
var _evolution: EvolutionManager
var _has_results := false
var _results: Array[Dictionary] = []
var _generation := 0

@onready var status_panel: PanelContainer = $Layout/StatusPanel
@onready var status_label: Label = $Layout/StatusPanel/StatusLabel
@onready var results_panel: PanelContainer = $Layout/ResultsPanel
@onready var title_label: Label = $Layout/ResultsPanel/Content/TitleLabel
@onready var rows: RichTextLabel = $Layout/ResultsPanel/Content/Rows


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_manager = get_node_or_null(evaluation_manager_path) as NeuralEvaluationManager
	_evolution = get_node_or_null(evolution_manager_path) as EvolutionManager
	_camera = get_node_or_null(camera_path) as RaceCamera
	status_panel.visible = false
	results_panel.visible = false
	if _manager == null:
		push_error("NeuralEvaluationHUD requires NeuralEvaluationManager.")
		return
	_manager.evaluation_started.connect(_on_evaluation_started)
	_manager.evaluation_updated.connect(_on_evaluation_updated)
	_manager.evaluation_finished.connect(_on_evaluation_finished)
	_manager.evaluation_cancelled.connect(_on_evaluation_cancelled)
	if _evolution != null:
		_evolution.generation_started.connect(_on_generation_started)
		_evolution.generation_updated.connect(_on_generation_updated)
		_evolution.generation_finished.connect(_on_generation_finished)
		_evolution.training_stopped.connect(_on_training_stopped)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_evaluation_results") and not event.is_echo():
		if _has_results:
			results_panel.visible = not results_panel.visible
		get_viewport().set_input_as_handled()


func _on_evaluation_started(maximum_duration: float, agent_count: int) -> void:
	_has_results = false
	_results.clear()
	results_panel.visible = false
	status_panel.visible = true
	if _evolution != null and _evolution.is_training_active():
		return
	status_label.text = "NEURAL EVALUATION  00.0/%05.1fs  %02d/%02d ACTIVE  [F] RESTART  [B] EXIT" % [
		maximum_duration,
		agent_count,
		agent_count,
	]


func _on_evaluation_updated(
	elapsed_time: float,
	maximum_duration: float,
	active_agents: int,
	total_agents: int
) -> void:
	if _evolution != null and _evolution.is_training_active():
		return
	status_label.text = "NEURAL EVALUATION  %05.1f/%05.1fs  %02d/%02d ACTIVE  [F] RESTART  [B] EXIT" % [
		elapsed_time,
		maximum_duration,
		active_agents,
		total_agents,
	]


func _on_evaluation_finished(results: Array[Dictionary]) -> void:
	_results = results.duplicate(true)
	_has_results = true
	if _evolution != null and _evolution.is_training_active():
		return
	status_panel.visible = true
	status_label.text = "EVALUATION COMPLETE  [H] RESULTS  [F] RESTART  [B] EXIT"
	results_panel.visible = true
	_update_results_table()


func _on_evaluation_cancelled() -> void:
	_has_results = false
	_results.clear()
	status_panel.visible = false
	results_panel.visible = false


func _on_generation_started(generation: int, _population_size: int) -> void:
	_generation = generation
	status_panel.visible = true
	results_panel.visible = false


func _on_generation_updated(status: Dictionary) -> void:
	if not bool(status.get("active", false)):
		return
	var state_name := String(status.get("state", "INACTIVE"))
	var flags := ""
	if bool(status.get("paused", false)):
		flags += " PAUSED"
	if bool(status.get("results_pinned", false)):
		flags += " RESULTS PINNED"
	status_panel.visible = true
	status_label.text = "GEN %03d | %02d/%02d ACTIVE | BEST %.0f | ALL %.0f | PREV AVG %.0f | %s%s | [SPACE] PAUSE [ENTER] NEXT [U] HOLD" % [
		int(status.get("generation", 0)),
		int(status.get("active_agents", 0)),
		int(status.get("population_size", 0)),
		float(status.get("best_current", 0.0)),
		float(status.get("best_historical", 0.0)),
		float(status.get("previous_average", 0.0)),
		state_name,
		flags,
	]


func _on_generation_finished(
	summary: Dictionary,
	results: Array[Dictionary]
) -> void:
	_generation = int(summary.get("generation", _generation))
	_results = results.duplicate(true)
	_has_results = true
	results_panel.visible = true
	_update_results_table()
	status_label.text = "GEN %03d COMPLETE  CHAMP %s  FIT %.0f  AVG %.0f  DIV %.4f  [ENTER] NEXT  [U] HOLD  [H] HIDE" % [
		_generation,
		String(summary.get("champion_id", "--")),
		float(summary.get("best_fitness", 0.0)),
		float(summary.get("average_fitness", 0.0)),
		float(summary.get("diversity", 0.0)),
	]


func _on_training_stopped() -> void:
	_generation = 0


func _update_results_table() -> void:
	var followed_id := ""
	if _camera != null and _camera.get_target() != null:
		followed_id = _camera.get_target().vehicle_id
	var lines := PackedStringArray()
	for result in _results:
		var agent_id := String(result["agent_id"])
		var line := "%02d  %-9s FIT %9.0f  PROG %6.2f  CP %3d  LAP %d  AVG %5.1f  ROAD %5.1f%%  GRASS %5.1f%%  P%02d  OVT %2d" % [
			int(result["fitness_rank"]),
			agent_id,
			float(result["fitness"]),
			float(result["progress"]),
			int(result["checkpoints"]),
			int(result["laps"]),
			float(result["average_speed_kmh"]),
			float(result["asphalt_ratio"]) * 100.0,
			float(result["grass_ratio"]) * 100.0,
			int(result["final_position"]),
			int(result["overtakes"]),
		]
		if agent_id == followed_id:
			line = "[color=#ffd45e]>%s[/color]" % line
		elif int(result["fitness_rank"]) == 1:
			line = "[color=#8fe07d] %s[/color]" % line
		else:
			line = " %s" % line
		lines.append(line)
		lines.append(
			"    JUMP %.3f  REJECT D/O/T/R %d/%d/%d/%d  INVALID %s  TOTAL %s  LAPS %s  END %s" % [
				float(result["maximum_progress_jump"]),
				int(result["rejected_by_direction"]),
				int(result["rejected_by_order"]),
				int(result["rejected_by_timing"]),
				int(result["rejected_by_route"]),
				"YES" if bool(result["invalid_course_warning"]) else "NO",
				_format_time(float(result["total_time"])),
				_format_lap_times(result["lap_times"] as PackedFloat32Array),
				String(result["end_reason"]),
			]
		)
	for result in _results:
		lines.append(
			"GENOME %-12s  PARENT %-12s  SEED %-10d  %s  MUTATIONS %d" % [
				String(result.get("genome_id", "--")),
				String(result.get("parent_id", "--")),
				int(result.get("genome_seed", 0)),
				(
					"ELITE"
					if bool(result.get("genome_is_elite", false))
					else "MUTANT" if bool(result.get("genome_is_mutant", false))
					else "INITIAL"
				),
				int(result.get("genome_mutation_count", 0)),
			]
		)
	title_label.text = "GEN %03d FITNESS RESULTS  ·  %d AGENTS  ·  [H] HIDE" % [
		_generation,
		_results.size(),
	]
	rows.text = "\n".join(lines)


func _format_lap_times(lap_times: PackedFloat32Array) -> String:
	if lap_times.is_empty():
		return "--"
	var values := PackedStringArray()
	for lap_time in lap_times:
		values.append(_format_time(lap_time))
	return "/".join(values)


func _format_time(value: float) -> String:
	return "%02d:%04.1f" % [floori(value / 60.0), fmod(value, 60.0)]
