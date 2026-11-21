class_name RngStreams
extends RefCounted

## Deterministic multi-stream random number generator state.

const SALT_CUSTOMER: int = 1
const SALT_EVENT: int = 2
const SALT_MARKET: int = 3
const SALT_CANDIDATE: int = 4

var world_seed: int = 20261121
var customer_rng: RandomNumberGenerator = null
var event_rng: RandomNumberGenerator = null
var market_rng: RandomNumberGenerator = null
var candidate_rng: RandomNumberGenerator = null


func _init(p_world_seed: int = 20261121) -> void:
	world_seed = p_world_seed
	customer_rng = _make_rng(_derive_seed(world_seed, SALT_CUSTOMER))
	event_rng = _make_rng(_derive_seed(world_seed, SALT_EVENT))
	market_rng = _make_rng(_derive_seed(world_seed, SALT_MARKET))
	candidate_rng = _make_rng(_derive_seed(world_seed, SALT_CANDIDATE))


static func _derive_seed(base_seed: int, salt: int) -> int:
	var z: int = base_seed ^ (salt * -7046029254386353131)
	z = (z ^ (z >> 30)) * -4658895280553007687
	z = (z ^ (z >> 27)) * -7723592293110705685
	z = z ^ (z >> 31)
	if z == 0:
		z = salt + 1
	return z


static func _make_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


static func _parse_i64(val: Variant, fallback: int = 0) -> int:
	if val is int:
		return int(val)
	if val is float:
		return int(val)
	if val is String:
		var s: String = (val as String).strip_edges()
		if s.is_valid_int():
			return s.to_int()
	return fallback


static func _serialize_rng(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"seed": str(rng.seed),
		"state": str(rng.state),
	}


static func _restore_rng(data: Dictionary, fallback_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var parsed_seed: int = _parse_i64(data.get("seed", fallback_seed), fallback_seed)
	var parsed_state: int = _parse_i64(data.get("state", 0), 0)
	# Assign seed BEFORE state because setting seed resets state.
	rng.seed = parsed_seed
	if data.has("state"):
		rng.state = parsed_state
	return rng


func to_dict() -> Dictionary:
	return {
		"world_seed": str(world_seed),
		"customer_rng": _serialize_rng(customer_rng),
		"event_rng": _serialize_rng(event_rng),
		"market_rng": _serialize_rng(market_rng),
		"candidate_rng": _serialize_rng(candidate_rng),
	}


static func from_dict(data: Dictionary) -> Result:
	if not data.has("world_seed"):
		return Result.fail(&"INVALID_RNG_STREAMS", "ERR_INVALID_RNG_STREAMS", {"missing": "world_seed"})
	var w_seed: int = _parse_i64(data.get("world_seed", 20261121), 20261121)
	var streams := RngStreams.new(w_seed)

	var stream_keys: Array[String] = ["customer_rng", "event_rng", "market_rng", "candidate_rng"]
	var salts: Array[int] = [SALT_CUSTOMER, SALT_EVENT, SALT_MARKET, SALT_CANDIDATE]
	for i in range(stream_keys.size()):
		var sk: String = stream_keys[i]
		if not data.has(sk) or not (data[sk] is Dictionary):
			return Result.fail(&"INVALID_RNG_STREAM", "ERR_INVALID_RNG_STREAM", {"stream": sk})
		var restored: RandomNumberGenerator = _restore_rng(data[sk] as Dictionary, _derive_seed(w_seed, salts[i]))
		match sk:
			"customer_rng":
				streams.customer_rng = restored
			"event_rng":
				streams.event_rng = restored
			"market_rng":
				streams.market_rng = restored
			"candidate_rng":
				streams.candidate_rng = restored

	return Result.succeed(streams)
