extends Node

## Сквозной тест по сети. Клиент подключается к серверу, встаёт у дерева,
## просит добычу и проверяет, что сервер начислил ресурс, что чужим
## инструментом добыча не проходит и что состояние источника синхронизируется.
## Запускается флагом --e2e <адрес> [порт].

const TIMEOUT := 60.0

var _elapsed := 0.0
var _wait := 0.0
var _phase := 0
var _failures := 0
var _checks := 0
var _tree_id := -1
var _wood_before := 0
var _car_id := -1
var _car_start := Vector3.ZERO
var _mp_before := 0.0
var _mp_after := 0.0
var _boar_id := -1
var _boar_start := Vector3.ZERO
var _stone_id := -1
var _hunt_id := -1

func _ready() -> void:
	print("[E2E] старт")
	Game.notice.connect(_on_notice)

func _on_notice(text: String) -> void:
	print("[E2E] сообщение сервера: %s" % text)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > TIMEOUT:
		_fail("таймаут на фазе %d" % _phase)
		_finish()
		return
	if _wait > 0.0:
		_wait -= delta
		return

	match _phase:
		0:
			var ready := Net.is_client and Net.my_id > 1
			if ready and Game.world_ready and Game.get_inventory(Net.my_id) != null and not Game.resources.is_empty():
				_check(Net.player_count() == 2, "сервер видит двух игроков, видит %d" % Net.player_count())
				var tree := _first_resource("tree")
				if tree.is_empty():
					_fail("в мире нет деревьев")
					_finish()
					return
				_tree_id = int(tree["id"])
				var player := _local_player()
				if player == null:
					_fail("не нашёл своего персонажа в мире")
					_finish()
					return
				# Стартового инструмента больше нет: сначала собираем палки и
				# камни с земли и крафтим примитивный топор.
				_begin_start()
		1:
			_test_stats()
			_wood_before = _inv().count("wood")
			print("[E2E] дерево #%d, дерева в сумке %d, в руках %s" % [_tree_id, _wood_before, Game.get_equipped(Net.my_id)])
			Game.request_harvest(_tree_id)
			# Кирка нужна на следующем шаге: заказываем её, пока проверяем дерево.
			var crafting := Features.mechanic("crafting")
			if crafting != null:
				crafting.request_craft("primitive_pickaxe")
			_phase = 2
			_wait = 2.4
		2:
			_check(_inv().count("wood") == _wood_before + 1, "топор дал дерево: было %d, стало %d" % [_wood_before, _inv().count("wood")])
			_check(_inv().count("primitive_pickaxe") == 1, "примитивная кирка скрафчена: %d" % _inv().count("primitive_pickaxe"))
			Game.request_tool("pickaxe")
			_phase = 3
			_wait = 0.6
		3:
			_check(ItemDB.tool_tag(Game.get_equipped(Net.my_id)) == "pickaxe", "кирка взята в руки, в руках %s" % Game.get_equipped(Net.my_id))
			_wood_before = _inv().count("wood")
			Game.request_harvest(_tree_id)
			_phase = 4
			_wait = 0.8
		4:
			_check(_inv().count("wood") == _wood_before, "киркой по дереву добычи нет")
			var hits := _hits(_tree_id)
			_check(hits == 2, "у дерева осталось 2 удара, осталось %d" % hits)
			_phase = 5
			_wait = 0.2
		5:
			Game.request_tool("axe")
			_phase = 6
			_wait = 0.6
		6:
			Game.request_harvest(_tree_id)
			_phase = 7
			_wait = 0.8
		7:
			Game.request_harvest(_tree_id)
			_phase = 8
			_wait = 0.8
		8:
			var state: Dictionary = Game.resources.get(_tree_id, {})
			_check(int(state.get("hits", -1)) == 0, "после трёх ударов у дерева ноль ударов, сейчас %d" % int(state.get("hits", -1)))
			_check(not bool(state.get("alive", true)), "дерево помечено истощённым и скрыто у всех")
			_check(_inv().count("wood") == 3, "в сумке три дерева, сейчас %d" % _inv().count("wood"))
			_phase = 9
			_wait = 0.2
		9:
			# Машины: сначала садимся, потом едем, потом выходим.
			_car_id = _first_free_car()
			if _car_id < 0:
				_fail("в мире нет свободной машины")
				_finish()
				return
			var player := _local_player()
			if player == null:
				_fail("не нашёл своего персонажа перед посадкой в машину")
				_finish()
				return
			var car_state: Dictionary = Game.vehicles.get(_car_id, {})
			player.global_position = Vector3(car_state.get("position", Vector3.ZERO)) + Vector3(2.6, 0.6, 0.0)
			_phase = 10
			_wait = 0.5
		10:
			print("[E2E] садимся в машину #%d" % _car_id)
			Game.request_vehicle_enter(_car_id)
			_phase = 11
			_wait = 0.6
		11:
			var state: Dictionary = Game.vehicles.get(_car_id, {})
			_check(int(state.get("driver", 0)) == Net.my_id, "сервер посадил за руль, водитель %d" % int(state.get("driver", 0)))
			_check(_local_player() != null and _local_player().get_vehicle() != null, "игрок видит себя в машине")
			_check_audio_in_car()
			_car_start = Vector3(state.get("position", Vector3.ZERO))
			_phase = 12
			_wait = 0.8
		12:
			# Без газа машина обязана стоять: иначе она уезжает сама.
			var parked: Dictionary = Game.vehicles.get(_car_id, {})
			var drift := Vector3(parked.get("position", Vector3.ZERO)).distance_to(_car_start)
			_check(drift < 1.0, "без газа машина стоит, сдвиг %.2f м" % drift)
			Input.action_press("move_forward")
			_phase = 13
			_wait = 1.0
		13:
			Input.action_release("move_forward")
			var moved: Dictionary = Game.vehicles.get(_car_id, {})
			var travelled := Vector3(moved.get("position", Vector3.ZERO)).distance_to(_car_start)
			_check(travelled > 2.0, "машина проехала %.1f м" % travelled)
			var car_speed := float(moved.get("speed", 0.0))
			_check(car_speed > 1.0, "скорость машины посчитана: %.1f м/с" % car_speed)
			Game.request_vehicle_exit()
			_phase = 14
			_wait = 0.6
		14:
			var left: Dictionary = Game.vehicles.get(_car_id, {})
			_check(int(left.get("driver", 0)) == 0, "после выхода машина свободна, водитель %d" % int(left.get("driver", 0)))
			_check(_local_player() != null and _local_player().get_vehicle() == null, "игрок больше не в машине")
			_check_audio_after_exit()
			_phase = 15
			_wait = 0.2
		15:
			_spend_mana()
			_phase = 16
			_wait = 0.8
		16:
			var stats := _stats()
			var mp_now: float = stats.mp(Net.my_id) if stats != null else _mp_before
			_check(mp_now < _mp_before - 1.0, "сервер списал запас сил по просьбе клиента: было %.0f, стало %.0f" % [_mp_before, mp_now])
			_check_speeds()
			_phase = 17
			_wait = 0.2
		17:
			_mobs_setup()
			_phase = 18
			_wait = 0.5
		18:
			_mobs_attack()
			_phase = 19
			_wait = 1.2
		19:
			_mobs_check()
			_phase = 20
			_wait = 0.2
		20:
			_craft_setup()
			_phase = 21
			_wait = 0.6
		21:
			Game.request_tool("pickaxe")
			_phase = 22
			_wait = 0.6
		22:
			Game.request_harvest(_stone_id)
			_phase = 23
			_wait = 0.8
		23:
			Game.request_harvest(_stone_id)
			_phase = 24
			_wait = 0.8
		24:
			_craft_request()
			_phase = 25
			_wait = 0.3
		25:
			_craft_progress()
			_phase = 26
			_wait = 5.6
		26:
			_craft_result()
			_phase = 27
			_wait = 0.5
		27:
			_check(Game.get_equipped(Net.my_id) == "spear", "копьё взято в руки: %s" % Game.get_equipped(Net.my_id))
			_check_inventory_ui()
			_ram_test()
			_hunt_start()
			_phase = 28
			_wait = 0.6
		28:
			_hunt_hit()
			_phase = 29
			_wait = 0.5
		29:
			_hunt_hit()
			_phase = 30
			_wait = 0.5
		30:
			_hunt_hit()
			_phase = 31
			_wait = 0.5
		31:
			_hunt_hit()
			_phase = 32
			_wait = 1.0
		32:
			# Копьё добило моба на сервере, за убийство капает опыт.
			_check_xp()
			_finish()

