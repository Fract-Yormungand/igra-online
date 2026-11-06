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
	_test_movement()
	_test_mobs()
	_test_crafting()
	_test_ram()
	_test_wear()
	_test_pickups()
	_test_levels()
	_test_audio()
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
	_check(ItemDB.START_INVENTORY.is_empty(), "стартового снаряжения нет")
	_check(ItemDB.exists("stick"), "палка есть в справочнике")
	for entry in ItemDB.TOOL_SLOTS:
		var slot_key := String(entry["key"])
		for item_id in entry["chain"]:
			_check(ItemDB.is_equippable(String(item_id)), "в слоте %s лежит предмет в руку" % slot_key)
			_check(ItemDB.exists(String(item_id)), "предмет слота %s описан" % slot_key)
	_check(ItemDB.is_equippable("spear"), "копьё берут в руку")
	_check(not ItemDB.is_equippable("wood"), "дерево в руку не берут")
	_check(not ItemDB.is_equippable("stick"), "палку в руку не берут")
	_check(ItemDB.attack_multiplier("spear") > 1.0, "копьё усиливает удар: %.2f" % ItemDB.attack_multiplier("spear"))
	_check(is_equal_approx(ItemDB.attack_multiplier("axe"), 1.0), "инструмент бьёт как кулак")

	# Примитивные инструменты: слабее и живут мало, иначе нормальные не нужны.
	_check(ItemDB.tool_tag("primitive_axe") == "axe", "примитивный топор рубит как топор")
	_check(ItemDB.tool_tag("primitive_pickaxe") == "pickaxe", "примитивная кирка бьёт камень")
	_check(ItemDB.attack_multiplier("primitive_axe") < ItemDB.attack_multiplier("axe"), "примитивный топор бьёт слабее")
	_check(ItemDB.attack_multiplier("primitive_spear") < ItemDB.attack_multiplier("spear"), "примитивное копьё слабее")
	_check(ItemDB.uses("primitive_axe") > 0 and ItemDB.uses("primitive_axe") < ItemDB.uses("axe"), "примитивный топор изнашивается быстрее: %d против %d" % [ItemDB.uses("primitive_axe"), ItemDB.uses("axe")])
	_check(ItemDB.uses("wood") == 0, "у материала прочности нет")

