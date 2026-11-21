extends SceneTree

## Standalone & embeddable 4-Tier E2E Test Runner for Starway Bank / Bank Tycoon.
## CLI:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path "bank_tycoon_demo" --script "res://tests/e2e/run_e2e_tests.gd"
## Embeddable:
##   var summary: Dictionary = load("res://tests/e2e/run_e2e_tests.gd").run_all(root_tree)

const HARNESS_PATH: String = "res://tests/e2e/e2e_harness.gd"

## Tiers 1-4 are pure synchronous suites (run inside a single `_process` frame).
const TIER_SPECS: Array[Dictionary] = [
	{"tier": 1, "key": "tier1", "script": "res://tests/e2e/test_tier1_features.gd"},
	{"tier": 2, "key": "tier2", "script": "res://tests/e2e/test_tier2_boundaries.gd"},
	{"tier": 3, "key": "tier3", "script": "res://tests/e2e/test_tier3_combinations.gd"},
	{"tier": 4, "key": "tier4", "script": "res://tests/e2e/test_tier4_scenarios.gd"},
]

## Tier 5 needs real frame boundaries (Container layout is deferred through the
## MessageQueue), so it is a coroutine suite driven by `start_tier5_async()`.
## It is registered here so the suite has a single registry / single accounting path.
const TIER5_SPEC: Dictionary = {
	"tier": 5,
	"key": "tier5",
	"script": "res://tests/e2e/test_tier5_ui_input.gd",
}


var _started: bool = false

## Holds the *current* suspended coroutine state of the Tier 5 suite (see
## `start_tier5_async`). Keeping a reference prevents the suspension from being
## collected between two `await SceneTree.process_frame` boundaries.
static var _pending_tier5_state: Variant = null
## The Tier 5 suite is a RefCounted coroutine owner, not a Node. Without a strong
## reference the instance would be freed the moment `start_tier5_async()` returns and
## the suspension would silently never resume. Same reason the harness is kept alive.
static var _pending_tier5_suite: Variant = null
static var _pending_tier5_harness: Variant = null


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var summary: Dictionary = run_all(self)
	var exit_code: int = 0 if (int(summary.get("failed", 1)) == 0 and int(summary.get("total", 0)) > 0) else 1
	quit(exit_code)
	return false


