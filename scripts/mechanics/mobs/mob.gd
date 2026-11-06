class_name Mob
extends Node3D

## Один моб в мире: внешность и плавное движение к последней позиции с
## сервера. Поведение, здоровье и урон живут в mobs_mechanic.gd, узел о них
## ничего не знает и ничего не решает.

const LERP_SPEED := 12.0

var mob_id := 0
var mob_type := ""

var _visual: Node3D
var _target_position := Vector3.ZERO
var _target_yaw := 0.0
var _remote := false
var _alive := true
var _flash := 0.0

func setup(id: int, type: String, spot: Vector3, rot_y: float) -> void:
	mob_id = id
	mob_type = type
	position = spot
	rotation.y = rot_y
	_target_position = spot
	_target_yaw = rot_y

func _ready() -> void:
	add_to_group("mobs")
	_build_visual()

## Клиент поведение не считает: он только догоняет сервер.
func set_remote(value: bool) -> void:
	_remote = value

func is_alive() -> bool:
	return _alive

## Состояние с сервера: куда моб пришёл и жив ли он.
func apply_state(spot: Vector3, yaw: float, alive: bool, health_share: float) -> void:
	_target_position = spot
	_target_yaw = yaw
	_alive = alive
	visible = alive
	if health_share < 0.999:
		_flash = maxf(_flash, 0.08)

func flash_hit() -> void:
	_flash = 0.25

func _process(delta: float) -> void:
	if _remote and _alive:
		var weight := clampf(delta * LERP_SPEED, 0.0, 1.0)
		position = position.lerp(_target_position, weight)
		rotation.y = lerp_angle(rotation.y, _target_yaw, weight)
	_flash = maxf(0.0, _flash - delta)
	_animate()

## Слайм дышит, удар на миг сжимает любого моба: видно, что попал.
func _animate() -> void:
	if _visual == null:
		return
	var squash := 1.0
	if mob_type == WorldGen.MOB_SLIME:
		var t := float(Time.get_ticks_msec()) / 1000.0
		squash = 0.9 + 0.1 * sin(t * 5.0)
	if _flash > 0.0:
		squash *= 0.86
	var spread := 1.0 + (1.0 - squash) * 0.6
	_visual.scale = Vector3(spread, squash, spread)

# --- внешность -------------------------------------------------------------

func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	match mob_type:
		WorldGen.MOB_BOAR:
			_build_boar()
		WorldGen.MOB_SLIME:
			_build_slime()
		WorldGen.MOB_SPIDER:
			_build_spider()
		_:
			_build_slime()

func _build_boar() -> void:
	var hide := _material(Color(0.31, 0.22, 0.14))
	var lighter := _material(Color(0.39, 0.29, 0.19))
	_add_box(Vector3(0.8, 0.7, 1.5), Vector3(0.0, 0.68, 0.0), hide)
	_add_box(Vector3(0.55, 0.5, 0.5), Vector3(0.0, 0.78, -0.9), lighter)
	_add_box(Vector3(0.28, 0.24, 0.26), Vector3(0.0, 0.62, -1.2), _material(Color(0.55, 0.36, 0.34)))
	_add_box(Vector3(0.1, 0.16, 0.1), Vector3(-0.16, 0.66, -1.24), _material(Color(0.95, 0.93, 0.86)))
	_add_box(Vector3(0.1, 0.16, 0.1), Vector3(0.16, 0.66, -1.24), _material(Color(0.95, 0.93, 0.86)))
	_add_box(Vector3(0.12, 0.22, 0.12), Vector3(-0.2, 1.0, -0.75), lighter)
	_add_box(Vector3(0.12, 0.22, 0.12), Vector3(0.2, 1.0, -0.75), lighter)
	for side in [-1.0, 1.0]:
		for front in [-1.0, 1.0]:
			_add_box(
				Vector3(0.16, 0.45, 0.16),
				Vector3(0.28 * side, 0.22, 0.45 * front),
				hide
			)

func _build_slime() -> void:
	var jelly := _material(Color(0.34, 0.83, 0.38))
	jelly.emission_enabled = true
	jelly.emission = Color(0.18, 0.55, 0.22)
	jelly.emission_energy_multiplier = 0.7
	var body := SphereMesh.new()
	body.radius = 0.55
	body.height = 1.0
	body.radial_segments = 16
	body.rings = 8
	_add_mesh(body, Vector3(0.0, 0.5, 0.0), jelly)
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.09
		eye.height = 0.18
		_add_mesh(eye, Vector3(0.18 * side, 0.62, -0.44), _material(Color(0.08, 0.12, 0.08)))

func _build_spider() -> void:
	var chitin := _material(Color(0.13, 0.12, 0.14))
	var legs := _material(Color(0.09, 0.08, 0.10))
	var abdomen := SphereMesh.new()
	abdomen.radius = 0.55
	abdomen.height = 1.0
	_add_mesh(abdomen, Vector3(0.0, 0.62, 0.3), chitin)
	var head := SphereMesh.new()
	head.radius = 0.34
	head.height = 0.6
	_add_mesh(head, Vector3(0.0, 0.55, -0.45), chitin)
	for i in 4:
		var angle := -0.55 + 0.36 * float(i)
		for side in [-1.0, 1.0]:
			var leg := _add_box(
				Vector3(1.0, 0.08, 0.08),
				Vector3(0.55 * side, 0.42, 0.15 + 0.18 * float(i)),
				legs
			)
			leg.rotation.z = 0.5 * side
			leg.rotation.y = angle * side
	var eye_material := _material(Color(0.95, 0.2, 0.22))
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.85, 0.12, 0.14)
	eye_material.emission_energy_multiplier = 2.0
	for i in 4:
		var eye := SphereMesh.new()
		eye.radius = 0.055
		eye.height = 0.11
		var offset := Vector3(-0.15 + 0.1 * float(i), 0.66, -0.72)
		_add_mesh(eye, offset, eye_material)

func _add_mesh(mesh: Mesh, spot: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = spot
	node.material_override = material
	_visual.add_child(node)
	return node

func _add_box(size: Vector3, spot: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(mesh, spot, material)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
