@tool
extends RefCounted
## Spatial hash of painted prop positions plus brush-circle sampling.
## Built once per stroke so spacing checks stay fast with thousands of props.

var _cell := 32.0
var _cells := {} # Vector2i -> Array[Node2D]


func _init(cell_size: float) -> void:
	_cell = maxf(cell_size, 8.0)


func _key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _cell), floori(p.y / _cell))


func insert(node: Node2D) -> void:
	var k := _key(node.position)
	if not _cells.has(k):
		_cells[k] = []
	_cells[k].append(node)


func remove(node: Node2D) -> void:
	var k := _key(node.position)
	if _cells.has(k):
		_cells[k].erase(node)


func query_circle(center: Vector2, r: float) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var lo := _key(center - Vector2(r, r))
	var hi := _key(center + Vector2(r, r))
	var r2 := r * r
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var bucket = _cells.get(Vector2i(x, y))
			if bucket == null:
				continue
			for n in bucket:
				if is_instance_valid(n) and n.position.distance_squared_to(center) <= r2:
					out.append(n)
	return out


func has_within(p: Vector2, d: float) -> bool:
	if d <= 0.0:
		return false
	var lo := _key(p - Vector2(d, d))
	var hi := _key(p + Vector2(d, d))
	var d2 := d * d
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var bucket = _cells.get(Vector2i(x, y))
			if bucket == null:
				continue
			for n in bucket:
				if is_instance_valid(n) and n.position.distance_squared_to(p) < d2:
					return true
	return false


## Uniform random point inside a circle.
static func random_in_circle(rng: RandomNumberGenerator, center: Vector2, r: float) -> Vector2:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	return center + Vector2(cos(a), sin(a)) * d


## Picks up to `count` points in the circle that keep `spacing` from existing
## props and from each other (dart throwing, close to a Poisson-disc result).
func sample(rng: RandomNumberGenerator, center: Vector2, r: float, count: int, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if count <= 0:
		return out
	var attempts := count * 30
	var s2 := spacing * spacing
	while attempts > 0 and out.size() < count:
		attempts -= 1
		var p := random_in_circle(rng, center, r)
		if has_within(p, spacing):
			continue
		var ok := true
		for q in out:
			if q.distance_squared_to(p) < s2:
				ok = false
				break
		if ok:
			out.append(p)
	return out
