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
const ATTACK_COOLDOWN := 0.7
## Толчок от моба это короткий рывок, а не полёт: скорость гаснет быстро.
const PUSH_TIME := 0.25
const PUSH_DECAY := 24.0
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
var _target_vehicle: Car = null
var _vehicle: Car = null
var _shape: CollisionShape3D = null
var _revive_requested := false
var _attack_cooldown := 0.0
## Режим шага: игрок держит ровно 10 км/ч, пока ловкость выше 50.
var _walking := false
var _slow_left := 0.0
var _slow_factor := 1.0
var _push_left := 0.0
var _push_velocity := Vector3.ZERO

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

func get_target_vehicle() -> Car:
	return _target_vehicle

func get_vehicle() -> Car:
	return _vehicle

## Садится в машину: своё тело больше не толкает физику, но позиция идёт
## в сеть, поэтому другие видят игрока в машине, а не рядом с ней.
func enter_vehicle(car: Car) -> void:
	_vehicle = car
	velocity = Vector3.ZERO
	_target = null
	_target_vehicle = null
	if _shape != null:
		_shape.disabled = true

func leave_vehicle() -> void:
	var car := _vehicle
	_vehicle = null
	if _shape != null:
		_shape.disabled = false
	if car == null:
		return
	var side := car.global_transform.basis.x.normalized() * 2.4
	global_position = car.global_position + side + Vector3(0.0, 0.4, 0.0)

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
	_shape = shape

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
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_slow_left = maxf(0.0, _slow_left - delta)
	_check_downed()

	if _vehicle != null:
		_ride_vehicle(delta)
		return

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	var move_speed := _move_speed()
	if _push_left > 0.0:
		# Толчок от моба: короткий рывок, управление на эти доли секунды
		# отпускает, иначе игрока отбрасывает на полшага.
		_push_left -= delta
		velocity.x = _push_velocity.x
		velocity.z = _push_velocity.z
		_push_velocity = _push_velocity.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	elif direction.length() > 0.01:
		direction = direction.normalized()
		var accel := ACCELERATION if is_on_floor() else ACCELERATION * AIR_CONTROL
		velocity.x = move_toward(velocity.x, direction.x * move_speed, accel * delta * 10.0)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, accel * delta * 10.0)
	else:
		var brake := ACCELERATION * (1.0 if is_on_floor() else AIR_CONTROL) * delta * 10.0
		velocity.x = move_toward(velocity.x, 0.0, brake)
		velocity.z = move_toward(velocity.z, 0.0, brake)

	move_and_slide()

	_target = _find_target()
	_target_vehicle = _find_target_vehicle()
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		Net.send_transform(global_position, rotation.y)

## Едем на машине: сидим на месте водителя, свою физику и обзор крутит она.
func _ride_vehicle(delta: float) -> void:
	if not is_instance_valid(_vehicle):
		leave_vehicle()
		return
	velocity = Vector3.ZERO
	global_position = _vehicle.seat_position()
	_yaw = _vehicle.rotation.y
	rotation.y = _yaw
	_target = null
	_target_vehicle = null
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		Net.send_transform(global_position, rotation.y)

func _find_target_vehicle() -> Car:
	if not Features.on("vehicles"):
		return null
	var best: Car = null
	var best_distance := REACH + 1.6
	for node in get_tree().get_nodes_in_group("vehicles"):
		var candidate := node as Car
		if candidate == null or not candidate.is_free():
			continue
		var to_target := candidate.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance >= best_distance:
			continue
		best = candidate
		best_distance = distance
	return best

## Скорость берётся из ловкости: одно очко это один километр в час, как в
## калькуляторе. Обычный ход это половина максимума, Shift разгоняет до
## максимума, включённый шаг держит ровно 10 км/ч. Раненый и обессиленный
## идёт медленнее, потому что ловкость умножается на коэффициент состояния.
## Нет механики, работает запасная скорость.
func _move_speed() -> float:
	var kmh := DerivedStats.movement_kmh(_top_speed_kmh(), _walking, Input.is_action_pressed("sprint"))
	return kmh * DerivedStats.KMH_TO_MPS * _slow_multiplier()

