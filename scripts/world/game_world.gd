extends Node3D

## Мир игры: строит площадку, зоны, источники ресурсов и держит персонажей
## в соответствии со списком игроков из Net.

const HUDScript := preload("res://scripts/ui/hud.gd")

const MOUNTAIN_SEGMENTS := 40
const MOUNTAIN_ENTRANCE_WIDTH := 0.30
## Небо перекрашиваем не каждый кадр: смена цвета тянет пересчёт освещения.
const DAY_UPDATE_INTERVAL := 0.25
const ROCK_COLOR := Color(0.38, 0.37, 0.36)
const GROUND_COLOR := Color(0.31, 0.43, 0.25)

var world_data: Dictionary = {}
var resource_nodes: Dictionary = {}
var players_root: Node3D
var hud: CanvasLayer
var local_player: Player = null

var _player_nodes: Dictionary = {}
var _vehicle_nodes: Dictionary = {}

var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _day_timer := 0.0

func _ready() -> void:
	world_data = WorldGen.build()
	_build_environment()
	_build_platform()
	_build_border()
	_build_mountain()
	_spawn_resources()

	# Машины это отдельная механика: выключил флаг vehicles, и площадка
	# остаётся без машин, остальное работает как раньше.
	if Features.on("vehicles"):
		_build_vehicles()

	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	Game.setup_world(world_data["resources"], world_data.get("vehicles", []))
	Net.roster_changed.connect(_on_roster_changed)
	Net.player_transform.connect(_on_player_transform)
	Net.vehicle_transform.connect(_on_vehicle_transform)
	Game.vehicles_changed.connect(_on_vehicles_changed)
	Game.state_reset.connect(_on_state_reset)

	# Механики встают до HUD: окно статуса и подсказки ищут их по id.
	# Каждая механика это узел под миром, свои узлы она строит сама.
	Features.attach_mechanics(self)

	hud = HUDScript.new()
	add_child(hud)
	hud.setup(self)

	_on_roster_changed(Net.players)
	# Список игроков приходит отдельным пакетом после подключения. Свой
	# персонаж нужен сразу: без него в мире нет камеры и экран остаётся
	# серым, хотя HUD уже нарисован.
	_ensure_local_player()
	_on_vehicles_changed()

	if Net.is_client:
		Game.request_state()

	print("[WORLD] готов: сервер=%s клиент=%s источников=%d машин=%d | %s" % [
		Net.is_host, Net.is_client, resource_nodes.size(), _vehicle_nodes.size(),
		FeatureFlags.summary(Features.flags)
	])

func get_local_player() -> Player:
	return local_player

# --- построение ------------------------------------------------------------

## Небо, солнце и луна. Цвета и углы каждый раз считает DayCycle из
## системных часов, поэтому у всех игроков одна и та же ночь.
func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_material = ProceduralSkyMaterial.new()
	sky.sky_material = _sky_material
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)

	# Тени от луны не включаю: дорого и почти незаметно.
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.62, 0.70, 0.95)
	_moon.shadow_enabled = false
	add_child(_moon)

	_update_day_cycle()

func _exit_tree() -> void:
	Features.detach_mechanics()

func _process(delta: float) -> void:
	if not Features.on("day_night"):
		return
	_day_timer += delta
	if _day_timer < DAY_UPDATE_INTERVAL:
		return
	_day_timer = 0.0
	_update_day_cycle()

func _update_day_cycle() -> void:
	if _sun == null or _sky_material == null:
		return
	# Флаг day_night выключен: небо и свет стоят в полдень и не двигаются.
	var progress := DayCycle.progress_now() if Features.on("day_night") else 0.5
	_sun.rotation_degrees = DayCycle.sun_rotation_degrees(progress)
	_sun.light_energy = DayCycle.sun_energy(progress)
	_moon.rotation_degrees = DayCycle.moon_rotation_degrees(progress)
	_moon.light_energy = DayCycle.moon_energy(progress)
	_sky_material.sky_top_color = DayCycle.sky_top(progress)
	_sky_material.sky_horizon_color = DayCycle.sky_horizon(progress)
	_sky_material.ground_bottom_color = DayCycle.ground_color(progress)
	_sky_material.ground_horizon_color = DayCycle.sky_horizon(progress)
	_environment.ambient_light_energy = DayCycle.ambient_energy(progress)

