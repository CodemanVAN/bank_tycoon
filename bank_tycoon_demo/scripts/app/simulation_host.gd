class_name SimulationHost
extends Node

## Runtime simulation coordinator Node bridging GameRoot/UI/tests with pure domain services.

signal snapshot_changed()

const ContentStudioStoreScript := preload("res://scripts/infrastructure/content_studio_store.gd")

var bank_state: BankState = null
var clock: GameClock = null
var simulation: BranchSimulation = null
var command_service: BankCommandService = null
var event_bus: DomainEventBus = null
var content_defs: Dictionary = {}
var modifiers: ModifierService = null
var auto_process: bool = true

var _last_step_frame: int = -1


func _ready() -> void:
	set_process(auto_process)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if command_service != null:
			command_service.on_state_mutated = Callable()
		if what == NOTIFICATION_PREDELETE:
			command_service = null
			simulation = null
			event_bus = null
			clock = null
			modifiers = null
			bank_state = null



func set_auto_process(enabled: bool) -> void:
	auto_process = enabled
	set_process(auto_process)


func _process(delta: float) -> void:
	if not auto_process or bank_state == null:
		return
	var cur_frame: int = Engine.get_process_frames()
	if _last_step_frame == cur_frame:
		return
	step_simulation(delta)


func bind_session(state: BankState, defs: Dictionary = {}) -> void:
	bank_state = state
	var base_defs: Dictionary = defs.duplicate(true) if not defs.is_empty() else _try_fetch_content_defs()
	content_defs = ContentStudioStoreScript.merge_into_content_defs(base_defs)

	clock = GameClock.new()
	clock.minute_duration_sec = _read_session_minute_duration()
	if bank_state != null:
		clock.speed_multiplier = bank_state.speed_multiplier

	event_bus = DomainEventBus.new()
	if bank_state != null:
		event_bus.current_day = bank_state.current_day
		event_bus.current_minute = bank_state.current_minute_of_day

	modifiers = ModifierService.new()
	simulation = BranchSimulation.new(bank_state, event_bus, content_defs, modifiers)
	command_service = BankCommandService.new(bank_state, clock, event_bus, content_defs, modifiers)
	command_service.on_state_mutated = func() -> void:
		snapshot_changed.emit()

	snapshot_changed.emit()


func reload_content_defs(merged_defs: Dictionary) -> void:
	content_defs = merged_defs.duplicate(true)
	if simulation != null:
		simulation.content_defs = content_defs
	if command_service != null:
		command_service.content_defs = content_defs
	snapshot_changed.emit()


func step_simulation(delta: float) -> void:
	if bank_state == null or clock == null or simulation == null:
		return
	_last_step_frame = Engine.get_process_frames()
	clock.speed_multiplier = bank_state.speed_multiplier
	var ticks: int = clock.advance(delta)
	if ticks <= 0:
		return
	for _i in range(ticks):
		simulation.tick_minute()
	snapshot_changed.emit()


