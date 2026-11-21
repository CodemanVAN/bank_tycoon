extends SceneTree

## Master headless test runner for Starway Bank / Bank Tycoon Demo (bank_tycoon_demo).
##
## Phase 1 (same `_process` frame as before): Tiers 1-4 run synchronously through
## `run_e2e_tests.run_all()` — unchanged behaviour, unchanged assertions.
## Phase 2 (following frames): Tier 5 (HUD input hit-testing) is a coroutine suite that
## needs real frame boundaries because Godot's Container layout is deferred. It reports
## back through `start_tier5_async()`'s completion callback, then the combined total is
## printed and the tree quits.
##
## A frame watchdog guarantees the process always terminates (never hang CI).

const E2E_RUNNER_PATH: String = "res://tests/e2e/run_e2e_tests.gd"
const MAX_IDLE_FRAMES: int = 1800

var _started: bool = false
var _finished: bool = false
var _idle_frames: int = 0


func _process(_delta: float) -> bool:
	if _finished:
		return false

	if not _started:
		_started = true
		_run_phase_one()
		return false

	_idle_frames += 1
	if _idle_frames > MAX_IDLE_FRAMES:
		push_error("[RUN_TESTS] Tier 5 async phase did not complete within %d frames — aborting" % MAX_IDLE_FRAMES)
		_finish(1, "Tier 5 async phase timed out")
	return false


func _run_phase_one() -> void:
	print("==================================================================")
	print("[RUN_TESTS] Starway Bank / Bank Tycoon — Master Automated QA Suite")
	print("==================================================================")

	if not ResourceLoader.exists(E2E_RUNNER_PATH):
		push_error("[RUN_TESTS] Missing %s" % E2E_RUNNER_PATH)
		_finish(1, "missing E2E runner")
		return

	var e2e_res: Resource = ResourceLoader.load(E2E_RUNNER_PATH)
	if not (e2e_res is GDScript):
		push_error("[RUN_TESTS] Failed to load %s" % E2E_RUNNER_PATH)
		_finish(1, "unparsable E2E runner")
		return

	var e2e_script: GDScript = e2e_res as GDScript
	var base_summary: Dictionary = e2e_script.run_all(self)
	print("[RUN_TESTS] E2E Suite (Tiers 1-4): %d/%d passed (%d failed)" % [
		int(base_summary.get("passed", 0)),
		int(base_summary.get("total", 0)),
		int(base_summary.get("failed", 0)),
	])

	if not e2e_script.has_method("start_tier5_async") or not e2e_script.has_method("combine_summaries"):
		push_error("[RUN_TESTS] E2E runner does not expose Tier 5 hooks")
		_finish(1, "Tier 5 hooks missing")
		return

	var on_tier5_done := func(tier5_summary: Variant) -> void:
		var t5: Dictionary = tier5_summary as Dictionary if tier5_summary is Dictionary else {}
		var combined: Dictionary = e2e_script.combine_summaries(base_summary, t5, "Tiers 1-5")
		var total: int = int(combined.get("total", 0))
		var passed: int = int(combined.get("passed", 0))
		var failed: int = int(combined.get("failed", 0))

		print("[RUN_TESTS] E2E Suite (Tiers 1-5): %d/%d passed (%d failed)" % [passed, total, failed])
		var failures: Variant = combined.get("failures", [])
		if failures is Array and not (failures as Array).is_empty():
			print("[RUN_TESTS] Failing cases:")
			for item: Variant in (failures as Array):
				if item is Dictionary:
					var rec: Dictionary = item as Dictionary
					print("  - [%s] %s: %s" % [str(rec.get("tier", "?")), str(rec.get("test", "?")), str(rec.get("reason", ""))])

		var code: int = 0 if (total > 0 and failed == 0) else 1
		_finish(code, "%d failing case(s)" % failed)

	e2e_script.start_tier5_async(self, on_tier5_done)


func _finish(code: int, detail: String) -> void:
	if _finished:
		return
	_finished = true
	print("==================================================================")
	if code == 0:
		print("[RUN_TESTS] ALL AUTOMATED SUITES PASSED (0 failures)")
	else:
		print("[RUN_TESTS] SUITE FAILED: %s" % detail)
	quit(code)
