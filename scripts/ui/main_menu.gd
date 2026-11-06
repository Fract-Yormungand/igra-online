class_name MainMenu
extends Control

## Меню: имя, порт, адрес. Отсюда либо поднимаем сервер, либо подключаемся.

signal host_requested(nick: String, port: int)
signal join_requested(nick: String, address: String, port: int)

const DEFAULT_PORT := 7777

var _nick_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: LineEdit
var _status: Label
var _addresses: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.06, 0.07, 0.09)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(340.0, 0.0)
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_label("Игра онлайн", 30, Color(0.95, 0.97, 1.0)))
	column.add_child(_label("Площадка, лес, каменоломня у горы и шахта внутри.", 14, Color(0.75, 0.80, 0.86)))

	column.add_child(_label("Имя", 14, Color(0.72, 0.78, 0.84)))
	_nick_edit = LineEdit.new()
	_nick_edit.text = "Игрок"
	_nick_edit.max_length = 16
	column.add_child(_nick_edit)

	column.add_child(_label("Порт", 14, Color(0.72, 0.78, 0.84)))
	_port_edit = LineEdit.new()
	_port_edit.text = str(DEFAULT_PORT)
	_port_edit.text_changed.connect(_on_port_changed)
	column.add_child(_port_edit)

	# Адрес, который надо назвать другу. Считается из сетевых интерфейсов
	# машины, поэтому всегда актуален.
	_addresses = _label("", 12, Color(0.60, 0.74, 0.60))
	column.add_child(_addresses)
	_refresh_addresses()

	var host_button := Button.new()
	host_button.text = "Создать сервер"
	host_button.pressed.connect(_on_host_pressed)
	_style_button(host_button, true)
	column.add_child(host_button)

	column.add_child(_label("Адрес сервера для подключения", 14, Color(0.72, 0.78, 0.84)))
	_address_edit = LineEdit.new()
	_address_edit.text = "127.0.0.1"
	column.add_child(_address_edit)

	var join_button := Button.new()
	join_button.text = "Подключиться"
	join_button.pressed.connect(_on_join_pressed)
	_style_button(join_button, false)
	column.add_child(join_button)

	_status = _label("", 14, Color(1.0, 0.74, 0.58))
	column.add_child(_status)

	column.add_child(_label("При первом запуске сервера разреши игру в брандмауэре Windows.", 12, Color(0.62, 0.66, 0.72)))
	column.add_child(_label("Через интернет проще через Radmin VPN, Tailscale или ZeroTier: они дают общий адрес и не требуют проброса порта.", 12, Color(0.62, 0.66, 0.72)))

func _on_port_changed(_text: String) -> void:
	_refresh_addresses()

func _refresh_addresses() -> void:
	if _addresses == null:
		return
	var found: Array = []
	for address in IP.get_local_addresses():
		if not address.is_valid_ip_address():
			continue
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("0."):
			continue
		if address.begins_with("169.254."):
			continue
		found.append(address)
	if found.is_empty():
		_addresses.text = "Свой адрес в сети не определён, подключение только по внешнему IP"
		return
	_addresses.text = "Твой адрес для друзей: %s, порт %d" % [", ".join(found), _port()]

func set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func _on_host_pressed() -> void:
	host_requested.emit(_nick(), _port())

func _on_join_pressed() -> void:
	join_requested.emit(_nick(), _address(), _port())

func _nick() -> String:
	var nick := _nick_edit.text.strip_edges()
	return "Игрок" if nick.is_empty() else nick

func _address() -> String:
	var address := _address_edit.text.strip_edges()
	return "127.0.0.1" if address.is_empty() else address

func _port() -> int:
	var port := int(_port_edit.text.strip_edges())
	return DEFAULT_PORT if port <= 0 else port

## Кнопки по умолчанию в тёмной сцене выглядят как текст: без своей подложки
## новичок не понимает, что на это можно нажать.
func _style_button(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.42, 0.24) if primary else Color(0.16, 0.17, 0.20)
	normal.border_color = Color(0.55, 0.85, 0.55, 0.85) if primary else Color(0.33, 0.36, 0.42, 0.90)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(12.0)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.14)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.18)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_font_size_override("font_size", 18)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
