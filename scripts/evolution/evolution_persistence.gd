class_name EvolutionPersistence
extends RefCounted

const DATA_VERSION := 1
const CHAMPION_SCHEMA := "evoracer_champion"
const HISTORY_SCHEMA := "evoracer_generation_history"


static func save_champion(path: String, champion: HistoricalChampion) -> Error:
	if champion == null or not champion.is_valid():
		return ERR_INVALID_DATA
	var genome := champion.get_genome_copy()
	var metadata := champion.get_metadata()
	var data := {
		"schema": CHAMPION_SCHEMA,
		"version": DATA_VERSION,
		"champion": {
			"id": metadata["id"],
			"generation": metadata["generation"],
			"fitness": metadata["fitness"],
			"progress": metadata["progress"],
			"checkpoints": metadata["checkpoints"],
			"laps": metadata["laps"],
			"seed": metadata["seed"],
			"track_id": metadata["track_id"],
			"architecture": metadata["architecture"],
			"fitness_parameters": metadata["fitness_parameters"],
			"trajectory": _vectors_to_json(metadata["trajectory"]),
			"offroad_points": _vectors_to_json(metadata["offroad_points"]),
			"checkpoint_points": _vectors_to_json(metadata["checkpoint_points"]),
			"end_position": _vector_to_json(metadata["end_position"]),
		},
		"genome": _genome_to_dictionary(genome),
	}
	return _write_json(path, data)


static func load_champion(
	path: String,
	expected_track_id: String,
	expected_architecture: Dictionary
) -> Dictionary:
	var read_result := _read_json(path)
	if not bool(read_result.get("ok", false)):
		return read_result
	var data: Dictionary = read_result["data"]
	if data.get("schema") != CHAMPION_SCHEMA:
		return _failure("Champion schema is incompatible.")
	if int(data.get("version", -1)) != DATA_VERSION:
		return _failure("Champion data version is incompatible.")
	var champion_data := data.get("champion", {}) as Dictionary
	if String(champion_data.get("track_id", "")) != expected_track_id:
		return _failure("Champion belongs to a different track.")
	var architecture := champion_data.get("architecture", {}) as Dictionary
	for key in ["inputs", "hidden", "outputs"]:
		if int(architecture.get(key, -1)) != int(expected_architecture.get(key, -2)):
			return _failure("Champion neural architecture is incompatible.")
	var genome_result := _genome_from_dictionary(
		data.get("genome", {}) as Dictionary
	)
	if not bool(genome_result.get("ok", false)):
		return genome_result
	var result_data := {
		"fitness": float(champion_data.get("fitness", -INF)),
		"progress": float(champion_data.get("progress", 0.0)),
		"checkpoints": int(champion_data.get("checkpoints", 0)),
		"laps": int(champion_data.get("laps", 0)),
		"trajectory": _vectors_from_json(champion_data.get("trajectory", [])),
		"offroad_points": _vectors_from_json(champion_data.get("offroad_points", [])),
		"checkpoint_points": _vectors_from_json(
			champion_data.get("checkpoint_points", [])
		),
		"end_position": _vector_from_json(
			champion_data.get("end_position", [0.0, 0.0])
		),
	}
	var champion := HistoricalChampion.new()
	champion.initialize(
		genome_result["genome"] as NeuralGenome,
		result_data,
		int(champion_data.get("generation", 0)),
		expected_track_id,
		champion_data.get("fitness_parameters", {}) as Dictionary
	)
	champion.champion_id = String(champion_data.get("id", champion.champion_id))
	return {"ok": true, "champion": champion}


static func save_history(
	path: String,
	track_id: String,
	entries: Array[Dictionary]
) -> Error:
	return _write_json(path, {
		"schema": HISTORY_SCHEMA,
		"version": DATA_VERSION,
		"track_id": track_id,
		"generations": entries,
	})


static func load_history(path: String, expected_track_id: String) -> Dictionary:
	var read_result := _read_json(path)
	if not bool(read_result.get("ok", false)):
		return read_result
	var data: Dictionary = read_result["data"]
	if data.get("schema") != HISTORY_SCHEMA:
		return _failure("Generation history schema is incompatible.")
	if int(data.get("version", -1)) != DATA_VERSION:
		return _failure("Generation history version is incompatible.")
	if String(data.get("track_id", "")) != expected_track_id:
		return _failure("Generation history belongs to a different track.")
	var entries: Array[Dictionary] = []
	for value in data.get("generations", []):
		if value is Dictionary:
			entries.append((value as Dictionary).duplicate(true))
	return {"ok": true, "entries": entries}


static func _write_json(path: String, data: Dictionary) -> Error:
	var directory := path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory)
	)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  "))
	return OK


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": true, "error": "File not found."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not open data file.")
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK or not json.data is Dictionary:
		return _failure("Data file is corrupted or is not valid JSON.")
	return {"ok": true, "data": json.data as Dictionary}


static func _genome_to_dictionary(genome: NeuralGenome) -> Dictionary:
	return {
		"genome_id": genome.genome_id,
		"seed": genome.seed,
		"generation": genome.generation,
		"parent_id": genome.parent_id,
		"is_elite": genome.is_elite,
		"is_mutant": genome.is_mutant,
		"mutation_count": genome.mutation_count,
		"input_count": genome.input_count,
		"hidden_count": genome.hidden_count,
		"output_count": genome.output_count,
		"input_hidden_weights": Array(genome.input_hidden_weights),
		"hidden_biases": Array(genome.hidden_biases),
		"hidden_output_weights": Array(genome.hidden_output_weights),
		"output_biases": Array(genome.output_biases),
	}


static func _genome_from_dictionary(data: Dictionary) -> Dictionary:
	var genome := NeuralGenome.new()
	genome.genome_id = String(data.get("genome_id", ""))
	genome.seed = int(data.get("seed", 0))
	genome.generation = int(data.get("generation", 0))
	genome.parent_id = String(data.get("parent_id", ""))
	genome.is_elite = bool(data.get("is_elite", false))
	genome.is_mutant = bool(data.get("is_mutant", false))
	genome.mutation_count = int(data.get("mutation_count", 0))
	genome.input_count = int(data.get("input_count", 0))
	genome.hidden_count = int(data.get("hidden_count", 0))
	genome.output_count = int(data.get("output_count", 0))
	genome.input_hidden_weights = PackedFloat32Array(
		data.get("input_hidden_weights", [])
	)
	genome.hidden_biases = PackedFloat32Array(data.get("hidden_biases", []))
	genome.hidden_output_weights = PackedFloat32Array(
		data.get("hidden_output_weights", [])
	)
	genome.output_biases = PackedFloat32Array(data.get("output_biases", []))
	if not genome.is_valid():
		return _failure("Champion genome parameters are incomplete or corrupted.")
	return {"ok": true, "genome": genome}


static func _vectors_to_json(points: PackedVector2Array) -> Array:
	var result := []
	for point in points:
		result.append(_vector_to_json(point))
	return result


static func _vectors_from_json(values: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not values is Array:
		return result
	for value in values:
		result.append(_vector_from_json(value))
	return result


static func _vector_to_json(value: Vector2) -> Array:
	return [value.x, value.y]


static func _vector_from_json(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "missing": false, "error": message}
