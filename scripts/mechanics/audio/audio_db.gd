class_name AudioDB
extends RefCounted

## Звук машины: реестр файлов и чистые правила громкости и высоты тона.
## Ни сцен, ни сети, поэтому числа проверяются тестом в headless.
## Поменять трек или файл двигателя можно здесь, код машины при этом не трогаем.

const FOLDER := "res://assets/audio/car/"

## Музыка в машине. Порядок в списке задаёт порядок листания клавишей Q.
const TRACKS := [
	{"title": "Трек 1", "file": "track_1.mp3"},
	{"title": "Трек 2", "file": "track_2.mp3"},
]

const ENGINE_FILE := "engine.mp3"

## Громкость в децибелах: ноль это полная громкость, минус тише.
const MUSIC_DB := -9.0
const ENGINE_IDLE_DB := -13.0
const ENGINE_DRIVE_DB := -3.0
## Ниже этого порога звук считается выключенным.
const SILENT_DB := -60.0

## Прогрев: первые секунды двигатель работает на месте, не разгоняясь.
const WARMUP_SECONDS := 2.0
const ENGINE_IDLE_PITCH := 0.72
const ENGINE_MAX_PITCH := 1.6

static func track_count() -> int:
	return TRACKS.size()

static func track_title(index: int) -> String:
	if index < 0 or index >= TRACKS.size():
		return "выкл"
	return String(TRACKS[index].get("title", "Трек"))

## Листание клавишей Q: выключено, трек 1, трек 2, снова выключено.
static func next_track(index: int) -> int:
	var next := index + 1
	if next < 0 or next >= TRACKS.size():
		return -1
	return next

static func track_path(index: int) -> String:
	if index < 0 or index >= TRACKS.size():
		return ""
	return FOLDER + String(TRACKS[index].get("file", ""))

static func engine_path() -> String:
	return FOLDER + ENGINE_FILE

## Доля от максимальной скорости, от 0 до 1. Задний ход считается по модулю.
static func speed_ratio(speed_mps: float, max_speed_mps: float) -> float:
	if max_speed_mps <= 0.0:
		return 0.0
	return clampf(absf(speed_mps) / max_speed_mps, 0.0, 1.0)

## На прогреве тон стоит холостым, после него тянется за скоростью.
static func engine_pitch(ratio: float, warmup_left: float) -> float:
	if warmup_left > 0.0:
		return ENGINE_IDLE_PITCH
	return lerpf(ENGINE_IDLE_PITCH, ENGINE_MAX_PITCH, clampf(ratio, 0.0, 1.0))

static func engine_volume_db(ratio: float, warmup_left: float) -> float:
	if warmup_left > 0.0:
		return ENGINE_IDLE_DB
	return lerpf(ENGINE_IDLE_DB, ENGINE_DRIVE_DB, clampf(ratio, 0.0, 1.0))

## Загрузка с зацикливанием. Файла нет, вернётся null, и механика просто молчит.
static func load_loop(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream
