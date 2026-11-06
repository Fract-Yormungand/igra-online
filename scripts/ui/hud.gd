extends CanvasLayer

## Интерфейс: состояние сети, зона, подсказка у источника, сумка,
## панель быстрого доступа и короткие сообщения от сервера.

var _world: Node = null

## Сетка сумки: пять ячеек в ряд, ячейка под один стак предмета.
const GRID_COLUMNS := 5
const GRID_CELL := Vector2(92.0, 62.0)

var _root: Control
var _status: Label
var _zone: Label
var _clock: Label
var _hint: Label
var _prompt: Label
var _toast: Label
var _inv_panel: PanelContainer
var _inv_view: Control
var _inv_grid: GridContainer
var _craft_panel: Control
var _tab_items: Button
var _tab_craft: Button
var _hotbar_slots: Dictionary = {}

var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _hp_text: Label
var _mp_text: Label
var _stats_panel: Control
var _bars_left := 0.0

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

	var status_box := VBoxContainer.new()
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_box.add_theme_constant_override("separation", 4)
	top.add_child(status_box)

	_status = _make_label("", 16, Color(0.92, 0.95, 1.0))
	status_box.add_child(_status)

	# Полоски здоровья и запаса сил видно всегда: окно статуса открывают
	# редко, а понимать, сколько осталось, нужно постоянно.
	var bars := HBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 6)
	status_box.add_child(bars)

	_hp_bar = _make_bar(Color(0.78, 0.26, 0.26), 160.0)
	bars.add_child(_hp_bar)
	_hp_text = _make_label("", 13, Color(0.96, 0.90, 0.90))
	bars.add_child(_hp_text)

	_mp_bar = _make_bar(Color(0.30, 0.52, 0.92), 130.0)
	bars.add_child(_mp_bar)
	_mp_text = _make_label("", 13, Color(0.88, 0.92, 1.0))
	bars.add_child(_mp_text)

	var center_box := VBoxContainer.new()
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_box.add_theme_constant_override("separation", 0)
	top.add_child(center_box)

	_zone = _make_label("", 20, Color(1.0, 1.0, 1.0))
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_zone)

	_clock = _make_label("", 14, Color(0.86, 0.90, 0.98, 0.85))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_clock)

	_hint = _make_label("Tab — сумка и крафт    C — статус    E — добыча    ЛКМ — удар    Shift — бег    Alt — шаг    1/2/3 — топор, кирка, копьё    Esc — меню", 14, Color(0.86, 0.90, 0.94))
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
	_build_stats()

## Окно статуса живёт в папке механики: удалил папку, окна нет, HUD цел.
func _build_stats() -> void:
	if not Features.on("stats"):
		return
	var path := "res://scripts/mechanics/stats/stats_panel.gd"
	if not ResourceLoader.exists(path):
		return
	var script: Script = load(path)
	if script == null:
		return
	var panel: Control = script.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	_root.add_child(panel)
	_stats_panel = panel

func _build_inventory() -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_inv_panel.offset_left = -280.0
	_inv_panel.offset_top = -225.0
	_inv_panel.offset_right = 280.0
	_inv_panel.offset_bottom = 225.0
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

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)

	_tab_items = _tab_button("Предметы")
	_tab_items.button_pressed = true
	_tab_items.pressed.connect(_show_tab.bind(false))
	tabs.add_child(_tab_items)

	_tab_craft = _tab_button("Крафт")
	_tab_craft.visible = false
	_tab_craft.pressed.connect(_show_tab.bind(true))
	tabs.add_child(_tab_craft)

	_inv_view = ScrollContainer.new()
	_inv_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_inv_view)

	_inv_grid = GridContainer.new()
	_inv_grid.columns = GRID_COLUMNS
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_grid.add_theme_constant_override("h_separation", 6)
	_inv_grid.add_theme_constant_override("v_separation", 6)
	_inv_view.add_child(_inv_grid)

	# Вкладка крафта живёт в папке механики: нет механики, нет и вкладки.
	_craft_panel = _build_craft()
	if _craft_panel != null:
		column.add_child(_craft_panel)
		_tab_craft.visible = true

	column.add_child(_make_label("Tab или Esc — закрыть", 14, Color(0.82, 0.86, 0.90)))
	_show_tab(false)

## Вкладка крафта собирается по пути из папки механики. Механики нет,
## файла нет, и сумка остаётся только с предметами.
func _build_craft() -> Control:
	if not Features.on("crafting"):
		return null
	var path := "res://scripts/mechanics/crafting/craft_panel.gd"
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	if script == null:
		return null
	var panel: Control = script.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.visible = false
	return panel

func _show_tab(craft: bool) -> void:
	var allowed := craft and _craft_panel != null
	if _inv_view != null:
		_inv_view.visible = not allowed
	if _craft_panel != null:
		_craft_panel.visible = allowed
	if _tab_items != null:
		_tab_items.button_pressed = not allowed
	if _tab_craft != null:
		_tab_craft.button_pressed = allowed
	if allowed and _craft_panel.has_method("refresh"):
		_craft_panel.refresh()

