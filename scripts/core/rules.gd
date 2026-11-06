class_name Rules
extends RefCounted

## Правила добычи. Чистая логика без сцен и сети: вход и выход это словари.
## Так правила можно прогнать тестом в headless-режиме и не дублировать
## на клиенте и сервере.

const RESOURCE_TREE := "tree"
const RESOURCE_STONE := "stone"
const RESOURCE_ORE := "ore"

const RESOURCE_SPECS := {
	"tree": {
		"label": "дерево",
		"required_tool": "axe",
		"item": "wood",
		"hits": 3,
		"respawn_seconds": 25.0,
	},
	"stone": {
		"label": "камень",
		"required_tool": "pickaxe",
		"item": "stone",
		"hits": 4,
		"respawn_seconds": 35.0,
	},
	"ore": {
		"label": "металл",
		"required_tool": "pickaxe",
		"item": "metal",
		"hits": 6,
		"respawn_seconds": 50.0,
	},
}

static func spec(resource_type: String) -> Dictionary:
	return RESOURCE_SPECS.get(resource_type, {})

static func is_known(resource_type: String) -> bool:
	return RESOURCE_SPECS.has(resource_type)

static func required_tool(resource_type: String) -> String:
	return String(spec(resource_type).get("required_tool", ""))

static func label(resource_type: String) -> String:
	return String(spec(resource_type).get("label", resource_type))

static func item_for(resource_type: String) -> String:
	return String(spec(resource_type).get("item", ""))

static func can_harvest(resource_type: String, tool_tag: String) -> bool:
	if not is_known(resource_type):
		return false
	if tool_tag.is_empty():
		return false
	return required_tool(resource_type) == tool_tag

## Свежее состояние источника ресурса. Позиция добавляется снаружи: правила
## про геометрию ничего не знают.
static func new_state(resource_type: String) -> Dictionary:
	var data := spec(resource_type)
	if data.is_empty():
		return {}
	return {
		"type": resource_type,
		"hits": int(data.get("hits", 1)),
		"alive": true,
		"respawn_at": 0.0,
	}

## Один удар по источнику. Возвращает результат и новое состояние, старый
## словарь не меняется: вызывающая сторона сама решает, куда его положить.
static func apply_hit(state: Dictionary, tool_tag: String) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"item": "",
		"count": 0,
		"node_state": {},
	}
	if state.is_empty():
		result["reason"] = "источник не найден"
		return result

	var new_state: Dictionary = state.duplicate(true)
	result["node_state"] = new_state

	var resource_type := String(state.get("type", ""))
	if not is_known(resource_type):
		result["reason"] = "неизвестный источник"
		return result
	if not bool(state.get("alive", false)):
		result["reason"] = "источник истощён"
		return result
	if tool_tag.is_empty():
		result["reason"] = "возьми инструмент в руку"
		return result
	if not can_harvest(resource_type, tool_tag):
		result["reason"] = "нужен другой инструмент: %s" % required_tool(resource_type)
		return result

	var left := int(new_state.get("hits", 0)) - 1
	new_state["hits"] = maxi(0, left)
	if left <= 0:
		new_state["alive"] = false

	result["ok"] = true
	result["item"] = item_for(resource_type)
	result["count"] = 1
	return result