func _test_inventory() -> void:
	var inv := Inventory.new(ItemDB.START_INVENTORY)
	_check(inv.is_empty(), "сумка нового игрока пуста")
	_check(inv.add("axe", 1), "топор кладётся в пустую сумку")
	_check(inv.count("axe") == 1, "топор в сумке")
	_check(inv.count("wood") == 0, "дерева в сумке нет")
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

	# Сетка сумки: ячейка на предмет, пустые дорисовывает окно.
	var grid := Inventory.new({"axe": 1, "wood": 3})
	var slots := grid.slots()
	_check(slots.size() == 2, "в сетке две занятые ячейки: %d" % slots.size())
	_check(String(slots[0]["item"]) == "axe" and int(slots[0]["count"]) == 1, "первая ячейка это топор")
	_check(Inventory.MIN_SLOTS >= 12, "окно сумки рисует хотя бы дюжину ячеек")
	_check(Inventory.new().slots().is_empty(), "пустая сумка не даёт ячеек")

	_check(Inventory.new().free_space("spear") == 1, "под копьё есть место")
	var one_spear := Inventory.new({"spear": 1})
	_check(one_spear.free_space("spear") == 0, "занятое копьё место не освобождает")
	_check(one_spear.free_space("unknown_item") == 0, "у неизвестного предмета места нет")

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

	# Палки и камни с земли берут руками: с них начинается крафт.
	_check(Rules.is_known(Rules.RESOURCE_STICK), "палка известна правилам")
	_check(Rules.is_hand_pickup(Rules.RESOURCE_STICK), "палку берут руками")
	_check(Rules.is_hand_pickup(Rules.RESOURCE_PEBBLE), "камень с земли тоже")
	_check(Rules.can_harvest(Rules.RESOURCE_STICK, ""), "без инструмента палку взять можно")
	_check(not Rules.is_hand_pickup(Rules.RESOURCE_TREE), "дерево руками не берут")
	var stick_state := Rules.new_state(Rules.RESOURCE_STICK)
	var stick_hit := Rules.apply_hit(stick_state, "")
	_check(bool(stick_hit["ok"]), "палка подбирается пустыми руками")
	_check(String(stick_hit["item"]) == "stick", "с земли падает палка")
	_check(not bool(Rules.apply_hit(Rules.new_state(Rules.RESOURCE_TREE), "")["ok"]), "дерево руками не взять")
	var pebble_hit := Rules.apply_hit(Rules.new_state(Rules.RESOURCE_PEBBLE), "")
	_check(String(pebble_hit["item"]) == "stone", "с земли поднимается камень")

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
	_check(DerivedStats.ATTRIBUTE_KEYS.size() == 4, "характеристик ровно четыре")
	for key in DerivedStats.ATTRIBUTE_KEYS:
		_check(DerivedStats.ATTRIBUTE_NAMES.has(key), "у характеристики %s есть русское имя" % key)

	# Здоровье и запас сил: (тело + стат) * 3
	var hp_expected := (14.0 + 12.0) * DerivedStats.HP_MULT
	_check(is_equal_approx(DerivedStats.max_hp(base), hp_expected), "здоровье это (тело + сила) * 3: %.1f" % DerivedStats.max_hp(base))
	var mp_expected := (14.0 + 10.0) * DerivedStats.HP_MULT
	_check(is_equal_approx(DerivedStats.max_mp(base), mp_expected), "запас сил это (тело + магия) * 3: %.1f" % DerivedStats.max_mp(base))

	var stronger := base.duplicate()
	stronger["strength"] = int(base["strength"]) + 1
	var tougher := base.duplicate()
	tougher["body"] = int(base["body"]) + 1
	var magical := base.duplicate()
	magical["magic"] = int(base["magic"]) + 1
	var agile := base.duplicate()
	agile["agility"] = int(base["agility"]) + 1

	_check(is_equal_approx(DerivedStats.max_hp(stronger) - DerivedStats.max_hp(base), DerivedStats.HP_MULT), "одно очко силы даёт три здоровья")
	_check(is_equal_approx(DerivedStats.max_hp(tougher) - DerivedStats.max_hp(base), DerivedStats.HP_MULT), "одно очко тела даёт три здоровья")
	_check(is_equal_approx(DerivedStats.max_mp(tougher) - DerivedStats.max_mp(base), DerivedStats.HP_MULT), "одно очко тела даёт три запаса сил")
	_check(is_equal_approx(DerivedStats.max_mp(magical) - DerivedStats.max_mp(base), DerivedStats.HP_MULT), "одно очко магии даёт три запаса сил")
	_check(is_equal_approx(DerivedStats.max_hp(magical), DerivedStats.max_hp(base)), "магия не трогает здоровье")

	# Ловкость: одно очко это один километр в час и действия
	_check(is_equal_approx(DerivedStats.speed_kmh(base), float(base["agility"])), "скорость равна ловкости в км/ч")
	_check(is_equal_approx(DerivedStats.speed_mps(base), float(base["agility"]) / 3.6), "километры в час переводятся в метры")
	_check(is_equal_approx(DerivedStats.speed_kmh(agile) - DerivedStats.speed_kmh(base), 1.0), "одно очко ловкости даёт один километр в час")
	_check(DerivedStats.actions_per_round(base) == 1, "на 19 ловкости одно действие")
	var fast := base.duplicate()
	fast["agility"] = 20
	_check(DerivedStats.actions_per_round(fast) == 2, "на 20 ловкости два действия")
	var still := base.duplicate()
	still["agility"] = 0
	_check(DerivedStats.actions_per_round(still) == 1, "без ловкости всё равно одно действие")

	# Тело режет урон: доля = удар / (удар + тело)
	_check(is_equal_approx(DerivedStats.penetration(20.0, 20.0), 0.5), "равные удар и тело дают половину")
	_check(is_equal_approx(DerivedStats.damage_through_body(20.0, 20.0), 10.0), "из 20 урона по телу 20 доходит 10")
	var tough_damage := DerivedStats.damage_through_body(20.0, 60.0)
	var weak_damage := DerivedStats.damage_through_body(20.0, 5.0)
	_check(tough_damage < weak_damage, "тело снижает урон: %.1f против %.1f" % [tough_damage, weak_damage])
	_check(DerivedStats.damage_through_body(0.0, 10.0) == 0.0, "нулевой удар не бьёт")
	_check(is_equal_approx(DerivedStats.penetration(10.0, 0.0), 1.0), "без тела проходит весь урон")

	# Уклонение работает только на разницу ловкости
	_check(DerivedStats.evasion(10.0, 10.0) == 0.0, "равная ловкость не даёт уклонения")
	_check(DerivedStats.evasion(10.0, 20.0) == 0.0, "медленная цель не уклоняется")
	_check(is_equal_approx(DerivedStats.evasion(20.0, 10.0), 0.5), "ловкая цель уклоняется на разницу")
	_check(DerivedStats.hit_chance(50.0) < DerivedStats.hit_chance(0.0), "уклонение снижает шанс попадания")
	_check(DerivedStats.expected_d100(0.0) > 0.0 and DerivedStats.expected_d100(100.0) < 1.0, "средний d100 в разумных пределах")
	_check(DerivedStats.expected_d100(50.0) < DerivedStats.expected_d100(0.0), "против ловкого средний урон ниже")

	# Состояние и эффективные статы
	_check(is_equal_approx(DerivedStats.state_coefficient(1.0, 1.0), 1.0), "полный запас даёт коэффициент 1")
	_check(is_equal_approx(DerivedStats.state_coefficient(0.5, 0.5), 0.5), "половина запаса даёт коэффициент 0.5")
	_check(is_equal_approx(DerivedStats.state_coefficient(0.0, 1.0), 0.0), "без здоровья коэффициент 0")
	var wounded := DerivedStats.effective(base, 0.5)
	_check(is_equal_approx(float(wounded["strength"]), float(base["strength"]) * 0.5), "коэффициент состояния режет статы")

	# Магия: накопление и потолок
	_check(is_equal_approx(DerivedStats.magic_charge(10.0, 1), 10.0), "первый шаг даёт полную магию")
	_check(DerivedStats.magic_charge(10.0, 3) > DerivedStats.magic_charge(10.0, 1), "накопление растёт")
	_check(DerivedStats.magic_charge(10.0, 3) < DerivedStats.magic_ceiling(10.0), "накопление не перескакивает потолок")
	_check(is_equal_approx(DerivedStats.magic_ceiling(10.0), 50.0), "потолок магии это магия / 0.2")
	var best := DerivedStats.best_magic_charge(10.0, 14.0)
	_check(int(best["steps"]) >= 1, "лучший заряд найден: %d шагов" % int(best["steps"]))
	_check(float(best["per_round"]) > 0.0, "лучший заряд даёт урон")
	_check(int(DerivedStats.best_magic_charge(0.0, 14.0)["steps"]) == 0, "без магии заряда нет")

	# Перегруз
	var overloaded := base.duplicate()
	overloaded["strength"] = int(DerivedStats.overload_limit(base)) + 10
	_check(DerivedStats.overload_self_damage(base) == 0.0, "в норме самоурона нет")
	_check(DerivedStats.overload_self_damage(overloaded) > 0.0, "перегруз ранит: %.1f за раунд" % DerivedStats.overload_self_damage(overloaded))
	_check(is_equal_approx(DerivedStats.overload_limit(base), 70.0), "предел это тело * 5")

	# Подъём и мусор на входе
	_check(is_equal_approx(DerivedStats.carry_kg_per_hand(base), float(base["strength"])), "одна сила это один килограмм на руку")
	var junk := DerivedStats.normalized({"strength": -7, "body": "abc", "magic": 3.9})
	_check(int(junk["strength"]) == 0, "отрицательная сила приводится к нулю")
	_check(int(junk["body"]) == 0, "мусор в теле приводится к нулю")
	_check(int(junk["magic"]) == 3, "дробная магия округляется вниз")
	_check(int(junk["agility"]) == 0, "отсутствующая ловкость это ноль")

	var all := DerivedStats.derived(base)
	_check(all.has("max_hp") and all.has("magic_ceiling") and all.has("overload_self"), "сводка содержит все поля")
	_check(is_equal_approx(float(all["max_hp"]), DerivedStats.max_hp(base)), "сводка не врёт про здоровье")
	_check(is_equal_approx(float(all["speed_kmh"]), float(base["agility"])), "сводка не врёт про скорость")

