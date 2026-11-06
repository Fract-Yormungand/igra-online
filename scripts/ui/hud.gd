extends CanvasLayer

## Интерфейс: состояние сети, зона, подсказка у источника, сумка,
## панель быстрого доступа и короткие сообщения от сервера.

var _world: Node = null

var _root: Control
var _status: Label
var _zone: Label
var _hint: Label
var _prompt: Label
var _toast: Label
var _inv_panel: PanelContainer
var _inv_list: VBoxContainer
var _hotbar_slots: Dictionary = {}

var _toast_left := 0.0

func setup(world: Node) -> void:
	_world = world
	_build()
	Game.inventory_changed.connect(_on_inventory_changed)
	Game.equipped_changed.connect(_on_equipped_changed)
	Game.state_reset.connect(refresh_all)
	Game.notice.connect(show_notice)
	Net.roster_changed.connect(_on_roster_changed)
	refresh_all()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 16)
	column.add_child(top)

	_status = _make_label("", 16, Color(0.92, 0.95, 1.0))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)

	_zone = _make_label("", 20, Color(1.0, 1.0, 1.0))
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_zone)

	_hint = _make_label("Tab — сумка    E — добыча    1/2 — инструмент", 14, Color(0.86, 0.90, 0.94))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_hint)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_prompt = _make_label("", 18, Color(1.0, 0.95, 0.70))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_prompt)

	_toast = _make_label("", 16, Color(1.0, 0.62, 0.52))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_toast)

	var hotbar_wrap := CenterContainer.new()
	hotbar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hotbar_wrap)

	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 8)
	hotbar_wrap.add_child(hotbar)

	for i in ItemDB.HOTBAR.size():
		var item_id := String(ItemDB.HOTBAR[i])
		var slot := _make_label("%d  %s" % [i + 1, ItemDB.display_name(item_id)], 16, Color(1, 1, 1))
		slot.add_theme_stylebox_override("normal", _slot_style(false))
		hotbar.add_child(slot)
		_hotbar_slots[item_id] = slot

	var crosshair := _make_label("+", 22, Color(1.0, 1.0, 1.0, 0.75))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -14.0
	crosshair.offset_top = -16.0
	crosshair.offset_right = 14.0
	crosshair.offset_bottom = 16.0
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(crosshair)

	_build_inventory()

func _build_inventory() -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_inv_panel.offset_left = -210.0
	_inv_panel.offset_top = -160.0
	_inv_panel.offset_right = 210.0
	_inv_panel.offset_bottom = 160.0
	_inv_panel.visible = false
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Своя подложка: тема по умолчанию просвечивает и текст теряется на фоне мира.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.10, 0.96)
	panel_style.border_color = Color(0.45, 0.55, 0.45, 0.90)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	_inv_panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(_inv_panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_inv_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _make_label("Сумка", 22, Color(1, 1, 1))
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_inv_list = VBoxContainer.new()
	_inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_inv_list)

	column.add_child(_make_label("Tab или Esc — закрыть", 14, Color(0.82, 0.86, 0.90)))

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _slot_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.28, 0.16, 0.92) if active else Color(0.08, 0.09, 0.11, 0.82)
	style.border_color = Color(0.85, 0.95, 0.65, 0.95) if active else Color(0.30, 0.33, 0.38, 0.85)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

# --- обновление ------------------------------------------------------------

func _process(delta: float) -> void:
	if _status != null:
		_status.text = _network_text()

	var player := _local_player()
	if _zone != null:
		if player == null:
			_zone.text = ""
		else:
			_zone.text = WorldGen.zone_at(player.global_position)

	if _prompt != null:
		_prompt.text = _prompt_text(player)

	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0 and _toast != null:
			_toast.text = ""

func _local_player() -> Player:
	if _world == null:
		return null
	return _world.get_local_player()

func _network_text() -> String:
	var mode := "Нет сети"
	if Net.is_host:
		mode = "Сервер"
	elif Net.is_client:
		mode = "Клиент"
	return "%s • игроков: %d • %s" % [mode, Net.player_count(), Net.nick_of(Net.my_id)]

func _prompt_text(player: Player) -> String:
	if player == null:
		return ""
	var target: ResourceNode = player.get_target()
	if target == null:
		return ""
	var tool := ItemDB.tool_tag(Game.get_equipped(Net.my_id))
	if Rules.can_harvest(target.resource_type, tool):
		return "E — добыть: %s" % target.label()
	var need := Rules.required_tool(target.resource_type)
	return "E — нужен инструмент: %s" % ItemDB.display_name(need)

func refresh_all() -> void:
	_refresh_inventory()
	_refresh_hotbar()

func _refresh_inventory() -> void:
	if _inv_list == null:
		return
	for child in _inv_list.get_children():
		child.queue_free()

	var inv: Inventory = Game.get_inventory(Net.my_id)
	if inv == null or inv.is_empty():
		_inv_list.add_child(_make_label("Пусто", 16, Color(0.80, 0.83, 0.88)))
		return

	var data := inv.items()
	var keys := data.keys()
	keys.sort()
	for item_id in keys:
		var text := "%s — %d" % [ItemDB.display_name(String(item_id)), int(data[item_id])]
		_inv_list.add_child(_make_label(text, 18, ItemDB.color(String(item_id))))

func _refresh_hotbar() -> void:
	var current := Game.get_equipped(Net.my_id)
	for i in ItemDB.HOTBAR.size():
		var item_id := String(ItemDB.HOTBAR[i])
		var slot: Label = _hotbar_slots.get(item_id, null)
		if slot == null:
			continue
		var owned := _owns(item_id)
		slot.add_theme_stylebox_override("normal", _slot_style(item_id == current))
		slot.modulate = Color(1, 1, 1, 1) if owned else Color(1, 1, 1, 0.45)

func _owns(item_id: String) -> bool:
	var inv: Inventory = Game.get_inventory(Net.my_id)
	return inv != null and inv.has(item_id)

func show_notice(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast_left = 2.5

func _on_inventory_changed(peer_id: int) -> void:
	if peer_id == Net.my_id:
		refresh_all()

func _on_equipped_changed(peer_id: int) -> void:
	if peer_id == Net.my_id:
		_refresh_hotbar()

func _on_roster_changed(_players: Dictionary) -> void:
	_refresh_hotbar()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and Game.ui_inventory_open:
		_toggle_inventory()
		get_viewport().set_input_as_handled()

func _toggle_inventory() -> void:
	Game.ui_inventory_open = not Game.ui_inventory_open
	if _inv_panel != null:
		_inv_panel.visible = Game.ui_inventory_open
	if DisplayServer.get_name() == "headless":
		return
	if Game.ui_inventory_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
