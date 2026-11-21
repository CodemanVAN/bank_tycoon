extends SceneTree

## Standalone & embeddable 4-Tier E2E Test Runner for Starway Bank / Bank Tycoon.
## CLI:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path "bank_tycoon_demo" --script "res://tests/e2e/run_e2e_tests.gd"
## Embeddable:
##   var summary: Dictionary = load("res://tests/e2e/run_e2e_tests.gd").run_all(root_tree)

const HARNESS_PATH: String = "res://tests/e2e/e2e_harness.gd"

const TIER_SPECS: Array[Dictionary] = [
	{"tier": 1, "key": "tier1", "script": "res://tests/e2e/test_tier1_features.gd"},
	{"tier": 2, "key": "tier2", "script": "res://tests/e2e/test_tier2_boundaries.gd"},
	{"tier": 3, "key": "tier3", "script": "res://tests/e2e/test_tier3_combinations.gd"},
	{"tier": 4, "key": "tier4", "script": "res://tests/e2e/test_tier4_scenarios.gd"},
]


var _started: bool = false


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
	print("[E2E] TOTAL: %d/%d passed, %d failed" % [passed_all, total_all, failed_all])

	return {
		"total": total_all,
		"passed": passed_all,
		"failed": failed_all,
		"tiers": tiers_summary,
		"failures": failures,
	}