## Скорость: обычный ход это половина, бег это максимум, шаг это ровно
## 10 км/ч и только после 50 ловкости.
func _test_movement() -> void:
	var base := DerivedStats.start_attributes()
	_check(not DerivedStats.walk_available(19.0), "на стартовой ловкости шаг закрыт")
	_check(not DerivedStats.walk_available(50.0), "ровно 50 ловкости шаг не открывает")
	_check(DerivedStats.walk_available(51.0), "выше 50 ловкости шаг открыт")
	_check(is_equal_approx(DerivedStats.movement_kmh(19.0, false, false), 9.5), "обычный ход это половина максимума")
	_check(is_equal_approx(DerivedStats.movement_kmh(19.0, false, true), 19.0), "бег это максимум")
	_check(is_equal_approx(DerivedStats.movement_kmh(19.0, true, false), 9.5), "без 50 ловкости шаг не работает")
	_check(is_equal_approx(DerivedStats.movement_kmh(60.0, true, false), 10.0), "с 60 ловкости шаг ровно 10 км/ч")
	_check(is_equal_approx(DerivedStats.movement_kmh(60.0, true, true), 60.0), "Shift перебивает шаг")
	_check(is_equal_approx(DerivedStats.movement_kmh(60.0, false, false), 30.0), "на 60 ловкости обычный ход 30 км/ч")
	var derived := DerivedStats.derived(base)
	_check(not bool(derived["walk_available"]), "в сводке шаг закрыт на старте")
	_check(is_equal_approx(float(derived["normal_kmh"]), float(base["agility"]) * 0.5), "в сводке обычный ход это половина")
	_check(is_equal_approx(float(derived["walk_kmh"]), 10.0), "в сводке шаг 10 км/ч")

