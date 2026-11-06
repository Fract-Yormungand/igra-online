class_name Car
extends CharacterBody3D

## Машина. Управляет только тот, кого сервер назначил водителем, он и считает
## движение у себя. Остальные получают позицию по сети и плавно догоняют её.
## Так же сделаны персонажи, поэтому правила одни на всю игру.

const MAX_SPEED := 17.0
const REVERSE_SPEED := 7.0
## Метры в секунду за секунду. Машина выходит на максимум примерно за две
## секунды: резко, но не телепортом.
const ACCELERATION := 8.0
const BRAKE := 14.0
const ROLL_DRAG := 3.5
const STEER_RATE := 1.9
const GRAVITY := 22.0
const SEND_INTERVAL := 1.0 / 15.0
const REMOTE_LERP_SPEED := 10.0
## Угол поворота колёс на малой скорости больше, иначе машина не развернётся.
const STEER_FULL_SPEED := 4.0

const BODY_LENGTH := 4.4
const BODY_WIDTH := 2.0
const BODY_HEIGHT := 1.2

var car_id := 0
var driver_id := 0
var is_local_driver := false

var _speed := 0.0
var _send_timer := 0.0
var _remote_position := Vector3.ZERO
var _remote_yaw := 0.0
var _lights: Array = []

func setup(id: int, spawn: Vector3, rot_y: float) -> void:
	car_id = id
	position = spawn
	rotation.y = rot_y
	_remote_position = spawn
	_remote_yaw = rot_y

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	add_to_group("vehicles")
	_build_body()

## Место водителя: по нему персонаж садится и по нему едет камера.
func seat_position() -> Vector3:
	return global_transform * Vector3(0.0, 1.15, -0.2)

func speed_kmh() -> float:
	return absf(_speed) * 3.6

func is_free() -> bool:
	return driver_id == 0

func set_driver(peer_id: int, local_driver: bool) -> void:
	driver_id = peer_id
	is_local_driver = local_driver
	if peer_id == 0:
		_speed = 0.0

func set_remote_state(new_position: Vector3, new_yaw: float) -> void:
	if is_local_driver:
		return
	_remote_position = new_position
	_remote_yaw = new_yaw

func _build_body() -> void:
	var pane := Color(0.22, 0.30, 0.38)
	var hull := _material(Color(0.72, 0.24, 0.20))

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BODY_WIDTH, BODY_HEIGHT, BODY_LENGTH)
	shape.shape = box
	shape.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	add_child(shape)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(BODY_WIDTH, 0.75, BODY_LENGTH)
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.55, 0.0)
	body.material_override = hull
	add_child(body)

	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(BODY_WIDTH - 0.3, 0.66, 2.0)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.0, 1.18, 0.15)
	cabin.material_override = _material(pane)
	add_child(cabin)

	for corner in [
		Vector3(-0.95, 0.35, -1.5), Vector3(0.95, 0.35, -1.5),
		Vector3(-0.95, 0.35, 1.5), Vector3(0.95, 0.35, 1.5),
	]:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.35
		wheel_mesh.bottom_radius = 0.35
		wheel_mesh.height = 0.28
		wheel_mesh.radial_segments = 14
		wheel.mesh = wheel_mesh
		wheel.rotation.z = PI * 0.5
		wheel.position = corner
		wheel.material_override = _material(Color(0.10, 0.10, 0.11))
		add_child(wheel)

	# Фары светят только ночью, днём они бесполезны.
	for side in [-0.65, 0.65]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(side, 0.6, -BODY_LENGTH * 0.5)
		lamp.omni_range = 18.0
		lamp.light_energy = 2.2
		lamp.light_color = Color(1.0, 0.95, 0.78)
		lamp.visible = false
		add_child(lamp)
		_lights.append(lamp)

	var label := Label3D.new()
	label.text = "Машина"
	label.font_size = 36
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 2.1, 0.0)
	label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	label.outline_size = 10
	add_child(label)

func _process(_delta: float) -> void:
	var night := DayCycle.is_night(DayCycle.progress_now())
	for lamp in _lights:
		lamp.visible = night

func _physics_process(delta: float) -> void:
	if not is_local_driver:
		var weight := clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0)
		global_position = global_position.lerp(_remote_position, weight)
		rotation.y = lerp_angle(rotation.y, _remote_yaw, weight)
		return

	var steer := Input.get_axis("move_right", "move_left")
	var throttle := Input.get_axis("move_back", "move_forward")
	var brake := Input.is_action_pressed("jump")

	if throttle > 0.0:
		_speed = move_toward(_speed, MAX_SPEED * throttle, ACCELERATION * delta)
	elif throttle < 0.0:
		_speed = move_toward(_speed, -REVERSE_SPEED * -throttle, ACCELERATION * delta)
	else:
		_speed = move_toward(_speed, 0.0, ROLL_DRAG * delta)
	if brake:
		_speed = move_toward(_speed, 0.0, BRAKE * delta)

	# На месте руль не крутит: машина поворачивает только в движении.
	var grip := clampf(absf(_speed) / STEER_FULL_SPEED, 0.0, 1.0)
	if absf(_speed) > 0.2:
		var direction := signf(_speed)
		rotation.y += steer * STEER_RATE * grip * direction * delta

	velocity.x = -transform.basis.z.x * _speed
	velocity.z = -transform.basis.z.z * _speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	# Упёрся в стену: скорость гасим, иначе машина дрожит о препятствие.
	if is_on_wall():
		_speed = move_toward(_speed, 0.0, BRAKE * delta * 2.0)

	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		Net.send_vehicle(car_id, global_position, rotation.y)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	return material