func _top_speed_kmh() -> float:
	var stats := _stats()
	if stats == null:
		return SPEED * 3.6
	return float(stats.speed_kmh(peer_id))

## Замедление от паутины режет любую скорость, пока висит.
func _slow_multiplier() -> float:
	return _slow_factor if _slow_left > 0.0 else 1.0

func _stats() -> Node:
	return Features.mechanic("stats")

## Шаг открыт только ловкому: на слабой ловкости режим не включается.
func _can_walk() -> bool:
	return DerivedStats.walk_available(_top_speed_kmh())

func _toggle_walk() -> void:
	if not _can_walk():
		_walking = false
		Game.notify_peer(peer_id, "Шаг откроется, когда ловкость станет выше 50")
		return
	_walking = not _walking
	Game.notify_peer(peer_id, "Шаг включён: 10 км/ч" if _walking else "Шаг выключен: обычный ход")

## Толчок от моба. Позиция персонажа клиентская, поэтому решает сервер,
## а применяет клиент-владелец: игрока отбрасывает на его же экране.
func apply_push(direction: Vector3, force: float) -> void:
	if not is_local:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		flat = -global_transform.basis.z
	_push_velocity = flat.normalized() * force
	_push_left = PUSH_TIME

## Замедление от паутины: скорость падает на время, потом возвращается сама.
func apply_slow(duration: float, factor: float = 0.4) -> void:
	if not is_local:
		return
	_slow_left = maxf(_slow_left, duration)
	_slow_factor = clampf(factor, 0.05, 1.0)

## Упавшего игрока уводит в лагерь его же клиент: позиция персонажа и так
## клиентская. Сервер только решает, что здоровья больше нет.
func _check_downed() -> void:
	var stats := _stats()
	if stats == null:
		return
	if not bool(stats.is_downed(peer_id)):
		_revive_requested = false
		return
	if _revive_requested:
		return
	_revive_requested = true
	if _vehicle != null:
		Game.request_vehicle_exit()
	global_position = WorldGen.spawn_position(peer_id)
	velocity = Vector3.ZERO
	_target = null
	_target_vehicle = null
	Net.send_transform(global_position, rotation.y)
	stats.request_revive()

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
		# В машине обзор держится за корпусом, иначе руль и мышь спорят.
		if _vehicle == null:
			_yaw -= event.relative.x * MOUSE_SENSITIVITY
			rotation.y = _yaw
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		if _pivot != null:
			_pivot.rotation.x = _pitch
		return
	if event.is_action_pressed("toggle_walk"):
		_toggle_walk()
		return
	if event.is_action_pressed("attack") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_try_attack()
		return
	if event.is_action_pressed("interact"):
		if _vehicle != null:
			Game.request_vehicle_exit()
			return
		if _target_vehicle != null:
			Game.request_vehicle_enter(_target_vehicle.car_id)
			return
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

## Удар по мобу. Что именно перед игроком, решает клиент, а сервер проверяет
## расстояние и сам считает урон по характеристикам.
func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	var mobs := Features.mechanic("mobs")
	if mobs == null:
		return
	var target := _find_mob()
	if target == null:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	mobs.request_attack(target.mob_id)

func _find_mob() -> Mob:
	var best: Mob = null
	var best_distance := REACH
	var forward := -global_transform.basis.z
	for node in get_tree().get_nodes_in_group("mobs"):
		var candidate := node as Mob
		if candidate == null or not candidate.is_alive():
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

func _color_for_peer() -> Color:
	var hue := fmod(float(peer_id) * 0.37, 1.0)
	return Color.from_hsv(hue, 0.55, 0.88)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	return material
