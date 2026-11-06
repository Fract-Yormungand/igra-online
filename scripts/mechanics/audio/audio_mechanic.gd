extends Mechanic

## Звук в машине: музыка по клавише Q и гул двигателя.
##
## Слышит это только водитель, поэтому в сеть ничего не уходит и сервер про
## звук не знает. Механика сама смотрит, сидит ли местный игрок за рулём:
## сел, двигатель завёлся; вышел, всё погасло. Отдельный запрос от персонажа
## не нужен, поэтому персонаж про звук вообще ничего не знает.
##
## Нет файла на диске, механика молчит и пишет одну строку в лог, игра играется.

var _music: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _track := -1
var _engine_on := false
var _warmup := 0.0
var _warned := false

func start() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = AudioDB.MUSIC_DB
	add_child(_music)

	_engine = AudioStreamPlayer.new()
	_engine.name = "Engine"
	_engine.volume_db = AudioDB.SILENT_DB
	add_child(_engine)

func stop() -> void:
	_engine_on = false
	_track = -1
	if _music != null:
		_music.stop()
	if _engine != null:
		_engine.stop()

func _process(delta: float) -> void:
	var car := _player_car()
	if car == null:
		_silence()
		return
	if not _engine_on:
		_begin_engine()
	_warmup = maxf(0.0, _warmup - delta)
	_follow_speed(car)

# --- музыка ----------------------------------------------------------------

## Клавиша Q: выключено, трек 1, трек 2, снова выключено.
func cycle_music() -> int:
	_track = AudioDB.next_track(_track)
	_apply_music()
	return _track

## Подпись для подсказки внизу экрана.
func music_label() -> String:
	return AudioDB.track_title(_track)

func music_state() -> Dictionary:
	return {
		"index": _track,
		"title": AudioDB.track_title(_track),
		"playing": _music != null and _music.playing,
	}

func _apply_music() -> void:
	if _music == null:
		return
	if _track < 0:
		_music.stop()
		_music.stream = null
		return
	var path := AudioDB.track_path(_track)
	if _music.stream == null or _music.stream.resource_path != path:
		_music.stream = AudioDB.load_loop(path)
	if _music.stream == null:
		_warn_file(path)
		return
	if not _music.playing:
		_music.play()

# --- двигатель -------------------------------------------------------------

func engine_running() -> bool:
	return _engine_on

## Звук двигателя реально идёт: файл загрузился и поток играет.
func engine_audible() -> bool:
	return _engine != null and _engine.stream != null and _engine.playing

func warmup_left() -> float:
	return _warmup

func _begin_engine() -> void:
	_engine_on = true
	_warmup = AudioDB.WARMUP_SECONDS
	if _engine == null:
		return
	if _engine.stream == null:
		_engine.stream = AudioDB.load_loop(AudioDB.engine_path())
	if _engine.stream == null:
		_warn_file(AudioDB.engine_path())
		return
	_engine.pitch_scale = AudioDB.ENGINE_IDLE_PITCH
	_engine.volume_db = AudioDB.ENGINE_IDLE_DB
	if not _engine.playing:
		_engine.play()

## Тон и громкость тянутся за скоростью, но только после прогрева.
func _follow_speed(car: Car) -> void:
	if _engine == null or _engine.stream == null:
		return
	var ratio := AudioDB.speed_ratio(car.speed_mps(), Car.MAX_SPEED)
	_engine.pitch_scale = AudioDB.engine_pitch(ratio, _warmup)
	_engine.volume_db = AudioDB.engine_volume_db(ratio, _warmup)

## Вне машины тишина: и двигатель, и музыка. Трек сбрасывается, поэтому
## следующая посадка начинается с выключенной музыки и одного нажатия Q.
func _silence() -> void:
	if _engine_on:
		_engine_on = false
		_warmup = 0.0
		if _engine != null:
			_engine.stop()
	if _track >= 0:
		_track = -1
		_apply_music()

func _player_car() -> Car:
	var player := local_player()
	if player == null:
		return null
	return player.get_vehicle()

func _warn_file(path: String) -> void:
	if _warned:
		return
	_warned = true
	print("[AUDIO] нет звукового файла: %s, механика молчит" % path)
