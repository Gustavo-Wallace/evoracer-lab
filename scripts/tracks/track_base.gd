class_name RaceTrackBase
extends Node2D

const CHECKPOINT_SCENE := preload("res://scenes/tracks/components/RaceCheckpoint.tscn")

@export_group("Identity")
@export var track_id: StringName = &"track_base"
@export var display_name := "TRACK BASE"

@export_group("Geometry")
@export var centerline_points := PackedVector2Array()
@export_range(1, 5, 1) var smoothing_iterations := 3
@export var start_line_anchor := Vector2.ZERO

@export_group("Width From Vehicle")
@export var reference_vehicle: VehicleDimensions
@export_range(1, 8, 1) var lane_capacity := 5
@export_range(0.0, 2.0, 0.05) var safety_margin_per_side := 0.75
@export_range(1.0, 4.0, 0.25) var grass_runoff_in_car_widths := 2.5

@export_group("Surfaces")
@export var asphalt_surface: SurfaceProfile
@export var grass_surface: SurfaceProfile

@export_group("Classic Palette")
@export var road_color := Color("5a5d62")
@export var track_shadow_color := Color("2e6d32")
@export var curb_base_color := Color("f4edda")
@export var curb_red_color := Color("d5483b")
@export var center_marking_color := Color(0.94, 0.9, 0.74, 0.42)

@onready var track_shadow: Line2D = $TrackShadow
@onready var curb_underlay: Line2D = $CurbUnderlay
@onready var road_surface: Line2D = $RoadSurface
@onready var road_inner_surface: Line2D = $RoadInnerSurface
@onready var curb_segments: Node2D = $CurbSegments
@onready var center_markings: Node2D = $CenterMarkings
@onready var outer_barrier_shadow: Line2D = $OuterBarrierShadow
@onready var inner_barrier_shadow: Line2D = $InnerBarrierShadow
@onready var outer_barrier: Line2D = $OuterBarrier
@onready var inner_barrier: Line2D = $InnerBarrier
@onready var barrier_red_segments: Node2D = $BarrierRedSegments
@onready var start_grid: Node2D = $StartGrid
@onready var boundaries: StaticBody2D = $Boundaries
@onready var checkpoint_container: Node2D = $Checkpoints
@onready var racing_line: Path2D = $RacingLine

var _sampled_centerline := PackedVector2Array()
var _track_width := 0.0
var _grass_runoff_width := 0.0
var _local_bounds := Rect2()
var _checkpoints: Array[RaceCheckpoint] = []
var _checkpoint_sample_indices := PackedInt32Array()
var _circuit_length := 0.0
var _debug_checkpoints_visible := false


func _ready() -> void:
	if centerline_points.size() < 4:
		push_error("Track '%s' needs at least four centerline points." % track_id)
		return
	if reference_vehicle == null:
		push_error("Track '%s' requires reference vehicle dimensions." % track_id)
		return

	_track_width = (
		reference_vehicle.body_width
		* (float(lane_capacity) + safety_margin_per_side * 2.0)
	)
	_grass_runoff_width = reference_vehicle.body_width * grass_runoff_in_car_widths

	_sampled_centerline = _sample_closed_curve(centerline_points, smoothing_iterations)
	_calculate_circuit_length()
	_configure_racing_line()
	var edges := _build_track_edges(_sampled_centerline, _track_width * 0.5)
	var outer_points: PackedVector2Array = edges[0]
	var inner_points: PackedVector2Array = edges[1]
	var barrier_edges := _build_track_edges(
		_sampled_centerline,
		_track_width * 0.5 + _grass_runoff_width
	)
	var outer_barrier_points: PackedVector2Array = barrier_edges[0]
	var inner_barrier_points: PackedVector2Array = barrier_edges[1]
	_local_bounds = _calculate_bounds(outer_barrier_points).grow(20.0)

	_configure_visuals(outer_points, inner_points)
	_configure_barriers(outer_barrier_points, inner_barrier_points)
	_create_center_markings(_sampled_centerline)
	_create_collision_boundary(outer_barrier_points, "Outer")
	_create_collision_boundary(inner_barrier_points, "Inner")
	_create_start_grid(_sampled_centerline)
	_create_checkpoints()
	get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_register_existing_cars")


func get_start_transform() -> Transform2D:
	return _get_centerline_transform(start_line_anchor)


func get_track_width() -> float:
	return _track_width


func get_grass_runoff_width() -> float:
	return _grass_runoff_width


func get_local_bounds() -> Rect2:
	return _local_bounds


func get_checkpoint_count() -> int:
	return _checkpoints.size()


