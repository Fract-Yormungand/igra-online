class_name Inventory
extends RefCounted

## Сумка игрока. Только данные и проверки, к сцене не привязана.

signal changed

var _items: Dictionary = {}

func _init(initial: Dictionary = {}) -> void:
	for item_id in initial:
		add(String(item_id), int(initial[item_id]), false)

func count(item_id: String) -> int:
	return int(_items.get(item_id, 0))

func has(item_id: String, amount: int = 1) -> bool:
	return count(item_id) >= amount

func is_empty() -> bool:
	return _items.is_empty()

func items() -> Dictionary:
	return _items.duplicate()

## Кладёт предмет. Возвращает false, если предмет неизвестен или стак полон.
## При частичном влечении кладёт сколько влезает и возвращает true.
func add(item_id: String, amount: int = 1, notify: bool = true) -> bool:
	if not ItemDB.exists(item_id) or amount <= 0:
		return false
	var capacity := ItemDB.max_stack(item_id)
	var current := count(item_id)
	if current >= capacity:
		return false
	var free_space := capacity - current
	if amount > free_space:
		amount = free_space
	_items[item_id] = current + amount
	if notify:
		changed.emit()
	return true

func remove(item_id: String, amount: int = 1, notify: bool = true) -> bool:
	var current := count(item_id)
	if amount <= 0 or current < amount:
		return false
	var left := current - amount
	if left == 0:
		_items.erase(item_id)
	else:
		_items[item_id] = left
	if notify:
		changed.emit()
	return true

func to_dict() -> Dictionary:
	return _items.duplicate()

static func from_dict(data: Dictionary) -> Inventory:
	var inv := Inventory.new()
	for item_id in data:
		inv.add(String(item_id), int(data[item_id]), false)
	return inv
