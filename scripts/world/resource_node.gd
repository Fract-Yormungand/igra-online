class_name ResourceNode
extends StaticBody3D

## Источник ресурса в мире: дерево, осколки камня, руда. Данные о состоянии
## живут в Game, узел только рисует их и сообщает, доступен ли он.

var resource_id := 0
var resource_type := ""

var _visual: Node3D
var _shape: CollisionShape3D
var _last_hits := -1
var _tween: Tween

func setup(id: int, type: String, ground_position: Vector3, rot_y: float, size_scale: float) -> void:
	resource_id = id
	resource_type = type
	position = ground_position
	rotation.y = rot_y
	scale = Vector3.ONE * size_scale

func _ready() -> void:
	add_to_group("resource_nodes")
	collision_layer = 2
	collision_mask = 0
	_build_visual()
	Game.resources_changed.connect(_refresh)
	_refresh()

func is_available() -> bool:
	var state: Dictionary = Game.resources.get(resource_id, {})
	return bool(state.get("alive", false))

func label() -> String:
	return Rules.label(resource_type)

func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	match resource_type:
		Rules.RESOURCE_TREE:
			_build_tree()
		Rules.RESOURCE_STONE:
			_build_stone()
		Rules.RESOURCE_ORE:
			_build_ore()
		_:
			_build_stone()

## Палка лежит на земле: тонкий цилиндр, чуть повёрнутый.
func _build_stick() -> void:
	var stick := MeshInstance3D.new()
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.045
	stick_mesh.bottom_radius = 0.06
	stick_mesh.height = 0.95
	stick_mesh.radial_segments = 6
	stick.mesh = stick_mesh
	stick.position = Vector3(0.0, 0.07, 0.0)
	stick.rotation = Vector3(0.0, 0.0, PI * 0.5)
	stick.material_override = _material(Color(0.46, 0.32, 0.17))
	_visual.add_child(stick)

	var knot := MeshInstance3D.new()
	var knot_mesh := BoxMesh.new()
	knot_mesh.size = Vector3(0.09, 0.09, 0.09)
	knot.mesh = knot_mesh
	knot.position = Vector3(0.28, 0.08, 0.05)
	knot.rotation = Vector3(0.2, 0.5, 0.0)
	knot.material_override = _material(Color(0.38, 0.26, 0.14))
	_visual.add_child(knot)

	_add_collision(_box(Vector3(1.0, 0.25, 0.35)), Vector3(0.0, 0.1, 0.0))

## Камень на земле: два небольших обломка, чтобы читался издалека.
func _build_pebble() -> void:
	var rock := MeshInstance3D.new()
	var rock_mesh := BoxMesh.new()
	rock_mesh.size = Vector3(0.42, 0.3, 0.36)
	rock.mesh = rock_mesh
	rock.position = Vector3(0.0, 0.15, 0.0)
	rock.rotation = Vector3(0.1, 0.5, 0.05)
	rock.material_override = _material(Color(0.54, 0.55, 0.57))
	_visual.add_child(rock)

	var chip := MeshInstance3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.2, 0.14, 0.18)
	chip.mesh = chip_mesh
	chip.position = Vector3(0.32, 0.07, 0.18)
	chip.rotation = Vector3(0.0, 0.9, 0.2)
	chip.material_override = _material(Color(0.47, 0.48, 0.50))
	_visual.add_child(chip)

	_add_collision(_box(Vector3(0.6, 0.3, 0.5)), Vector3(0.0, 0.15, 0.0))

func _build_tree() -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.30
	trunk_mesh.height = 2.6
	trunk_mesh.radial_segments = 8
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, 1.3, 0.0)
	trunk.material_override = _material(Color(0.38, 0.25, 0.13))
	_visual.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.5
	crown_mesh.height = 2.9
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 6
	crown.mesh = crown_mesh
	crown.position = Vector3(0.0, 3.2, 0.0)
	crown.material_override = _material(Color(0.18, 0.42, 0.18))
	_visual.add_child(crown)

	_add_collision(_capsule(0.45, 2.4), Vector3(0.0, 1.2, 0.0))

func _build_stone() -> void:
	var rock := MeshInstance3D.new()
	var rock_mesh := BoxMesh.new()
	rock_mesh.size = Vector3(1.5, 1.1, 1.3)
	rock.mesh = rock_mesh
	rock.position = Vector3(0.0, 0.55, 0.0)
	rock.rotation = Vector3(0.15, 0.4, -0.1)
	rock.material_override = _material(Color(0.52, 0.53, 0.55))
	_visual.add_child(rock)

	var chip := MeshInstance3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.7, 0.5, 0.6)
	chip.mesh = chip_mesh
	chip.position = Vector3(0.85, 0.25, 0.45)
	chip.rotation = Vector3(0.0, 0.9, 0.2)
	chip.material_override = _material(Color(0.45, 0.46, 0.48))
	_visual.add_child(chip)

	_add_collision(_box(Vector3(1.6, 1.15, 1.4)), Vector3(0.0, 0.55, 0.0))

func _build_ore() -> void:
	var rock := MeshInstance3D.new()
	var rock_mesh := BoxMesh.new()
	rock_mesh.size = Vector3(1.4, 1.2, 1.3)
	rock.mesh = rock_mesh
	rock.position = Vector3(0.0, 0.6, 0.0)
	rock.rotation = Vector3(0.2, 0.6, 0.05)
	rock.material_override = _material(Color(0.22, 0.22, 0.24))
	_visual.add_child(rock)

	var vein_material := _material(Color(0.80, 0.82, 0.90))
	vein_material.emission_enabled = true
	vein_material.emission = Color(0.55, 0.60, 0.75)
	vein_material.emission_energy_multiplier = 1.6

	for i in 4:
		var vein := MeshInstance3D.new()
		var vein_mesh := SphereMesh.new()
		vein_mesh.radius = 0.16
		vein_mesh.height = 0.32
		vein.mesh = vein_mesh
		var angle := TAU * float(i) / 4.0
		vein.position = Vector3(cos(angle) * 0.5, 0.55 + sin(angle) * 0.35, sin(angle) * 0.6)
		vein.material_override = vein_material
		_visual.add_child(vein)

	_add_collision(_box(Vector3(1.5, 1.25, 1.4)), Vector3(0.0, 0.6, 0.0))

func _add_collision(shape: Shape3D, offset: Vector3) -> void:
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position = offset
	add_child(_shape)

func _capsule(radius: float, height: float) -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	return shape

func _box(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _refresh() -> void:
	var state: Dictionary = Game.resources.get(resource_id, {})
	var alive := bool(state.get("alive", false))
	if _visual != null:
		_visual.visible = alive
	if _shape != null:
		_shape.set_deferred("disabled", not alive)

	var hits := int(state.get("hits", 0))
	if alive and _last_hits >= 0 and hits < _last_hits:
		_play_hit_feedback()
	_last_hits = hits

func _play_hit_feedback() -> void:
	if _visual == null:
		return
	if _tween != null and _tween.is_running():
		_tween.kill()
	_visual.scale = Vector3(1.08, 0.92, 1.08)
	_tween = create_tween()
	_tween.tween_property(_visual, "scale", Vector3.ONE, 0.18)
