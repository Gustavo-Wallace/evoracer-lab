class_name NeuralNetworkConfig
extends Resource

@export_category("Architecture")
@export_range(1, 128, 1) var hidden_neuron_count := 12
@export_range(3, 3, 1) var output_neuron_count := 3

@export_category("Initialization")
@export var random_seed_base := 47001
@export_range(0.01, 4.0, 0.01) var random_weight_scale := 1.0
@export_range(1, 1000000, 1) var reroll_seed_stride := 1000


func is_valid_for(input_count: int) -> bool:
	return (
		input_count > 0
		and hidden_neuron_count > 0
		and output_neuron_count == 3
	)
