class_name RaceManager
extends Node2D

signal cars_spawned(cars: Array[CarController])
signal rankings_updated(ranked_cars: Array[CarController])

const CAR_SCENE := preload("res://scenes/car/Car.tscn")
const TEMPORARY_CONTROLLER_SCENE := preload(
	"res://scenes/controllers/TemporaryLineFollower.tscn"
)
const CAR_COLORS: Array[Color] = [
	Color("1480b8"),
	Color("d94a3a"),
	Color("e6b82e"),
	Color("43a047"),
	Color("8e5bb7"),
	Color("e67e32"),
	Color("d96891"),
	Color("2b9c91"),
	Color("eeeeee"),
	Color("4056a1"),
	Color("8dbb3f"),
	Color("8a5a44"),
]
const SPEED_FACTORS := [0.92, 0.97, 1.03, 0.95, 1.06, 0.99, 0.93, 1.04, 0.96, 1.01, 0.94, 1.02]

@export_range(2, 24, 1) var car_count := 12
@export var ranking_refresh_interval := 0.1

@onready var cars_container: Node2D = $Cars

var manual_car: CarController
var _track: RaceTrackBase
var _cars: Array[CarController] = []
var _ranked_cars: Array[CarController] = []
var _ranking_timer := 0.0


func _ready() -> void:
	_find_track()
	if _track == null:
		push_error("RaceManager requires an active RaceTrackBase.")
		return
	_spawn_cars()
	_update_rankings()


func _physics_process(delta: float) -> void:
	_ranking_timer -= delta
	if _ranking_timer <= 0.0:
		_ranking_timer = ranking_refresh_interval
		_update_rankings()


func get_cars() -> Array[CarController]:
	return _cars.duplicate()


func get_ranked_cars() -> Array[CarController]:
	return _ranked_cars.duplicate()


func get_manual_car() -> CarController:
	return manual_car


func get_leader() -> CarController:
	return _ranked_cars[0] if not _ranked_cars.is_empty() else null


func get_car(index: int) -> CarController:
	if _cars.is_empty():
		return null
	return _cars[posmod(index, _cars.size())]


func get_car_index(car: CarController) -> int:
	return _cars.find(car)


func get_car_count() -> int:
	return _cars.size()


func get_position_for_car(car: CarController) -> int:
	var position := _ranked_cars.find(car)
	return position + 1 if position >= 0 else 0


func _find_track() -> void:
	for candidate in get_tree().get_nodes_in_group("race_track"):
		if candidate is RaceTrackBase:
			_track = candidate
			return


func _spawn_cars() -> void:
	var grid_transforms := _track.get_start_grid_transforms(car_count)

	for index in range(car_count):
		var car := CAR_SCENE.instantiate() as CarController
		car.manual_control_enabled = index == 0
		car.transform = grid_transforms[index]
		cars_container.add_child(car)
		car.set_vehicle_identity(
			"CAR-%02d" % (index + 1),
			CAR_COLORS[index % CAR_COLORS.size()]
		)

		var progress := car.get_node("RaceProgress") as RaceProgressTracker
		progress.allow_manual_respawn = index == 0
		_track.register_car(car)

		if index == 0:
			manual_car = car
		else:
			var controller := (
				TEMPORARY_CONTROLLER_SCENE.instantiate() as TemporaryLineFollower
			)
			controller.speed_factor = SPEED_FACTORS[index % SPEED_FACTORS.size()]
			car.add_child(controller)

		_cars.append(car)

	cars_spawned.emit(get_cars())


func _update_rankings() -> void:
	_ranked_cars = _cars.duplicate()
	_ranked_cars.sort_custom(_is_car_ahead)
	rankings_updated.emit(get_ranked_cars())


func _is_car_ahead(first: CarController, second: CarController) -> bool:
	var first_progress := first.get_node("RaceProgress") as RaceProgressTracker
	var second_progress := second.get_node("RaceProgress") as RaceProgressTracker

	if not is_equal_approx(first_progress.total_progress, second_progress.total_progress):
		return first_progress.total_progress > second_progress.total_progress

	var first_target := _track.get_checkpoint_global_position(
		first_progress.get_next_checkpoint()
	)
	var second_target := _track.get_checkpoint_global_position(
		second_progress.get_next_checkpoint()
	)
	var first_distance := first.global_position.distance_squared_to(first_target)
	var second_distance := second.global_position.distance_squared_to(second_target)

	if not is_equal_approx(first_distance, second_distance):
		return first_distance < second_distance
	return first.vehicle_id < second.vehicle_id
