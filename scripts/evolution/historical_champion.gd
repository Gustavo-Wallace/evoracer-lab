class_name HistoricalChampion
extends RefCounted

var champion_id := ""
var generation := 0
var fitness := -INF
var progress := 0.0
var checkpoints := 0
var laps := 0
var seed := 0
var track_id := ""
var architecture: Dictionary = {}
var fitness_parameters: Dictionary = {}
var trajectory := PackedVector2Array()
var offroad_points := PackedVector2Array()
var checkpoint_points := PackedVector2Array()
var end_position := Vector2.ZERO
var _genome: NeuralGenome


func initialize(
	source_genome: NeuralGenome,
	result: Dictionary,
	champion_generation: int,
	champion_track_id: String,
	fitness_snapshot: Dictionary
) -> void:
	_genome = source_genome.copy_genome()
	champion_id = source_genome.genome_id
	generation = champion_generation
	fitness = float(result.get("fitness", -INF))
	progress = float(result.get("progress", 0.0))
	checkpoints = int(result.get("checkpoints", 0))
	laps = int(result.get("laps", 0))
	seed = source_genome.seed
	track_id = champion_track_id
	architecture = {
		"inputs": source_genome.input_count,
		"hidden": source_genome.hidden_count,
		"outputs": source_genome.output_count,
	}
	fitness_parameters = fitness_snapshot.duplicate(true)
	trajectory = _copy_vector_array(result.get("trajectory", PackedVector2Array()))
	offroad_points = _copy_vector_array(
		result.get("offroad_points", PackedVector2Array())
	)
	checkpoint_points = _copy_vector_array(
		result.get("checkpoint_points", PackedVector2Array())
	)
	end_position = result.get("end_position", Vector2.ZERO) as Vector2


func get_genome_copy() -> NeuralGenome:
	return _genome.copy_genome() if _genome != null else null


func get_metadata() -> Dictionary:
	return {
		"id": champion_id,
		"generation": generation,
		"fitness": fitness,
		"progress": progress,
		"checkpoints": checkpoints,
		"laps": laps,
		"seed": seed,
		"track_id": track_id,
		"architecture": architecture.duplicate(true),
		"fitness_parameters": fitness_parameters.duplicate(true),
		"trajectory": trajectory.duplicate(),
		"offroad_points": offroad_points.duplicate(),
		"checkpoint_points": checkpoint_points.duplicate(),
		"end_position": end_position,
	}


func is_valid() -> bool:
	return _genome != null and _genome.is_valid() and not champion_id.is_empty()


func _copy_vector_array(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	return PackedVector2Array()
