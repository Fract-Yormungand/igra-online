class_name Wear
extends RefCounted

## Прочность инструмента. Правила без сцен и сети: вход и выход это числа,
## поэтому износ проверяется тестом в headless-режиме.
##
## Сломанный инструмент исчезает из сумки. Запас прочности задан в ItemDB
## полем uses, ноль значит вечный предмет.

static func max_uses(item_id: String) -> int:
	return ItemDB.uses(item_id)

static func is_breakable(item_id: String) -> bool:
	return max_uses(item_id) > 0

## Свежий предмет приходит с полным запасом.
static func fresh(item_id: String) -> int:
	return max_uses(item_id)

## Один удар по прочности. Ниже нуля не уходим.
static func spend(left: int) -> int:
	return maxi(0, left - 1)

static func is_broken(left: int) -> bool:
	return left <= 0

## Доля остатка: окно рисует по ней полоску.
static func share(left: int, capacity: int) -> float:
	if capacity <= 0:
		return 1.0
	return clampf(float(left) / float(capacity), 0.0, 1.0)

## Подпись для окна: "7/10". Для вечного предмета пустая строка.
static func text(left: int, capacity: int) -> String:
	if capacity <= 0:
		return ""
	return "%d/%d" % [left, capacity]
