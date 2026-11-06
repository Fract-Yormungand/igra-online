class_name ItemDB
extends RefCounted

## Справочник предметов. Единственное место в проекте, где описаны предметы,
## их имена, стаки и теги инструментов. Логика сюда не пишется.

const ITEMS := {
	"axe": {
		"name": "Топор",
		"kind": "tool",
		"tool": "axe",
		"max_stack": 1,
		"color": Color(0.62, 0.40, 0.16),
	},
	"pickaxe": {
		"name": "Кирка",
		"kind": "tool",
		"tool": "pickaxe",
		"max_stack": 1,
		"color": Color(0.66, 0.68, 0.72),
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

## Что лежит в сумке при подключении. Список один для сервера и клиента.
const START_INVENTORY := {
	"axe": 1,
	"pickaxe": 1,
}

## Предметы, которые показываются в панели быстрого доступа, по порядку слотов.
const HOTBAR := ["axe", "pickaxe"]

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

## Тег инструмента нужен правилам добычи: топор рубит дерево, кирка бьёт камень.
## Для не-инструментов возвращает пустую строку.
static func tool_tag(item_id: String) -> String:
	return String(info(item_id).get("tool", ""))

static func max_stack(item_id: String) -> int:
	return int(info(item_id).get("max_stack", 1))

static func color(item_id: String) -> Color:
	return info(item_id).get("color", Color.WHITE)
