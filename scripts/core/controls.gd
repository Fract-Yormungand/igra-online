extends Node

## Карта управления поднимается кодом при старте, чтобы не зависеть от
## сериализации InputMap в project.godot и правок через редактор.
##
## На каждую клавишу вешаются две привязки: по keycode и по physical_keycode.
## Физический код привязывает действие к позиции клавиши и не зависит от
## раскладки, обычный код ловит события, где физический код не пришёл
## (например, синтетический ввод и часть драйверов).

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"toggle_inventory": [KEY_TAB, KEY_I],
	"slot_1": [KEY_1],
	"slot_2": [KEY_2],
	"slot_3": [KEY_3],
}

func _ready() -> void:
	for action_name in ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in ACTIONS[action_name]:
			_add_key(action_name, keycode, true)
			_add_key(action_name, keycode, false)

func _add_key(action_name: String, keycode: int, use_physical: bool) -> void:
	var event := InputEventKey.new()
	if use_physical:
		event.physical_keycode = keycode
	else:
		event.keycode = keycode
	if InputMap.action_has_event(action_name, event):
		return
	InputMap.action_add_event(action_name, event)
