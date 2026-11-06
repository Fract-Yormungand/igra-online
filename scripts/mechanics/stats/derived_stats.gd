class_name DerivedStats
extends RefCounted

## Характеристики и всё, что из них считается. Правила взяты из калькулятора
## манкинов, здесь только перенос в игру: ни сцен, ни сети, ни состояния.
##
## Сила: урон удара и подъём одной рукой, одно очко это один килограмм.
## Тело: здоровье, запас сил и защита от физики и магии.
## Магия: запас сил и сила заклинаний.
## Ловкость: скорость в км/ч и число действий за раунд.

const ATTRIBUTE_KEYS := ["strength", "body", "magic", "agility"]
const ATTRIBUTE_NAMES := {
	"strength": "Сила",
	"body": "Тело",
	"magic": "Магия",
	"agility": "Ловкость",
}

## Коэффициенты калькулятора. Меняются здесь и только здесь.
## HP и MP = (тело + стат) * HP_MULT.
const HP_MULT := 3.0
## Одно действие за каждые столько ловкости.
const ACTION_AGILITY := 10.0
## Стат выше тела * LIMIT_MULT ранит носителя.
const LIMIT_MULT := 5.0
## Доля излишка, которая возвращается самоуроном за раунд.
const SELF_MULT := 0.2
## Затухание накопления магии.
const MAGIC_DECAY := 0.8
## Дальше этого накопление не считаем: выгода давно кончилась.
const MAGIC_MAX_STEPS := 15
const KMH_TO_MPS := 1.0 / 3.6

## Стартовые характеристики. Ловкость подобрана под привычные 19 км/ч,
## тело и сила выше магии: первый персонаж ближе к добытчику, чем к магу.
const START_ATTRIBUTES := {"strength": 12, "body": 14, "magic": 10, "agility": 19}

static func start_attributes() -> Dictionary:
	return START_ATTRIBUTES.duplicate()

## Характеристики приходят из сети, поэтому мусор и минусы приводим к нулю.
static func normalized(attributes: Dictionary) -> Dictionary:
	var result := {}
	for key in ATTRIBUTE_KEYS:
		result[key] = maxi(0, int(attributes.get(key, 0)))
	return result

static func max_hp(attributes: Dictionary) -> float:
	var a := normalized(attributes)
	return (float(a["body"]) + float(a["strength"])) * HP_MULT

static func max_mp(attributes: Dictionary) -> float:
	var a := normalized(attributes)
	return (float(a["body"]) + float(a["magic"])) * HP_MULT

## Ловкость это километры в час, одно очко равно одному километру.
static func speed_kmh(attributes: Dictionary) -> float:
	return float(normalized(attributes)["agility"])

static func speed_mps(attributes: Dictionary) -> float:
	return speed_kmh(attributes) * KMH_TO_MPS

## Действий за раунд. Меньше одного не бывает.
static func actions_per_round(attributes: Dictionary) -> int:
	var agility := float(normalized(attributes)["agility"])
	if agility <= 0.0:
		return 1
	return maxi(1, int(floor(agility / ACTION_AGILITY)))

## Коэффициент состояния C = корень из произведения долей HP и MP.
## Раненый и обессиленный персонаж слабее по всем статам сразу.
static func state_coefficient(hp_share: float, mp_share: float) -> float:
	return sqrt(clampf(hp_share, 0.0, 1.0) * clampf(mp_share, 0.0, 1.0))

## Эффективные характеристики: базовые, умноженные на коэффициент состояния.
static func effective(attributes: Dictionary, coefficient: float) -> Dictionary:
	var a := normalized(attributes)
	var c := clampf(coefficient, 0.0, 1.0)
	var result := {}
	for key in ATTRIBUTE_KEYS:
		result[key] = float(a[key]) * c
	return result

## Доля урона, пробившая защиту тела: удар / (удар + тело).
## Равные значения дают половину, двойной перевес даёт две трети.
static func penetration(attack: float, body: float) -> float:
	var a := maxf(0.0, attack)
	var b := maxf(0.0, body)
	if a <= 0.0:
		return 0.0
	return a / (a + b)