static func run_all(root_tree: SceneTree = null) -> Dictionary:
	var tree: SceneTree = root_tree
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree

	var total_all: int = 0
	var passed_all: int = 0
	var failed_all: int = 0
	var tiers_summary: Dictionary = {}
	var failures: Array = []

	if not ResourceLoader.exists(HARNESS_PATH):
		var msg: String = "Missing E2E harness script: %s" % HARNESS_PATH
		print("[E2E] Tier 0 | HARNESS_LOAD | FAIL: %s" % msg)
		failures.append({"tier": "harness", "test": "HARNESS_LOAD", "reason": msg})
		return {
			"total": 1,
			"passed": 0,
			"failed": 1,
			"tiers": tiers_summary,
			"failures": failures,
		}

	var harness_res: Resource = ResourceLoader.load(HARNESS_PATH)
	if harness_res == null or not (harness_res is GDScript):
		var msg: String = "Failed to load E2E harness script: %s" % HARNESS_PATH
		print("[E2E] Tier 0 | HARNESS_LOAD | FAIL: %s" % msg)
		failures.append({"tier": "harness", "test": "HARNESS_LOAD", "reason": msg})
		return {
			"total": 1,
			"passed": 0,
			"failed": 1,
			"tiers": tiers_summary,
			"failures": failures,
		}

	var harness: RefCounted = (harness_res as GDScript).new(tree)
	harness.call("snapshot_environment")

	for spec in TIER_SPECS:
		var tier_num: int = int(spec.get("tier", 0))
		var tier_key: String = str(spec.get("key", ""))
		var script_path: String = str(spec.get("script", ""))

		var tier_total: int = 0
		var tier_passed: int = 0
		var tier_failed: int = 0

		if not ResourceLoader.exists(script_path):
			tier_total = 1
			tier_failed = 1
			var reason: String = "Missing tier script: %s" % script_path
			print("[E2E] Tier %d | TIER_LOAD | FAIL: %s" % [tier_num, reason])
			failures.append({"tier": tier_key, "test": "TIER_LOAD", "reason": reason})
		else:
			var tier_res: Resource = ResourceLoader.load(script_path)
			if tier_res == null or not (tier_res is GDScript):
				tier_total = 1
				tier_failed = 1
				var reason: String = "Failed to parse tier script: %s" % script_path
				print("[E2E] Tier %d | TIER_LOAD | FAIL: %s" % [tier_num, reason])
				failures.append({"tier": tier_key, "test": "TIER_LOAD", "reason": reason})
			else:
				var suite_inst: Variant = (tier_res as GDScript).new()
				if suite_inst == null or not (suite_inst is Object) or not (suite_inst as Object).has_method("run_suite"):
					tier_total = 1
					tier_failed = 1
					var reason: String = "Tier script missing run_suite(harness): %s" % script_path
					print("[E2E] Tier %d | TIER_RUN | FAIL: %s" % [tier_num, reason])
					failures.append({"tier": tier_key, "test": "TIER_RUN", "reason": reason})
				else:
					var results: Variant = (suite_inst as Object).call("run_suite", harness)
					if results is Array and not (results as Array).is_empty():
						for item in (results as Array):
							if item is Dictionary:
								var rec: Dictionary = item as Dictionary
								tier_total += 1
								if bool(rec.get("passed", false)):
									tier_passed += 1
								else:
									tier_failed += 1
									failures.append({
										"tier": tier_key,
										"test": str(rec.get("test", "UNKNOWN")),
										"reason": str(rec.get("reason", "Unknown failure")),
									})
					else:
						tier_total = 1
						tier_failed = 1
						var reason: String = "Tier run_suite returned empty or non-Array: %s" % script_path
						print("[E2E] Tier %d | TIER_EMPTY | FAIL: %s" % [tier_num, reason])
						failures.append({"tier": tier_key, "test": "TIER_EMPTY", "reason": reason})

		print("[E2E] Tier %d Summary: %d/%d passed (%d failed)" % [tier_num, tier_passed, tier_total, tier_failed])
		tiers_summary[tier_key] = {
			"total": tier_total,
			"passed": tier_passed,
			"failed": tier_failed,
		}
		total_all += tier_total
		passed_all += tier_passed
		failed_all += tier_failed

	harness.call("restore_environment")
	print("[E2E] TOTAL (Tiers 1-4 sync): %d/%d passed, %d failed" % [passed_all, total_all, failed_all])

	return {
		"total": total_all,
		"passed": passed_all,
		"failed": failed_all,
		"tiers": tiers_summary,
		"failures": failures,
	}


# ---------------------------------------------------------------------------
# Tier 5 (async / frame-driven): HUD input hit-testing regression.
# ---------------------------------------------------------------------------