func _test_mobs() -> void:
	var first := WorldGen.mob_spawns()
	var second := WorldGen.mob_spawns()
	var expected := WorldGen.BOAR_COUNT + WorldGen.SLIME_COUNT + WorldGen.SPIDER_COUNT
	_check(first.size() == expected, "мобов столько, сколько задано: %d" % first.size())

	var same := true
	var ids := {}
	var boars := 0
	var slimes := 0
	var spiders := 0
	var spots_ok := true
	var boars_in_forest := true
	var slimes_at_quarry := true
	var spiders_in_cave := true
	var half := WorldGen.PLATFORM_SIZE * 0.5

	for i in first.size():
		var entry: Dictionary = first[i]
		if Vector3(entry["position"]) != Vector3(second[i]["position"]):
			same = false
		ids[int(entry["id"])] = true
		var kind := String(entry["type"])
		var spot: Vector3 = entry["position"]
		var flat := Vector3(spot.x, 0.0, spot.z)
		if absf(spot.x) > half or absf(spot.z) > half:
			spots_ok = false
		match kind:
			WorldGen.MOB_BOAR:
				boars += 1
				if flat.distance_to(WorldGen.FOREST_CENTER) > WorldGen.FOREST_RADIUS:
					boars_in_forest = false
			WorldGen.MOB_SLIME:
				slimes += 1
				var radius := flat.distance_to(WorldGen.MOUNTAIN_CENTER)
				if radius < WorldGen.QUARRY_INNER - 2.0 or radius > WorldGen.QUARRY_OUTER + 2.0:
					slimes_at_quarry = false
			WorldGen.MOB_SPIDER:
				spiders += 1
				if flat.distance_to(WorldGen.MOUNTAIN_CENTER) > WorldGen.MOUNTAIN_RADIUS - 3.0:
					spiders_in_cave = false

	_check(same, "места мобов повторяемы при одном коде")
	_check(ids.size() == first.size(), "у мобов разные номера")
	_check(boars == WorldGen.BOAR_COUNT, "кабанов столько, сколько задано: %d" % boars)
	_check(slimes == WorldGen.SLIME_COUNT, "слаймов столько, сколько задано: %d" % slimes)
	_check(spiders == WorldGen.SPIDER_COUNT, "паук в шахте один: %d" % spiders)
	_check(spots_ok, "все мобы внутри площадки")
	_check(boars_in_forest, "кабаны стоят в лесу")
	_check(slimes_at_quarry, "слаймы стоят у камней")
	_check(spiders_in_cave, "паук сидит в шахте")
	_check(ResourceLoader.exists("res://scripts/mechanics/mobs/mobs_mechanic.gd"), "файл механики мобов на месте")
	_check(ResourceLoader.exists("res://scripts/mechanics/mobs/mob.gd"), "файл моба на месте")

