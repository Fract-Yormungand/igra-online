class_name Player
extends CharacterBody3D

## Персонаж от третьего лица. Своим персонажем управляет владелец,
## чужие только показываются: позицию присылает владелец через Net.

const SPEED := 5.4
const AIR_CONTROL := 0.55
const ACCELERATION := 14.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 22.0
const MOUSE_SENSITIVITY := 0.0026
const PITCH_MIN := -1.15
const PITCH_MAX := 0.55
const CAMERA_LENGTH := 4.6
const REACH := 4.2
const HARVEST_COOLDOWN := 0.35
const SEND_INTERVAL := 1.0 / 15.0
const REMOTE_LERP_SPEED := 12.0

var peer_id := 0
var display_name := ""
var is_local := false

var _pivot: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _mesh: MeshInstance3D
var _name_label: Label3D

var _yaw := 0.0
var _pitch := -0.18
var _cooldown := 0.0
var _send_timer := 0.0
var _remote_position := Vector3.ZERO
var _remote_yaw := 0.0
var _target: ResourceNode = null

func setup(id: int, nick: String, local: bool, spawn_position: Vector3, yaw: float) -> void:
	peer_id = id
	display_name = nick
	is_local = local
	position = spawn_position
	_yaw = yaw
	rotation.y = yaw
	_remote_position = spawn_position
	_remote_yaw = yaw

func set_display_name(nick: String) -> void:
	display_name = nick
	if _name_label != null:
		_name_label.text = nick

func get_target() -> ResourceNode:
	return _target

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	_build_body()
	if is_local:
		_setup_camera()
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 1.8
	_mesh.mesh = body_mesh
	_mesh.position = Vector3(0.0, 0.9, 0.0)
	_mesh.material_override = _material(_color_for_peer())
	add_child(_mesh)

	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.2, 0.2, 0.45)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 1.45, -0.42)
	nose.material_override = _material(Color(0.95, 0.85, 0.4))
	add_child(nose)

	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.font_size = 48
	_name_label.pixel_size = 0.004
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position = Vector3(0.0, 2.25, 0.0)
	_name_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_name_label.outline_size = 12
	add_child(_name_label)

func _setup_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 1.45, 0.0)
	_pivot.rotation.x = _pitch
	add_child(_pivot)

	_spring = SpringArm3D.new()
	_spring.spring_length = CAMERA_LENGTH
	_spring.margin = 0.3
	_spring.collision_mask = 1
	_spring.add_excluded_object(get_rid())
	_pivot.add_child(_spring)

	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.make_current()
	_spring.add_child(_camera)

func _physics_process(delta: float) -> void:
	if not is_local:
		var weight := clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0)
		global_position = global_position.lerp(_remote_position, weight)
		rotation.y = lerp_angle(rotation.y, _remote_yaw, weight)
		return

	_cooldown = maxf(0.0, _cooldown - delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	if direction.length() > 0.01:
		direction = direction.normalized()
		var accel := ACCELERATION if is_on_floor() else ACCELERATION * AIR_CONTROL
		velocity.x = move_toward(velocity.x, direction.x * SPEED, accel * delta * 10.0)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, accel * delta * 10.0)
	else:
		var brake := ACCELERATION * (1.0 if is_on_floor() else AIR_CONTROL) * delta * 10.0
		velocity.x = move_toward(velocity.x, 0.0, brake)
		velocity.z = move_toward(velocity.z, 0.0, brake)

	move_and_slide()

	_target = _find_target()
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		Net.send_transform(global_position, rotation.y)

func set_remote_state(new_position: Vector3, new_yaw: float) -> void:
	if is_local:
		return
	_remote_position = new_position
	_remote_yaw = new_yaw

func _find_target() -> ResourceNode:
	var best: ResourceNode = null
	var best_distance := REACH
	var forward := -global_transform.basis.z
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		var candidate := node as ResourceNode
		if candidate == null or not candidate.is_available():
			continue
		var to_target := candidate.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > best_distance:
			continue
		if distance > 0.05 and forward.dot(to_target / distance) < 0.15:
			continue
		best = candidate
		best_distance = distance
	return best

func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		rotation.y = _yaw
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		if _pivot != null:
			_pivot.rotation.x = _pitch
		return
	if event.is_action_pressed("interact"):
		_try_harvest()
		return
	if event.is_action_pressed("slot_1"):
		Game.request_equip("axe")
		return
	if event.is_action_pressed("slot_2"):
		Game.request_equip("pickaxe")
		return
	if event is InputEventMouseButton and event.pressed and not Game.ui_inventory_open:
		if DisplayServer.get_name() != "headless" and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _try_harvest() -> void:
	if _cooldown > 0.0 or _target == null:
		return
	_cooldown = HARVEST_COOLDOWN
	Game.request_harvest(_target.resource_id)

func _color_for_peer() -> Color:
	var hue := fmod(float(peer_id) * 0.37, 1.0)
	return Color.from_hsv(hue, 0.55, 0.88)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	return material