func _build_platform() -> void:
	var size := float(world_data["platform_size"])
	var body := StaticBody3D.new()
	body.name = "Platform"
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxMesh.new()
	box.size = Vector3(size, 2.0, size)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position = Vector3(0.0, -1.0, 0.0)
	mesh.material_override = _material(GROUND_COLOR)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(size, 2.0, size)
	shape.shape = box_shape
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	add_child(body)

func _build_border() -> void:
	var size := float(world_data["platform_size"])
	var height := float(world_data["wall_height"])
	var half := size * 0.5
	var walls := [
		{"pos": Vector3(0.0, height * 0.5, -half), "size": Vector3(size, height, 2.0)},
		{"pos": Vector3(0.0, height * 0.5, half), "size": Vector3(size, height, 2.0)},
		{"pos": Vector3(-half, height * 0.5, 0.0), "size": Vector3(2.0, height, size)},
		{"pos": Vector3(half, height * 0.5, 0.0), "size": Vector3(2.0, height, size)},
	]
	for wall in walls:
		_add_block(wall["pos"], wall["size"], 0.0, ROCK_COLOR)

func _build_mountain() -> void:
	var center: Vector3 = world_data["mountain_center"]
	var radius := float(world_data["mountain_radius"])
	var height := float(world_data["mountain_height"])
	var entrance := float(world_data["mountain_entrance_angle"])

	# Блок идёт по касательной к кругу, поэтому его ширина это длина сегмента
	# окружности. Раньше здесь стояла константа, блоки перекрывались и гора
	# выглядела гладким цилиндром.
	var segment_width := TAU * radius / float(MOUNTAIN_SEGMENTS) * 1.2
	for i in MOUNTAIN_SEGMENTS:
		var angle := TAU * float(i) / float(MOUNTAIN_SEGMENTS)
		if absf(wrapf(angle - entrance, -PI, PI)) < MOUNTAIN_ENTRANCE_WIDTH:
			continue
		# Высота и выступ считаются от индекса, а не от рандома: у всех
		# игроков гора обязана быть одинаковой, иначе разъедется столкновения.
		var jitter := 0.5 + 0.5 * sin(float(i) * 2.399)
		var block_height := height * (1.0 + 0.12 * jitter)
		var block_radius := radius + 0.7 * sin(float(i) * 1.7)
		var offset := Vector3(cos(angle) * block_radius, 0.0, sin(angle) * block_radius)
		var block_size := Vector3(segment_width, block_height, 5.0)
		_add_block(center + Vector3(offset.x, block_height * 0.5, offset.z), block_size, PI * 0.5 - angle, ROCK_COLOR)

	# Потолок шахты: без него пещера превращается в колодец.
	var ceiling := StaticBody3D.new()
	ceiling.name = "CaveCeiling"
	ceiling.collision_layer = 1
	ceiling.collision_mask = 0
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius + 1.0
	cyl.bottom_radius = radius + 1.0
	cyl.height = 2.0
	cyl.radial_segments = 40
	var ceiling_mesh := MeshInstance3D.new()
	ceiling_mesh.mesh = cyl
	ceiling_mesh.position = Vector3(0.0, height + 1.0, 0.0)
	ceiling_mesh.material_override = _material(ROCK_COLOR)
	ceiling.add_child(ceiling_mesh)
	var ceiling_shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius + 1.0
	cyl_shape.height = 2.0
	ceiling_shape.shape = cyl_shape
	ceiling_shape.position = Vector3(0.0, height + 1.0, 0.0)
	ceiling.add_child(ceiling_shape)
	ceiling.position = center
	add_child(ceiling)

	# Верхушка горы, только вид.
	var peak := MeshInstance3D.new()
	var peak_mesh := CylinderMesh.new()
	peak_mesh.top_radius = 0.0
	peak_mesh.bottom_radius = radius
	peak_mesh.height = 12.0
	peak_mesh.radial_segments = 24
	peak.mesh = peak_mesh
	peak.position = center + Vector3(0.0, height + 2.0 + 6.0, 0.0)
	peak.material_override = _material(Color(0.45, 0.44, 0.43))
	add_child(peak)

	# Шахту надо чем-то осветить, иначе внутри чёрный экран.
	for i in 3:
		var angle := TAU * float(i) / 3.0
		var lamp := OmniLight3D.new()
		lamp.position = center + Vector3(cos(angle) * radius * 0.45, height * 0.55, sin(angle) * radius * 0.45)
		lamp.omni_range = 26.0
		lamp.light_energy = 2.4
		lamp.light_color = Color(1.0, 0.86, 0.62)
		add_child(lamp)