func get_checkpoint_global_position(index: int) -> Vector2:
	if index < 0 or index >= _checkpoints.size():
		return global_position
	return _checkpoints[index].global_position


func get_circuit_length() -> float:
	return _circuit_length


func get_checkpoint_segment_progress(
	world_position: Vector2,
	last_checkpoint: int,
	next_checkpoint: int
) -> float:
	if (
		last_checkpoint < 0
		or next_checkpoint < 0
		or last_checkpoint >= _checkpoint_sample_indices.size()
		or next_checkpoint >= _checkpoint_sample_indices.size()
	):
		return 0.0

	var target := to_local(world_position)
	var start_index := _checkpoint_sample_indices[last_checkpoint]
	var end_index := _checkpoint_sample_indices[next_checkpoint]
	var current_index := start_index
	var accumulated_distance := 0.0
	var best_distance_squared := INF
	var best_path_distance := 0.0
	var visited_segments := 0

	while current_index != end_index and visited_segments < _sampled_centerline.size():
		var following_index := (current_index + 1) % _sampled_centerline.size()
		var segment_start := _sampled_centerline[current_index]
		var segment_end := _sampled_centerline[following_index]
		var segment := segment_end - segment_start
		var segment_length := segment.length()
		var interpolation := 0.0
		if segment_length > 0.0:
			interpolation = clampf(
				(target - segment_start).dot(segment)
				/ (segment_length * segment_length),
				0.0,
				1.0
			)
		var nearest := segment_start + segment * interpolation
		var distance_squared := target.distance_squared_to(nearest)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_path_distance = accumulated_distance + segment_length * interpolation

		accumulated_distance += segment_length
		current_index = following_index
		visited_segments += 1

	if accumulated_distance <= 0.001:
		return 0.0
	return clampf(best_path_distance / accumulated_distance, 0.0, 1.0)


func get_racing_line_points() -> PackedVector2Array:
	return _sampled_centerline


func get_closest_racing_line_index(world_position: Vector2) -> int:
	return _find_closest_sample(to_local(world_position))


func get_surface_at_world_position(world_position: Vector2) -> SurfaceProfile:
	var distance_to_center := _distance_to_centerline(to_local(world_position))
	if distance_to_center <= _track_width * 0.5:
		return asphalt_surface
	return grass_surface


func is_world_position_on_asphalt(world_position: Vector2) -> bool:
	return _distance_to_centerline(to_local(world_position)) <= _track_width * 0.5


func get_start_grid_transforms(car_count: int) -> Array[Transform2D]:
	var transforms: Array[Transform2D] = []
	var start_transform := get_start_transform()
	var lateral_spacing := reference_vehicle.body_width * 1.75
	var row_spacing := reference_vehicle.body_length * 1.75
	var column_offsets := [0.0, -1.0, 1.0]

	for index in range(car_count):
		var row := floori(float(index) / column_offsets.size())
		var column := index % column_offsets.size()
		var local_offset := Vector2(
			column_offsets[column] * lateral_spacing,
			reference_vehicle.body_length * 1.4 + row * row_spacing
		)
		transforms.append(start_transform * Transform2D(0.0, local_offset))

	return transforms


func register_car(car: Node2D) -> void:
	if not car.is_in_group("race_cars") or _checkpoints.is_empty():
		return

	for child in car.get_children():
		if child is RaceProgressTracker and not child.is_configured():
			child.configure(_checkpoints.size(), _checkpoints[0].global_transform)
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_checkpoints") and not event.is_echo():
		_debug_checkpoints_visible = not _debug_checkpoints_visible
		for checkpoint in _checkpoints:
			checkpoint.set_debug_visible(_debug_checkpoints_visible)
		get_viewport().set_input_as_handled()


func _sample_closed_curve(
	control_points: PackedVector2Array,
	iterations: int
) -> PackedVector2Array:
	var samples := control_points.duplicate()

	for _iteration in range(iterations):
		var refined := PackedVector2Array()
		for index in range(samples.size()):
			var current := samples[index]
			var following := samples[(index + 1) % samples.size()]
			refined.append(current.lerp(following, 0.25))
			refined.append(current.lerp(following, 0.75))
		samples = refined

	return samples


func _configure_racing_line() -> void:
	var curve := Curve2D.new()
	for point in _sampled_centerline:
		curve.add_point(point)
	if not _sampled_centerline.is_empty():
		curve.add_point(_sampled_centerline[0])
	racing_line.curve = curve


func _calculate_circuit_length() -> void:
	_circuit_length = 0.0
	for index in range(_sampled_centerline.size()):
		_circuit_length += _sampled_centerline[index].distance_to(
			_sampled_centerline[(index + 1) % _sampled_centerline.size()]
		)