func get_snapshot() -> Dictionary:
	if bank_state == null or bank_state.ledger == null:
		return {
			"day": 1,
			"minute": BalanceConfig.BUSINESS_OPEN_MINUTE,
			"phase": Enums.DayPhase.PRE_OPEN,
			"speed": 1,
			"cash_minor": 0,
			"deposits_minor": 0,
			"loans_minor": 0,
			"equity_minor": 0,
			"today_profit_minor": 0,
			"satisfaction": BalanceConfig.INITIAL_SATISFACTION,
			"reputation": BalanceConfig.INITIAL_REPUTATION,
			"strategy_points": BalanceConfig.INITIAL_STRATEGY_POINTS,
			"employee_count": 0,
			"queue_length": 0,
			"waiting_customers": 0,
			"pending_approvals": 0,
			"active_events": 0,
			"liquidity_ratio_bps": 990_000,
			"liquidity_status": Enums.LiquidityStatus.SAFE,
			"npl_ratio_bps": 0,
			"deposit_rate_bps": BalanceConfig.DEFAULT_DEPOSIT_RATE_BPS,
			"loan_base_rate_bps": BalanceConfig.DEFAULT_LOAN_BASE_RATE_BPS,
		}

	var ledger: Ledger = bank_state.ledger
	var cash_minor: int = ledger.get_balance(&"cash_reserves")
	var deposits_minor: int = ledger.get_balance(&"customer_deposits")
	var loans_minor: int = ledger.get_balance(&"loan_principal_outstanding")
	var equity_minor: int = ledger.get_balance(&"equity_capital") + ledger.get_balance(&"retained_earnings")

	var unclosed_income: int = ledger.get_balance(&"loan_interest_income") + ledger.get_balance(&"fee_income")
	var unclosed_expense: int = (
		ledger.get_balance(&"deposit_interest_expense")
		+ ledger.get_balance(&"operating_expense")
		+ ledger.get_balance(&"credit_loss_expense")
		+ ledger.get_balance(&"event_expense")
	)
	var today_profit_minor: int = unclosed_income - unclosed_expense
	if bank_state.day_phase == Enums.DayPhase.SETTLED and not bank_state.daily_reports.is_empty():
		var last_rep: Dictionary = bank_state.daily_reports.back() as Dictionary
		today_profit_minor = int(last_rep.get("net_profit", today_profit_minor))

	var queue_len: int = 0
	for req in bank_state.service_requests:
		if req != null and req.status == Enums.RequestStatus.QUEUED:
			queue_len += 1

	var waiting_custs: int = 0
	for cust_v: Variant in bank_state.active_customers.values():
		if cust_v is CustomerInstance:
			var cst: int = (cust_v as CustomerInstance).state
			if cst == Enums.CustomerState.WAITING or cst == Enums.CustomerState.FINDING_SERVICE:
				waiting_custs += 1

	var liq_ratio_bps: int = 990_000
	var liq_status: int = Enums.LiquidityStatus.SAFE
	if deposits_minor > 0:
		var base_wd: int = maxi(
			BalanceConfig.MIN_NEAR_TERM_WITHDRAWAL_FLOOR_MINOR,
			FinanceEngine.round_div(deposits_minor * BalanceConfig.NEAR_TERM_WITHDRAWAL_RATIO_BPS, BalanceConfig.BPS_DENOMINATOR)
		)
		var buf_bps: int = BalanceConfig.BPS_DENOMINATOR
		if modifiers != null:
			buf_bps = maxi(
				1_000,
				modifiers.evaluate_state_target(bank_state, content_defs, "liquidity.required_buffer_bps", BalanceConfig.BPS_DENOMINATOR)
			)
		var scaled_wd: int = maxi(1, FinanceEngine.round_div(base_wd * buf_bps, BalanceConfig.BPS_DENOMINATOR))
		liq_ratio_bps = FinanceEngine.round_div(cash_minor * BalanceConfig.BPS_DENOMINATOR, scaled_wd)
		if liq_ratio_bps >= BalanceConfig.LIQUIDITY_SAFE_BPS:
			liq_status = Enums.LiquidityStatus.SAFE
		elif liq_ratio_bps >= BalanceConfig.LIQUIDITY_CAUTION_BPS:
			liq_status = Enums.LiquidityStatus.CAUTION
		else:
			liq_status = Enums.LiquidityStatus.DANGER

	var npl_balance: int = 0
	for ln_v: Variant in bank_state.loans.values():
		if ln_v is LoanInstance and (ln_v as LoanInstance).is_npl():
			npl_balance += (ln_v as LoanInstance).principal_outstanding
	var npl_ratio_bps: int = FinanceEngine.round_div(npl_balance * BalanceConfig.BPS_DENOMINATOR, loans_minor) if loans_minor > 0 else 0

	return {
		"day": bank_state.current_day,
		"minute": bank_state.current_minute_of_day,
		"phase": bank_state.day_phase,
		"speed": bank_state.speed_multiplier,
		"cash_minor": cash_minor,
		"deposits_minor": deposits_minor,
		"loans_minor": loans_minor,
		"equity_minor": equity_minor,
		"today_profit_minor": today_profit_minor,
		"satisfaction": bank_state.satisfaction,
		"reputation": bank_state.reputation,
		"strategy_points": bank_state.strategy_points,
		"employee_count": bank_state.employees.size(),
		"queue_length": queue_len,
		"waiting_customers": waiting_custs,
		"pending_approvals": bank_state.pending_loan_approvals.size(),
		"active_events": bank_state.active_events.size(),
		"liquidity_ratio_bps": liq_ratio_bps,
		"liquidity_status": liq_status,
		"npl_ratio_bps": npl_ratio_bps,
		"deposit_rate_bps": bank_state.deposit_rate_bps,
		"loan_base_rate_bps": bank_state.loan_base_rate_bps,
	}


func _read_session_minute_duration() -> float:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var sess: Node = (loop as SceneTree).root.get_node_or_null("GameSession")
		if sess != null:
			var v: Variant = sess.get("minute_duration_sec")
			if v is float or v is int:
				var f: float = float(v)
				if f > 0.0:
					return f
	return 0.25


func _try_fetch_content_defs() -> Dictionary:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var reg: Node = (loop as SceneTree).root.get_node_or_null("ContentRegistry")
		if reg != null:
			if reg.has_method("get_content_defs"):
				var d: Variant = reg.call("get_content_defs")
				if d is Dictionary:
					return d as Dictionary
			elif reg.has_method("get_all_by_type"):
				return {
					"departments": reg.call("get_all_by_type", &"departments"),
					"policies": reg.call("get_all_by_type", &"policies"),
					"events": reg.call("get_all_by_type", &"events"),
					"traits": reg.call("get_all_by_type", &"traits"),
					"customers": reg.call("get_all_by_type", &"customers"),
				}
	return {}
