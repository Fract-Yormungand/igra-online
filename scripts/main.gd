extends Node

## Точка входа: меню или автозапуск сервера и клиента по аргументам.
## Аргументы после "--": --server [порт], --client <адрес> [порт],
## --e2e <адрес> [порт] для сквозного теста.

const WORLD_SCENE := preload("res://scenes/world.tscn")
const E2E_SCRIPT := "res://tests/e2e_harvest.gd"

var _menu: Control = null
var _world: Node = null
var _e2e: Node = null

func _ready() -> void:
	Net.status_changed.connect(_on_status_changed)
	Net.connection_lost.connect(_on_connection_lost)

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_show_menu()
		return
	_run_args(args)

func _run_args(args: PackedStringArray) -> void:
	var mode := String(args[0])
	match mode:
		"--server":
			var port := int(args[1]) if args.size() > 1 else Net.DEFAULT_PORT
			_start_host("Сервер", port)
		"--client":
			var address := String(args[1]) if args.size() > 1 else "127.0.0.1"
			var port := int(args[2]) if args.size() > 2 else Net.DEFAULT_PORT
			_start_join("Клиент", address, port, false)
		"--e2e":
			var address := String(args[1]) if args.size() > 1 else "127.0.0.1"
			var port := int(args[2]) if args.size() > 2 else Net.DEFAULT_PORT
			_start_join("Тест", address, port, true)
		_:
			print("Неизвестный аргумент: %s" % mode)
			_show_menu()

func _show_menu() -> void:
	if _menu != null:
		return
	var menu := MainMenu.new()
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	add_child(menu)
	_menu = menu

func _on_host_requested(nick: String, port: int) -> void:
	_start_host(nick, port)

func _on_join_requested(nick: String, address: String, port: int) -> void:
	_start_join(nick, address, port, false)

func _start_host(nick: String, port: int) -> void:
	if not Net.host(port, nick):
		_show_menu()
		return
	_start_world(false)

func _start_join(nick: String, address: String, port: int, run_test: bool) -> void:
	if not Net.join(address, port, nick):
		_show_menu()
		return
	_start_world(run_test)

func _start_world(run_test: bool) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _world != null:
		return
	_world = WORLD_SCENE.instantiate()
	add_child(_world)
	if run_test:
		var script := load(E2E_SCRIPT)
		if script != null:
			_e2e = script.new()
			_e2e.name = "E2E"
			add_child(_e2e)

func _on_status_changed(text: String) -> void:
	print("[NET] %s" % text)
	if _menu != null:
		_menu.set_status(text)

func _on_connection_lost(reason: String) -> void:
	if _world != null:
		_world.queue_free()
		_world = null
	if _e2e != null:
		_e2e.queue_free()
		_e2e = null
	_show_menu()
	if _menu != null:
		_menu.set_status(reason)
