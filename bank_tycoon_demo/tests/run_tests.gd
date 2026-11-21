extends SceneTree

## Master headless test runner for Starway Bank / Bank Tycoon Demo (bank_tycoon_demo).
## Runs on first _process frame so SceneTree.root is inside the tree and mounted scenes
## synchronously fire _enter_tree() and _ready().

var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true

	print("==================================================================")
	print("[RUN_TESTS] Starway Bank / Bank Tycoon — Master Automated QA Suite")
	print("==================================================================")

	var total_failures: int = 0

	if ResourceLoader.exists("res://tests/e2e/run_e2e_tests.gd"):
		var e2e_script: GDScript = load("res://tests/e2e/run_e2e_tests.gd")
		if e2e_script != null:
			var summary: Dictionary = e2e_script.run_all(self)
			var e2e_total: int = int(summary.get("total", 0))
			var e2e_passed: int = int(summary.get("passed", 0))
			var e2e_failed: int = int(summary.get("failed", 0))
			print("[RUN_TESTS] E2E Suite (Tiers 1-4): %d/%d passed (%d failed)" % [e2e_passed, e2e_total, e2e_failed])
			if e2e_total <= 0 or e2e_failed > 0:
				total_failures += maxi(1, e2e_failed)
		else:
			push_error("[RUN_TESTS] Failed to load res://tests/e2e/run_e2e_tests.gd")
			total_failures += 1
	else:
		push_error("[RUN_TESTS] Missing res://tests/e2e/run_e2e_tests.gd")
		total_failures += 1

	print("==================================================================")
	if total_failures == 0:
		print("[RUN_TESTS] ALL AUTOMATED SUITES PASSED (0 failures)")
		quit(0)
	else:
		print("[RUN_TESTS] SUITE FAILED with %d failure(s)" % total_failures)
		quit(1)
	return false