func _tab_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _tab_style(false))
	button.add_theme_stylebox_override("hover", _tab_style(false))
	button.add_theme_stylebox_override("pressed", _tab_style(true))
	button.add_theme_stylebox_override("disabled", _tab_style(false))
	return button

func _tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.32, 0.20, 0.96) if active else Color(0.11, 0.12, 0.15, 0.96)
	style.border_color = Color(0.55, 0.85, 0.55, 0.95) if active else Color(0.28, 0.31, 0.36, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style

## Одна ячейка сетки. Пустая запись это пустая ячейка: сетка без пустых
## мест выглядит списком, а не сумкой.
func _make_slot(entry: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = GRID_CELL
	var item_id := String(entry.get("item", ""))
	cell.add_theme_stylebox_override("panel", _cell_style(item_id))
	if item_id.is_empty():
		return cell

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(column)

	var item_name := _make_label(ItemDB.display_name(item_id), 12, ItemDB.color(item_id))
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(item_name)

	var count := _make_label("%d" % int(entry.get("count", 0)), 16, Color(1, 1, 1))
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(count)
	return cell

func _cell_style(item_id: String) -> StyleBoxFlat:
	var filled := not item_id.is_empty()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.18, 0.92) if filled else Color(0.09, 0.10, 0.12, 0.85)
	style.border_color = ItemDB.color(item_id).darkened(0.25) if filled else Color(0.20, 0.22, 0.26, 0.85)
	style.set_border_width_all(2 if filled else 1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 14.0)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.07, 0.09, 0.85)
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

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
	_refresh_bars(delta)

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

	if _clock != null:
		_clock.text = DayCycle.clock_text(DayCycle.progress_now())

	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0 and _toast != null:
			_toast.text = ""

## Полоски обновляем пять раз в секунду: каждый кадр незачем, а запаздывание
## на доли секунды глаз не замечает.
func _refresh_bars(delta: float) -> void:
	if _hp_bar == null:
		return
	_bars_left -= delta
	if _bars_left > 0.0:
		return
	_bars_left = 0.2
	var stats := Features.mechanic("stats")
	if stats == null:
		_hp_bar.value = 0.0
		_mp_bar.value = 0.0
		_hp_text.text = ""
		_mp_text.text = ""
		return
	var peer_id := Net.my_id
	var max_hp: float = maxf(1.0, stats.max_hp(peer_id))
	var max_mp: float = maxf(1.0, stats.max_mp(peer_id))
	var hp: float = stats.hp(peer_id)
	var mp: float = stats.mp(peer_id)
	_hp_bar.max_value = max_hp
	_hp_bar.value = clampf(hp, 0.0, max_hp)
	_mp_bar.max_value = max_mp
	_mp_bar.value = clampf(mp, 0.0, max_mp)
	_hp_text.text = "%d/%d" % [int(round(hp)), int(round(max_hp))]
	_mp_text.text = "%d/%d" % [int(round(mp)), int(round(max_mp))]

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
	var car := player.get_vehicle()
	if car != null:
		return "E — выйти из машины    %d км/ч    W/S газ и назад, A/D руль" % int(round(car.speed_kmh()))
	var near := player.get_target_vehicle()
	if near != null:
		return "E — сесть за руль"
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
	if _inv_grid == null:
		return
	for child in _inv_grid.get_children():
		# remove_child сразу: queue_free оставил бы старые ячейки на кадр.
		_inv_grid.remove_child(child)
		child.queue_free()

	var inv: Inventory = Game.get_inventory(Net.my_id)
	var stacks: Array = inv.slots() if inv != null else []
	var cells := maxi(stacks.size(), Inventory.MIN_SLOTS)
	for i in cells:
		if i < stacks.size():
			_inv_grid.add_child(_make_slot(stacks[i]))
		else:
			_inv_grid.add_child(_make_slot({}))

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
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		# Esc по шагам: закрыть окно статуса и сумку, потом освободить курсор,
		# потом выйти в меню. Без последнего шага из мира не выйти.
		if _stats_panel != null and _stats_panel.visible:
			_toggle_stats()
		elif Game.ui_inventory_open:
			_toggle_inventory()
		elif _is_cursor_captured():
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Net.request_leave()
		get_viewport().set_input_as_handled()

func _is_cursor_captured() -> bool:
	return DisplayServer.get_name() != "headless" and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

func _toggle_stats() -> void:
	if _stats_panel == null:
		return
	_stats_panel.visible = not _stats_panel.visible
	if _stats_panel.visible and _stats_panel.has_method("refresh"):
		_stats_panel.refresh()

func _toggle_inventory() -> void:
	Game.ui_inventory_open = not Game.ui_inventory_open
	if _inv_panel != null:
		_inv_panel.visible = Game.ui_inventory_open
	if Game.ui_inventory_open:
		_refresh_inventory()
		if _craft_panel != null and _craft_panel.visible and _craft_panel.has_method("refresh"):
			_craft_panel.refresh()
	if DisplayServer.get_name() == "headless":
		return
	if Game.ui_inventory_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
