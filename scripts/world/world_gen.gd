class_name WorldGen
extends RefCounted

## Детерминированная генерация мира. Один и тот же код и сид на сервере
## и на клиенте дают одинаковую карту, поэтому по сети едет только состояние
## источников, а не геометрия.
##
## Раскладка: плоская площадка, роща у точки появления, лес на северо-западе,
## гора на северо-востоке с каменоломней у подножия и шахтой внутри.

const WORLD_SEED := 20261106
const PLATFORM_SIZE := 170.0
const WALL_HEIGHT := 8.0

const FOREST_CENTER := Vector3(-48.0, 0.0, -28.0)
const FOREST_RADIUS := 30.0
const FOREST_TREES := 42

const MOUNTAIN_CENTER := Vector3(46.0, 0.0, -26.0)
const MOUNTAIN_RADIUS := 24.0
const MOUNTAIN_HEIGHT := 16.0
## Направление входа в шахту в радианах: смотрит в сторону площадки.
const MOUNTAIN_ENTRANCE_ANGLE := 2.55

const QUARRY_INNER := 27.0
const QUARRY_OUTER := 40.0
const QUARRY_STONES := 20
const CAVE_ORES := 12

const SPAWN_CENTER := Vector3(0.0, 0.0, 26.0)
const SPAWN_POINTS := 8

static func build() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	var resources: Array = []
	var next_id := 0

	# Роща у спавна: первый источник игрока в двух шагах.
	for i in 7:
		var angle := TAU * float(i) / 7.0
		var pos := Vector3(cos(angle) * 10.0, 0.0, 22.0 + sin(angle) * 7.0)
		resources.append(_entry(next_id, Rules.RESOURCE_TREE, pos, rng))
		next_id += 1

	var trees: Array[Vector3] = []
	var attempts := 0
	while trees.size() < FOREST_TREES and attempts < 1200:
		attempts += 1
		var angle := rng.randf_range(0.0, TAU)
		var radius := sqrt(rng.randf()) * (FOREST_RADIUS - 5.0)
		var pos := FOREST_CENTER + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if not _has_space(trees, pos, 5.0):
			continue
		trees.append(pos)
		resources.append(_entry(next_id, Rules.RESOURCE_TREE, pos, rng))
		next_id += 1

	var stones: Array[Vector3] = []
	attempts = 0
	while stones.size() < QUARRY_STONES and attempts < 1200:
		attempts += 1
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(QUARRY_INNER, QUARRY_OUTER)
		# вход в шахту не заваливаем камнями
		if absf(wrapf(angle - MOUNTAIN_ENTRANCE_ANGLE, -PI, PI)) < 0.30:
			continue
		var pos := MOUNTAIN_CENTER + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if absf(pos.x) > PLATFORM_SIZE * 0.45 or absf(pos.z) > PLATFORM_SIZE * 0.45:
			continue
		if not _has_space(stones, pos, 4.5):
			continue
		stones.append(pos)
		resources.append(_entry(next_id, Rules.RESOURCE_STONE, pos, rng))
		next_id += 1

	var ores: Array[Vector3] = []
	attempts = 0
	while ores.size() < CAVE_ORES and attempts < 1200:
		attempts += 1
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(6.0, MOUNTAIN_RADIUS - 5.0)
		var pos := MOUNTAIN_CENTER + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if not _has_space(ores, pos, 5.0):
			continue
		ores.append(pos)
		resources.append(_entry(next_id, Rules.RESOURCE_ORE, pos, rng))
		next_id += 1

	return {
		"resources": resources,
		"spawn_points": _spawn_points(),
		"platform_size": PLATFORM_SIZE,
		"wall_height": WALL_HEIGHT,
		"forest_center": FOREST_CENTER,
		"forest_radius": FOREST_RADIUS,
		"mountain_center": MOUNTAIN_CENTER,
		"mountain_radius": MOUNTAIN_RADIUS,
		"mountain_height": MOUNTAIN_HEIGHT,
		"mountain_entrance_angle": MOUNTAIN_ENTRANCE_ANGLE,
		"quarry_inner": QUARRY_INNER,
		"quarry_outer": QUARRY_OUTER,
	}

static func spawn_position(index: int) -> Vector3:
	var points := _spawn_points()
	return points[index % points.size()]

static func _spawn_points() -> Array:
	var points: Array = []
	for i in SPAWN_POINTS:
		var angle := TAU * float(i) / float(SPAWN_POINTS)
		points.append(SPAWN_CENTER + Vector3(cos(angle) * 3.5, 0.6, sin(angle) * 3.5))
	return points

static func _entry(id: int, resource_type: String, position: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"id": id,
		"type": resource_type,
		"position": position,
		"rot_y": rng.randf_range(0.0, TAU),
		"size": rng.randf_range(0.9, 1.2),
	}

static func _has_space(placed: Array, position: Vector3, min_distance: float) -> bool:
	for other in placed:
		if position.distance_to(Vector3(other)) < min_distance:
			return false
	return true

## Имя зоны для интерфейса. Порядок проверок важен: шахта внутри каменоломни.
static func zone_at(position: Vector3) -> String:
	var flat := Vector3(position.x, 0.0, position.z)
	var to_mountain := flat.distance_to(MOUNTAIN_CENTER)
	if to_mountain < MOUNTAIN_RADIUS - 1.0:
		return "Шахта"
	if to_mountain < QUARRY_OUTER + 8.0:
		return "Каменоломня"
	if flat.distance_to(FOREST_CENTER) < FOREST_RADIUS + 6.0:
		return "Лес"
	if flat.distance_to(Vector3(SPAWN_CENTER.x, 0.0, SPAWN_CENTER.z)) < 18.0:
		return "Лагерь"
	return "Поляна"
