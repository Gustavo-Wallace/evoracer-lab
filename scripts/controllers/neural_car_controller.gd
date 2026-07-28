class_name NeuralCarController
extends Node

enum OutputIndex {
	STEERING,
	ACCELERATION,
	BRAKE_REVERSE,
}

var genome: NeuralGenome
var last_inputs := PackedFloat32Array()
var last_outputs := PackedFloat32Array()
var applied_steering := 0.0
var applied_acceleration := 0.0
var applied_brake_reverse := 0.0

var _vehicle: CarController
var _network := FeedForwardNetwork.new()


func _ready() -> void:
	_vehicle = get_parent() as CarController
	if _vehicle == null:
		push_error("NeuralCarController must be a child of CarController.")
		set_physics_process(false)
		return
	if genome == null or not _network.configure(genome):
		push_error("NeuralCarController requires a valid NeuralGenome.")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if _vehicle == null or genome == null:
		return

	# This perception array is the controller's only source of information.
	last_inputs = _vehicle.get_neural_inputs()
	last_outputs = _network.evaluate(last_inputs)
	if last_outputs.size() != 3:
		_vehicle.set_control_inputs(0.0, 0.0)
		return

	applied_steering = clampf(last_outputs[OutputIndex.STEERING], -1.0, 1.0)
	applied_acceleration = clampf(
		(last_outputs[OutputIndex.ACCELERATION] + 1.0) * 0.5,
		0.0,
		1.0
	)
	applied_brake_reverse = clampf(
		(last_outputs[OutputIndex.BRAKE_REVERSE] + 1.0) * 0.5,
		0.0,
		1.0
	)
	_vehicle.set_control_inputs(
		applied_acceleration - applied_brake_reverse,
		applied_steering
	)


func assign_genome(new_genome: NeuralGenome) -> bool:
	if new_genome == null or not new_genome.is_valid():
		return false
	genome = new_genome.copy_genome()
	var configured := _network.configure(genome)
	set_physics_process(configured and _vehicle != null)
	return configured


func get_debug_snapshot() -> Dictionary:
	return {
		"genome_id": genome.genome_id if genome != null else "NONE",
		"seed": genome.seed if genome != null else 0,
		"inputs": last_inputs.duplicate(),
		"outputs": last_outputs.duplicate(),
		"steering": applied_steering,
		"acceleration": applied_acceleration,
		"brake_reverse": applied_brake_reverse,
		"throttle": applied_acceleration - applied_brake_reverse,
	}
