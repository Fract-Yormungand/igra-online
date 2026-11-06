class_name ToolVisual
extends Node3D

## Модель инструмента в руке. Собрана из примитивов: цилиндр это рукоять,
## бокс это голова. Персонаж и сеть о модели ничего не знают, узел только
## показывает то, что лежит в руке.

## Куда вешаем модель относительно тела персонажа.
const HAND_POSITION := Vector3(0.42, 1.02, -0.14)
## Наклон, чтобы инструмент смотрел вперёд, а не торчал вверх.
const HAND_ROTATION := Vector3(-68.0, 0.0, -14.0)

const WOOD := Color(0.46, 0.32, 0.17)
const WOOD_LIGHT := Color(0.55, 0.40, 0.22)
const STONE := Color(0.55, 0.56, 0.58)
const STONE_DARK := Color(0.44, 0.45, 0.47)

var _model: Node3D

func _ready() -> void:
	position = HAND_POSITION
	rotation_degrees = HAND_ROTATION
	visible = false

## Показать предмет в руке. Пустая строка убирает модель.
func show_item(item_id: String) -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	visible = false
	if item_id.is_empty():
		return

	_model = Node3D.new()
	add_child(_model)
	match item_id:
		"primitive_axe":
			_build_axe(0.75, 0.20, 0.10, WOOD_LIGHT, STONE)
		"primitive_pickaxe":
			_build_pickaxe(0.75, 0.42, 0.08, WOOD_LIGHT, STONE)
		"primitive_spear":
			_build_spear(1.15, 0.16, WOOD_LIGHT, STONE)
		"axe":
			_build_axe(0.85, 0.28, 0.14, WOOD, STONE_DARK)
		"pickaxe":
			_build_pickaxe(0.85, 0.55, 0.10, WOOD, STONE_DARK)
		"spear":
			_build_spear(1.45, 0.22, WOOD, STONE_DARK)
		_:
			return
	visible = true

# --- модели ----------------------------------------------------------------

## Топор: рукоять и клин на конце.
func _build_axe(handle_length: float, blade_width: float, blade_height: float, wood: Color, head: Color) -> void:
	_add_cylinder(Vector3.ZERO, 0.030, handle_length, wood)
	_add_box(Vector3(blade_width * 0.5, blade_height, 0.07), Vector3(blade_width * 0.30, handle_length * 0.5, 0.0), head)
	_add_box(Vector3(blade_width * 0.35, blade_height * 0.55, 0.09), Vector3(blade_width * 0.62, handle_length * 0.5, 0.0), head.darkened(0.15))

## Кирка: рукоять и поперечина с двумя концами.
func _build_pickaxe(handle_length: float, head_width: float, head_height: float, wood: Color, head: Color) -> void:
	_add_cylinder(Vector3.ZERO, 0.030, handle_length, wood)
	var bar := _add_box(Vector3(head_width, head_height, head_height * 0.8), Vector3(0.0, handle_length * 0.5, 0.0), head)
	bar.rotation.z = 0.0
	for side in [-1.0, 1.0]:
		var tip := _add_box(
			Vector3(head_width * 0.28, head_height * 0.7, head_height * 0.7),
			Vector3(head_width * 0.5 * side, handle_length * 0.5 - head_height * 0.2, 0.0),
			head.darkened(0.12)
		)
		tip.rotation.z = -0.5 * side

## Копьё: длинное древко, наконечник и обмотка под ним.
func _build_spear(shaft_length: float, tip_length: float, wood: Color, head: Color) -> void:
	_add_cylinder(Vector3.ZERO, 0.026, shaft_length, wood)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.055
	cone.height = tip_length
	cone.radial_segments = 8
	tip.mesh = cone
	tip.position = Vector3(0.0, shaft_length * 0.5 + tip_length * 0.5, 0.0)
	tip.material_override = _material(head)
	_model.add_child(tip)
	_add_box(Vector3(0.05, 0.06, 0.05), Vector3(0.0, shaft_length * 0.5 - 0.03, 0.0), wood.darkened(0.25))

# --- примитивы -------------------------------------------------------------

func _add_cylinder(spot: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.15
	mesh.height = height
	mesh.radial_segments = 8
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = spot
	node.material_override = _material(color)
	_model.add_child(node)
	return node

func _add_box(size: Vector3, spot: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = spot
	node.material_override = _material(color)
	_model.add_child(node)
	return node

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