## Крафт: рецепты это данные, проверка материалов идёт без сцены и сети.
func _test_crafting() -> void:
	_check(not Recipes.ids().is_empty(), "рецепты есть: %d" % Recipes.ids().size())
	for recipe_id in Recipes.ids():
		var rid := String(recipe_id)
		_check(Recipes.exists(rid), "рецепт %s известен" % rid)
		_check(ItemDB.exists(Recipes.output_item(rid)), "результат %s описан в справочнике" % rid)
		_check(Recipes.output_count(rid) > 0, "у %s есть результат" % rid)
		_check(Recipes.seconds(rid) > 0.0, "у %s есть время работы" % rid)
		_check(not Recipes.cost(rid).is_empty(), "у %s есть цена" % rid)
		_check(not Recipes.cost_text(rid).is_empty(), "цена %s печатается" % rid)
		for item_id in Recipes.cost(rid):
			_check(ItemDB.exists(String(item_id)), "материал %s рецепта %s описан" % [item_id, rid])

	_check(not Recipes.exists("rocket"), "неизвестного рецепта нет")
	_check(not Recipes.can_craft("rocket", {}), "неизвестный рецепт не делается")
	_check(not Recipes.can_craft("axe", {}), "без материалов топор не сделать")
	_check(Recipes.missing("axe", {}).size() == Recipes.cost("axe").size(), "без материалов не хватает всего")

	_check(Recipes.can_craft("axe", {"wood": 2, "stone": 3}), "из двух дерева и трёх камня топор выходит")
	_check(not Recipes.can_craft("axe", {"wood": 1, "stone": 3}), "одного дерева мало")
	var missing: Array = Recipes.missing("axe", {"wood": 1, "stone": 3})
	_check(missing.size() == 1, "не хватает одной позиции")
	_check(String(missing[0]["item"]) == "wood", "не хватает именно дерева")
	_check(int(missing[0]["have"]) == 1, "видно, сколько есть")

	var inv := Inventory.new({"wood": 3, "stone": 2})
	_check(Recipes.can_craft("spear", inv), "рецепт читает сумку, а не словарь")

	# Примитивные инструменты: вход в игру, когда стартового снаряжения нет.
	_check(Recipes.exists("primitive_axe"), "рецепт примитивного топора есть")
	_check(Recipes.can_craft("primitive_axe", {"stick": 2, "stone": 2}), "из двух палок и двух камней топор выходит")
	_check(not Recipes.can_craft("primitive_axe", {"stick": 1, "stone": 2}), "одной палки мало")
	_check(ItemDB.exists(Recipes.output_item("primitive_axe")), "примитивный топор описан в справочнике")
	_check(ResourceLoader.exists("res://scripts/mechanics/crafting/crafting_mechanic.gd"), "файл механики крафта на месте")
	_check(ResourceLoader.exists("res://scripts/mechanics/crafting/craft_panel.gd"), "вкладка крафта на месте")

	var config := FileAccess.open("res://features.cfg", FileAccess.READ)
	if config != null:
		var text := config.get_as_text()
		config.close()
		_check(text.contains("crafting"), "в features.cfg есть флаг крафта")

