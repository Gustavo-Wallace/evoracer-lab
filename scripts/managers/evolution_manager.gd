class_name EvolutionManager
extends Node

signal training_started(master_seed: int, population_size: int)
signal generation_started(generation: int, population_size: int)
signal generation_updated(status: Dictionary)
signal generation_finished(summary: Dictionary, results: Array[Dictionary])
signal training_stopped
signal pause_changed(is_paused: bool)
signal results_pin_changed(is_pinned: bool)

enum EvolutionState {
	INACTIVE,
	EVALUATING,
	RESULTS,
}

@export var config: EvolutionConfig
@export var evaluation_manager_path := NodePath("../NeuralEvaluationManager")
@export var race_manager_path := NodePath("../RaceManager")

var state := EvolutionState.INACTIVE
var current_generation := 0
var best_historical_fitness := -INF
var previous_generation_average := 0.0
var is_training_paused := false
var keep_results_open := false

var _evaluation: NeuralEvaluationManager
var _race_manager: RaceManager
var _current_population: Array[NeuralGenome] = []
var _generation_history: Array[Dictionary] = []
var _last_results: Array[Dictionary] = []
var _best_historical_genome: NeuralGenome
var _results_pause_remaining := 0.0
var _status_accumulator := 0.0
var _rng := RandomNumberGenerator.new()
var _last_parent_audit_passed := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_evaluation = get_node_or_null(
		evaluation_manager_path
	) as NeuralEvaluationManager
	_race_manager = get_node_or_null(race_manager_path) as RaceManager
	if _evaluation == null or _race_manager == null:
		push_error("EvolutionManager requires evaluation and race managers.")
		return
	if config == null or not config.is_valid():
		push_error("EvolutionManager requires a valid EvolutionConfig.")
		return
	_evaluation.evaluation_started.connect(_on_evaluation_started)
	_evaluation.evaluation_finished.connect(_on_evaluation_finished)
	_evaluation.evaluation_cancelled.connect(_on_evaluation_cancelled)


func _process(delta: float) -> void:
	if state == EvolutionState.INACTIVE:
		return
	_status_accumulator += delta
	if _status_accumulator >= 0.25:
		_status_accumulator = 0.0
		generation_updated.emit(get_status_snapshot())

	if (
		state == EvolutionState.RESULTS
		and not is_training_paused
		and not keep_results_open
	):
		_results_pause_remaining -= delta
		if _results_pause_remaining <= 0.0:
			advance_generation()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("start_neural_evaluation"):
		start_training()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_evolution") and is_training_active():
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("advance_evolution") and is_training_active():
		advance_generation()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart_evolution"):
		start_training()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pin_evolution_results") and is_training_active():
		keep_results_open = not keep_results_open
		results_pin_changed.emit(keep_results_open)
		generation_updated.emit(get_status_snapshot())
		get_viewport().set_input_as_handled()


func start_training() -> void:
	if _evaluation == null or _race_manager == null or config == null:
		return
	_set_paused(false)
	state = EvolutionState.EVALUATING
	current_generation = 1
	best_historical_fitness = -INF
	previous_generation_average = 0.0
	_current_population.clear()
	_generation_history.clear()
	_last_results.clear()
	_best_historical_genome = null
	_results_pause_remaining = 0.0
	_status_accumulator = 0.0
	_last_parent_audit_passed = true
	_rng.seed = config.master_seed
	training_started.emit(config.master_seed, config.population_size)
	generation_started.emit(current_generation, config.population_size)
	_evaluation.start_seeded_evaluation(
		config.population_size,
		config.master_seed
	)


func stop_training() -> void:
	if state == EvolutionState.INACTIVE:
		return
	_set_paused(false)
	state = EvolutionState.INACTIVE
	training_stopped.emit()


func toggle_pause() -> void:
	_set_paused(not is_training_paused)


func advance_generation() -> void:
	if state != EvolutionState.RESULTS or _last_results.is_empty():
		return
	_set_paused(false)
	var next_population := _build_next_population(_last_results)
	if next_population.size() != config.population_size:
		push_error("Evolution failed to build a complete population.")
		stop_training()
		return
	current_generation += 1
	_current_population = _copy_population(next_population)
	state = EvolutionState.EVALUATING
	_results_pause_remaining = 0.0
	generation_started.emit(current_generation, _current_population.size())
	_evaluation.start_evaluation_with_genomes(_current_population)


