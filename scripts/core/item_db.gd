class_name ItemDB
extends RefCounted

## Справочник предметов. Единственное место в проекте, где описаны предметы,
## их имена, стаки, урон и запас прочности. Логика сюда не пишется.

const ITEMS := {
	"primitive_axe": {
		"name": "Примитивный топор",
		"kind": "tool",
		"tool": "axe",
		"attack": 0.8,
		"uses": 10,
		"max_stack": 1,
		"color": Color(0.62, 0.50, 0.30),
	},
	"primitive_pickaxe": {
		"name": "Примитивная кирка",
		"kind": "tool",
		"tool": "pickaxe",
		"attack": 0.8,
		"uses": 10,
		"max_stack": 1,
		"color": Color(0.58, 0.55, 0.45),
	},
	"primitive_spear": {
		"name": "Примитивное копьё",
		"kind": "weapon",
		"tool": "",
		"attack": 1.2,
		"uses": 8,
		"max_stack": 1,
		"color": Color(0.66, 0.54, 0.34),
	},
	"axe": {
		"name": "Топор",
		"kind": "tool",
		"tool": "axe",
		"attack": 1.0,
		"uses": 60,
		"max_stack": 1,
		"color": Color(0.62, 0.40, 0.16),
	},
	"pickaxe": {
		"name": "Кирка",
		"kind": "tool",
		"tool": "pickaxe",
		"attack": 1.0,
		"uses": 70,
		"max_stack": 1,
		"color": Color(0.66, 0.68, 0.72),
	},
	"spear": {
		"name": "Копьё",
		"kind": "weapon",
		"tool": "",
		"attack": 1.6,
		"uses": 40,
		"max_stack": 1,
		"color": Color(0.80, 0.66, 0.32),
	},
	"stick": {
		"name": "Палка",
		"kind": "material",
		"tool": "",
		"max_stack": 200,
		"color": Color(0.55, 0.40, 0.22),
	},
	"wood": {
		"name": "Дерево",
		"kind": "material",
		"tool": "",
		"max_stack": 200,
		"color": Color(0.50, 0.33, 0.16),
	},
	"stone": {
		"name": "Камень",
		"kind": "material",
		"tool": "",
		"max_stack": 200,
		"color": Color(0.55, 0.56, 0.58),
	},
	"metal": {
		"name": "Металл",
		"kind": "material",
		"tool": "",
		"max_stack": 200,
		"color": Color(0.72, 0.74, 0.80),
	},
}

## Что лежит в сумке при подключении. Пусто: первый инструмент игрок собирает
## из палок и камней, которые лежат на земле у лагеря.
const START_INVENTORY := {}

## Слоты быстрого доступа. В слоте лежит цепочка от лучшего инструмента к
## примитивному: клавиша берёт первый, который есть в сумке.
const TOOL_SLOTS := [
	{"key": "axe", "label": "Топор", "chain": ["axe", "primitive_axe"]},
	{"key": "pickaxe", "label": "Кирка", "chain": ["pickaxe", "primitive_pickaxe"]},
	{"key": "spear", "label": "Копьё", "chain": ["spear", "primitive_spear"]},
]

static func exists(item_id: String) -> bool:
	return ITEMS.has(item_id)

static func info(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})

static func display_name(item_id: String) -> String:
	return String(info(item_id).get("name", item_id))

static func kind(item_id: String) -> String:
	return String(info(item_id).get("kind", ""))

## Имя не is_tool: так называется встроенный метод Script, он перебивает статику.
static func is_tool_item(item_id: String) -> bool:
	return kind(item_id) == "tool"

## В руку берут инструменты и оружие, остальное лежит в сумке.
static func is_equippable(item_id: String) -> bool:
	var item_kind := kind(item_id)
	return item_kind == "tool" or item_kind == "weapon"

## Во сколько раз предмет в руке усиливает удар. У пустых рук множитель
## единица, у примитивных инструментов ниже, у копья выше.
static func attack_multiplier(item_id: String) -> float:
	return float(info(item_id).get("attack", 1.0))

## Тег инструмента нужен правилам добычи: топор рубит дерево, кирка бьёт камень.
## Для не-инструментов возвращает пустую строку.
static func tool_tag(item_id: String) -> String:
	return String(info(item_id).get("tool", ""))

## Запас прочности: сколько ударов выдерживает предмет. Ноль значит вечный.
static func uses(item_id: String) -> int:
	return int(info(item_id).get("uses", 0))

static func is_breakable(item_id: String) -> bool:
	return uses(item_id) > 0

## Цепочка слота: от лучшего инструмента к примитивному.
static func tool_chain(slot_key: String) -> Array:
	for entry in TOOL_SLOTS:
		if String(entry.get("key", "")) == slot_key:
			return entry.get("chain", [])
	return []

static func tool_label(slot_key: String) -> String:
	for entry in TOOL_SLOTS:
		if String(entry.get("key", "")) == slot_key:
			return String(entry.get("label", slot_key))
	return slot_key

## Все предметы цепочки: по ним окно понимает, какой инструмент подсветить.
static func is_in_chain(slot_key: String, item_id: String) -> bool:
	return tool_chain(slot_key).has(item_id)

static func max_stack(item_id: String) -> int:
	return int(info(item_id).get("max_stack", 1))

static func color(item_id: String) -> Color:
	return info(item_id).get("color", Color.WHITE)