## Сколько урона дойдёт до цели с таким телом.
static func damage_through_body(attack: float, body: float) -> float:
	if attack <= 0.0:
		return 0.0
	return attack * penetration(attack, body)

## Уклонение работает только на разницу ловкости: цель должна быть ловчее.
static func evasion(defender_agility: float, attacker_agility: float) -> float:
	if defender_agility <= 0.0 or defender_agility <= attacker_agility:
		return 0.0
	return (defender_agility - attacker_agility) / defender_agility

## С какого броска d100 начинается попадание.
static func d100_start(evasion_percent: float) -> int:
	var e := clampf(evasion_percent, 0.0, 100.0)
	return int(minf(100.0, maxf(2.0, floorf(e) + 1.0)))

static func hit_chance(evasion_percent: float) -> float:
	return float(101 - d100_start(evasion_percent)) / 100.0

## Средний множитель урона по d100: бросок 1 это провал, 100 это двойной урон.
static func expected_d100(evasion_percent: float) -> float:
	var start := d100_start(evasion_percent)
	var total := 2.0
	for roll in range(start, 100):
		total += float(roll) / 100.0
	return total / 100.0

## Заряд заклинания после накопления за N шагов.
static func magic_charge(magic: float, steps: int) -> float:
	var m := maxf(0.0, magic)
	if m <= 0.0 or steps <= 0:
		return 0.0
	return m * (1.0 - pow(MAGIC_DECAY, steps)) / (1.0 - MAGIC_DECAY)

## Потолок накопления: копить дальше бессмысленно.
static func magic_ceiling(magic: float) -> float:
	return maxf(0.0, magic) / (1.0 - MAGIC_DECAY)

## Выгоднейшее накопление по среднему урону за раунд.
static func best_magic_charge(magic: float, target_body: float) -> Dictionary:
	var best := {"steps": 0, "charge": 0.0, "per_hit": 0.0, "per_round": 0.0}
	if magic <= 0.0:
		return best
	for steps in range(1, MAGIC_MAX_STEPS + 1):
		var charge := magic_charge(magic, steps)
		var per_hit := damage_through_body(charge, target_body)
		var per_round := per_hit / float(steps)
		if per_round > float(best["per_round"]):
			best = {
				"steps": steps,
				"charge": charge,
				"per_hit": per_hit,
				"per_round": per_round,
			}
	return best

static func overload_limit(attributes: Dictionary) -> float:
	return float(normalized(attributes)["body"]) * LIMIT_MULT

## Самоурон за раунд от перегруза. Тело в перегруз не входит.
static func overload_self_damage(attributes: Dictionary) -> float:
	var a := normalized(attributes)
	var limit := float(a["body"]) * LIMIT_MULT
	var total := 0.0
	for key in ["strength", "magic", "agility"]:
		total += maxf(0.0, float(a[key]) - limit) * SELF_MULT
	return total

## Сколько килограммов поднимает одна рука.
static func carry_kg_per_hand(attributes: Dictionary) -> float:
	return float(normalized(attributes)["strength"])

## Всё сразу, для панели статуса и тестов.
static func derived(attributes: Dictionary) -> Dictionary:
	var a := normalized(attributes)
	var body := float(a["body"])
	var strength := float(a["strength"])
	return {
		"max_hp": max_hp(a),
		"max_mp": max_mp(a),
		"speed_kmh": speed_kmh(a),
		"speed_mps": speed_mps(a),
		"actions": actions_per_round(a),
		"penetration_vs_self": penetration(strength, body),
		"reference_damage": damage_through_body(strength, body),
		"carry_kg": carry_kg_per_hand(a),
		"magic_ceiling": magic_ceiling(float(a["magic"])),
		"overload_limit": overload_limit(a),
		"overload_self": overload_self_damage(a),
		"expected_d100": expected_d100(0.0),
	}
