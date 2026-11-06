class_name Recipes
extends RefCounted

## Рецепты крафта. Данные и чистые проверки, без сцен и сети: сервер и тест
## смотрят один и тот же список, поэтому расхождений быть не может.
## Порядок в LIST задаёт порядок строк в окне крафта.
##
## Примитивные инструменты делаются из палок и камней с земли, живут мало и
## бьют слабо. Они открывают дерево, из которого уже выходит нормальный
## инструмент.

const LIST := {
	"primitive_axe": {
		"name": "Примитивный топор",
		"output": {"item": "primitive_axe", "count": 1},
		"cost": {"stick": 2, "stone": 2},
		"seconds": 1.5,
	},
	"primitive_pickaxe": {
		"name": "Примитивная кирка",
		"output": {"item": "primitive_pickaxe", "count": 1},
		"cost": {"stick": 2, "stone": 3},
		"seconds": 2.0,
	},
	"primitive_spear": {
		"name": "Примитивное копьё",
		"output": {"item": "primitive_spear", "count": 1},
		"cost": {"stick": 3, "stone": 1},
		"seconds": 2.0,
	},
	"axe": {
		"name": "Топор",
		"output": {"item": "axe", "count": 1},
		"cost": {"wood": 2, "stone": 3},
		"seconds": 3.0,
	},
	"pickaxe": {
		"name": "Кирка",
		"output": {"item": "pickaxe", "count": 1},
		"cost": {"wood": 2, "metal": 2},
		"seconds": 4.0,
	},
	"spear": {
		"name": "Копьё",
		"output": {"item": "spear", "count": 1},
		"cost": {"wood": 3, "stone": 2},
		"seconds": 5.0,
	},
}

static func ids() -> Array:
	return LIST.keys()

static func exists(recipe_id: String) -> bool:
	return LIST.has(recipe_id)

static func get_recipe(recipe_id: String) -> Dictionary:
	return LIST.get(recipe_id, {})

static func display_name(recipe_id: String) -> String:
	return String(get_recipe(recipe_id).get("name", recipe_id))

static func output_item(recipe_id: String) -> String:
	return String(get_recipe(recipe_id).get("output", {}).get("item", ""))

static func output_count(recipe_id: String) -> int:
	return int(get_recipe(recipe_id).get("output", {}).get("count", 1))

static func seconds(recipe_id: String) -> float:
	return float(get_recipe(recipe_id).get("seconds", 0.0))

static func cost(recipe_id: String) -> Dictionary:
	return get_recipe(recipe_id).get("cost", {})

## Чего не хватает. Список пустой, значит материалов хватает.
static func missing(recipe_id: String, stock) -> Array:
	var result: Array = []
	var price := cost(recipe_id)
	for item_id in price:
		var need := int(price[item_id])
		var have := _count(stock, String(item_id))
		if have < need:
			result.append({"item": String(item_id), "need": need, "have": have})
	return result

static func can_craft(recipe_id: String, stock) -> bool:
	return exists(recipe_id) and missing(recipe_id, stock).is_empty()

## Строка для окна: "Топор: Дерево 2, Камень 3".
static func cost_text(recipe_id: String) -> String:
	var parts: Array = []
	var price := cost(recipe_id)
	for item_id in price:
		parts.append("%s %d" % [ItemDB.display_name(String(item_id)), int(price[item_id])])
	return ", ".join(PackedStringArray(parts))

## Материалы приходят либо сумкой, либо голым словарём: сервер держит сумку,
## окно на клиенте тоже, а тесту удобнее словарь.
static func _count(stock, item_id: String) -> int:
	if stock is Inventory:
		return (stock as Inventory).count(item_id)
	if stock is Dictionary:
		return int((stock as Dictionary).get(item_id, 0))
	return 0
