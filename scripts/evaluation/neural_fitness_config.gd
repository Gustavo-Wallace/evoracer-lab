class_name NeuralFitnessConfig
extends Resource

@export_category("Evaluation")
@export_range(2, 24, 1) var agent_count := 12
@export_range(10.0, 1800.0, 5.0) var maximum_duration := 120.0
@export_range(0.05, 1.0, 0.05) var sample_interval := 0.1

@export_category("Termination")
@export_range(0.0, 30.0, 0.5) var initial_grace_time := 4.0
@export_range(2.0, 120.0, 1.0) var no_progress_time_limit := 20.0
@export_range(2.0, 60.0, 1.0) var stationary_time_limit := 10.0
@export_range(2.0, 60.0, 1.0) var wrong_direction_time_limit := 7.0
@export var stationary_speed_threshold := 24.0
@export var wrong_direction_minimum_speed := 45.0
@export_range(-1.0, 0.0, 0.05) var wrong_direction_alignment := -0.25

@export_category("Primary Fitness")
@export var lap_tier_weight := 250000.0
@export var non_lap_component_limit := 100000.0
@export var valid_progress_weight := 1200.0
@export var valid_checkpoint_weight := 4000.0
@export var finish_line_crossing_weight := 15000.0
@export var target_lap_time := 80.0
@export var fast_lap_second_weight := 200.0
@export var fast_lap_bonus_limit := 15000.0

@export_category("Secondary Bonuses")
@export var useful_speed_weight := 3000.0
@export var asphalt_ratio_weight := 2500.0
@export var best_position_weight := 1000.0
@export var final_position_weight := 750.0
@export var leader_second_weight := 10.0
@export var overtake_weight := 100.0

@export_category("Penalties")
@export var stationary_second_penalty := 120.0
@export var wrong_direction_second_penalty := 300.0
@export var grass_second_penalty := 60.0
@export var barrier_contact_penalty := 250.0
@export var barrier_second_penalty := 80.0
@export_range(0.0, 30.0, 0.5) var no_progress_penalty_grace := 4.0
@export var no_progress_second_penalty := 150.0
@export var spinning_second_penalty := 200.0
@export var spinning_angular_speed := 2.0
@export var spinning_linear_speed_limit := 60.0


func is_valid() -> bool:
	return (
		agent_count >= 2
		and maximum_duration > 0.0
		and sample_interval > 0.0
		and lap_tier_weight > non_lap_component_limit * 2.0
	)
