class_name NeuralGenome
extends Resource

@export var genome_id := "UNASSIGNED"
@export var seed := 0
@export var generation := 0
@export var parent_id := "INITIAL_RANDOM"
@export var is_elite := false
@export var is_mutant := false
@export var mutation_count := 0
@export var input_count := 0
@export var hidden_count := 0
@export var output_count := 0
@export var input_hidden_weights := PackedFloat32Array()
@export var hidden_biases := PackedFloat32Array()
@export var hidden_output_weights := PackedFloat32Array()
@export var output_biases := PackedFloat32Array()


func configure_random(
	new_input_count: int,
	new_hidden_count: int,
	new_output_count: int,
	random_seed: int,
	weight_scale := 1.0,
	identifier := ""
) -> void:
	input_count = maxi(new_input_count, 0)
	hidden_count = maxi(new_hidden_count, 0)
	output_count = maxi(new_output_count, 0)
	seed = random_seed
	genome_id = identifier if not identifier.is_empty() else "GENOME-%d" % seed
	generation = 1
	parent_id = "INITIAL_RANDOM"
	is_elite = false
	is_mutant = false
	mutation_count = 0

	var random := RandomNumberGenerator.new()
	random.seed = seed
	var hidden_deviation := weight_scale * sqrt(
		2.0 / maxf(float(input_count + hidden_count), 1.0)
	)
	var output_deviation := weight_scale * sqrt(
		2.0 / maxf(float(hidden_count + output_count), 1.0)
	)

	input_hidden_weights.resize(input_count * hidden_count)
	for index in range(input_hidden_weights.size()):
		input_hidden_weights[index] = random.randfn(0.0, hidden_deviation)
	hidden_biases.resize(hidden_count)
	for index in range(hidden_biases.size()):
		hidden_biases[index] = random.randfn(0.0, hidden_deviation * 0.25)

	hidden_output_weights.resize(hidden_count * output_count)
	for index in range(hidden_output_weights.size()):
		hidden_output_weights[index] = random.randfn(0.0, output_deviation)
	output_biases.resize(output_count)
	for index in range(output_biases.size()):
		output_biases[index] = random.randfn(0.0, output_deviation * 0.25)


func is_valid() -> bool:
	return (
		input_count > 0
		and hidden_count > 0
		and output_count > 0
		and input_hidden_weights.size() == input_count * hidden_count
		and hidden_biases.size() == hidden_count
		and hidden_output_weights.size() == hidden_count * output_count
		and output_biases.size() == output_count
	)


func copy_genome() -> NeuralGenome:
	var result := NeuralGenome.new()
	result.genome_id = genome_id
	result.seed = seed
	result.generation = generation
	result.parent_id = parent_id
	result.is_elite = is_elite
	result.is_mutant = is_mutant
	result.mutation_count = mutation_count
	result.input_count = input_count
	result.hidden_count = hidden_count
	result.output_count = output_count
	result.input_hidden_weights = input_hidden_weights.duplicate()
	result.hidden_biases = hidden_biases.duplicate()
	result.hidden_output_weights = hidden_output_weights.duplicate()
	result.output_biases = output_biases.duplicate()
	return result


func get_parameter_count() -> int:
	return (
		input_hidden_weights.size()
		+ hidden_biases.size()
		+ hidden_output_weights.size()
		+ output_biases.size()
	)


func get_parameters() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.append_array(input_hidden_weights)
	result.append_array(hidden_biases)
	result.append_array(hidden_output_weights)
	result.append_array(output_biases)
	return result


func has_identical_parameters(other: NeuralGenome) -> bool:
	return other != null and get_parameters() == other.get_parameters()


func save_to_file(path: String) -> Error:
	return ResourceSaver.save(self, path)
