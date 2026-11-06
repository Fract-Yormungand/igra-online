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
			_finish()

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