func _add_block(center_position: Vector3, size: Vector3, rotation_y: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center_position
	body.rotation.y = rotation_y

	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	add_child(body)
	return body

func _spawn_resources() -> void:
	for entry in world_data["resources"]:
		var node := ResourceNode.new()
		node.setup(
			int(entry["id"]),
			String(entry["type"]),
			entry["position"],
			float(entry["rot_y"]),
			float(entry["size"])
		)
		node.name = "R_%d" % int(entry["id"])
		add_child(node)
		resource_nodes[int(entry["id"])] = node

# --- машины ----------------------------------------------------------------

func _build_vehicles() -> void:
	for entry in world_data.get("vehicles", []):
		var car := Car.new()
		car.setup(int(entry["id"]), entry["position"], float(entry["rot_y"]))
		car.name = "C_%d" % int(entry["id"])
		add_child(car)
		_vehicle_nodes[int(entry["id"])] = car

## Сервер назначил водителей: свою машину ведём сами, чужие только показываем.
func _on_vehicles_changed() -> void:
	for key in _vehicle_nodes:
		var car: Car = _vehicle_nodes[key]
		var state: Dictionary = Game.vehicles.get(int(key), {})
		var driver := int(state.get("driver", 0))
		var mine := driver != 0 and driver == Net.my_id
		car.set_driver(driver, mine)
		if driver != 0 and not mine:
			car.set_remote_state(
				state.get("position", car.global_position),
				float(state.get("rotation", car.rotation.y))
			)
	if local_player == null:
		return
	var my_car := _my_car_id()
	if my_car < 0:
		if local_player.get_vehicle() != null:
			local_player.leave_vehicle()
		return
	var node: Car = _vehicle_nodes.get(my_car, null)
	if node != null and local_player.get_vehicle() != node:
		local_player.enter_vehicle(node)

func _on_vehicle_transform(peer_id: int, vehicle_id: int, position: Vector3, rotation_y: float) -> void:
	Game.note_vehicle_transform(vehicle_id, peer_id, position, rotation_y)
	var car: Car = _vehicle_nodes.get(vehicle_id, null)
	if car != null:
		car.set_remote_state(position, rotation_y)

func _my_car_id() -> int:
	for key in Game.vehicles:
		if int(Game.vehicles[key].get("driver", 0)) == Net.my_id:
			return int(key)
	return -1

# --- игроки ----------------------------------------------------------------

func _on_roster_changed(players: Dictionary) -> void:
	if players_root == null:
		return
	for key in players:
		var peer_id := int(key)
		var nick := String(players[key].get("nick", "Игрок"))
		if _player_nodes.has(peer_id):
			var existing: Player = _player_nodes[peer_id]
			existing.set_display_name(nick)
			continue
		_spawn_player(peer_id, nick)

	for key in _player_nodes.keys():
		var pid := int(key)
		if players.has(pid):
			continue
		# Своего персонажа не удаляем никогда: сервер может прислать список
		# раньше, чем зарегистрирует нас, и без камеры останется серый экран.
		if pid == Net.my_id:
			continue
		var gone: Player = _player_nodes[pid]
		_player_nodes.erase(pid)
		if gone == local_player:
			local_player = null
		gone.queue_free()

	if local_player != null:
		_on_vehicles_changed()

func _ensure_local_player() -> void:
	if local_player != null or Net.is_offline():
		return
	_spawn_player(Net.my_id, Net.nick_of(Net.my_id))

func _spawn_player(peer_id: int, nick: String) -> void:
	var player := Player.new()
	var spawn := WorldGen.spawn_position(peer_id)
	var yaw := atan2(-(0.0 - spawn.x), -(0.0 - spawn.z))
	player.setup(peer_id, nick, peer_id == Net.my_id, spawn, yaw)
	player.name = "P_%d" % peer_id
	players_root.add_child(player)
	_player_nodes[peer_id] = player
	if peer_id == Net.my_id:
		local_player = player

func _on_player_transform(peer_id: int, new_position: Vector3, yaw: float) -> void:
	var player: Player = _player_nodes.get(peer_id, null)
	if player == null:
		return
	player.set_remote_state(new_position, yaw)

func _on_state_reset() -> void:
	if hud != null:
		hud.refresh_all()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material
