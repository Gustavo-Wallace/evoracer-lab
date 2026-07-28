class_name EvolutionHistory
extends RefCounted

var _entries: Array[Dictionary] = []


func add_generation(entry: Dictionary) -> void:
	_entries.append(entry.duplicate(true))


func replace_entries(entries: Array[Dictionary]) -> void:
	_entries.clear()
	for entry in entries:
		_entries.append(entry.duplicate(true))


func clear() -> void:
	_entries.clear()


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func get_recent(count: int) -> Array[Dictionary]:
	var start := maxi(_entries.size() - maxi(count, 0), 0)
	return _entries.slice(start).duplicate(true)


func get_last() -> Dictionary:
	return _entries[-1].duplicate(true) if not _entries.is_empty() else {}


func size() -> int:
	return _entries.size()
