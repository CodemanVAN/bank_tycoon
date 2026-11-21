class_name GameClock
extends RefCounted

## Fixed-step deterministic simulation clock with catch-up cap and pause support.

const EPS: float = 1e-6

var speed_multiplier: int = 1
var speed: int:
	get:
		return speed_multiplier
	set(value):
		speed_multiplier = value

var minute_duration_sec: float = 0.25
var accumulator: float = 0.0


func set_speed(mult: int) -> Result:
	if not BalanceConfig.VALID_SPEED_MULTIPLIERS.has(mult):
		return Result.fail(
			&"INVALID_SPEED",
			"ERR_INVALID_SPEED",
			{"speed": mult}
		)
	speed_multiplier = mult
	return Result.succeed({
		"speed": speed_multiplier,
		"speed_multiplier": speed_multiplier,
	})


func reset_accumulator() -> void:
	accumulator = 0.0


func advance(delta: float) -> int:
	if speed_multiplier <= 0 or delta <= 0.0 or minute_duration_sec <= 0.0:
		return 0
	accumulator += delta * float(speed_multiplier)
	var ticks: int = 0
	while accumulator + EPS >= minute_duration_sec and ticks < BalanceConfig.MAX_TICKS_PER_FRAME:
		accumulator = maxf(0.0, accumulator - minute_duration_sec)
		ticks += 1
	if accumulator >= minute_duration_sec:
		accumulator = fmod(accumulator, minute_duration_sec)
	return ticks
