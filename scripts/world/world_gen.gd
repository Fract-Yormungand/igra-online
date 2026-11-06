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

## Машины стоят у лагеря: до них пара шагов от точки появления.
const CAR_SPAWNS := 2

## Палки и камни лежат на земле у лагеря: с них начинается крафт, когда
## стартового инструмента нет. Берутся руками, инструмент не нужен.
const STICK_COUNT := 14
const PEBBLE_COUNT := 14

## Мобы. Вид задаёт поведение в механике mobs.
const MOB_BOAR := "boar"
const MOB_SLIME := "slime"
const MOB_SPIDER := "spider"

## Сколько кого. Кабаны в лесу, слаймы у камней, паук один в шахте.
const BOAR_COUNT := 4
const SLIME_COUNT := 3
const SPIDER_COUNT := 1

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

	# Палки и камни на земле. Кольцо вокруг лагеря: не дальше пары шагов,
	# но и не под ногами у точки появления.
	for i in STICK_COUNT + PEBBLE_COUNT:
		var angle := TAU * float(i) / float(STICK_COUNT + PEBBLE_COUNT) + 0.31
		var radius := 7.0 + 14.0 * float(i % 5) / 4.0
		var spot := SPAWN_CENTER + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius * 0.75)
		var pickup_type := Rules.RESOURCE_STICK if i % 2 == 0 else Rules.RESOURCE_PEBBLE
		# Палки и камни не садятся в дерево и друг в друга.
		if not _far_from_entries(resources, spot, 2.4):
			continue
		resources.append(_entry(next_id, pickup_type, spot, rng))
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
		"vehicles": car_spawns(),
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

## Места машин. Считаются кодом, а не константой с векторами, чтобы
## одинаковый список был и на сервере, и на клиенте.
static func car_spawns() -> Array:
	var result: Array = []
	for i in CAR_SPAWNS:
		var side := -1.0 if i % 2 == 0 else 1.0
		var offset := 7.0 + 10.0 * float(i / 2)
		result.append({
			"id": i,
			"position": Vector3(side * offset, 0.3, 31.0 + float(i) * 0.5),
			"rot_y": -0.45 * side,
		})
	return result

## Места мобов считаются кодом, а не рандомом: сервер и клиент строят
## одинаковые узлы в одинаковых точках, поэтому по сети едет только
## поведение, а не точка появления.
static func mob_spawns() -> Array:
	var result: Array = []
	var next_id := 0

	for i in BOAR_COUNT:
		var angle := TAU * float(i) / float(BOAR_COUNT) + 0.6
		var spot := FOREST_CENTER + Vector3(cos(angle) * 13.0, 0.0, sin(angle) * 13.0)
		result.append({"id": next_id, "type": MOB_BOAR, "position": spot, "rot_y": angle + PI})
		next_id += 1

	for i in SLIME_COUNT:
		var angle := TAU * float(i) / float(SLIME_COUNT) + 0.9
		var radius := QUARRY_INNER + 6.0
		var spot := MOUNTAIN_CENTER + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		result.append({"id": next_id, "type": MOB_SLIME, "position": spot, "rot_y": angle})
		next_id += 1

	for i in SPIDER_COUNT:
		var angle := TAU * float(i) / float(SPIDER_COUNT)
		var spot := MOUNTAIN_CENTER + Vector3(cos(angle) * 8.0, 0.0, sin(angle) * 8.0)
		result.append({"id": next_id, "type": MOB_SPIDER, "position": spot, "rot_y": angle})
		next_id += 1

	return result

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

## То же, но по готовым записям источников: у них позиция лежит в словаре.
static func _far_from_entries(placed: Array, position: Vector3, min_distance: float) -> bool:
	for entry in placed:
		if position.distance_to(Vector3(entry.get("position", Vector3.ZERO))) < min_distance:
			return false
	return true

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
