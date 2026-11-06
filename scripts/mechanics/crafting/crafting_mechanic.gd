extends Mechanic

## Крафт в духе Ark: сетка предметов в сумке и вкладка рецептов рядом.
## Считает сервер: он проверяет материалы, списывает их, ждёт время рецепта
## и кладёт готовый предмет в сумку. Клиент только показывает и просит.
##
## Одна работа на игрока: пока делается топор, второй заказ не примут.
## Материалы списываются в начале, поэтому два быстрых клика не сделают
## два предмета из одного набора.
##
## Выключил флаг crafting в features.cfg, и вкладка пропадает из сумки,
## а остальная игра работает как раньше.

signal craft_changed(peer_id: int)

## Кто что делает: peer_id -> {recipe, left, total}. На сервере это очередь
## работы, на клиенте только зеркало для окна.
var _jobs: Dictionary = {}

func start() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if not is_server():
		return
	for key in _jobs.keys():
		var peer_id := int(key)
		var job: Dictionary = _jobs[key]
		job["left"] = float(job["left"]) - delta
		_jobs[peer_id] = job
		if float(job["left"]) > 0.0:
			continue
		_jobs.erase(peer_id)
		_finish_job(peer_id, job)

## Что сейчас делает игрок. Пустой словарь, если ничего не делает.
func job(peer_id: int) -> Dictionary:
	var job: Dictionary = _jobs.get(peer_id, {})
	return job.duplicate()

func is_crafting(peer_id: int) -> bool:
	return _jobs.has(peer_id)

# --- просьба клиента -------------------------------------------------------

func request_craft(recipe_id: String) -> void:
	if is_server():
		_craft_on_server(Net.my_id, recipe_id)
		return
	if Net.is_offline():
		return
	_request_craft.rpc_id(1, recipe_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_craft(recipe_id: String) -> void:
	if not is_server():
		return
	_craft_on_server(multiplayer.get_remote_sender_id(), recipe_id)

func _craft_on_server(peer_id: int, recipe_id: String) -> void:
	if not Recipes.exists(recipe_id):
		return
	if _jobs.has(peer_id):
		Game.notify_peer(peer_id, "Сначала доделаю: %s" % Recipes.display_name(String(_jobs[peer_id]["recipe"])))
		return
	var inv: Inventory = Game.get_inventory(peer_id)
	if inv == null:
		return

	var missing := Recipes.missing(recipe_id, inv)
	if not missing.is_empty():
		var first: Dictionary = missing[0]
		Game.notify_peer(peer_id, "Не хватает: %s, есть %d из %d" % [
			ItemDB.display_name(String(first["item"])), int(first["have"]), int(first["need"])
		])
		return

	var output := Recipes.output_item(recipe_id)
	if inv.free_space(output) < Recipes.output_count(recipe_id):
		Game.notify_peer(peer_id, "Сумка полна: %s" % ItemDB.display_name(output))
		return

	for item_id in Recipes.cost(recipe_id):
		inv.remove(String(item_id), int(Recipes.cost(recipe_id)[item_id]))
	Game.push_inventory(peer_id)

	var total := Recipes.seconds(recipe_id)
	_broadcast_craft(peer_id, recipe_id, total, total)
	print("[CRAFT] #%d начал %s за %.1f с" % [peer_id, recipe_id, total])
	Game.notify_peer(peer_id, "Начал: %s" % Recipes.display_name(recipe_id))

func _finish_job(peer_id: int, job: Dictionary) -> void:
	var recipe_id := String(job.get("recipe", ""))
	_broadcast_craft(peer_id, "", 0.0, 0.0)
	if Game.give_item(peer_id, Recipes.output_item(recipe_id), Recipes.output_count(recipe_id)):
		print("[CRAFT] #%d сделал %s" % [peer_id, recipe_id])
		Game.notify_peer(peer_id, "Готово: %s" % Recipes.display_name(recipe_id))
		return
	# Пока шла работа, сумку забили добычей: возвращаем материалы, чтобы они
	# не пропали молча.
	for item_id in Recipes.cost(recipe_id):
		Game.give_item(peer_id, String(item_id), int(Recipes.cost(recipe_id)[item_id]))
	Game.notify_peer(peer_id, "Сумка полна, материалы вернул")

# --- сеть ------------------------------------------------------------------

func _broadcast_craft(peer_id: int, recipe_id: String, left: float, total: float) -> void:
	_apply_craft(peer_id, recipe_id, left, total)
	if Net.is_offline():
		return
	_sync_craft.rpc(peer_id, recipe_id, left, total)

@rpc("authority", "call_remote", "reliable")
func _sync_craft(peer_id: int, recipe_id: String, left: float, total: float) -> void:
	_apply_craft(peer_id, recipe_id, left, total)

func _apply_craft(peer_id: int, recipe_id: String, left: float, total: float) -> void:
	if recipe_id.is_empty():
		_jobs.erase(peer_id)
	else:
		_jobs[peer_id] = {"recipe": recipe_id, "left": left, "total": total}
	craft_changed.emit(peer_id)
