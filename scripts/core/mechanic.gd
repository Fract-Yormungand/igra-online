class_name Mechanic
extends Node

## Контракт механики. Одна механика это отдельный узел под миром, у него своя
## папка в scripts/mechanics и своя строка в реестре Features.MECHANICS.
##
## Механика живёт по трём правилам:
##   1. Свои узлы строит сам, в чужие не лезет.
##   2. Своё состояние держит сам и само же гоняет по сети.
##   3. Остальной мир общается с ней только через Features.mechanic(id)
##      с проверкой на null. Нет механики, никто не падает.
##
## Как выключить: флаг в features.cfg (false) или удаление папки механики
## вместе со строкой в Features.MECHANICS. Ядро об этом не узнает.

## Узел мира, под которым живёт механика. Нужен, чтобы дотянуться до игроков,
## HUD и источников ресурсов, не копируя их состояние.
var world: Node = null

## Имя узла совпадает с id механики: по нему сходятся RPC на сервере и клиенте.
func id() -> String:
	return String(name)

## Вызывается до add_child. Здесь строятся узлы и читаются данные.
func setup(world_node: Node) -> void:
	world = world_node

## Вызывается после add_child. Здесь подключаются сигналы и запрашивается
## состояние у сервера.
func start() -> void:
	pass

## Вызывается перед удалением механики.
func stop() -> void:
	pass

func is_server() -> bool:
	return Net.is_host

func local_player() -> Player:
	if world == null or not world.has_method("get_local_player"):
		return null
	return world.get_local_player()