func is_training_active() -> bool:
	return state != EvolutionState.INACTIVE


func get_generation_history() -> Array[Dictionary]:
	return _generation_history.duplicate(true)


func get_last_results() -> Array[Dictionary]:
	return _last_results.duplicate(true)


func get_current_population() -> Array[NeuralGenome]:
	return _copy_population(_current_population)


func get_status_snapshot() -> Dictionary:
	var live := _evaluation.get_live_fitness_summary() if (
		_evaluation != null and state == EvolutionState.EVALUATING
	) else {}
	var current_best := float(live.get("best_fitness", 0.0))
	if state == EvolutionState.RESULTS and not _last_results.is_empty():
		current_best = float(_last_results[0].get("fitness", 0.0))
	return {
		"active": is_training_active(),
		"state": EvolutionState.keys()[state],
		"generation": current_generation,
		"active_agents": int(live.get("active_agents", 0)),
		"population_size": config.population_size if config != null else 0,
		"best_current": current_best,
		"best_historical": (
			best_historical_fitness if best_historical_fitness > -INF else 0.0
		),
		"previous_average": previous_generation_average,
		"paused": is_training_paused,
		"results_pinned": keep_results_open,
		"results_pause": maxf(_results_pause_remaining, 0.0),
		"parent_audit_passed": _last_parent_audit_passed,
		"master_seed": config.master_seed if config != null else 0,
	}


func _on_evaluation_started(_duration: float, _agent_count: int) -> void:
	if state != EvolutionState.EVALUATING:
		return
	if _current_population.is_empty():
		_current_population = _race_manager.get_neural_genome_copies()


func _on_evaluation_finished(results: Array[Dictionary]) -> void:
	if state != EvolutionState.EVALUATING:
		return
	_last_results = results.duplicate(true)
	if _last_results.is_empty():
		push_error("Evolution generation ended without results.")
		stop_training()
		return

	var fitness_sum := 0.0
	var worst_fitness := INF
	var best_progress := 0.0
	for result in _last_results:
		fitness_sum += float(result["fitness"])
		worst_fitness = minf(worst_fitness, float(result["fitness"]))
		best_progress = maxf(best_progress, float(result["progress"]))
	previous_generation_average = fitness_sum / float(_last_results.size())
	var best_fitness := float(_last_results[0]["fitness"])
	var champion := _find_genome(String(_last_results[0]["genome_id"]))
	if best_fitness > best_historical_fitness:
		best_historical_fitness = best_fitness
		_best_historical_genome = champion.copy_genome() if champion != null else null

	var summary := {
		"generation": current_generation,
		"best_fitness": best_fitness,
		"average_fitness": previous_generation_average,
		"worst_fitness": worst_fitness,
		"best_progress": best_progress,
		"champion_checkpoints": int(_last_results[0]["checkpoints"]),
		"champion_id": String(_last_results[0]["genome_id"]),
		"diversity": _calculate_population_diversity(_current_population),
		"master_seed": config.master_seed,
	}
	_generation_history.append(summary.duplicate(true))
	state = EvolutionState.RESULTS
	_results_pause_remaining = config.result_pause_duration
	generation_finished.emit(summary, get_last_results())
	generation_updated.emit(get_status_snapshot())


func _on_evaluation_cancelled() -> void:
	stop_training()


func _build_next_population(
	ranked_results: Array[Dictionary]
) -> Array[NeuralGenome]:
	var ranked_genomes: Array[NeuralGenome] = []
	for result in ranked_results:
		var genome := _find_genome(String(result["genome_id"]))
		if genome != null:
			ranked_genomes.append(genome)
	if ranked_genomes.size() != config.population_size:
		push_error("Evolution could not match every result to its genome.")
		return []

	var parent_snapshots: Dictionary = {}
	for parent in ranked_genomes:
		parent_snapshots[parent.genome_id] = parent.get_parameters()

	var next_population: Array[NeuralGenome] = []
	var next_generation := current_generation + 1
	for elite_index in range(config.elite_count):
		var elite_parent := ranked_genomes[elite_index]
		var elite := elite_parent.copy_genome()
		elite.parent_id = elite_parent.genome_id
		elite.generation = next_generation
		elite.genome_id = "G%03d-E%02d" % [next_generation, elite_index + 1]
		elite.is_elite = true
		elite.is_mutant = false
		elite.mutation_count = 0
		next_population.append(elite)

	for child_index in range(config.elite_count, config.population_size):
		var parent := _select_tournament_parent(ranked_genomes)
		var child := parent.copy_genome()
		child.parent_id = parent.genome_id
		child.generation = next_generation
		child.genome_id = "G%03d-M%02d" % [next_generation, child_index + 1]
		child.seed = int(_rng.randi())
		child.is_elite = false
		child.is_mutant = true
		child.mutation_count = _mutate_genome(child)
		next_population.append(child)

	_last_parent_audit_passed = _audit_deep_copies(
		ranked_genomes,
		next_population,
		parent_snapshots
	)
	if not _last_parent_audit_passed:
		push_error("Evolution parent/deep-copy audit failed.")
		return []
	return next_population


