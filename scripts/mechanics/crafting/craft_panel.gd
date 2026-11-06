extends VBoxContainer

## Вкладка крафта в окне сумки. Показывает рецепты, цену и кнопку.
## Ничего не решает: просит механику крафта, а считает сервер.
## Файл лежит в папке механики, поэтому удаление папки убирает и вкладку.

var _list: VBoxContainer
var _status: Label
var _rows: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()
	var crafting := _crafting()
	if crafting != null and crafting.has_signal("craft_changed"):
		crafting.craft_changed.connect(_on_craft_changed)
	Game.inventory_changed.connect(_on_inventory_changed)
	refresh()

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_status = _label("", 14, Color(0.80, 0.86, 0.92))
	add_child(_status)

func refresh() -> void:
	if _list == null:
		return
	if _list.get_child_count() == 0:
		for recipe_id in Recipes.ids():
			_list.add_child(_build_row(String(recipe_id)))

	var inv: Inventory = Game.get_inventory(Net.my_id)
	var busy := _busy_recipe()
	for key in _rows:
		var recipe_id := String(key)
		var row: Dictionary = _rows[recipe_id]
		var button: Button = row["button"]
		var price: Label = row["price"]
		var enough := Recipes.can_craft(recipe_id, inv)
		var room := inv == null or inv.free_space(Recipes.output_item(recipe_id)) > 0
		button.disabled = not busy.is_empty() or not enough or not room
		price.add_theme_color_override(
			"font_color",
			Color(0.78, 0.84, 0.90) if enough else Color(0.88, 0.60, 0.56)
		)
	_status.text = _status_text(busy)

func _build_row(recipe_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)

	text.add_child(_label(Recipes.display_name(recipe_id), 16, Color(1, 1, 1)))
	var price := _label(Recipes.cost_text(recipe_id), 13, Color(0.78, 0.84, 0.90))
	text.add_child(price)

	var button := Button.new()
	button.text = "Сделать"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(110.0, 0.0)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(_on_craft_pressed.bind(recipe_id))
	row.add_child(button)

	_rows[recipe_id] = {"button": button, "price": price}
	return row

func _status_text(busy: String) -> String:
	if not busy.is_empty():
		return "В работе: %s" % Recipes.display_name(busy)
	return "Дерево даёт топор, камень и металл добывает кирка"

func _busy_recipe() -> String:
	var crafting := _crafting()
	if crafting == null:
		return ""
	return String(crafting.job(Net.my_id).get("recipe", ""))

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _crafting() -> Node:
	return Features.mechanic("crafting")

func _on_craft_pressed(recipe_id: String) -> void:
	var crafting := _crafting()
	if crafting == null:
		return
	crafting.request_craft(recipe_id)
	refresh()

func _on_craft_changed(peer_id: int) -> void:
	if peer_id == Net.my_id:
		refresh()

func _on_inventory_changed(peer_id: int) -> void:
	if peer_id == Net.my_id:
		refresh()
