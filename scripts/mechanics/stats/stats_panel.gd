extends Control

## Окно статуса: здоровье, запас сил, характеристики и то, что из них выходит.
## Данные берёт у механики stats, сама ничего не считает. Нет механики, окно
## просто показывает прочерки и не ломает остальной интерфейс.

const REFRESH_INTERVAL := 0.2
const UNKNOWN := "—"

var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _hp_text: Label
var _mp_text: Label
var _attribute_values: Dictionary = {}
var _derived_label: Label
var _refresh_left := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	refresh()

func refresh() -> void:
	if _hp_bar == null:
		return
	var stats := Features.mechanic("stats")
	if stats == null:
		_set_unavailable()
		return
	var peer_id := Net.my_id
	var attrs: Dictionary = stats.attributes(peer_id)
	var max_hp: float = maxf(1.0, stats.max_hp(peer_id))
	var max_mp: float = maxf(1.0, stats.max_mp(peer_id))
	var hp: float = stats.hp(peer_id)
	var mp: float = stats.mp(peer_id)

	_hp_bar.max_value = max_hp
	_hp_bar.value = clampf(hp, 0.0, max_hp)
	_mp_bar.max_value = max_mp
	_mp_bar.value = clampf(mp, 0.0, max_mp)
	_hp_text.text = "%d / %d" % [int(round(hp)), int(round(max_hp))]
	_mp_text.text = "%d / %d" % [int(round(mp)), int(round(max_mp))]

	for key in _attribute_values:
		var label: Label = _attribute_values[key]
		label.text = str(int(attrs.get(key, 0)))

	var derived: Dictionary = stats.derived(peer_id)
	var best: Dictionary = derived.get("magic_best", {})
	_derived_label.text = "\n".join(PackedStringArray([
		"Состояние           x%.2f" % float(derived["coefficient"]),
		"Скорость            %d км/ч" % int(round(float(derived["speed_kmh"]))),
		"Действий за раунд   %d" % int(derived["actions"]),
		"Удар по телу %d: %.1f" % [int(attrs["body"]), float(derived["reference_damage"])],
		"Подъём на руку      %d кг" % int(round(float(derived["carry_kg"]))),
		"Потолок магии       %d" % int(round(float(derived["magic_ceiling"]))),
		"Лучший заряд        %d шагов" % int(best.get("steps", 0)),
		"Предел перегруза    %d" % int(round(float(derived["overload_limit"]))),
		"Самоурон за раунд   %.1f" % float(derived["overload_self"]),
	]))

func _set_unavailable() -> void:
	_hp_bar.value = 0.0
	_mp_bar.value = 0.0
	_hp_text.text = UNKNOWN
	_mp_text.text = UNKNOWN
	for key in _attribute_values:
		var label: Label = _attribute_values[key]
		label.text = UNKNOWN
	_derived_label.text = "Механика характеристик выключена"

# --- построение ------------------------------------------------------------

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_label("Статус", 22, Color(1.0, 1.0, 1.0)))

	var hp_row := _bar_row("Здоровье", Color(0.78, 0.26, 0.26))
	_hp_bar = hp_row["bar"]
	_hp_text = hp_row["value"]
	column.add_child(hp_row["row"])

	var mp_row := _bar_row("Запас сил", Color(0.30, 0.52, 0.92))
	_mp_bar = mp_row["bar"]
	_mp_text = mp_row["value"]
	column.add_child(mp_row["row"])

	column.add_child(_label("Характеристики", 18, Color(0.86, 0.92, 1.0)))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for key in DerivedStats.ATTRIBUTE_KEYS:
		grid.add_child(_label(String(DerivedStats.ATTRIBUTE_NAMES[key]), 16, Color(0.80, 0.84, 0.90)))
		var value := _label(UNKNOWN, 16, Color(1.0, 1.0, 1.0))
		grid.add_child(value)
		_attribute_values[key] = value

	column.add_child(_label("Что из этого выходит", 18, Color(0.86, 0.92, 1.0)))
	_derived_label = _label(UNKNOWN, 15, Color(0.86, 0.90, 0.96))
	column.add_child(_derived_label)

	column.add_child(_label("C или Esc — закрыть", 13, Color(0.72, 0.78, 0.84)))

func _bar_row(title: String, color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := _label(title, 16, Color(0.88, 0.92, 0.98))
	name_label.custom_minimum_size = Vector2(110.0, 0.0)
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220.0, 18.0)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.07, 0.09, 0.90)
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var value := _label(UNKNOWN, 15, Color(1.0, 1.0, 1.0))
	value.custom_minimum_size = Vector2(90.0, 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return {"row": row, "bar": bar, "value": value}

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.10, 0.96)
	style.border_color = Color(0.42, 0.52, 0.62, 0.90)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
