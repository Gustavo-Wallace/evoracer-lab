class_name EvolutionConfig
extends Resource

@export_category("Population")
@export_range(2, 24, 1) var population_size := 12
@export_range(1, 23, 1) var elite_count := 2
@export_range(2, 24, 1) var tournament_size := 3

@export_category("Mutation")
@export_range(0.0, 1.0, 0.01) var mutation_chance := 0.05
@export_range(0.0, 2.0, 0.01) var mutation_intensity := 0.20
@export_range(0.1, 20.0, 0.1) var maximum_absolute_parameter := 5.0

@export_category("Generations")
@export var master_seed := 947001
@export_range(0.0, 30.0, 0.25) var result_pause_duration := 3.0


func is_valid() -> bool:
	return (
		population_size >= 2
		and elite_count >= 1
		and elite_count < population_size
		and tournament_size >= 2
		and tournament_size <= population_size
		and mutation_chance >= 0.0
		and mutation_chance <= 1.0
		and mutation_intensity >= 0.0
	)