## Сбор старта: палки и камни с земли, затем примитивный топор. Корутина,
## потому что сервер проверяет расстояние и должен увидеть нашу позицию.
func _begin_start() -> void:
	_phase = -1
	for kind in [Rules.RESOURCE_STICK, Rules.RESOURCE_PEBBLE]:
		var want := 4 if kind == Rules.RESOURCE_STICK else 5
		var picked := 0
		for resource_id in _resource_ids(kind, want):
			var player := _local_player()
			if player == null:
				_fail("нет персонажа для сбора с земли")
				break
			var spot: Vector3 = Game.resources[resource_id].get("position", Vector3.ZERO)
			player.global_position = spot + Vector3(1.4, 0.3, 0.0)
			await get_tree().create_timer(0.4).timeout
			Game.request_harvest(resource_id)
			picked += 1
			await get_tree().create_timer(0.2).timeout
		print("[E2E] собрано %s: %d" % [kind, picked])

	_check(_inv().count("stick") >= 4, "палки собраны с земли: %d" % _inv().count("stick"))
	_check(_inv().count("stone") >= 5, "камни собраны с земли: %d" % _inv().count("stone"))

	var crafting := Features.mechanic("crafting")
	if crafting != null:
		crafting.request_craft("primitive_axe")
	await get_tree().create_timer(1.9).timeout
	_check(_inv().count("primitive_axe") == 1, "примитивный топор скрафчен: %d" % _inv().count("primitive_axe"))
	_check(Game.get_equipped(Net.my_id) == "primitive_axe", "топор сам встал в руку: %s" % Game.get_equipped(Net.my_id))

	var tree := _first_resource("tree")
	var player := _local_player()
	if player != null and not tree.is_empty():
		player.global_position = Vector3(tree["position"]) + Vector3(2.0, 0.3, 0.0)
	await get_tree().create_timer(0.5).timeout
	_phase = 1
	_wait = 0.2