func _select_tournament_parent(
	ranked_genomes: Array[NeuralGenome]
) -> NeuralGenome:
	var winner_index := ranked_genomes.size() - 1
	for _draw in range(config.tournament_size):
		winner_index = mini(winner_index, _rng.randi_range(0, ranked_genomes.size() - 1))
	return ranked_genomes[winner_index]


func _mutate_genome(genome: NeuralGenome) -> int:
	var mutation_total := 0
	var result := _mutate_parameters(genome.input_hidden_weights)
	genome.input_hidden_weights = result["values"]
	mutation_total += int(result["count"])
	result = _mutate_parameters(genome.hidden_biases)
	genome.hidden_biases = result["values"]
	mutation_total += int(result["count"])
	result = _mutate_parameters(genome.hidden_output_weights)
	genome.hidden_output_weights = result["values"]
	mutation_total += int(result["count"])
	result = _mutate_parameters(genome.output_biases)
	genome.output_biases = result["values"]
	mutation_total += int(result["count"])
	return mutation_total


func _mutate_parameters(source: PackedFloat32Array) -> Dictionary:
	var values := source.duplicate()
	var mutation_count := 0
	for index in range(values.size()):
		if _rng.randf() <= config.mutation_chance:
			values[index] = clampf(
				values[index] + _rng.randfn(0.0, config.mutation_intensity),
				-config.maximum_absolute_parameter,
				config.maximum_absolute_parameter
			)
			mutation_count += 1
	return {"values": values, "count": mutation_count}


func _audit_deep_copies(
	parents: Array[NeuralGenome],
	children: Array[NeuralGenome],
	parent_snapshots: Dictionary
) -> bool:
	for child in children:
		for parent in parents:
			if child == parent:
				return false
		var parent := _find_genome_in(child.parent_id, parents)
		if parent == null:
			return false
		if child.is_elite and not child.has_identical_parameters(parent):
			return false
	for parent in parents:
		var snapshot := parent_snapshots.get(parent.genome_id) as PackedFloat32Array
		if parent.get_parameters() != snapshot:
			return false
	return true


func _calculate_population_diversity(
	population: Array[NeuralGenome]
) -> float:
	if population.size() < 2:
		return 0.0
	var pair_total := 0.0
	var pair_count := 0
	for first_index in range(population.size() - 1):
		var first := population[first_index].get_parameters()
		for second_index in range(first_index + 1, population.size()):
			var second := population[second_index].get_parameters()
			var squared_difference := 0.0
			for parameter_index in range(first.size()):
				var difference := first[parameter_index] - second[parameter_index]
				squared_difference += difference * difference
			pair_total += sqrt(squared_difference / maxf(float(first.size()), 1.0))
			pair_count += 1
	return pair_total / float(pair_count) if pair_count > 0 else 0.0


func _find_genome(genome_id: String) -> NeuralGenome:
	return _find_genome_in(genome_id, _current_population)


func _find_genome_in(
	genome_id: String,
	population: Array[NeuralGenome]
) -> NeuralGenome:
	for genome in population:
		if genome.genome_id == genome_id:
			return genome
	return null


func _copy_population(source: Array[NeuralGenome]) -> Array[NeuralGenome]:
	var result: Array[NeuralGenome] = []
	for genome in source:
		result.append(genome.copy_genome())
	return result


func _set_paused(is_paused: bool) -> void:
	is_training_paused = is_paused
	if _evaluation != null:
		_evaluation.set_evaluation_paused(is_paused)
	if _race_manager != null:
		_race_manager.process_mode = (
			Node.PROCESS_MODE_DISABLED if is_paused else Node.PROCESS_MODE_INHERIT
		)
	pause_changed.emit(is_paused)
	if is_training_active():
		generation_updated.emit(get_status_snapshot())
