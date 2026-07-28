class_name NeuralEvaluationRecord
extends RefCounted

var car: CarController
var agent_id := ""
var genome_id := ""
var genome_seed := 0
var parent_id := ""
var genome_generation := 0
var genome_is_elite := false
var genome_is_mutant := false
var genome_mutation_count := 0
var active := true
var end_reason: StringName = &"RUNNING"
var elapsed_time := 0.0
var end_time := 0.0
var total_race_time := 0.0

var max_continuous_progress := 0.0
var valid_checkpoints := 0
var completed_laps := 0
var best_position := 0
var final_position := 0
var overtakes := 0
var leader_time := 0.0

var speed_integral := 0.0
var useful_speed_integral := 0.0
var sampled_time := 0.0
var asphalt_time := 0.0
var grass_time := 0.0
var grass_penalty_time := 0.0
var grass_streak := 0.0
var stationary_time := 0.0
var wrong_direction_time := 0.0
var barrier_contact_time := 0.0
var barrier_contacts := 0
var no_progress_penalty_time := 0.0
var spinning_time := 0.0
var stationary_streak := 0.0
var wrong_direction_streak := 0.0
var lap_times := PackedFloat32Array()
var maximum_progress_jump := 0.0
var invalid_course_warning := false
var rejected_by_order := 0
var rejected_by_direction := 0
var rejected_by_timing := 0
var rejected_by_route := 0

var fitness := 0.0
var fitness_components: Dictionary = {}
var _last_barrier_contact := false
var _last_rotation := 0.0
var _maximum_speed_kmh := 1.0


func initialize(vehicle: CarController, controller: NeuralCarController) -> void:
	car = vehicle
	agent_id = vehicle.vehicle_id
	genome_id = (
		controller.genome.genome_id
		if controller != null and controller.genome != null
		else "NONE"
	)
	if controller != null and controller.genome != null:
		genome_seed = controller.genome.seed
		parent_id = controller.genome.parent_id
		genome_generation = controller.genome.generation
		genome_is_elite = controller.genome.is_elite
		genome_is_mutant = controller.genome.is_mutant
		genome_mutation_count = controller.genome.mutation_count
	best_position = 0
	_last_rotation = vehicle.rotation
	_maximum_speed_kmh = maxf(
		vehicle.maximum_forward_speed * vehicle.pixels_per_second_to_kmh,
		1.0
	)


func sample(
	delta: float,
	evaluation_time: float,
	progress: RaceProgressTracker,
	telemetry: CarRaceTelemetry,
	is_on_asphalt: bool,
	forward_alignment: float,
	config: NeuralFitnessConfig
) -> void:
	if not active or car == null:
		return

	elapsed_time = evaluation_time
	sampled_time += delta
	var speed_kmh := car.get_speed_kmh()
	speed_integral += speed_kmh * delta
	var useful_ratio := clampf(forward_alignment, 0.0, 1.0)
	if car.current_speed > 0.0 and is_on_asphalt:
		useful_speed_integral += speed_kmh * useful_ratio * delta

	if is_on_asphalt:
		asphalt_time += delta
		grass_streak = 0.0
	else:
		grass_time += delta
		grass_streak += delta
		if grass_streak > config.grass_penalty_grace:
			grass_penalty_time += delta

	if evaluation_time >= config.initial_grace_time:
		if absf(car.current_speed) < config.stationary_speed_threshold:
			stationary_streak += delta
			stationary_time += delta
		else:
			stationary_streak = 0.0

		var moving_in_wrong_direction := (
			absf(car.current_speed) >= config.wrong_direction_minimum_speed
			and forward_alignment <= config.wrong_direction_alignment
		)
		if moving_in_wrong_direction:
			wrong_direction_streak += delta
			wrong_direction_time += delta
		else:
			wrong_direction_streak = maxf(wrong_direction_streak - delta, 0.0)

	var touching_barrier := car.barrier_contact_time > 0.0
	if touching_barrier:
		barrier_contact_time += delta
		if not _last_barrier_contact:
			barrier_contacts += 1
	_last_barrier_contact = touching_barrier

	if progress != null:
		valid_checkpoints = maxi(valid_checkpoints, progress.total_checkpoints_passed)
		maximum_progress_jump = maxf(
			maximum_progress_jump,
			progress.maximum_progress_jump
		)
		invalid_course_warning = (
			invalid_course_warning
			or progress.invalid_course_warning
		)
		rejected_by_order = progress.rejected_by_order
		rejected_by_direction = progress.rejected_by_direction
		rejected_by_timing = progress.rejected_by_timing
		rejected_by_route = progress.rejected_by_route
		if progress.time_since_last_progress > config.no_progress_penalty_grace:
			no_progress_penalty_time += delta

	if telemetry != null:
		total_race_time = telemetry.total_race_time
		max_continuous_progress = maxf(
			max_continuous_progress,
			telemetry.continuous_progress
		)
		completed_laps = maxi(completed_laps, telemetry.completed_laps)
		# Ignore the arbitrary identifier tie-break at the untouched start line.
		if max_continuous_progress > 0.01:
			best_position = (
				telemetry.current_position
				if best_position <= 0
				else mini(best_position, telemetry.current_position)
			)
		overtakes = telemetry.overtakes_completed
		leader_time = telemetry.time_in_first_place

	var angular_speed := absf(
		angle_difference(_last_rotation, car.rotation)
	) / maxf(delta, 0.0001)
	if (
		angular_speed >= config.spinning_angular_speed
		and car.velocity.length() <= config.spinning_linear_speed_limit
	):
		spinning_time += delta
	_last_rotation = car.rotation


