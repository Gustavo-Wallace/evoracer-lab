class_name FeedForwardNetwork
extends RefCounted

var _genome: NeuralGenome


func configure(source_genome: NeuralGenome) -> bool:
	if source_genome == null or not source_genome.is_valid():
		_genome = null
		return false
	_genome = source_genome.copy_genome()
	return true


func evaluate(inputs: PackedFloat32Array) -> PackedFloat32Array:
	var outputs := PackedFloat32Array()
	if _genome == null or inputs.size() != _genome.input_count:
		return outputs

	var hidden_values := PackedFloat32Array()
	hidden_values.resize(_genome.hidden_count)
	for hidden_index in range(_genome.hidden_count):
		var sum := _genome.hidden_biases[hidden_index]
		var weight_offset := hidden_index * _genome.input_count
		for input_index in range(_genome.input_count):
			sum += (
				inputs[input_index]
				* _genome.input_hidden_weights[weight_offset + input_index]
			)
		hidden_values[hidden_index] = tanh(sum)

	outputs.resize(_genome.output_count)
	for output_index in range(_genome.output_count):
		var sum := _genome.output_biases[output_index]
		var weight_offset := output_index * _genome.hidden_count
		for hidden_index in range(_genome.hidden_count):
			sum += (
				hidden_values[hidden_index]
				* _genome.hidden_output_weights[weight_offset + hidden_index]
			)
		outputs[output_index] = clampf(tanh(sum), -1.0, 1.0)
	return outputs


func get_genome_copy() -> NeuralGenome:
	return _genome.copy_genome() if _genome != null else null