## Starts the async Tier 5 suite. `on_complete` receives a summary Dictionary shaped
## exactly like the one returned by `run_all()`, so the two can be combined with
## `combine_summaries()`.
static func start_tier5_async(root_tree: SceneTree, on_complete: Callable) -> void:
	var tier_key: String = str(TIER5_SPEC.get("key", "tier5"))
	var tier_num: int = int(TIER5_SPEC.get("tier", 5))
	var script_path: String = str(TIER5_SPEC.get("script", ""))

	var tier_res: Resource = null
	if ResourceLoader.exists(script_path):
		tier_res = ResourceLoader.load(script_path)
	if tier_res == null or not (tier_res is GDScript):
		var reason: String = "Missing or unparsable tier script: %s" % script_path
		print("[E2E] Tier %d | TIER_LOAD | FAIL: %s" % [tier_num, reason])
		on_complete.call(_summary_from_records(tier_num, tier_key, [{
			"test": "TIER_LOAD",
			"passed": false,
			"reason": reason,
		}]))
		return

	var harness: RefCounted = null
	if ResourceLoader.exists(HARNESS_PATH):
		var harness_res: Resource = ResourceLoader.load(HARNESS_PATH)
		if harness_res is GDScript:
			harness = (harness_res as GDScript).new(root_tree)
	if harness == null:
		var reason2: String = "Missing E2E harness: %s" % HARNESS_PATH
		print("[E2E] Tier %d | HARNESS_LOAD | FAIL: %s" % [tier_num, reason2])
		on_complete.call(_summary_from_records(tier_num, tier_key, [{
			"test": "HARNESS_LOAD",
			"passed": false,
			"reason": reason2,
		}]))
		return

	harness.call("snapshot_environment")

	var suite: Variant = (tier_res as GDScript).new()
	if suite == null or not (suite is Object) or not (suite as Object).has_method("run_suite_async"):
		var reason3: String = "Tier script missing run_suite_async(harness, on_complete): %s" % script_path
		print("[E2E] Tier %d | TIER_RUN | FAIL: %s" % [tier_num, reason3])
		harness.call("restore_environment")
		on_complete.call(_summary_from_records(tier_num, tier_key, [{
			"test": "TIER_RUN",
			"passed": false,
			"reason": reason3,
		}]))
		return

	var done_cb := func(results: Variant) -> void:
		harness.call("restore_environment")
		_pending_tier5_state = null
		_pending_tier5_suite = null
		_pending_tier5_harness = null
		var records: Array = results as Array if results is Array else []
		on_complete.call(_summary_from_records(tier_num, tier_key, records))

	# The suite instance is a RefCounted and must outlive the suspension: keep it (and the
	# harness it uses) referenced by static state until the completion callback fires.
	_pending_tier5_suite = suite
	_pending_tier5_harness = harness

	# Fire-and-forget coroutine: it resumes on SceneTree.process_frame.
	# Keep a strong reference to the returned function state so the suspension can never
	# be garbage collected before the suite reports back.
	_pending_tier5_state = (suite as Object).call("run_suite_async", harness, done_cb)


static func _summary_from_records(tier_num: int, tier_key: String, records: Array) -> Dictionary:
	var total: int = 0
	var passed: int = 0
	var failed: int = 0
	var assertions: int = 0
	var failures: Array = []

	for item: Variant in records:
		if not (item is Dictionary):
			continue
		var rec: Dictionary = item as Dictionary
		total += 1
		assertions += int(rec.get("assertions", 0))
		if bool(rec.get("passed", false)):
			passed += 1
		else:
			failed += 1
			failures.append({
				"tier": tier_key,
				"test": str(rec.get("test", "UNKNOWN")),
				"reason": str(rec.get("reason", "Unknown failure")),
			})

	if total == 0:
		var reason: String = "Tier %d run_suite_async returned empty results" % tier_num
		print("[E2E] Tier %d | TIER_EMPTY | FAIL: %s" % [tier_num, reason])
		total = 1
		failed = 1
		failures.append({"tier": tier_key, "test": "TIER_EMPTY", "reason": reason})

	print("[E2E] Tier %d Summary: %d/%d passed (%d failed) | %d assertions" % [tier_num, passed, total, failed, assertions])
	var tiers: Dictionary = {}
	tiers[tier_key] = {"total": total, "passed": passed, "failed": failed}
	return {
		"total": total,
		"passed": passed,
		"failed": failed,
		"tiers": tiers,
		"failures": failures,
	}


## Sums two summaries (e.g. Tiers 1-4 + Tier 5) and prints the grand total line.
static func combine_summaries(first: Dictionary, second: Dictionary, label: String = "Tiers 1-5") -> Dictionary:
	var total_all: int = int(first.get("total", 0)) + int(second.get("total", 0))
	var passed_all: int = int(first.get("passed", 0)) + int(second.get("passed", 0))
	var failed_all: int = int(first.get("failed", 0)) + int(second.get("failed", 0))

	var tiers: Dictionary = {}
	var raw_a: Variant = first.get("tiers", {})
	if raw_a is Dictionary:
		tiers.merge(raw_a as Dictionary, true)
	var raw_b: Variant = second.get("tiers", {})
	if raw_b is Dictionary:
		tiers.merge(raw_b as Dictionary, true)

	var failures: Array = []
	var fa: Variant = first.get("failures", [])
	if fa is Array:
		failures.append_array(fa as Array)
	var fb: Variant = second.get("failures", [])
	if fb is Array:
		failures.append_array(fb as Array)

	print("[E2E] TOTAL (%s): %d/%d passed, %d failed" % [label, passed_all, total_all, failed_all])
	return {
		"total": total_all,
		"passed": passed_all,
		"failed": failed_all,
		"tiers": tiers,
		"failures": failures,
	}
