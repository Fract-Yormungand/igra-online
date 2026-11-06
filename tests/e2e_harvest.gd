extends Node

## Сквозной тест по сети. Клиент подключается к серверу, встаёт у дерева,
## просит добычу и проверяет, что сервер начислил ресурс, что чужим
## инструментом добыча не проходит и что состояние источника синхронизируется.
## Запускается флагом --e2e <адрес> [порт].

const TIMEOUT := 30.0

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
				# Двигаем самого персонажа: позицию на сервер шлёт его же
				# _physics_process, ручная отправка тут же перезапишется.
				player.global_position = Vector3(tree["position"]) + Vector3(2.0, 0.3, 0.0)
				_phase = 1
				_wait = 0.6
		1:
			_test_stats()
			_wood_before = _inv().count("wood")
			print("[E2E] дерево #%d, дерева в сумке %d, в руках %s" % [_tree_id, _wood_before, Game.get_equipped(Net.my_id)])
			Game.request_harvest(_tree_id)
			_phase = 2
			_wait = 0.8
		2:
			_check(_inv().count("wood") == _wood_before + 1, "топор дал дерево: было %d, стало %d" % [_wood_before, _inv().count("wood")])
			Game.request_equip("pickaxe")
			_phase = 3
			_wait = 0.6
		3:
			_check(Game.get_equipped(Net.my_id) == "pickaxe", "кирка взята в руки, в руках %s" % Game.get_equipped(Net.my_id))
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
			Game.request_equip("axe")
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
			Game.request_vehicle_exit()
			_phase = 14
			_wait = 0.6
		14:
			var left: Dictionary = Game.vehicles.get(_car_id, {})
			_check(int(left.get("driver", 0)) == 0, "после выхода машина свободна, водитель %d" % int(left.get("driver", 0)))
			_check(_local_player() != null and _local_player().get_vehicle() == null, "игрок больше не в машине")
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
			_finish()

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