## Номера живых источников нужного вида.
func _resource_ids(kind: String, want: int) -> Array:
	var result: Array = []
	for key in Game.resources:
		var state: Dictionary = Game.resources[key]
		if String(state.get("type", "")) != kind:
			continue
		if not bool(state.get("alive", false)):
			continue
		result.append(int(key))
		if result.size() >= want:
			break
	return result

## Характеристики приходят с сервера отдельным пакетом: клиент обязан получить
## здоровье, запас сил и все четыре характеристики.
func _test_stats() -> void:
	var stats := _stats()
	if stats == null:
		_fail("механика характеристик не создалась на клиенте")
		return
	var hp: float = stats.hp(Net.my_id)
	var max_hp: float = stats.max_hp(Net.my_id)
	var attrs: Dictionary = stats.attributes(Net.my_id)
	print("[E2E] статы: hp %.0f/%.0f, mp %.0f/%.0f, сила %d тело %d магия %d ловкость %d" % [
		hp, max_hp, stats.mp(Net.my_id), stats.max_mp(Net.my_id),
		int(attrs["strength"]), int(attrs["body"]), int(attrs["magic"]), int(attrs["agility"]),
	])
	_check(max_hp > 0.0, "максимум здоровья посчитан: %.0f" % max_hp)
	_check(hp > 0.0, "здоровье пришло с сервера: %.0f" % hp)
	_check(is_equal_approx(hp, max_hp), "новый игрок приходит с полным здоровьем")
	_check(stats.max_mp(Net.my_id) > 0.0, "запас сил посчитан: %.0f" % stats.max_mp(Net.my_id))
	for key in DerivedStats.ATTRIBUTE_KEYS:
		_check(int(attrs[key]) >= 0, "характеристика %s пришла" % key)
	_check(is_equal_approx(
		stats.max_hp(Net.my_id),
		(float(attrs["body"]) + float(attrs["strength"])) * DerivedStats.HP_MULT
	), "здоровье посчитано из тела и силы")
	_check(is_equal_approx(stats.speed_mps(Net.my_id), float(attrs["agility"]) / 3.6), "скорость равна ловкости в км/ч: %.2f м/с" % stats.speed_mps(Net.my_id))
	_check(stats.actions_per_round(Net.my_id) >= 1, "действий за раунд хотя бы одно: %d" % stats.actions_per_round(Net.my_id))
	_check(is_equal_approx(stats.state_coefficient(Net.my_id), 1.0), "целый персонаж в полной силе")
	_check(not stats.is_downed(Net.my_id), "новый игрок на ногах")
	_check_stats_panel()

