class_name LevelRules
extends RefCounted

## Прокачка по калькулятору персонажа. Чистая математика без сцен и сети:
## кап уровня, цена шага, пул очков и награда за убийство.
##
## Нумерация эволюции в игре на единицу меньше калькуляторной: эво 0 игры
## это первая эволюция калькулятора. Формулы перенесены один в один.

const BASE_STAT := 10
const LEVELS_PER_EVOLUTION := 10
const EVOLUTION_POINT_BONUS := 10
const EVOLUTION_BONUS_FROM := 2
## Предохранитель, чтобы цикл эволюций не ушёл в бесконечность.
const MAX_EVOLUTION := 5000
## Делитель награды за убийство: сумма характеристик моба на пятёрку.
const REWARD_DIVISOR := 5.0

## Кап уровня для эволюции: (эво+1)*10, то есть 10, 20, 30, 40.
static func level_cap(evolution: int) -> int:
	return (maxi(evolution, 0) + 1) * LEVELS_PER_EVOLUTION

## Базовый опыт эволюции: 10 на эво 0, дальше плюс кап прошлой.
## Выходит 10, 20, 40, 70, 110.
static func base_exp(evolution: int) -> int:
	var ev := maxi(evolution, 0)
	return BASE_STAT + LEVELS_PER_EVOLUTION * ev * (ev + 1) / 2

## Опыт на шаг с текущего уровня: база эволюции плюс уровень.
static func exp_to_next(evolution: int, level: int) -> int:
	return base_exp(evolution) + maxi(level, 0)

## Пул очков на эволюции и уровне. Растёт на единицу за уровень.
static func total_points(evolution: int, level: int) -> int:
	var ev := maxi(evolution, 0)
	var bonus := EVOLUTION_POINT_BONUS if ev >= EVOLUTION_BONUS_FROM else 0
	return 5 * ev * (ev + 1) + bonus + maxi(level, 0)

## Итоговый стат: база калькулятора плюс распределённые очки. В игре база
## берётся из стартового набора персонажа, поэтому функция оставлена для
## проверок калькулятора.
static func stat_from_points(points: float) -> float:
	return float(BASE_STAT) + points

## Награда за убийство: сумма характеристик моба, делённая на пять.
## Формула из калькулятора: max_hp + max(сила, магия) + тело + ловкость.
static func exp_reward(max_hp: float, strength: float, magic: float, body: float, agility: float) -> int:
	var attack := maxf(strength, magic)
	var total := maxf(0.0, max_hp) + attack + maxf(0.0, body) + maxf(0.0, agility)
	return maxi(1, int(total / REWARD_DIVISOR))

## Начисление опыта. Возвращает новый прогресс и что произошло.
## На капе уровень сбрасывается, эволюция растёт: новой подрасы у нас нет,
## поэтому шаг идёт сам, без выбора.
static func add_exp(evolution: int, level: int, exp: int, gain: int) -> Dictionary:
	var ev := clampi(evolution, 0, MAX_EVOLUTION)
	var lvl := maxi(level, 0)
	var current := maxi(exp, 0) + maxi(gain, 0)
	var levels := 0
	var evolved := 0

	while lvl < level_cap(ev) and current >= exp_to_next(ev, lvl):
		current -= exp_to_next(ev, lvl)
		lvl += 1
		levels += 1

	if lvl >= level_cap(ev):
		current = mini(current, exp_to_next(ev, lvl))
		if ev < MAX_EVOLUTION:
			ev += 1
			lvl = 0
			current = 0
			evolved = 1

	return {
		"evolution": ev,
		"level": lvl,
		"exp": current,
		"levels_gained": levels,
		"evolved": evolved,
	}