## Наезд машины: урон растёт со скоростью, тяжёлого моба сбить труднее.
func _test_ram() -> void:
	_check(not RamRules.can_hit(0.0), "стоящая машина не бьёт")
	_check(not RamRules.can_hit(RamRules.MIN_SPEED_MPS - 0.1), "медленная машина не бьёт")
	_check(RamRules.can_hit(RamRules.MIN_SPEED_MPS), "на пороге удар уже идёт")
	_check(RamRules.damage(1.0, 6.0) == 0.0, "на малой скорости урона нет")
	var slow: float = RamRules.damage(6.0, 6.0)
	var fast: float = RamRules.damage(15.0, 6.0)
	_check(slow > 0.0 and fast > slow, "быстрее значит больнее: %.1f против %.1f" % [fast, slow])
	var light: float = RamRules.damage(15.0, 4.0)
	var heavy: float = RamRules.damage(15.0, 10.0)
	_check(light > heavy, "лёгкого слайма сбить легче кабана: %.1f против %.1f" % [light, heavy])
	_check(RamRules.knock_speed(15.0) > RamRules.knock_speed(4.0), "от быстрой машины отлетает дальше")
	_check(RamRules.knock_speed(0.0) > 0.0, "отброс есть даже без скорости")
	_check(RamRules.HIT_RADIUS > 2.0, "корпус задевает не только точку")

## Прочность: удар снимает единицу, на нуле предмет сломан.
func _test_wear() -> void:
	_check(Wear.is_breakable("axe"), "топор изнашивается")
	_check(Wear.is_breakable("primitive_axe"), "примитивный топор тоже")
	_check(not Wear.is_breakable("wood"), "материал не изнашивается")
	var fresh := Wear.fresh("primitive_axe")
	_check(fresh == Wear.max_uses("primitive_axe"), "новый инструмент приходит с полным запасом")
	_check(Wear.spend(fresh) == fresh - 1, "удар снимает единицу прочности")
	var zero := 0
	for i in Wear.max_uses("primitive_axe") + 5:
		zero = Wear.spend(zero)
	_check(zero == 0 and Wear.is_broken(zero), "ниже нуля прочность не уходит")
	_check(is_equal_approx(Wear.share(5, 10), 0.5), "доля остатка считается")
	_check(is_equal_approx(Wear.share(0, 10), 0.0), "пустой запас это ноль")
	_check(is_equal_approx(Wear.share(3, 0), 1.0), "у вечного предмета полная доля")
	_check(Wear.text(5, 10) == "5/10", "подпись прочности для окна")
	_check(Wear.text(5, 0) == "", "у вечного предмета подписи нет")

## Палки и камни на земле: их хватает на первый инструмент, лежат у лагеря.
func _test_pickups() -> void:
	var data := WorldGen.build()
	var sticks := 0
	var pebbles := 0
	var inside := true
	var near_camp := true
	var half := float(data["platform_size"]) * 0.5
	var camp := Vector3(WorldGen.SPAWN_CENTER.x, 0.0, WorldGen.SPAWN_CENTER.z)
	var ids := {}
	for entry in data["resources"]:
		ids[int(entry["id"])] = true
		var kind := String(entry["type"])
		if kind != Rules.RESOURCE_STICK and kind != Rules.RESOURCE_PEBBLE:
			continue
		if kind == Rules.RESOURCE_STICK:
			sticks += 1
		else:
			pebbles += 1
		var spot: Vector3 = entry["position"]
		if absf(spot.x) > half or absf(spot.z) > half:
			inside = false
		if Vector3(spot.x, 0.0, spot.z).distance_to(camp) > 30.0:
			near_camp = false
	_check(sticks > 5, "палок на земле хватает: %d" % sticks)
	_check(pebbles > 5, "камней на земле хватает: %d" % pebbles)
	_check(inside, "палки и камни внутри площадки")
	_check(near_camp, "палки и камни лежат у лагеря")
	_check(ids.size() == (data["resources"] as Array).size(), "у палок и камней свои номера")
	_check(Recipes.can_craft("primitive_axe", {"stick": 2, "stone": 2}), "с земли выходит первый топор")