## Окно статуса собирается в HUD и наполняется из механики. Содержимое глазом
## проверяют снимком, а здесь проверяется, что оно вообще есть и не падает.
func _check_stats_panel() -> void:
	var world := get_parent().get_node_or_null("World")
	var hud: Node = world.hud if world != null else null
	_check(hud != null and hud._stats_panel != null, "окно статуса создано в HUD")
	if hud == null or hud._stats_panel == null:
		return
	hud._toggle_stats()
	_check(hud._stats_panel.visible, "C открывает окно статуса")
	hud._stats_panel.refresh()
	_check(hud._stats_panel.get_child_count() > 0, "окно статуса наполнено")
	hud._toggle_stats()
	_check(not hud._stats_panel.visible, "повторное C закрывает окно статуса")

## Скорость: обычный ход половина, Shift полная, шаг без 50 ловкости
## не включается.
func _check_speeds() -> void:
	var player := _local_player()
	var stats := _stats()
	if player == null or stats == null:
		_fail("не проверить скорость: нет персонажа или характеристик")
		return
	var top: float = stats.speed_mps(Net.my_id)
	Input.action_release("sprint")
	_check(is_equal_approx(player._move_speed(), top * 0.5), "обычный ход это половина скорости: %.2f м/с" % player._move_speed())
	Input.action_press("sprint")
	_check(is_equal_approx(player._move_speed(), top), "Shift даёт полную скорость: %.2f м/с" % player._move_speed())
	Input.action_release("sprint")
	_check(not player._can_walk(), "на 19 ловкости шаг закрыт")
	player._toggle_walk()
	_check(not player._walking, "без 50 ловкости шаг не включается")