func _build_track_edges(
	points: PackedVector2Array,
	offset_distance: float
) -> Array[PackedVector2Array]:
	var expanded_edges := Geometry2D.offset_polygon(
		points,
		offset_distance,
		Geometry2D.JOIN_ROUND
	)
	var contracted_edges := Geometry2D.offset_polygon(
		points,
		-offset_distance,
		Geometry2D.JOIN_ROUND
	)

	if expanded_edges.is_empty() or contracted_edges.is_empty():
		push_error("Track '%s' could not generate valid boundary offsets." % track_id)
		return [PackedVector2Array(), PackedVector2Array()]

	return [
		_find_largest_polygon(expanded_edges),
		_find_largest_polygon(contracted_edges),
	]


func _calculate_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()

	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points.slice(1):
		bounds = bounds.expand(point)
	return bounds


func _find_largest_polygon(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var largest := polygons[0]
	var largest_area := absf(_signed_polygon_area(largest))

	for polygon in polygons.slice(1):
		var area := absf(_signed_polygon_area(polygon))
		if area > largest_area:
			largest = polygon
			largest_area = area

	return largest


func _signed_polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var following := points[(index + 1) % points.size()]
		area += current.x * following.y - following.x * current.y
	return area * 0.5


func _configure_visuals(
	outer_points: PackedVector2Array,
	inner_points: PackedVector2Array
) -> void:
	track_shadow.points = _sampled_centerline
	track_shadow.width = _track_width + 30.0
	track_shadow.default_color = track_shadow_color

	curb_underlay.points = _sampled_centerline
	curb_underlay.width = _track_width + 18.0
	curb_underlay.default_color = curb_base_color

	road_surface.points = _sampled_centerline
	road_surface.width = _track_width
	road_surface.default_color = road_color.darkened(0.08)

	road_inner_surface.points = _sampled_centerline
	road_inner_surface.width = _track_width - 10.0
	road_inner_surface.default_color = road_color.lightened(0.025)


func _configure_barriers(
	outer_points: PackedVector2Array,
	inner_points: PackedVector2Array
) -> void:
	outer_barrier_shadow.points = outer_points
	inner_barrier_shadow.points = inner_points
	outer_barrier.points = outer_points
	inner_barrier.points = inner_points
	_create_barrier_red_segments(outer_points)
	_create_barrier_red_segments(inner_points)


func _create_barrier_red_segments(points: PackedVector2Array) -> void:
	const SAMPLE_SPACING := 16.0
	const RED_STEPS := 3
	const GAP_STEPS := 2
	const MARK_WIDTH := 9.0
	var sampled_points := _resample_closed_path(points, SAMPLE_SPACING)
	var pattern_size := RED_STEPS + GAP_STEPS

	for start_index in range(0, sampled_points.size(), pattern_size):
		var mark := Line2D.new()
		mark.width = MARK_WIDTH
		mark.default_color = curb_red_color
		mark.joint_mode = Line2D.LINE_JOINT_ROUND
		mark.begin_cap_mode = Line2D.LINE_CAP_BOX
		mark.end_cap_mode = Line2D.LINE_CAP_BOX
		mark.antialiased = true

		for offset in range(RED_STEPS + 1):
			mark.add_point(
				sampled_points[(start_index + offset) % sampled_points.size()]
			)

		barrier_red_segments.add_child(mark)


func _resample_closed_path(
	points: PackedVector2Array,
	spacing: float
) -> PackedVector2Array:
	var resampled := PackedVector2Array([points[0]])
	var distance_to_next_sample := spacing

	for index in range(points.size()):
		var cursor := points[index]
		var segment_end := points[(index + 1) % points.size()]
		var segment_length := cursor.distance_to(segment_end)

		while segment_length >= distance_to_next_sample:
			cursor = cursor.move_toward(segment_end, distance_to_next_sample)
			resampled.append(cursor)
			segment_length = cursor.distance_to(segment_end)
			distance_to_next_sample = spacing

		distance_to_next_sample -= segment_length

	return resampled


func _create_center_markings(points: PackedVector2Array) -> void:
	const DASH_STEPS := 2
	const GAP_STEPS := 3
	var step_size := DASH_STEPS + GAP_STEPS

	for start_index in range(0, points.size(), step_size):
		var dash := Line2D.new()
		dash.width = 2.5
		dash.default_color = center_marking_color
		dash.antialiased = true

		for offset in range(DASH_STEPS + 1):
			dash.add_point(points[(start_index + offset) % points.size()])

		center_markings.add_child(dash)


func _create_collision_boundary(points: PackedVector2Array, prefix: String) -> void:
	for index in range(points.size()):
		var segment := SegmentShape2D.new()
		segment.a = points[index]
		segment.b = points[(index + 1) % points.size()]

		var collision := CollisionShape2D.new()
		collision.name = "%sSegment%03d" % [prefix, index]
		collision.shape = segment
		boundaries.add_child(collision)


func _create_checkpoints() -> void:
	var markers: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D and child.is_in_group("track_checkpoint_markers"):
			markers.append(child)
	markers.sort_custom(_sort_checkpoint_markers)

	if markers.size() < 2:
		push_error("Track '%s' needs a finish marker and at least one checkpoint." % track_id)
		return

	for index in range(markers.size()):
		var marker := markers[index]

		var checkpoint := CHECKPOINT_SCENE.instantiate() as RaceCheckpoint
		checkpoint_container.add_child(checkpoint)
		var local_anchor := to_local(marker.global_position)
		_checkpoint_sample_indices.append(_find_closest_sample(local_anchor))
		checkpoint.configure(
			index,
			markers.size(),
			_get_centerline_transform(local_anchor),
			_track_width + _grass_runoff_width * 2.0,
			reference_vehicle.body_length * 1.5
		)
		checkpoint.set_debug_visible(_debug_checkpoints_visible)
		_checkpoints.append(checkpoint)


func _sort_checkpoint_markers(first: Marker2D, second: Marker2D) -> bool:
	return String(first.name) < String(second.name)


func _get_centerline_transform(anchor: Vector2) -> Transform2D:
	if _sampled_centerline.is_empty():
		return Transform2D.IDENTITY

	var sample_index := _find_closest_sample(anchor)
	var previous := _sampled_centerline[
		posmod(sample_index - 1, _sampled_centerline.size())
	]
	var following := _sampled_centerline[(sample_index + 1) % _sampled_centerline.size()]
	var tangent := (following - previous).normalized()
	var vehicle_rotation := tangent.angle() + PI * 0.5
	return Transform2D(vehicle_rotation, _sampled_centerline[sample_index])


func _register_existing_cars() -> void:
	for car in get_tree().get_nodes_in_group("race_cars"):
		if car is Node2D:
			register_car(car)


func _on_tree_node_added(node: Node) -> void:
	if node.is_in_group("race_cars"):
		call_deferred("register_car", node)


func _create_start_grid(points: PackedVector2Array) -> void:
	const ROW_COUNT := 8
	const COLUMN_COUNT := 2
	const CELL_LENGTH := 9.0
	var start_index := _find_closest_sample(start_line_anchor)
	var previous := points[posmod(start_index - 1, points.size())]
	var following := points[(start_index + 1) % points.size()]
	var tangent := (following - previous).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	var cell_width := (_track_width - 10.0) / ROW_COUNT
	var grid_center := points[start_index]

	for row in range(ROW_COUNT):
		for column in range(COLUMN_COUNT):
			var tangent_offset := (float(column) - 1.0) * CELL_LENGTH
			var normal_offset := (float(row) - ROW_COUNT * 0.5) * cell_width
			var origin := grid_center + tangent * tangent_offset + normal * normal_offset
			var cell := Polygon2D.new()
			cell.polygon = PackedVector2Array([
				origin,
				origin + tangent * CELL_LENGTH,
				origin + tangent * CELL_LENGTH + normal * cell_width,
				origin + normal * cell_width,
			])
			cell.color = (
				Color("f5f7ff") if (row + column) % 2 == 0 else Color("151a30")
			)
			start_grid.add_child(cell)


func _find_closest_sample(target: Vector2) -> int:
	var closest_index := 0
	var closest_distance := INF

	for index in range(_sampled_centerline.size()):
		var distance := target.distance_squared_to(_sampled_centerline[index])
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index

	return closest_index


func _distance_to_centerline(target: Vector2) -> float:
	var closest_squared := INF
	for index in range(_sampled_centerline.size()):
		var segment_start := _sampled_centerline[index]
		var segment_end := _sampled_centerline[(index + 1) % _sampled_centerline.size()]
		var segment := segment_end - segment_start
		var segment_length_squared := segment.length_squared()
		var interpolation := 0.0
		if segment_length_squared > 0.0:
			interpolation = clampf(
				(target - segment_start).dot(segment) / segment_length_squared,
				0.0,
				1.0
			)
		var nearest := segment_start + segment * interpolation
		closest_squared = minf(closest_squared, target.distance_squared_to(nearest))
	return sqrt(closest_squared)
