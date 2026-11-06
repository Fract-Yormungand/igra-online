class_name Inventory
extends RefCounted

## Сумка игрока. Только данные и проверки, к сцене не привязана.

signal changed

var _items: Dictionary = {}

## Сколько пустых ячеек дорисовывает окно сумки. Сетка без пустых мест
## выглядит списком, а не сумкой.
const MIN_SLOTS := 24

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

## Раскладка по ячейкам сетки. Сумка держит один стек на предмет, поэтому
## ячейка это предмет и его количество. Пустые ячейки дорисовывает окно.
func slots() -> Array:
	var result: Array = []
	var keys := _items.keys()
	keys.sort()
	for item_id in keys:
		result.append({"item": String(item_id), "count": int(_items[item_id])})
	return result

## Сколько ещё влезет до полного стека. Крафт спрашивает это до того, как
## списать материалы: иначе готовый предмет некуда положить.
func free_space(item_id: String) -> int:
	if not ItemDB.exists(item_id):
		return 0
	return maxi(0, ItemDB.max_stack(item_id) - count(item_id))

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