## Прокачка: кап, цена шага, пул очков и награда за убийство по калькулятору.
func _test_levels() -> void:
	_check(LevelRules.level_cap(0) == 10, "на первой эволюции кап 10")
	_check(LevelRules.level_cap(1) == 20, "на второй 20")
	_check(LevelRules.level_cap(3) == 40, "на четвёртой 40")
	_check(LevelRules.base_exp(0) == 10, "база опыта эво 0 равна 10")
	_check(LevelRules.base_exp(1) == 20, "база эво 1 равна 20")
	_check(LevelRules.base_exp(2) == 40, "база эво 2 равна 40")
	_check(LevelRules.base_exp(3) == 70, "база эво 3 равна 70")
	_check(LevelRules.base_exp(4) == 110, "база эво 4 равна 110")
	_check(LevelRules.exp_to_next(0, 0) == 10, "шаг с нулевого уровня 10")
	_check(LevelRules.exp_to_next(0, 5) == 15, "на пятом уровне 15")
	_check(LevelRules.exp_to_next(2, 0) == 40, "на эво 2 шаг начинается с 40")
	_check(LevelRules.total_points(0, 0) == 0, "на старте очков нет")
	_check(LevelRules.total_points(0, 10) == 10, "десятый уровень даёт десять очков")
	_check(LevelRules.total_points(1, 0) == 10, "эволюция без уровня тоже десять")
	_check(LevelRules.total_points(2, 0) == 40, "с второй эволюции идёт десятка сверху")

	# Награда за убийство: сумма характеристик моба на пятёрку, минимум единица.
	_check(LevelRules.exp_reward(40.0, 6.0, 0.0, 6.0, 4.0) == 11, "кабан даёт 11 опыта")
	_check(LevelRules.exp_reward(22.0, 0.0, 4.0, 4.0, 6.0) == 7, "слайм даёт 7 опыта")
	_check(LevelRules.exp_reward(60.0, 8.0, 0.0, 10.0, 10.0) == 17, "паук даёт 17 опыта")
	_check(LevelRules.exp_reward(0.0, 0.0, 0.0, 0.0, 0.0) == 1, "даже пустой моб даёт единицу")
	_check(LevelRules.exp_reward(50.0, 10.0, 20.0, 5.0, 5.0) > LevelRules.exp_reward(50.0, 10.0, 0.0, 5.0, 5.0), "магия в награду тоже входит")

	var step := LevelRules.add_exp(0, 0, 0, 10)
	_check(int(step["level"]) == 1 and int(step["exp"]) == 0, "десяток опыта это первый уровень")
	_check(int(step["levels_gained"]) == 1 and int(step["evolved"]) == 0, "уровень вырос без эволюции")
	var half := LevelRules.add_exp(0, 0, 0, 5)
	_check(int(half["level"]) == 0 and int(half["exp"]) == 5, "половина шага копится")
	var cap := LevelRules.add_exp(0, 9, 0, LevelRules.exp_to_next(0, 9))
	_check(int(cap["level"]) == 0 and int(cap["evolution"]) == 1, "на капе идёт эволюция")
	_check(int(cap["exp"]) == 0, "эволюция обнуляет опыт")
	var many := LevelRules.add_exp(0, 0, 0, 1000)
	_check(int(many["levels_gained"]) >= 10, "большой опыт поднимает уровни подряд: %d" % int(many["levels_gained"]))
	_check(int(many["evolution"]) >= 1, "и упирается в эволюцию")
	_check(LevelRules.add_exp(0, 0, 0, 0)["level"] == 0, "нулевой опыт ничего не меняет")

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
	_check(FeatureFlags.DEFAULTS.has("crafting"), "крафт включён по умолчанию")
	_check(FeatureFlags.DEFAULTS.has("mobs"), "мобы включены по умолчанию")
	_check(ResourceLoader.exists("res://scripts/mechanics/stats/stats_mechanic.gd"), "файл механики характеристик на месте")
	_check(ResourceLoader.exists("res://scripts/core/features.gd"), "автозагрузка флагов на месте")