## Мобы: три вида на месте, кабан реагирует на удар.
func _mobs_setup() -> void:
	var mobs := Features.mechanic("mobs")
	_check(mobs != null, "механика мобов создалась")
	if mobs == null:
		return
	var snapshot: Dictionary = mobs.snapshot()
	_check(snapshot.size() >= 8, "мобы расставлены: %d" % snapshot.size())
	var kinds := {"boar": 0, "slime": 0, "spider": 0}
	for key in snapshot:
		var kind := String(snapshot[key].get("type", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	print("[E2E] мобы: кабанов %d, слаймов %d, пауков %d" % [
		int(kinds.get("boar", 0)), int(kinds.get("slime", 0)), int(kinds.get("spider", 0))
	])
	_check(int(kinds.get("boar", 0)) > 0, "кабаны в лесу есть: %d" % int(kinds.get("boar", 0)))
	_check(int(kinds.get("slime", 0)) > 0, "слаймы у камней есть: %d" % int(kinds.get("slime", 0)))
	_check(int(kinds.get("spider", 0)) == 1, "паук в шахте один")
	var boar := _first_mob("boar")
	if boar.is_empty():
		_fail("не нашёл кабана в снимке")
		return
	_boar_id = int(boar["id"])
	_boar_start = Vector3(boar["position"])
	var player := _local_player()
	if player == null:
		_fail("не нашёл персонажа для удара по кабану")
		return
	# Ставим персонажа рядом с кабаном: сервер проверит расстояние сам.
	player.global_position = _boar_start + Vector3(2.0, 0.4, 0.0)
	print("[E2E] бьём кабана #%d в точке %.1f, %.1f" % [_boar_id, _boar_start.x, _boar_start.z])

func _mobs_attack() -> void:
	var mobs := Features.mechanic("mobs")
	if mobs == null or _boar_id < 0:
		_fail("некому бить: механика мобов или цель пропала")
		return
	mobs.request_attack(_boar_id)

func _mobs_check() -> void:
	var mobs := Features.mechanic("mobs")
	var snapshot: Dictionary = mobs.snapshot() if mobs != null else {}
	var state: Dictionary = snapshot.get(_boar_id, {})
	_check(not state.is_empty(), "кабан есть в снимке после удара")
	if state.is_empty():
		return
	_check(float(state.get("hp", 0.0)) < 40.0, "удар снял здоровье кабана: %.1f" % float(state.get("hp", 0.0)))
	_check(String(state.get("mode", "")) == "flee", "кабан убегает, режим %s" % String(state.get("mode", "")))
	var moved := Vector3(state.get("position", Vector3.ZERO)).distance_to(_boar_start)
	_check(moved > 2.0, "кабан отбежал на %.1f м" % moved)
	var stats := _stats()
	if stats != null:
		_check(stats.hp(Net.my_id) > 0.0, "после удара и толчка игрок жив")

## Звук в машине: двигатель заводится на посадке, прогревается две секунды,
## музыка листается на Q и гаснет при выходе.
func _check_audio_in_car() -> void:
	var audio := Features.mechanic("audio")
	_check(audio != null, "механика звука поднялась")
	_check(Car.MAX_SPEED * 3.6 > 120.0, "максимум машины %.0f км/ч" % (Car.MAX_SPEED * 3.6))
	if audio == null:
		return
	_check(bool(audio.engine_running()), "сел в машину, двигатель завёлся")
	_check(bool(audio.engine_audible()), "звук двигателя реально играет")
	_check(audio.warmup_left() > 0.0, "сначала идёт прогрев: %.2f с" % audio.warmup_left())
	_check(audio.music_label() == "выкл", "при посадке музыка выключена")
	_check(audio.cycle_music() == 0, "первое нажатие Q включает трек 1")
	_check(bool(audio.music_state().get("playing", false)), "трек 1 реально играет")
	_check(audio.music_label() == AudioDB.track_title(0), "подпись трека совпала: %s" % audio.music_label())
	_check(audio.cycle_music() == 1, "второе нажатие Q включает трек 2")
	_check(audio.cycle_music() == -1, "третье нажатие Q выключает музыку")
	_check(audio.music_label() == "выкл", "после третьего нажатия тишина")

func _check_audio_after_exit() -> void:
	var audio := Features.mechanic("audio")
	if audio == null:
		return
	_check(not bool(audio.engine_running()), "вышел из машины, двигатель замолк")
	_check(audio.music_label() == "выкл", "вне машины музыки нет")

## Крафт: телепорт к камню, две добычи киркой, заказ копья.
func _craft_setup() -> void:
	var stone := _first_resource("stone")
	if stone.is_empty():
		_fail("в мире нет камня для крафта")
		return
	_stone_id = int(stone["id"])
	var player := _local_player()
	if player == null:
		_fail("не нашёл персонажа для крафта")
		return
	player.global_position = Vector3(stone["position"]) + Vector3(2.0, 0.3, 0.0)
	print("[E2E] крафт: камень #%d, дерева в сумке %d" % [_stone_id, _inv().count("wood")])

func _craft_request() -> void:
	_check(_inv().count("stone") >= 2, "камня хватает на копьё: %d" % _inv().count("stone"))
	var crafting := Features.mechanic("crafting")
	_check(crafting != null, "механика крафта создалась")
	if crafting == null:
		return
	print("[E2E] просим копьё: дерево %d, камень %d" % [_inv().count("wood"), _inv().count("stone")])
	crafting.request_craft("spear")

func _craft_progress() -> void:
	var crafting := Features.mechanic("crafting")
	if crafting == null:
		return
	var job: Dictionary = crafting.job(Net.my_id)
	_check(not job.is_empty(), "крафт пошёл, в работе: %s" % String(job.get("recipe", "")))
	_check(_inv().count("wood") == 0, "материалы списаны сразу, дерева %d" % _inv().count("wood"))

func _craft_result() -> void:
	var crafting := Features.mechanic("crafting")
	if crafting != null:
		_check(crafting.job(Net.my_id).is_empty(), "крафт закончился, очередь пуста")
	_check(_inv().count("spear") == 1, "копьё в сумке: %d" % _inv().count("spear"))
	var world := get_parent().get_node_or_null("World")
	var hud: Node = world.hud if world != null else null
	_check(hud != null and hud._craft_panel != null, "вкладка крафта собрана в окне сумки")
	if crafting != null:
		Game.request_equip("spear")

## Наезд: машину двигает клиент, поэтому здесь подставляем её положение и
## скорость вплотную к мобу и проверяем сам расчёт удара.
func _ram_test() -> void:
	var mobs := Features.mechanic("mobs")
	if mobs == null:
		_fail("наезд: нет механики мобов")
		return
	# Слайм слабее: наезд на скорости добивает его и даёт опыт.
	var target := _first_mob("slime")
	if target.is_empty():
		target = _first_mob("boar")
	if target.is_empty():
		_fail("наезд: не нашёл моба")
		return
	var mob_id := int(target["id"])
	var before := float(mobs.snapshot()[mob_id].get("hp", 0.0))
	var vehicle_id := _first_free_car()
	if vehicle_id < 0:
		vehicle_id = 0
	Game.vehicles[vehicle_id] = {
		"driver": Net.my_id,
		"position": Vector3(target["position"]),
		"rotation": 0.0,
		"speed": 14.0,
		"speed_time": 0.0,
	}
	mobs._ram_check(0.016)
	var state: Dictionary = mobs.snapshot().get(mob_id, {})
	var after := float(state.get("hp", 0.0))
	_check(after < before, "машина сбила моба: было %.1f, стало %.1f" % [before, after])
	_check(RamRules.damage(14.0, 6.0) > 0.0, "правило наезда даёт урон")

## Охота: встаём вплотную к мобу и бьём по-настоящему. Наезд считается
## только на сервере, поэтому опыт проверяем обычным ударом.
func _hunt_start() -> void:
	var target := _first_mob("slime")
	if target.is_empty():
		target = _first_mob("boar")
	if target.is_empty():
		_fail("не нашёл моба для удара")
		return
	_hunt_id = int(target["id"])
	var player := _local_player()
	if player != null:
		player.global_position = Vector3(target["position"]) + Vector3(2.0, 0.4, 0.0)
	print("[E2E] бьём моба #%d копьём в руках" % _hunt_id)

func _hunt_hit() -> void:
	var mobs := Features.mechanic("mobs")
	if mobs == null or _hunt_id < 0:
		return
	mobs.request_attack(_hunt_id)

## Прокачка: опыт приходит с сервера после убийства, уровень и пул очков
## считаются по калькулятору.
func _check_xp() -> void:
	var stats := _stats()
	if stats == null:
		_fail("прокачка: нет механики характеристик")
		return
	var progress: Dictionary = stats.progress(Net.my_id)
	print("[E2E] прокачка: уровень %d из %d, опыт %d/%d, эволюция %d, очков %d" % [
		int(progress["level"]), int(progress["cap"]), int(progress["exp"]),
		int(progress["exp_next"]), int(progress["evolution"]), int(progress["points"])
	])
	_check(
		int(progress["exp"]) > 0 or int(progress["level"]) > 0 or int(progress["evolution"]) > 0,
		"за убийство начислен опыт: %d" % int(progress["exp"])
	)
	var next := int(progress["exp_next"])
	_check(next > 0, "цена следующего уровня известна: %d" % next)
	_check(int(progress["cap"]) == LevelRules.level_cap(int(progress["evolution"])), "кап уровня по формуле")

## Сумка глазами интерфейса: сетка ячеек и вкладка крафта.
func _check_inventory_ui() -> void:
	var world := get_parent().get_node_or_null("World")
	var hud: Node = world.hud if world != null else null
	if hud == null:
		_fail("нет HUD для проверки сумки")
		return
	hud._toggle_inventory()
	_check(Game.ui_inventory_open, "Tab открывает сумку")
	_check(hud._inv_grid.get_child_count() >= Inventory.MIN_SLOTS, "в сетке сумки ячеек: %d" % hud._inv_grid.get_child_count())
	hud._show_tab(true)
	_check(hud._craft_panel.visible, "вкладка крафта открывается")
	_check(not hud._inv_view.visible, "сетка уступает место крафту")
	_check(hud._craft_panel._list.get_child_count() == Recipes.ids().size(), "в крафте все рецепты: %d" % hud._craft_panel._list.get_child_count())
	hud._show_tab(false)
	_check(hud._inv_view.visible and not hud._craft_panel.visible, "возврат к предметам")
	hud._toggle_inventory()
	_check(not Game.ui_inventory_open, "Tab закрывает сумку")

func _first_mob(kind: String) -> Dictionary:
	var mobs := Features.mechanic("mobs")
	if mobs == null:
		return {}
	var snapshot: Dictionary = mobs.snapshot()
	for key in snapshot:
		var state: Dictionary = snapshot[key]
		if String(state.get("type", "")) != kind:
			continue
		if not bool(state.get("alive", false)):
			continue
		return {"id": int(key), "position": state.get("position", Vector3.ZERO)}
	return {}

func _spend_mana() -> void:
	var stats := _stats()
	if stats == null:
		return
	_mp_before = stats.mp(Net.my_id)
	stats.request_mana(30.0)

func _stats() -> Node:
	return Features.mechanic("stats")

func _inv() -> Inventory:
	return Game.get_inventory(Net.my_id)

func _local_player() -> Player:
	var world := get_parent().get_node_or_null("World")
	if world == null:
		return null
	return world.get_local_player()

func _first_resource(kind: String) -> Dictionary:
	for key in Game.resources:
		var state: Dictionary = Game.resources[key]
		if String(state.get("type", "")) != kind:
			continue
		if not bool(state.get("alive", false)):
			continue
		return {"id": int(key), "position": state.get("position", Vector3.ZERO)}
	return {}

func _first_free_car() -> int:
	for key in Game.vehicles:
		if int(Game.vehicles[key].get("driver", 0)) == 0:
			return int(key)
	return -1

func _hits(resource_id: int) -> int:
	return int(Game.resources.get(resource_id, {}).get("hits", -1))

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[E2E] ок: %s" % label)
		return
	_fail(label)

func _fail(label: String) -> void:
	_failures += 1
	print("[E2E] ПРОВАЛ: %s" % label)

func _finish() -> void:
	print("[E2E] проверок: %d, провалов: %d" % [_checks, _failures])
	# Машинная строка без кириллицы: её разбирает tools/e2e.ps1 и любой CI.
	print("[E2E] RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
