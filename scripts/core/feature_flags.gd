class_name FeatureFlags
extends RefCounted

## Чистая логика флагов механик: значения по умолчанию плюс правки из файла.
## Без сцен, без сети, без файлов на диске, поэтому проверяется тестом.
## Чтение самого features.cfg живёт в автозагрузке Features.

## Что включено, если файла настроек нет вовсе.
const DEFAULTS := {
	"harvest": true,
	"vehicles": true,
	"day_night": true,
	"stats": true,
	"crafting": true,
	"mobs": true,
}

## Итоговые флаги: ключи только из defaults, значения перекрываются overrides.
## Лишние ключи из файла не просачиваются в игру, их видно через unknown_keys.
static func resolved(defaults: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := {}
	for key in defaults:
		var value: bool = bool(defaults[key])
		if overrides.has(key):
			value = bool(overrides[key])
		result[String(key)] = value
	return result

## Ключи из файла, которых нет в значениях по умолчанию. Так опечатка в
## features.cfg не превращается в молчаливо выключенную механику.
static func unknown_keys(defaults: Dictionary, overrides: Dictionary) -> Array:
	var result: Array = []
	for key in overrides:
		if not defaults.has(key):
			result.append(String(key))
	result.sort()
	return result

static func enabled(flags: Dictionary) -> Array:
	var result: Array = []
	for key in flags:
		if bool(flags[key]):
			result.append(String(key))
	result.sort()
	return result

static func disabled(flags: Dictionary) -> Array:
	var result: Array = []
	for key in flags:
		if not bool(flags[key]):
			result.append(String(key))
	result.sort()
	return result

static func summary(flags: Dictionary) -> String:
	var on := enabled(flags)
	var off := disabled(flags)
	return "включено: %s | выключено: %s" % [
		", ".join(PackedStringArray(on)) if not on.is_empty() else "ничего",
		", ".join(PackedStringArray(off)) if not off.is_empty() else "ничего",
	]