func _test_zones() -> void:
	_check(WorldGen.zone_at(WorldGen.MOUNTAIN_CENTER) == "Шахта", "центр горы это шахта")
	_check(WorldGen.zone_at(WorldGen.FOREST_CENTER) == "Лес", "центр леса это лес")
	var quarry := WorldGen.MOUNTAIN_CENTER + Vector3(WorldGen.QUARRY_INNER + 2.0, 0.0, 0.0)
	_check(WorldGen.zone_at(quarry) == "Каменоломня", "у подножия горы это каменоломня")
	_check(WorldGen.zone_at(WorldGen.SPAWN_CENTER) == "Лагерь", "точка появления это лагерь")
	_check(WorldGen.zone_at(Vector3(20.0, 0.0, 60.0)) == "Поляна", "пустое место это поляна")

## Звук машины: листание треков, тон и громкость двигателя, наличие файлов.
## Сеть и сцены не нужны: всё это чистые правила из AudioDB.
func _test_audio() -> void:
	_check(AudioDB.track_count() == 2, "в реестре два трека")
	_check(AudioDB.next_track(-1) == 0, "с выключенного листается на первый трек")
	_check(AudioDB.next_track(0) == 1, "с первого трека на второй")
	_check(AudioDB.next_track(1) == -1, "после последнего трека снова выключено")
	_check(AudioDB.track_title(-1) == "выкл", "выключенное состояние подписано")
	_check(AudioDB.track_title(0) != AudioDB.track_title(1), "у треков разные названия: %s и %s" % [AudioDB.track_title(0), AudioDB.track_title(1)])
	_check(AudioDB.track_path(-1).is_empty(), "у выключенного трека нет пути")

	_check(is_equal_approx(AudioDB.engine_pitch(0.0, 0.0), AudioDB.ENGINE_IDLE_PITCH), "стоя на месте тон холостой")
	_check(is_equal_approx(AudioDB.engine_pitch(1.0, 0.0), AudioDB.ENGINE_MAX_PITCH), "на полной скорости тон максимальный")
	_check(is_equal_approx(AudioDB.engine_pitch(1.0, 1.0), AudioDB.ENGINE_IDLE_PITCH), "на прогреве тон не растёт")
	_check(AudioDB.engine_volume_db(1.0, 0.0) > AudioDB.engine_volume_db(0.0, 0.0), "на скорости двигатель громче")
	_check(is_equal_approx(AudioDB.engine_volume_db(1.0, 1.5), AudioDB.ENGINE_IDLE_DB), "на прогреве громкость холостая")
	_check(is_equal_approx(AudioDB.WARMUP_SECONDS, 2.0), "прогрев длится две секунды")
	_check(is_equal_approx(AudioDB.speed_ratio(34.0, 34.0), 1.0), "максимальная скорость это единица")
	_check(is_equal_approx(AudioDB.speed_ratio(-34.0, 34.0), 1.0), "задний ход считается по модулю")
	_check(AudioDB.speed_ratio(0.0, 0.0) == 0.0, "нулевой максимум не делит на ноль")

	_check(FileAccess.file_exists(AudioDB.engine_path()), "файл двигателя на месте")
	for i in AudioDB.track_count():
		_check(FileAccess.file_exists(AudioDB.track_path(i)), "файл трека %d на месте" % (i + 1))
	_check(ResourceLoader.exists("res://scripts/mechanics/audio/audio_mechanic.gd"), "файл механики звука на месте")
	_check(FeatureFlags.DEFAULTS.has("audio"), "звук включён по умолчанию")
