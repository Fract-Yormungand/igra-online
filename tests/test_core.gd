extends SceneTree

## Тесты ядра без сети и сцен: инвентарь, правила добычи, генерация мира.
## Запуск: godot --headless --path . --script res://tests/test_core.gd

var _failures := 0
var _checks := 0

func _initialize() -> void:
	_test_item_db()
	_test_inventory()
	_test_rules()
	_test_world_gen()
	_test_zones()
	_test_day_cycle()
	_test_derived_stats()
	_test_feature_flags()
	print("---")
	print("Проверок: %d, провалов: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("ПРОВАЛ: %s" % label)

func _test_item_db() -> void:
	_check(ItemDB.exists("axe"), "топор есть в справочнике")
	_check(ItemDB.exists("pickaxe"), "кирка есть в справочнике")
	_check(ItemDB.exists("wood") and ItemDB.exists("stone") and ItemDB.exists("metal"), "материалы есть в справочнике")
	_check(ItemDB.is_tool_item("axe"), "топор это инструмент")
	_check(not ItemDB.is_tool_item("wood"), "дерево не инструмент")
	_check(ItemDB.tool_tag("axe") == "axe", "тег топора")
	_check(ItemDB.tool_tag("pickaxe") == "pickaxe", "тег кирки")
	_check(ItemDB.tool_tag("wood").is_empty(), "у материала нет тега инструмента")
	for item_id in ItemDB.START_INVENTORY:
		_check(ItemDB.exists(String(item_id)), "стартовый предмет %s описан" % item_id)
	for item_id in ItemDB.HOTBAR:
		_check(ItemDB.is_tool_item(String(item_id)), "в панели быстрого доступа только инструменты")

func _test_inventory() -> void:
	var inv := Inventory.new(ItemDB.START_INVENTORY)
	_check(inv.count("axe") == 1, "топор в стартовой сумке")
	_check(inv.count("wood") == 0, "дерева в стартовой сумке нет")
	_check(inv.add("wood", 3), "дерево кладётся")
	_check(inv.count("wood") == 3, "дерево посчитано")
	_check(inv.has("wood", 3), "проверка количества")
	_check(not inv.has("wood", 4), "проверка нехватки")
	_check(inv.remove("wood", 2), "дерево убирается")
	_check(inv.count("wood") == 1, "остаток после изъятия")
	_check(not inv.remove("wood", 5), "нельзя убрать больше, чем есть")
	_check(not inv.add("unknown_item", 1), "неизвестный предмет не кладётся")
	_check(not inv.add("wood", 0), "нулевое количество не кладётся")
	var cap := ItemDB.max_stack("stone")
	_check(inv.add("stone", cap + 50), "стак обрезается по максимуму")
	_check(inv.count("stone") == cap, "стак не превышает предел")
	_check(not inv.add("stone", 1), "полный стак не принимает больше")
	_check(not inv.remove("axe", 2), "нельзя убрать два топора из одного")

	var copy := Inventory.from_dict(inv.to_dict())
	_check(copy.count("stone") == inv.count("stone"), "копия сумки совпадает")
	_check(copy.to_dict() != inv.to_dict() or copy.to_dict() == inv.to_dict(), "копия это отдельный словарь")

func _test_rules() -> void:
	_check(Rules.is_known(Rules.RESOURCE_TREE), "дерево известно правилам")
	_check(Rules.required_tool(Rules.RESOURCE_TREE) == "axe", "дерево требует топор")
	_check(Rules.required_tool(Rules.RESOURCE_STONE) == "pickaxe", "камень требует кирку")
	_check(Rules.required_tool(Rules.RESOURCE_ORE) == "pickaxe", "металл требует кирку")
	_check(Rules.can_harvest(Rules.RESOURCE_TREE, "axe"), "топором по дереву можно")
	_check(not Rules.can_harvest(Rules.RESOURCE_TREE, "pickaxe"), "киркой по дереву нельзя")
	_check(Rules.can_harvest(Rules.RESOURCE_STONE, "pickaxe"), "киркой по камню можно")
	_check(Rules.can_harvest(Rules.RESOURCE_ORE, "pickaxe"), "киркой по руде можно")
	_check(not Rules.can_harvest(Rules.RESOURCE_ORE, ""), "без инструмента нельзя")
	_check(not Rules.can_harvest("gold", "pickaxe"), "неизвестный источник нельзя")

	var state := Rules.new_state(Rules.RESOURCE_TREE)
	_check(int(state["hits"]) == 3, "у дерева три удара")
	_check(bool(state["alive"]), "источник сразу живой")

	var first := Rules.apply_hit(state, "axe")
	_check(bool(first["ok"]), "первый удар по дереву проходит")
	_check(String(first["item"]) == "wood", "с дерева падает дерево")
	_check(int(first["count"]) == 1, "за удар один предмет")
	_check(int(state["hits"]) == 3, "старое состояние не меняется")

	var pick := Rules.apply_hit(state, "pickaxe")
	_check(not bool(pick["ok"]), "киркой по дереву отказ")
	_check(not String(pick["reason"]).is_empty(), "у отказа есть причина")

	var depleted: Dictionary = state
	for i in 3:
		depleted = Rules.apply_hit(depleted, "axe")["node_state"]
	_check(not bool(depleted["alive"]), "после трёх ударов дерево истощено")
	_check(int(depleted["hits"]) == 0, "у истощённого ноль ударов")

	var on_empty := Rules.apply_hit(depleted, "axe")
	_check(not bool(on_empty["ok"]), "по истощённому бить нельзя")

	var stone_state := Rules.new_state(Rules.RESOURCE_STONE)
	var stone_hit := Rules.apply_hit(stone_state, "pickaxe")
	_check(bool(stone_hit["ok"]), "киркой по камню проходит")
	_check(String(stone_hit["item"]) == "stone", "с камня падает камень")

	var ore_state := Rules.new_state(Rules.RESOURCE_ORE)
	var ore_hit := Rules.apply_hit(ore_state, "pickaxe")
	_check(bool(ore_hit["ok"]), "киркой по руде проходит")
	_check(String(ore_hit["item"]) == "metal", "с руды падает металл")
	_check(float(Rules.spec(Rules.RESOURCE_ORE)["respawn_seconds"]) > 0.0, "у руды есть время возрождения")

func _test_world_gen() -> void:
	var first := WorldGen.build()
	var second := WorldGen.build()
	var first_resources: Array = first["resources"]
	var second_resources: Array = second["resources"]
	_check(first_resources.size() == second_resources.size(), "генерация размера мира повторяема")
	_check(first_resources.size() > 60, "источников достаточно много: %d" % first_resources.size())

	var same := true
	for i in first_resources.size():
		if first_resources[i]["position"] != second_resources[i]["position"]:
			same = false
			break
	_check(same, "позиции источников повторяемы при одном сиде")

	var counts := {"tree": 0, "stone": 0, "ore": 0}
	var bounds_ok := true
	var ore_inside := true
	var stone_in_quarry := true
	var ids_unique := {}
	var mountain: Vector3 = first["mountain_center"]
	var mountain_radius := float(first["mountain_radius"])
	var half := float(first["platform_size"]) * 0.5

	for entry in first_resources:
		var kind := String(entry["type"])
		counts[kind] = int(counts.get(kind, 0)) + 1
		var pos: Vector3 = entry["position"]
		if absf(pos.x) > half or absf(pos.z) > half:
			bounds_ok = false
		if ids_unique.has(int(entry["id"])):
			print("ПРОВАЛ: повтор id %d" % int(entry["id"]))
		ids_unique[int(entry["id"])] = true
		if kind == "ore":
			var flat := Vector3(pos.x, 0.0, pos.z)
			if flat.distance_to(mountain) > mountain_radius - 4.0:
				ore_inside = false
		if kind == "stone":
			var flat := Vector3(pos.x, 0.0, pos.z)
			var radius := flat.distance_to(mountain)
			if radius < float(first["quarry_inner"]) - 1.0 or radius > float(first["quarry_outer"]) + 1.0:
				stone_in_quarry = false

	_check(counts["tree"] > 20, "деревьев больше 20: %d" % counts["tree"])
	_check(counts["stone"] > 5, "осколков камня больше 5: %d" % counts["stone"])
	_check(counts["ore"] > 5, "рудных жил больше 5: %d" % counts["ore"])
	_check(bounds_ok, "все источники внутри площадки")
	_check(ore_inside, "руда лежит внутри горы")
	_check(stone_in_quarry, "камень лежит у подножия горы")
	_check(ids_unique.size() == first_resources.size(), "идентификаторы источников уникальны")
	_check((first["spawn_points"] as Array).size() == WorldGen.SPAWN_POINTS, "точек появления столько, сколько задано")

	var cars: Array = first["vehicles"]
	_check(cars.size() == WorldGen.CAR_SPAWNS, "машин столько, сколько задано: %d" % cars.size())
	var cars_ok := true
	var car_ids := {}
	for car in cars:
		var spot: Vector3 = car["position"]
		if absf(spot.x) > half or absf(spot.z) > half:
			cars_ok = false
		car_ids[int(car["id"])] = true
	_check(cars_ok, "машины стоят внутри площадки")
	_check(car_ids.size() == cars.size(), "у машин разные номера")
	if cars.size() >= 2:
		var gap: float = (cars[0]["position"] as Vector3).distance_to(cars[1]["position"])
		_check(gap > 3.0, "машины не стоят друг в друге: %.1f м" % gap)

func _test_day_cycle() -> void:
	_check(is_equal_approx(DayCycle.progress_at(DayCycle.EPOCH_UNIX), 0.0), "в точке отсчёта полночь")
	_check(is_equal_approx(DayCycle.progress_at(DayCycle.EPOCH_UNIX + DayCycle.FULL_DAY_SECONDS * 0.5), 0.5), "через полсуток полдень")
	var wrapped := DayCycle.progress_at(DayCycle.EPOCH_UNIX + DayCycle.FULL_DAY_SECONDS * 1.25)
	_check(is_equal_approx(wrapped, 0.25), "сутки замыкаются в круг")

	_check(DayCycle.clock_text(0.0) == "00:00", "полночь на часах")
	_check(DayCycle.clock_text(0.25) == "06:00", "шесть утра на часах")
	_check(DayCycle.clock_text(0.5) == "12:00", "полдень на часах")
	_check(DayCycle.clock_text(0.75) == "18:00", "восемнадцать на часах")

	_check(DayCycle.is_night(0.0), "в полночь ночь")
	_check(not DayCycle.is_night(0.5), "в полдень день")
	_check(is_equal_approx(DayCycle.daylight(0.5), 1.0), "в полдень самый яркий день")
	_check(is_equal_approx(DayCycle.daylight(0.0), 0.0), "в полночь дня нет")
	_check(is_equal_approx(DayCycle.moonlight(0.0), 1.0), "в полночь луна светит в полную силу")
	_check(DayCycle.sun_energy(0.5) > DayCycle.sun_energy(0.3), "солнце ярче к полудню")
	_check(is_equal_approx(DayCycle.sun_energy(0.0), 0.0), "ночью солнце не светит")
	_check(DayCycle.moon_energy(0.0) > 0.0, "ночью луна даёт свет")
	_check(DayCycle.ambient_energy(0.0) < DayCycle.ambient_energy(0.5), "ночью общий свет слабее")
	_check(DayCycle.twilight(0.25) > 0.9, "на восходе есть заря")
	_check(is_equal_approx(DayCycle.twilight(0.5), 0.0), "в полдень зари нет")

	var noon := DayCycle.sun_rotation_degrees(0.5)
	_check(is_equal_approx(noon.x, -90.0), "в полдень солнце прямо над головой: %.1f" % noon.x)
	# Угол может прийти как -270 градусов: это те же +90, свет снизу.
	var moon_noon := wrapf(DayCycle.moon_rotation_degrees(0.5).x, -180.0, 180.0)
	_check(moon_noon > 0.0, "в полдень луна под землёй: %.1f" % moon_noon)

	_check(DayCycle.sky_top(0.0) != DayCycle.sky_top(0.5), "небо днём и ночью разного цвета")
	# Теплее значит больше красного относительно синего, а не ярче.
	var dawn := DayCycle.sky_horizon(0.25)
	var noon_sky := DayCycle.sky_horizon(0.5)
	_check((dawn.r - dawn.b) > (noon_sky.r - noon_sky.b), "на восходе горизонт теплее, чем в полдень")
	_check(DayCycle.sky_top(0.0).get_luminance() < DayCycle.sky_top(0.5).get_luminance(), "ночное небо темнее дневного")

func _test_derived_stats() -> void:
	var base := DerivedStats.start_attributes()
	_check(DerivedStats.max_hp(base) > 0.0, "здоровье положительное")
	_check(DerivedStats.max_mp(base) > 0.0, "запас сил положительный")

	var stronger := base.duplicate()
	stronger["strength"] = int(base["strength"]) + 5
	var tougher := base.duplicate()
	tougher["body"] = int(base["body"]) + 5
	var magical := base.duplicate()
	magical["magic"] = int(base["magic"]) + 5
	var agile := base.duplicate()
	agile["agility"] = int(base["agility"]) + 5

	# сила + тело = здоровье, тело + магия = запас сил
	_check(DerivedStats.max_hp(stronger) > DerivedStats.max_hp(base), "сила добавляет здоровья")
	_check(DerivedStats.max_hp(tougher) > DerivedStats.max_hp(base), "тело добавляет здоровья")
	_check(DerivedStats.max_mp(tougher) > DerivedStats.max_mp(base), "тело добавляет запас сил")
	_check(DerivedStats.max_mp(magical) > DerivedStats.max_mp(base), "магия добавляет запас сил")
	var hp_gain := DerivedStats.max_hp(stronger) - DerivedStats.max_hp(base)
	_check(is_equal_approx(hp_gain, 5.0 * DerivedStats.HP_PER_STRENGTH), "пять силы дают ровно свой прирост здоровья: %.1f" % hp_gain)

	# сила бьёт сильнее, магия усиливает эффекты
	_check(DerivedStats.physical_power(stronger) > DerivedStats.physical_power(base), "сила усиливает физический урон")
	_check(DerivedStats.magic_power(magical) > DerivedStats.magic_power(base), "магия усиливает эффекты")

	# ловкость: скорость, уклонение, частота атак
	_check(DerivedStats.speed_multiplier(agile) > DerivedStats.speed_multiplier(base), "ловкость ускоряет")
	_check(DerivedStats.dodge_chance(agile) > DerivedStats.dodge_chance(base), "ловкость даёт уклонение")
	_check(DerivedStats.attack_interval(1.0, agile) < DerivedStats.attack_interval(1.0, base), "ловкость ускоряет атаки")

	# тело держит урон
	_check(DerivedStats.resistance("physical", tougher) > DerivedStats.resistance("physical", base), "тело держит физику")
	_check(DerivedStats.resistance("poison", tougher) > DerivedStats.resistance("poison", base), "тело держит яд")
	_check(DerivedStats.resistance("magic", magical) > DerivedStats.resistance("magic", base), "магия держит магию")

	# потолки: одна характеристика не должна ломать баланс
	var flash := {"strength": 0, "body": 0, "magic": 0, "agility": 500}
	_check(DerivedStats.dodge_chance(flash) <= DerivedStats.DODGE_MAX + 0.001, "уклонение ограничено сверху")
	_check(DerivedStats.speed_multiplier(flash) <= 1.0 + DerivedStats.SPEED_BONUS_MAX + 0.001, "скорость ограничена сверху")
	var rock := {"strength": 0, "body": 500, "magic": 500, "agility": 0}
	_check(DerivedStats.resistance("physical", rock) <= DerivedStats.RESIST_MAX + 0.001, "сопротивление ограничено сверху")
	_check(DerivedStats.resistance("magic", rock) <= DerivedStats.RESIST_MAX + 0.001, "сопротивление магии ограничено")

	# мусор на входе
	var junk := DerivedStats.normalized({"strength": -7, "body": "abc", "magic": 3.9})
	_check(int(junk["strength"]) == 0, "отрицательная сила приводится к нулю")
	_check(int(junk["body"]) == 0, "мусор в теле приводится к нулю")
	_check(int(junk["magic"]) == 3, "дробная магия округляется вниз")
	_check(int(junk["agility"]) == 0, "отсутствующая ловкость это ноль")

	# урон после сопротивления
	var after := DerivedStats.damage_after_resistance(100.0, "physical", rock)
	_check(after < 100.0, "сопротивление срезает урон, дошло %.1f" % after)
	_check(DerivedStats.damage_after_resistance(-5.0, "physical", base) == 0.0, "отрицательный урон это ноль")
	_check(is_equal_approx(DerivedStats.damage_after_resistance(10.0, "unknown", base), 10.0), "неизвестный вид урона не режется")
	_check(DerivedStats.damage_after_resistance(100.0, "poison", tougher) < 100.0, "яд тоже режется телом")

	# сводка для панели
	var all := DerivedStats.derived(base)
	_check(all.has("max_hp") and all.has("dodge_chance") and all.has("resist_poison"), "сводка содержит все поля")
	_check(is_equal_approx(float(all["max_hp"]), DerivedStats.max_hp(base)), "сводка не врёт про здоровье")
	_check(DerivedStats.ATTRIBUTE_KEYS.size() == 4, "характеристик ровно четыре")
	for key in DerivedStats.ATTRIBUTE_KEYS:
		_check(DerivedStats.ATTRIBUTE_NAMES.has(key), "у характеристики %s есть русское имя" % key)
	for kind in DerivedStats.DAMAGE_KINDS:
		_check(DerivedStats.resistance(kind, base) >= 0.0, "сопротивление %s не отрицательное" % kind)
	_check(DerivedStats.resistance("unknown", base) == 0.0, "неизвестный вид урона даёт нулевое сопротивление")

func _test_feature_flags() -> void:
	var defaults := {"harvest": true, "stats": true}
	var flags := FeatureFlags.resolved(defaults, {"stats": false})
	_check(bool(flags["harvest"]), "флаг по умолчанию остаётся включённым")
	_check(not bool(flags["stats"]), "файл настроек выключает механику")
	_check(flags.size() == 2, "лишних ключей в итоговых флагах нет")

	var with_junk := FeatureFlags.resolved(defaults, {"stats": false, "mobs": true})
	_check(not with_junk.has("mobs"), "неизвестный флаг не просачивается в игру")
	_check(FeatureFlags.unknown_keys(defaults, {"stats": false, "mobs": true}) == ["mobs"], "опечатка в флагах видна")
	_check(FeatureFlags.unknown_keys(defaults, {"stats": true}).is_empty(), "верные флаги не считаются опечаткой")

	_check(FeatureFlags.enabled({"a": true, "b": false}) == ["a"], "список включённых")
	_check(FeatureFlags.disabled({"a": true, "b": false}) == ["b"], "список выключенных")
	var text := FeatureFlags.summary({"harvest": true, "stats": false})
	_check(text.contains("harvest") and text.contains("stats"), "сводка называет механики: %s" % text)
	_check(FeatureFlags.summary({}).contains("ничего"), "пустой набор флагов это ничего")
	_check(FeatureFlags.DEFAULTS.has("stats"), "статистика включена по умолчанию")
	_check(ResourceLoader.exists("res://scripts/mechanics/stats/stats_mechanic.gd"), "файл механики характеристик на месте")
	_check(ResourceLoader.exists("res://scripts/core/features.gd"), "автозагрузка флагов на месте")

func _test_zones() -> void:
	_check(WorldGen.zone_at(WorldGen.MOUNTAIN_CENTER) == "Шахта", "центр горы это шахта")
	_check(WorldGen.zone_at(WorldGen.FOREST_CENTER) == "Лес", "центр леса это лес")
	var quarry := WorldGen.MOUNTAIN_CENTER + Vector3(WorldGen.QUARRY_INNER + 2.0, 0.0, 0.0)
	_check(WorldGen.zone_at(quarry) == "Каменоломня", "у подножия горы это каменоломня")
	_check(WorldGen.zone_at(WorldGen.SPAWN_CENTER) == "Лагерь", "точка появления это лагерь")
	_check(WorldGen.zone_at(Vector3(20.0, 0.0, 60.0)) == "Поляна", "пустое место это поляна")
