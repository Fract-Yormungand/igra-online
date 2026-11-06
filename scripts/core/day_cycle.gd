class_name DayCycle
extends RefCounted

## Время суток: чистая математика без сцен, сети и узлов.
## Сервер и клиенты считают одно и то же из системных часов, поэтому по сети
## не едет ничего, а расхождение не больше сетевой задержки.

## Полный круг за 8 минут игры: смену видно, но она не мешает добыче.
const FULL_DAY_SECONDS := 480.0
## Точка отсчёта. Число любое, важно что оно одинаковое у всех.
const EPOCH_UNIX := 1762387200.0

const SKY_DAY_TOP := Color(0.29, 0.49, 0.80)
const SKY_NIGHT_TOP := Color(0.02, 0.03, 0.08)
const SKY_DAY_HORIZON := Color(0.72, 0.82, 0.92)
const SKY_NIGHT_HORIZON := Color(0.05, 0.06, 0.13)
const SKY_DUSK_HORIZON := Color(0.85, 0.45, 0.25)
const GROUND_DAY := Color(0.24, 0.30, 0.26)
const GROUND_NIGHT := Color(0.04, 0.05, 0.06)

const SUN_ENERGY := 1.15
const MOON_ENERGY := 0.42
const AMBIENT_DAY := 1.0
const AMBIENT_NIGHT := 0.28
## Солнце стоит не строго на востоке: так тени падают красивее.
const SUN_AZIMUTH_DEGREES := -38.0

## Доля суток от 0 до 1. 0.0 полночь, 0.25 шесть утра, 0.5 полдень.
static func progress_now() -> float:
	return progress_at(Time.get_unix_time_from_system())

static func progress_at(unix_now: float) -> float:
	return fposmod(unix_now - EPOCH_UNIX, FULL_DAY_SECONDS) / FULL_DAY_SECONDS

## Угол солнца в радианах: 0 на восходе, PI/2 в полдень, PI на закате.
static func sun_angle(progress: float) -> float:
	return (progress - 0.25) * TAU

## Высота солнца. Больше нуля день, меньше нуля ночь.
static func sun_height(progress: float) -> float:
	return sin(sun_angle(progress))

static func is_night(progress: float) -> bool:
	return sun_height(progress) < 0.0

## Насколько ярко светит день, от 0 до 1.
static func daylight(progress: float) -> float:
	return clampf(sun_height(progress), 0.0, 1.0)

static func moonlight(progress: float) -> float:
	return clampf(-sun_height(progress), 0.0, 1.0)

## Близость к горизонту: даёт оранжевую полосу на восходе и закате.
static func twilight(progress: float) -> float:
	return clampf(1.0 - absf(sun_height(progress)) / 0.22, 0.0, 1.0)

static func sun_rotation_degrees(progress: float) -> Vector3:
	return Vector3(-rad_to_deg(sun_angle(progress)), SUN_AZIMUTH_DEGREES, 0.0)

## Луна висит напротив солнца, поэтому светит ровно тогда, когда солнце село.
static func moon_rotation_degrees(progress: float) -> Vector3:
	return Vector3(-rad_to_deg(sun_angle(progress) + PI), SUN_AZIMUTH_DEGREES + 25.0, 0.0)

static func sun_energy(progress: float) -> float:
	return SUN_ENERGY * daylight(progress)

static func moon_energy(progress: float) -> float:
	return MOON_ENERGY * moonlight(progress)

static func ambient_energy(progress: float) -> float:
	return lerpf(AMBIENT_NIGHT, AMBIENT_DAY, daylight(progress))

static func sky_top(progress: float) -> Color:
	return SKY_NIGHT_TOP.lerp(SKY_DAY_TOP, daylight(progress))

static func sky_horizon(progress: float) -> Color:
	var base := SKY_NIGHT_HORIZON.lerp(SKY_DAY_HORIZON, daylight(progress))
	return base.lerp(SKY_DUSK_HORIZON, twilight(progress) * 0.75)

static func ground_color(progress: float) -> Color:
	return GROUND_NIGHT.lerp(GROUND_DAY, daylight(progress))

## Часы для интерфейса в формате ЧЧ:ММ.
static func clock_text(progress: float) -> String:
	var minutes := int(round(fposmod(progress, 1.0) * 1440.0)) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]
