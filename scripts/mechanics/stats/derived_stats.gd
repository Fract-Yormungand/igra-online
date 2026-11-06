class_name DerivedStats
extends RefCounted

## Формулы характеристик. Чистая математика: на вход словарь характеристик,
## на выход числа. Ни сцен, ни сети, ни состояния, поэтому одинаково считается
## на сервере и на клиенте и проверяется тестом в headless-режиме.
##
## Сила даёт физический урон и здоровье.
## Тело даёт здоровье, запас сил и сопротивление урону.
## Магия даёт запас сил и силу магических эффектов.
## Ловкость даёт скорость, уклонение и частоту атак.

const ATTRIBUTE_KEYS := ["strength", "body", "magic", "agility"]
const ATTRIBUTE_NAMES := {
	"strength": "Сила",
	"body": "Тело",
	"magic": "Магия",
	"agility": "Ловкость",
}

const DAMAGE_PHYSICAL := "physical"
const DAMAGE_MAGIC := "magic"
const DAMAGE_POISON := "poison"
const DAMAGE_KINDS := ["physical", "magic", "poison"]
const DAMAGE_NAMES := {
	"physical": "физика",
	"magic": "магия",
	"poison": "яд",
}

## Здоровье: сила и тело. Запас сил: тело и магия.
const HP_BASE := 50.0
const HP_PER_STRENGTH := 10.0
const HP_PER_BODY := 14.0
const MP_BASE := 20.0
const MP_PER_BODY := 8.0
const MP_PER_MAGIC := 12.0

const PHYSICAL_POWER_PER_STRENGTH := 0.06
const MAGIC_POWER_PER_MAGIC := 0.08

const SPEED_PER_AGILITY := 0.03
const SPEED_BONUS_MAX := 0.35
const DODGE_PER_AGILITY := 0.01
const DODGE_MAX := 0.35
const ATTACK_SPEED_PER_AGILITY := 0.04
const ATTACK_SPEED_MAX := 0.60

const PHYSICAL_RESIST_PER_BODY := 0.020
const MAGIC_RESIST_PER_BODY := 0.015
const MAGIC_RESIST_PER_MAGIC := 0.010
const POISON_RESIST_PER_BODY := 0.025
const RESIST_MAX := 0.60

## С чего начинает новый игрок. Пятёрки держим не везде: так характеристики
## заметно разные, и на панели видно, что цифры считаются.
const START_ATTRIBUTES := {"strength": 4, "body": 4, "magic": 2, "agility": 3}

static func start_attributes() -> Dictionary:
	return START_ATTRIBUTES.duplicate()

## Мусор и отрицательные числа приводим к нулю: характеристики приходят
## из сети, доверять им нельзя.
static func normalized(attributes: Dictionary) -> Dictionary:
	var result := {}
	for key in ATTRIBUTE_KEYS:
		result[key] = maxi(0, int(attributes.get(key, 0)))
	return result

static func max_hp(attributes: Dictionary) -> float:
	var a := normalized(attributes)
	return HP_BASE + HP_PER_STRENGTH * float(a["strength"]) + HP_PER_BODY * float(a["body"])

static func max_mp(attributes: Dictionary) -> float:
	var a := normalized(attributes)
	return MP_BASE + MP_PER_BODY * float(a["body"]) + MP_PER_MAGIC * float(a["magic"])

## Множитель физического урона. Сила бьёт сильнее.
static func physical_power(attributes: Dictionary) -> float:
	return 1.0 + PHYSICAL_POWER_PER_STRENGTH * float(normalized(attributes)["strength"])

## Множитель магических эффектов.
static func magic_power(attributes: Dictionary) -> float:
	return 1.0 + MAGIC_POWER_PER_MAGIC * float(normalized(attributes)["magic"])

static func speed_multiplier(attributes: Dictionary) -> float:
	var bonus := SPEED_PER_AGILITY * float(normalized(attributes)["agility"])
	return 1.0 + minf(SPEED_BONUS_MAX, bonus)

static func dodge_chance(attributes: Dictionary) -> float:
	var chance := DODGE_PER_AGILITY * float(normalized(attributes)["agility"])
	return minf(DODGE_MAX, chance)

## Пауза между атаками. Ловкость её сокращает, ниже минимума не опускаемся.
static func attack_interval(base_seconds: float, attributes: Dictionary) -> float:
	var bonus := ATTACK_SPEED_PER_AGILITY * float(normalized(attributes)["agility"])
	return base_seconds / (1.0 + minf(ATTACK_SPEED_MAX, bonus))

static func resistance(kind: String, attributes: Dictionary) -> float:
	var a := normalized(attributes)
	var body := float(a["body"])
	var magic := float(a["magic"])
	var value := 0.0
	match kind:
		DAMAGE_PHYSICAL:
			value = PHYSICAL_RESIST_PER_BODY * body
		DAMAGE_MAGIC:
			value = MAGIC_RESIST_PER_BODY * body + MAGIC_RESIST_PER_MAGIC * magic
		DAMAGE_POISON:
			value = POISON_RESIST_PER_BODY * body
		_:
			return 0.0
	return minf(RESIST_MAX, value)

## Сколько урона реально дойдёт после сопротивления. Меньше нуля не бывает.
static func damage_after_resistance(amount: float, kind: String, attributes: Dictionary) -> float:
	if amount <= 0.0:
		return 0.0
	return maxf(0.0, amount * (1.0 - resistance(kind, attributes)))

## Всё сразу, для панели статуса и тестов.
static func derived(attributes: Dictionary) -> Dictionary:
	var a := normalized(attributes)
	return {
		"max_hp": max_hp(a),
		"max_mp": max_mp(a),
		"physical_power": physical_power(a),
		"magic_power": magic_power(a),
		"speed_multiplier": speed_multiplier(a),
		"dodge_chance": dodge_chance(a),
		"attack_interval": attack_interval(1.0, a),
		"resist_physical": resistance(DAMAGE_PHYSICAL, a),
		"resist_magic": resistance(DAMAGE_MAGIC, a),
		"resist_poison": resistance(DAMAGE_POISON, a),
	}
