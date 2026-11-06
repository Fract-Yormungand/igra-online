class_name RamRules
extends RefCounted

## Наезд машины на моба. Чистая математика без сцен и сети: на входе скорость
## и тело моба, на выходе урон и отбрасывание. Поэтому правила проверяются
## тестом в headless, а механика мобов только применяет готовые числа.

## Ниже этой скорости машина не бьёт: пешком по двору не убивают.
const MIN_SPEED_MPS := 3.0
## Сколько силы удара даёт один метр в секунду.
const STRIKE_PER_MPS := 2.5
## Дальше этого моб не отлетает, иначе улетал бы сквозь стену.
const KNOCK_TIME := 0.45
const KNOCK_BASE := 3.0
const KNOCK_GAIN := 0.75
## Скорость отбрасывания гаснет за десятые доли секунды.
const KNOCK_DECAY := 22.0
## Радиус, в котором корпус машины задевает моба.
const HIT_RADIUS := 2.8

static func can_hit(speed_mps: float) -> bool:
	return speed_mps >= MIN_SPEED_MPS

static func impact(speed_mps: float) -> float:
	return maxf(0.0, speed_mps) * STRIKE_PER_MPS

## Урон идёт через тело моба, как любой другой удар: тяжёлого кабана сбить
## труднее, чем лёгкого слайма.
static func damage(speed_mps: float, body: float) -> float:
	if not can_hit(speed_mps):
		return 0.0
	return DerivedStats.damage_through_body(impact(speed_mps), body)

## С какой скоростью моб летит от машины.
static func knock_speed(speed_mps: float) -> float:
	return KNOCK_BASE + maxf(0.0, speed_mps) * KNOCK_GAIN
