extends Node

## Автозагрузка Features: какие механики включены и сборка самих механик.
##
## Флаги читаются из features.cfg. В собранной игре файл ищется рядом с exe,
## поэтому его можно править без пересборки. В редакторе и при запуске из
## проекта берётся features.cfg из корня проекта.
##
## Реестр MECHANICS это единственное место, где перечислены механики. Хочешь
## убрать механику совсем: удали её папку и строку отсюда. Хочешь выключить
## на время: поставь false в features.cfg.

const CONFIG_FILE := "features.cfg"
const CONFIG_SECTION := "mechanics"

## Порядок важен. Статистика встаёт раньше мобов: мобы наносят урон через неё.
const MECHANICS := [
	{"id": "stats", "path": "res://scripts/mechanics/stats/stats_mechanic.gd"},
	{"id": "crafting", "path": "res://scripts/mechanics/crafting/crafting_mechanic.gd"},
	{"id": "mobs", "path": "res://scripts/mechanics/mobs/mobs_mechanic.gd"},
	{"id": "audio", "path": "res://scripts/mechanics/audio/audio_mechanic.gd"},
]

var flags: Dictionary = {}
var _mechanics: Dictionary = {}
var _world: Node = null
var _warned: Dictionary = {}

func _ready() -> void:
	flags = FeatureFlags.resolved(FeatureFlags.DEFAULTS, _read_config())
	print("[FEATURES] %s" % FeatureFlags.summary(flags))

## Включена ли механика или базовая система. Неизвестный id считается
## выключенным: лучше ничего не показать, чем упасть.
func on(feature_id: String) -> bool:
	if flags.has(feature_id):
		return bool(flags[feature_id])
	if not _warned.has(feature_id):
		_warned[feature_id] = true
		print("[FEATURES] неизвестный флаг: %s, считаю выключенным" % feature_id)
	return false

func set_flag(feature_id: String, value: bool) -> void:
	flags[feature_id] = value

## Создаёт включённые механики под узлом мира. Имя узла равно id, поэтому
## RPC внутри механики находят друг друга на сервере и на клиенте.
func attach_mechanics(world: Node) -> void:
	_world = world
	for entry in MECHANICS:
		var mechanic_id := String(entry.get("id", ""))
		if not on(mechanic_id):
			print("[FEATURES] механика выключена: %s" % mechanic_id)
			continue
		var path := String(entry.get("path", ""))
		if not ResourceLoader.exists(path):
			print("[FEATURES] нет файла механики %s: %s" % [mechanic_id, path])
			continue
		var script: Script = load(path)
		if script == null:
			print("[FEATURES] скрипт не загрузился: %s" % path)
			continue
		var node: Node = script.new()
		if node == null:
			continue
		node.setup(world)
		node.name = mechanic_id
		world.add_child(node)
		if node.has_method("start"):
			node.start()
		_mechanics[mechanic_id] = node
		print("[FEATURES] механика включена: %s" % mechanic_id)

func detach_mechanics() -> void:
	for key in _mechanics:
		var node: Node = _mechanics[key]
		if is_instance_valid(node):
			if node.has_method("stop"):
				node.stop()
			node.queue_free()
	_mechanics.clear()
	_world = null

## Узел механики или null. Все внешние обращения идут через этот метод,
## поэтому выключенная механика никого не ломает.
func mechanic(mechanic_id: String) -> Node:
	var node: Node = _mechanics.get(mechanic_id, null)
	if node == null or not is_instance_valid(node):
		return null
	return node

## Пути к файлу настроек в порядке приоритета.
func config_paths() -> Array:
	var paths: Array = []
	if not OS.has_feature("editor"):
		paths.append(OS.get_executable_path().get_base_dir().path_join(CONFIG_FILE))
	paths.append("res://" + CONFIG_FILE)
	return paths

func _read_config() -> Dictionary:
	for path in config_paths():
		if not FileAccess.file_exists(path):
			continue
		var config := ConfigFile.new()
		if config.load(path) != OK:
			print("[FEATURES] не прочитал настройки: %s" % path)
			continue
		var overrides := {}
		if not config.has_section(CONFIG_SECTION):
			print("[FEATURES] в %s нет секции [%s]" % [path, CONFIG_SECTION])
			return {}
		for key in config.get_section_keys(CONFIG_SECTION):
			overrides[String(key)] = bool(config.get_value(CONFIG_SECTION, key, true))
		var unknown := FeatureFlags.unknown_keys(FeatureFlags.DEFAULTS, overrides)
		if not unknown.is_empty():
			print("[FEATURES] неизвестные флаги в %s: %s" % [path, ", ".join(PackedStringArray(unknown))])
		print("[FEATURES] настройки из %s" % path)
		return overrides
	print("[FEATURES] файла %s нет, беру значения по умолчанию" % CONFIG_FILE)
	return {}