func record_lap(lap_time: float) -> void:
	lap_times.append(lap_time)


func terminate(reason: StringName, evaluation_time: float) -> void:
	if not active:
		return
	active = false
	end_reason = reason
	end_time = evaluation_time
	elapsed_time = evaluation_time


func set_final_position(position: int) -> void:
	final_position = position


func calculate_fitness(config: NeuralFitnessConfig, participant_count: int) -> float:
	if (
		completed_laps > 0
		and get_asphalt_ratio() < config.invalid_course_asphalt_ratio_threshold
	):
		invalid_course_warning = true
	var pace_bonus := 0.0
	for lap_time in lap_times:
		pace_bonus += minf(
			maxf(config.target_lap_time - lap_time, 0.0)
			* config.fast_lap_second_weight,
			config.fast_lap_bonus_limit
		)

	var average_useful_speed := get_average_useful_speed_kmh()
	var progress_gate := clampf(
		float(valid_checkpoints)
		/ float(maxi(config.secondary_bonus_checkpoint_requirement, 1)),
		0.0,
		1.0
	)
	var secondary_gate := progress_gate * get_asphalt_ratio()
	var useful_speed_bonus := (
		clampf(average_useful_speed / _maximum_speed_kmh, 0.0, 1.0)
		* config.useful_speed_weight
		* progress_gate
	)
	var asphalt_bonus := (
		get_asphalt_ratio()
		* config.asphalt_ratio_weight
		* progress_gate
	)
	var best_position_bonus := _position_bonus(
		best_position,
		participant_count,
		config.best_position_weight * secondary_gate
	)
	var final_position_bonus := _position_bonus(
		final_position,
		participant_count,
		config.final_position_weight * secondary_gate
	)

	fitness_components = {
		"lap_tier": float(completed_laps) * config.lap_tier_weight,
		"valid_progress": max_continuous_progress * config.valid_progress_weight,
		"checkpoints": float(valid_checkpoints) * config.valid_checkpoint_weight,
		"finish_crossings": float(completed_laps) * config.finish_line_crossing_weight,
		"fast_laps": pace_bonus,
		"useful_speed": useful_speed_bonus,
		"asphalt": asphalt_bonus,
		"best_position": best_position_bonus,
		"final_position": final_position_bonus,
		"leader_time": leader_time * config.leader_second_weight * secondary_gate,
		"overtakes": float(overtakes) * config.overtake_weight * secondary_gate,
		"stationary_penalty": -stationary_time * config.stationary_second_penalty,
		"wrong_way_penalty": -wrong_direction_time * config.wrong_direction_second_penalty,
		"grass_penalty": -grass_penalty_time * config.grass_second_penalty,
		"barrier_penalty": -(
			float(barrier_contacts) * config.barrier_contact_penalty
			+ barrier_contact_time * config.barrier_second_penalty
		),
		"no_progress_penalty": -(
			no_progress_penalty_time * config.no_progress_second_penalty
		),
		"spinning_penalty": -spinning_time * config.spinning_second_penalty,
	}

	var lap_tier := float(fitness_components["lap_tier"])
	var non_lap_total := 0.0
	for component_name in fitness_components:
		if component_name != "lap_tier":
			non_lap_total += float(fitness_components[component_name])
	var bounded_non_lap := clampf(
		non_lap_total,
		-config.non_lap_component_limit,
		config.non_lap_component_limit
	)
	fitness_components["non_lap_raw"] = non_lap_total
	fitness_components["non_lap_bounded"] = bounded_non_lap
	fitness = lap_tier + bounded_non_lap
	return fitness


func get_average_speed_kmh() -> float:
	return speed_integral / sampled_time if sampled_time > 0.0 else 0.0


func get_average_useful_speed_kmh() -> float:
	return useful_speed_integral / sampled_time if sampled_time > 0.0 else 0.0


func get_asphalt_ratio() -> float:
	return asphalt_time / sampled_time if sampled_time > 0.0 else 0.0


func get_result_snapshot(fitness_rank: int) -> Dictionary:
	return {
		"fitness_rank": fitness_rank,
		"agent_id": agent_id,
		"genome_id": genome_id,
		"genome_seed": genome_seed,
		"parent_id": parent_id,
		"genome_generation": genome_generation,
		"genome_is_elite": genome_is_elite,
		"genome_is_mutant": genome_is_mutant,
		"genome_mutation_count": genome_mutation_count,
		"fitness": fitness,
		"progress": max_continuous_progress,
		"checkpoints": valid_checkpoints,
		"laps": completed_laps,
		"average_speed_kmh": get_average_speed_kmh(),
		"asphalt_ratio": get_asphalt_ratio(),
		"grass_ratio": get_grass_ratio(),
		"final_position": final_position,
		"overtakes": overtakes,
		"end_reason": String(end_reason),
		"end_time": end_time,
		"total_time": total_race_time if total_race_time > 0.0 else end_time,
		"lap_times": lap_times.duplicate(),
		"maximum_progress_jump": maximum_progress_jump,
		"invalid_course_warning": invalid_course_warning,
		"rejected_by_order": rejected_by_order,
		"rejected_by_direction": rejected_by_direction,
		"rejected_by_timing": rejected_by_timing,
		"rejected_by_route": rejected_by_route,
		"components": fitness_components.duplicate(true),
	}


func _position_bonus(position: int, participant_count: int, weight: float) -> float:
	if position <= 0 or participant_count <= 1:
		return 0.0
	var ratio := float(participant_count - position) / float(participant_count - 1)
	return clampf(ratio, 0.0, 1.0) * weight


func get_grass_ratio() -> float:
	return grass_time / sampled_time if sampled_time > 0.0 else 0.0
