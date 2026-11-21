class_name FinanceEngine
extends RefCounted

## Double-entry financial operations, credit evaluation, and 10-step daily settlement.


const INT64_MAX_VAL: int = 9223372036854775807
const INT64_MIN_VAL: int = -9223372036854775807 - 1


static func _sat_add(a: int, b: int) -> int:
	if b > 0 and a > INT64_MAX_VAL - b:
		return INT64_MAX_VAL
	if b < 0 and a < INT64_MIN_VAL - b:
		return INT64_MIN_VAL
	return a + b


static func _sat_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	if a == INT64_MIN_VAL:
		if b == 1:
			return INT64_MIN_VAL
		return INT64_MAX_VAL if b < 0 else INT64_MIN_VAL
	if b == INT64_MIN_VAL:
		if a == 1:
			return INT64_MIN_VAL
		return INT64_MAX_VAL if a < 0 else INT64_MIN_VAL
	var abs_a: int = absi(a)
	var abs_b: int = absi(b)
	if abs_a > INT64_MAX_VAL / abs_b:
		return INT64_MIN_VAL if ((a < 0) != (b < 0)) else INT64_MAX_VAL
	return a * b


static func _mul_div_nonneg_sat(val: int, mul: int, den: int) -> int:
	if val <= 0 or mul <= 0 or den <= 0:
		return 0
	if val <= INT64_MAX_VAL / mul:
		return round_div(val * mul, den)
	var q: int = val / den
	var r: int = val % den
	var p1: int = _sat_mul(q, mul)
	var p2: int = 0
	if r <= INT64_MAX_VAL / mul:
		p2 = round_div(r * mul, den)
	else:
		var mq: int = mul / den
		var mr: int = mul % den
		p2 = _sat_add(_sat_mul(r, mq), round_div(_sat_mul(r, mr), den))
	return _sat_add(p1, p2)


static func round_div(numerator: int, denominator: int) -> int:
	if denominator == 0 or numerator == 0:
		return 0
	if denominator == INT64_MIN_VAL:
		if numerator == INT64_MIN_VAL:
			return 1
		var abs_n: int = absi(numerator)
		if abs_n >= 4611686018427387904:
			return -1 if numerator > 0 else 1
		return 0
	var abs_den: int = absi(denominator)
	if numerator == INT64_MIN_VAL and abs_den == 1:
		return INT64_MIN_VAL if denominator > 0 else INT64_MAX_VAL
	var sign_val: int = -1 if ((numerator < 0) != (denominator < 0)) else 1
	var neg_num: int = numerator if numerator < 0 else -numerator
	var quotient: int = -(neg_num / abs_den)
	var remainder: int = -(neg_num % abs_den)
	var half_up: int = (abs_den / 2) + (abs_den % 2)
	if remainder >= half_up:
		quotient += 1
	return sign_val * quotient


func record_initial_capital(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "init_cap"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_INIT_CAPITAL", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": amount_minor},
		{"account": &"equity_capital", "side": "credit", "amount_minor": amount_minor},
	])


func record_deposit(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "deposit"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_DEPOSIT", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": amount_minor},
		{"account": &"customer_deposits", "side": "credit", "amount_minor": amount_minor},
	])


func record_withdrawal(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "withdrawal"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	var dep_bal: int = bank_state.ledger.get_balance(&"customer_deposits")
	if dep_bal < amount_minor:
		return Result.fail(
			&"INSUFFICIENT_DEPOSITS",
			"ERR_INSUFFICIENT_DEPOSITS",
			{"requested": amount_minor, "available": dep_bal}
		)
	var cash_bal: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_bal < amount_minor:
		return Result.fail(
			&"INSUFFICIENT_CASH",
			"ERR_INSUFFICIENT_CASH",
			{"requested": amount_minor, "available": cash_bal}
		)
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_WITHDRAWAL", [
		{"account": &"customer_deposits", "side": "debit", "amount_minor": amount_minor},
		{"account": &"cash_reserves", "side": "credit", "amount_minor": amount_minor},
	])


func record_service_fee(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "fee"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_SERVICE_FEE", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": amount_minor},
		{"account": &"fee_income", "side": "credit", "amount_minor": amount_minor},
	])


func disburse_loan(
	bank_state: BankState,
	customer_id: String,
	principal_minor: int,
	annual_rate_bps: int,
	term_days: int,
	ref_id: String = ""
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if principal_minor <= 0 or annual_rate_bps < 0 or term_days <= 0:
		return Result.fail(&"INVALID_LOAN_TERMS", "ERR_INVALID_LOAN_TERMS", {
			"principal_minor": principal_minor,
			"annual_rate_bps": annual_rate_bps,
			"term_days": term_days,
		})
	var cash_bal: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_bal < principal_minor:
		return Result.fail(
			&"INSUFFICIENT_CASH",
			"ERR_INSUFFICIENT_CASH",
			{"requested": principal_minor, "available": cash_bal}
		)

	var loan_id: String = bank_state.next_id("loan")
	var post_ref: String = ref_id if ref_id != "" else loan_id
	var post_res: Result = bank_state.ledger.post_entry(
		bank_state.current_day,
		bank_state.current_minute_of_day,
		post_ref,
		"LEDGER_LOAN_DISBURSEMENT",
		[
			{"account": &"loan_principal_outstanding", "side": "debit", "amount_minor": principal_minor},
			{"account": &"cash_reserves", "side": "credit", "amount_minor": principal_minor},
		]
	)
	if not post_res.ok:
		return post_res

	var loan := LoanInstance.new()
	loan.loan_id = loan_id
	loan.customer_id = customer_id
	loan.principal_original = principal_minor
	loan.principal_outstanding = principal_minor
	loan.annual_rate_bps = annual_rate_bps
	loan.term_days = term_days
	loan.originated_day = bank_state.current_day
	loan.repayment_mode = bank_state.loan_repayment_mode
	loan.status = Enums.LoanStatus.ACTIVE
	bank_state.loans[loan_id] = loan
	return Result.succeed(loan)


func record_loan_repayment(
	bank_state: BankState,
	loan_id: String,
	amount_minor: int,
	day: int = 1,
	minute: int = 560
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})

	var total_loan_bal: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
	if total_loan_bal < amount_minor:
		return Result.fail(
			&"LOAN_REPAYMENT_EXCEEDS_PRINCIPAL",
			"ERR_LOAN_REPAYMENT_EXCEEDS_PRINCIPAL",
			{"amount_minor": amount_minor, "outstanding": total_loan_bal}
		)

	if bank_state.loans.has(loan_id):
		var loan: LoanInstance = bank_state.loans[loan_id] as LoanInstance
		if loan == null:
			return Result.fail(&"ERR_INVALID_LOAN", "ERR_INVALID_LOAN", {"loan_id": loan_id})
		if not loan.is_active():
			return Result.fail(
				&"ERR_LOAN_NOT_ACTIVE",
				"ERR_LOAN_NOT_ACTIVE",
				{"loan_id": loan_id, "status": loan.status}
			)
		if amount_minor > loan.principal_outstanding:
			return Result.fail(
				&"LOAN_REPAYMENT_EXCEEDS_PRINCIPAL",
				"ERR_LOAN_REPAYMENT_EXCEEDS_PRINCIPAL",
				{"loan_id": loan_id, "amount_minor": amount_minor, "outstanding": loan.principal_outstanding}
			)
		var post_res: Result = bank_state.ledger.post_entry(day, minute, loan_id, "LEDGER_LOAN_REPAYMENT", [
			{"account": &"cash_reserves", "side": "debit", "amount_minor": amount_minor},
			{"account": &"loan_principal_outstanding", "side": "credit", "amount_minor": amount_minor},
		])
		if not post_res.ok:
			return post_res
		var apply_res: Result = loan.apply_repayment(amount_minor)
		if not apply_res.ok:
			return apply_res
		return Result.succeed(loan)

	# Unlinked repayment against aggregate loan principal outstanding
	var unlinked_res: Result = bank_state.ledger.post_entry(day, minute, loan_id, "LEDGER_LOAN_REPAYMENT", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": amount_minor},
		{"account": &"loan_principal_outstanding", "side": "credit", "amount_minor": amount_minor},
	])
	if not unlinked_res.ok:
		return unlinked_res
	return Result.succeed({"loan_id": loan_id, "amount_minor": amount_minor})


func record_credit_loss(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 1020,
	ref_id: String = "credit_loss"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	var loan_bal: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
	if loan_bal < amount_minor:
		return Result.fail(
			&"CREDIT_LOSS_EXCEEDS_LOANS",
			"ERR_CREDIT_LOSS_EXCEEDS_LOANS",
			{"amount_minor": amount_minor, "loan_principal_outstanding": loan_bal}
		)
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_CREDIT_LOSS", [
		{"account": &"credit_loss_expense", "side": "debit", "amount_minor": amount_minor},
		{"account": &"loan_principal_outstanding", "side": "credit", "amount_minor": amount_minor},
	])


func record_operating_cost(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 1020,
	ref_id: String = "opex"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	var cash_bal: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_bal < amount_minor:
		return Result.fail(
			&"INSUFFICIENT_CASH",
			"ERR_INSUFFICIENT_CASH",
			{"requested": amount_minor, "available": cash_bal}
		)
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_OPERATING_COST", [
		{"account": &"operating_expense", "side": "debit", "amount_minor": amount_minor},
		{"account": &"cash_reserves", "side": "credit", "amount_minor": amount_minor},
	])


func record_event_expense(
	bank_state: BankState,
	amount_minor: int,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "event_expense"
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if amount_minor <= 0:
		return Result.fail(&"INVALID_AMOUNT", "ERR_INVALID_AMOUNT", {"amount_minor": amount_minor})
	var cash_bal: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_bal < amount_minor:
		return Result.fail(
			&"INSUFFICIENT_CASH",
			"ERR_INSUFFICIENT_CASH",
			{"requested": amount_minor, "available": cash_bal}
		)
	return bank_state.ledger.post_entry(day, minute, ref_id, "LEDGER_EVENT_EXPENSE", [
		{"account": &"event_expense", "side": "debit", "amount_minor": amount_minor},
		{"account": &"cash_reserves", "side": "credit", "amount_minor": amount_minor},
	])


static func _dept_level(bank_state: BankState, dept_id: String) -> int:
	if bank_state == null or not bank_state.departments.has(dept_id):
		return 0
	var entry: Variant = bank_state.departments[dept_id]
	if entry is Object:
		return maxi(0, int((entry as Object).get("level")))
	if entry is Dictionary:
		return maxi(0, int((entry as Dictionary).get("level", 0)))
	return 0


func evaluate_loan_application(
	customer: Variant,
	loan_req: Dictionary,
	bank_state: BankState,
	modifiers: ModifierService = null
) -> Dictionary:
	var raw_principal: int = int(loan_req.get("principal_minor", 100_000))
	if raw_principal <= 0:
		return {
			"credit_score": 0,
			"risk_grade": "D",
			"estimated_pd_bps": int(BalanceConfig.PD_BPS_BY_GRADE.get("D", 1500)),
			"recommended_action": "reject",
			"requires_manual_approval": true,
		}
	var principal_minor: int = raw_principal
	var collateral_value: int = maxi(0, int(loan_req.get("collateral_value", 0)))

	var profile: Dictionary = {}
	var cust_type: String = "regular"
	if customer is CustomerInstance:
		profile = (customer as CustomerInstance).credit_profile
		cust_type = (customer as CustomerInstance).customer_type
	elif customer is Dictionary:
		var cd: Dictionary = customer as Dictionary
		cust_type = str(cd.get("customer_type", "regular"))
		var cp: Variant = cd.get("credit_profile", {})
		if cp is Dictionary:
			profile = cp as Dictionary

	var income_minor: int = int(profile.get("income_minor", 600_000))
	var history_score: int = int(profile.get("history_score", 70))
	var risk_tag: String = str(profile.get("risk_tag", "normal"))

	var income_factor: int = clampi(round_div(income_minor, 60_000), 0, 20)
	var history_factor: int = clampi(round_div(history_score - 40, 4), -10, 15)
	if cust_type == "vip":
		income_factor = mini(20, income_factor + 4)
	elif cust_type == "suspicious" or risk_tag == "high":
		history_factor -= 15

	var collateral_factor: int = 0
	if collateral_value >= principal_minor:
		collateral_factor = 20
	elif collateral_value > 0:
		if collateral_value <= 400_000_000_000_000_000:
			collateral_factor = clampi(round_div(collateral_value * 20, principal_minor), 0, 20)
		else:
			collateral_factor = clampi(round_div((collateral_value / 100) * 20, maxi(1, principal_minor / 100)), 0, 20)
	var debt_load: int = clampi(round_div(principal_minor, 100_000), 0, 15)

	var macro_risk: int = 0
	if bank_state != null:
		for ev_mod in bank_state.active_event_modifiers:
			if int(ev_mod.get("expires_day", 0)) >= bank_state.current_day:
				var eff: Variant = ev_mod.get("effect", {})
				if eff is Dictionary and str((eff as Dictionary).get("target", "")) == "loan.default_risk_bps":
					var d_val: int = int((eff as Dictionary).get("value", 0))
					if d_val > 0:
						macro_risk += clampi(round_div(d_val, 100), 0, 15)
	macro_risk = clampi(macro_risk, 0, 20)

	var credit_score: int = clampi(
		BalanceConfig.CREDIT_BASE_SCORE + income_factor + history_factor + collateral_factor - macro_risk - debt_load,
		0,
		100
	)

	var risk_grade: String = "D"
	if credit_score >= BalanceConfig.CREDIT_GRADE_A_MIN:
		risk_grade = "A"
	elif credit_score >= BalanceConfig.CREDIT_GRADE_B_MIN:
		risk_grade = "B"
	elif credit_score >= BalanceConfig.CREDIT_GRADE_C_MIN:
		risk_grade = "C"

	var base_pd_bps: int = int(BalanceConfig.PD_BPS_BY_GRADE.get(risk_grade, 700))
	var estimated_pd_bps: int = base_pd_bps
	if bank_state != null:
		if modifiers != null:
			estimated_pd_bps = modifiers.evaluate_state_target(bank_state, {}, "loan.default_risk_bps", base_pd_bps)
		var risk_lvl: int = _dept_level(bank_state, "core:department.risk")
		if risk_lvl >= 2:
			estimated_pd_bps = maxi(25, estimated_pd_bps - (risk_lvl - 1) * 100)
	estimated_pd_bps = clampi(estimated_pd_bps, 0, BalanceConfig.BPS_DENOMINATOR)

	var cash_avail: int = 0
	if bank_state != null and bank_state.ledger != null:
		cash_avail = bank_state.ledger.get_balance(&"cash_reserves")

	var recommended_action: String = "approve"
	var requires_manual_approval: bool = false
	if credit_score < BalanceConfig.CREDIT_GRADE_C_MIN or cash_avail < principal_minor:
		recommended_action = "reject"
	elif credit_score < BalanceConfig.CREDIT_GRADE_B_MIN or principal_minor > BalanceConfig.LOAN_AUTO_APPROVAL_LIMIT_MINOR:
		recommended_action = "review"
		requires_manual_approval = true

	return {
		"credit_score": credit_score,
		"risk_grade": risk_grade,
		"estimated_pd_bps": estimated_pd_bps,
		"recommended_action": recommended_action,
		"requires_manual_approval": requires_manual_approval,
	}


func run_daily_settlement(
	bank_state: BankState,
	modifiers: ModifierService = null,
	market_rng: RandomNumberGenerator = null,
	content_defs: Dictionary = {}
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var day: int = bank_state.current_day

	# Step 1: Idempotency check
	if bank_state.settled_days.has(day):
		return Result.fail(&"DAY_ALREADY_SETTLED", "ERR_DAY_ALREADY_SETTLED", {"day": day})
	for rep in bank_state.daily_reports:
		if int(rep.get("day", 0)) == day:
			return Result.fail(&"DAY_ALREADY_SETTLED", "ERR_DAY_ALREADY_SETTLED", {"day": day})

	bank_state.day_phase = Enums.DayPhase.CLOSING
	var active_effects: Array[Dictionary] = []
	if modifiers != null:
		active_effects = modifiers.collect_active_effects(bank_state, content_defs)

	# Step 2: Accrue daily interest & scheduled daily principal amortization (performing loans only; overdue loans do not pay)
	var total_loan_interest: int = 0
	var tracked_loan_principal: int = 0
	var loan_ids: Array[String] = []
	for lid: Variant in bank_state.loans.keys():
		loan_ids.append(str(lid))
	loan_ids.sort()

	for lid in loan_ids:
		var loan: LoanInstance = bank_state.loans[lid] as LoanInstance
		if loan == null:
			continue
		if (
			loan.status == Enums.LoanStatus.ACTIVE
			or loan.status == Enums.LoanStatus.DELINQUENT
			or loan.status == Enums.LoanStatus.DEFAULTED
		) and loan.principal_outstanding > 0:
			tracked_loan_principal += loan.principal_outstanding
		# Only performing loans (ACTIVE & 0 days past due) pay daily interest & principal per repayment_mode
		if loan.status == Enums.LoanStatus.ACTIVE and loan.days_past_due == 0 and loan.principal_outstanding > 0:
			var l_int: int = _mul_div_nonneg_sat(
				loan.principal_outstanding,
				loan.annual_rate_bps,
				BalanceConfig.BPS_DENOMINATOR * BalanceConfig.DAYS_PER_YEAR
			)
			if loan.repayment_mode == "principal_first":
				# Principal-first: defer daily interest until principal is paid off or maturity
				loan.accrued_unpaid_interest_minor += l_int
			else:
				total_loan_interest += l_int
				loan.total_interest_paid_minor += l_int
			loan.last_accrued_day = day

	var ledger_loan_bal: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
	if ledger_loan_bal > tracked_loan_principal:
		var unlinked_principal: int = ledger_loan_bal - tracked_loan_principal
		total_loan_interest += _mul_div_nonneg_sat(
			unlinked_principal,
			bank_state.loan_base_rate_bps,
			BalanceConfig.BPS_DENOMINATOR * BalanceConfig.DAYS_PER_YEAR
		)

	# Daily scheduled principal amortization according to each loan's repayment_mode:
	# - equal_installment (default): daily principal installment + daily interest
	# - interest_first: daily interest only during term, balloon principal at maturity
	# - principal_first: accelerated 1.5x daily principal first, deferred interest collected on payoff/maturity
	for lid in loan_ids:
		var loan_p: LoanInstance = bank_state.loans[lid] as LoanInstance
		if loan_p == null:
			continue
		if loan_p.status == Enums.LoanStatus.ACTIVE and loan_p.days_past_due == 0 and loan_p.principal_outstanding > 0:
			var daily_prin: int = 0
			if loan_p.repayment_mode == "interest_first":
				if loan_p.days_elapsed + 1 >= loan_p.term_days:
					daily_prin = loan_p.principal_outstanding
			elif loan_p.repayment_mode == "principal_first":
				var base_step: int = loan_p.get_daily_principal_installment()
				daily_prin = mini(loan_p.principal_outstanding, maxi(1, round_div(base_step * 150, 100)))
			else:
				# Default equal_installment: recover a portion of principal EVERY day alongside interest
				daily_prin = loan_p.get_daily_principal_installment()

			var max_ledger_prin: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
			var collect_prin: int = mini(daily_prin, max_ledger_prin)
			if collect_prin > 0:
				record_loan_repayment(bank_state, lid, collect_prin, day, BalanceConfig.BUSINESS_CLOSE_MINUTE)

			# If principal_first finished principal (or hit maturity), collect deferred interest now
			if loan_p.repayment_mode == "principal_first" and (loan_p.principal_outstanding == 0 or loan_p.days_elapsed + 1 >= loan_p.term_days):
				if loan_p.accrued_unpaid_interest_minor > 0:
					total_loan_interest += loan_p.accrued_unpaid_interest_minor
					loan_p.total_interest_paid_minor += loan_p.accrued_unpaid_interest_minor
					loan_p.accrued_unpaid_interest_minor = 0

	if total_loan_interest > 0:
		var li_res: Result = bank_state.ledger.post_entry(
			day,
			BalanceConfig.BUSINESS_CLOSE_MINUTE,
			"int_loan_d%d" % day,
			"LEDGER_DAILY_LOAN_INTEREST",
			[
				{"account": &"cash_reserves", "side": "debit", "amount_minor": total_loan_interest},
				{"account": &"loan_interest_income", "side": "credit", "amount_minor": total_loan_interest},
			]
		)
		if not li_res.ok:
			return li_res

	var dep_bal: int = bank_state.ledger.get_balance(&"customer_deposits")
	var total_dep_interest: int = _mul_div_nonneg_sat(
		dep_bal,
		bank_state.deposit_rate_bps,
		BalanceConfig.BPS_DENOMINATOR * BalanceConfig.DAYS_PER_YEAR
	)
	if total_dep_interest > 0:
		var di_res: Result = bank_state.ledger.post_entry(
			day,
			BalanceConfig.BUSINESS_CLOSE_MINUTE,
			"int_dep_d%d" % day,
			"LEDGER_DAILY_DEPOSIT_INTEREST",
			[
				{"account": &"deposit_interest_expense", "side": "debit", "amount_minor": total_dep_interest},
				{"account": &"customer_deposits", "side": "credit", "amount_minor": total_dep_interest},
			]
		)
		if not di_res.ok:
			return di_res

	# Step 3: Operating costs (Staff, Facility, Departments)
	var staff_cost: int = 0
	var emp_ids: Array[String] = []
	for eid: Variant in bank_state.employees.keys():
		emp_ids.append(str(eid))
	emp_ids.sort()
	for eid in emp_ids:
		var emp: EmployeeInstance = bank_state.employees[eid] as EmployeeInstance
		if emp != null:
			staff_cost += maxi(0, emp.daily_salary_minor)

	var facility_cost: int = BalanceConfig.DEFAULT_DAILY_FACILITY_RENT_MINOR

	var dept_defs_by_id: Dictionary = {}
	var raw_dept_defs: Variant = content_defs.get("departments", [])
	if raw_dept_defs is Array:
		for item in (raw_dept_defs as Array):
			if item is Dictionary:
				dept_defs_by_id[str((item as Dictionary).get("id", ""))] = item

	var department_cost: int = 0
	var dept_ids: Array[String] = []
	for did: Variant in bank_state.departments.keys():
		dept_ids.append(str(did))
	dept_ids.sort()
	for did in dept_ids:
		var dv: Variant = bank_state.departments[did]
		var lvl: int = _dept_level(bank_state, did)
		if lvl <= 0:
			continue
		var d_cost: int = 0
		if dept_defs_by_id.has(did):
			d_cost = int((dept_defs_by_id[did] as Dictionary).get("daily_cost_minor", 0))
		elif dv is Object:
			d_cost = int((dv as Object).get("daily_cost_minor"))
		elif dv is Dictionary:
			d_cost = int((dv as Dictionary).get("daily_cost_minor", 0))
		department_cost += maxi(0, d_cost)

	var cash_avail: int = bank_state.ledger.get_balance(&"cash_reserves")
	var paid_staff: int = mini(staff_cost, cash_avail)
	if paid_staff > 0:
		record_operating_cost(bank_state, paid_staff, day, BalanceConfig.BUSINESS_CLOSE_MINUTE, "payroll_d%d" % day)
		cash_avail = bank_state.ledger.get_balance(&"cash_reserves")

	var paid_facility: int = mini(facility_cost, cash_avail)
	if paid_facility > 0:
		record_operating_cost(bank_state, paid_facility, day, BalanceConfig.BUSINESS_CLOSE_MINUTE, "rent_d%d" % day)
		cash_avail = bank_state.ledger.get_balance(&"cash_reserves")

	var paid_dept: int = mini(department_cost, cash_avail)
	if paid_dept > 0:
		record_operating_cost(bank_state, paid_dept, day, BalanceConfig.BUSINESS_CLOSE_MINUTE, "dept_cost_d%d" % day)

	# Step 4: Summarize fee income (already posted during business hours)
	var fee_inc_day: int = bank_state.ledger.get_balance(&"fee_income")

	# Step 5: Loan delinquency, default & credit loss
	var risk_lvl: int = _dept_level(bank_state, "core:department.risk")
	var default_risk_bps_mod: int = 0
	if modifiers != null:
		default_risk_bps_mod = modifiers.evaluate_effects("loan.default_risk_bps", 0, active_effects)
	for lid in loan_ids:
		var loan: LoanInstance = bank_state.loans[lid] as LoanInstance
		if loan == null or not loan.is_active():
			continue
		loan.days_elapsed += 1
		var grade_code: String = loan.get_risk_grade_code()
		var base_pd_bps: int = int(BalanceConfig.PD_BPS_BY_GRADE.get(grade_code, 300))
		var effective_pd_bps: int = clampi(base_pd_bps + default_risk_bps_mod, 0, BalanceConfig.BPS_DENOMINATOR)
		if risk_lvl >= 2:
			effective_pd_bps = round_div(effective_pd_bps * maxi(40, 100 - (risk_lvl - 1) * 20), 100)
		var daily_hazard_bps: int = maxi(1, round_div(effective_pd_bps, maxi(1, loan.term_days)))
		var roll: int = market_rng.randi_range(0, 9999) if market_rng != null else 9999
		var matured_overdue: bool = loan.days_elapsed > loan.term_days and loan.principal_outstanding > 0

		if roll < daily_hazard_bps or (matured_overdue and roll < daily_hazard_bps * 3):
			loan.days_past_due += 1
			if loan.days_past_due >= 3 or roll < maxi(1, daily_hazard_bps / 2):
				var lgd_bps: int = int(BalanceConfig.LGD_BPS_BY_GRADE.get(grade_code, 5000))
				if risk_lvl >= 3:
					lgd_bps = round_div(lgd_bps * 75, 100)
				var raw_loss: int = maxi(1, _mul_div_nonneg_sat(loan.principal_outstanding, lgd_bps, BalanceConfig.BPS_DENOMINATOR))
				var max_loss: int = mini(loan.principal_outstanding, bank_state.ledger.get_balance(&"loan_principal_outstanding"))
				var actual_loss: int = mini(raw_loss, max_loss)
				if actual_loss > 0:
					record_credit_loss(bank_state, actual_loss, day, BalanceConfig.BUSINESS_CLOSE_MINUTE, "loss_" + lid)
				loan.write_off(actual_loss)
			else:
				loan.status = Enums.LoanStatus.DELINQUENT

	# Step 6: Employee overnight recovery, adaptation tick, and event modifier expiry
	var hr_lvl: int = _dept_level(bank_state, "core:department.hr")
	var fatigue_recovery: int = BalanceConfig.OVERNIGHT_FATIGUE_RECOVERY + (10 if hr_lvl >= 3 else 0)
	for eid in emp_ids:
		var emp: EmployeeInstance = bank_state.employees[eid] as EmployeeInstance
		if emp != null:
			emp.recover_fatigue(fatigue_recovery)
			emp.tick_adaptation_day()
			if emp.state != Enums.EmployeeState.OFF_DUTY:
				emp.current_request_id = ""
				emp.state = Enums.EmployeeState.OFF_DUTY

	var kept_mods: Array[Dictionary] = []
	for entry in bank_state.active_event_modifiers:
		if int(entry.get("expires_day", 0)) > day:
			kept_mods.append(entry)
	bank_state.active_event_modifiers = kept_mods

	bank_state.reputation = clampi(bank_state.reputation, 0, 100)
	bank_state.satisfaction = clampi(bank_state.satisfaction, 0, 100)

	# Step 7: Snapshot P&L accounts and close to retained_earnings
	var loan_int_inc: int = bank_state.ledger.get_balance(&"loan_interest_income")
	var fee_inc: int = bank_state.ledger.get_balance(&"fee_income")
	var dep_int_exp: int = bank_state.ledger.get_balance(&"deposit_interest_expense")
	var opex_total: int = bank_state.ledger.get_balance(&"operating_expense")
	var credit_loss_total: int = bank_state.ledger.get_balance(&"credit_loss_expense")
	var event_exp_total: int = bank_state.ledger.get_balance(&"event_expense")

	var total_income: int = loan_int_inc + fee_inc
	var total_expense: int = dep_int_exp + opex_total + credit_loss_total + event_exp_total
	var net_interest_income: int = loan_int_inc - dep_int_exp
	var operating_profit: int = net_interest_income + fee_inc - opex_total
	var net_profit: int = total_income - total_expense

	var close_lines: Array[Dictionary] = []
	if loan_int_inc > 0:
		close_lines.append({"account": &"loan_interest_income", "side": "debit", "amount_minor": loan_int_inc})
	if fee_inc > 0:
		close_lines.append({"account": &"fee_income", "side": "debit", "amount_minor": fee_inc})
	if dep_int_exp > 0:
		close_lines.append({"account": &"deposit_interest_expense", "side": "credit", "amount_minor": dep_int_exp})
	if opex_total > 0:
		close_lines.append({"account": &"operating_expense", "side": "credit", "amount_minor": opex_total})
	if credit_loss_total > 0:
		close_lines.append({"account": &"credit_loss_expense", "side": "credit", "amount_minor": credit_loss_total})
	if event_exp_total > 0:
		close_lines.append({"account": &"event_expense", "side": "credit", "amount_minor": event_exp_total})
	if net_profit > 0:
		close_lines.append({"account": &"retained_earnings", "side": "credit", "amount_minor": net_profit})
	elif net_profit < 0:
		close_lines.append({"account": &"retained_earnings", "side": "debit", "amount_minor": absi(net_profit)})

	if close_lines.size() >= 2:
		var close_res: Result = bank_state.ledger.post_entry(
			day,
			BalanceConfig.BUSINESS_CLOSE_MINUTE,
			"close_pnl_d%d" % day,
			"LEDGER_DAILY_CLOSEOUT",
			close_lines
		)
		if not close_res.ok:
			return close_res

	# Step 8: Liquidity, NPL, and warning levels
	var cash_end: int = bank_state.ledger.get_balance(&"cash_reserves")
	var loan_end: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
	var dep_end: int = bank_state.ledger.get_balance(&"customer_deposits")
	var eq_end: int = bank_state.ledger.get_balance(&"equity_capital")
	var ret_end: int = bank_state.ledger.get_balance(&"retained_earnings")

	var liquidity_ratio: float = 99.0
	var liquidity_status: int = Enums.LiquidityStatus.SAFE
	if dep_end > 0:
		var base_wd: int = maxi(
			BalanceConfig.MIN_NEAR_TERM_WITHDRAWAL_FLOOR_MINOR,
			_mul_div_nonneg_sat(dep_end, BalanceConfig.NEAR_TERM_WITHDRAWAL_RATIO_BPS, BalanceConfig.BPS_DENOMINATOR)
		)
		var buf_bps: int = BalanceConfig.BPS_DENOMINATOR
		if modifiers != null:
			buf_bps = maxi(1_000, modifiers.evaluate_effects("liquidity.required_buffer_bps", BalanceConfig.BPS_DENOMINATOR, active_effects))
		var scaled_wd: int = maxi(1, _mul_div_nonneg_sat(base_wd, buf_bps, BalanceConfig.BPS_DENOMINATOR))
		liquidity_ratio = snappedf(float(cash_end) / float(scaled_wd), 0.0001)
		if liquidity_ratio >= 1.5:
			liquidity_status = Enums.LiquidityStatus.SAFE
		elif liquidity_ratio >= 1.0:
			liquidity_status = Enums.LiquidityStatus.CAUTION
		else:
			liquidity_status = Enums.LiquidityStatus.DANGER

	var npl_balance: int = 0
	for lid in loan_ids:
		var loan: LoanInstance = bank_state.loans[lid] as LoanInstance
		if loan != null and loan.is_npl():
			npl_balance += loan.principal_outstanding
	var npl_ratio: float = snappedf(float(npl_balance) / float(loan_end), 0.0001) if loan_end > 0 else 0.0

	var warning_level: int = Enums.EventSeverity.INFO
	if liquidity_status == Enums.LiquidityStatus.DANGER or npl_ratio >= 0.12:
		warning_level = Enums.EventSeverity.CRITICAL
	elif liquidity_status == Enums.LiquidityStatus.CAUTION or npl_ratio >= 0.05 or net_profit < 0:
		warning_level = Enums.EventSeverity.WARNING

	# Step 8b: Organic daily awareness (知名度) growth from operations, staff loyalty/satisfaction, departments & luxury decor
	var awareness_gain: int = 1
	var emp_loyalty_sum: int = 0
	var emp_cnt: int = 0
	for ev_emp: Variant in bank_state.employees.values():
		if ev_emp is EmployeeInstance:
			emp_loyalty_sum += (ev_emp as EmployeeInstance).loyalty
			emp_cnt += 1
	var avg_loyalty: int = (emp_loyalty_sum / emp_cnt) if emp_cnt > 0 else 50
	if avg_loyalty >= 75 and bank_state.satisfaction >= 78:
		awareness_gain += 2
	elif avg_loyalty >= 62 and bank_state.satisfaction >= 65:
		awareness_gain += 1
	var active_dept_bonus: int = 0
	for did_aw: Variant in bank_state.departments.keys():
		var de_aw: Variant = bank_state.departments[did_aw]
		var has_staff_aw: bool = true
		if de_aw is Dictionary:
			var s_ids: Variant = (de_aw as Dictionary).get("staff_ids", [])
			if s_ids is Array and (s_ids as Array).is_empty() and bool((de_aw as Dictionary).get("requires_staff", false)):
				has_staff_aw = false
		if has_staff_aw:
			active_dept_bonus += 1
	awareness_gain += mini(3, active_dept_bonus)
	var lux_cnt: int = 0
	for pid_aw: Variant in bank_state.lobby_props.keys():
		var pr_aw: Variant = bank_state.lobby_props[pid_aw]
		if pr_aw is Dictionary and BalanceConfig.LUXURY_DECOR_TYPES.has(str((pr_aw as Dictionary).get("prop_type", ""))):
			lux_cnt += 1
	if lux_cnt >= 2:
		awareness_gain += 1
	if bank_state.satisfaction < 40:
		awareness_gain = mini(0, awareness_gain - 2)
	bank_state.awareness = clampi(bank_state.awareness + awareness_gain, 0, 100)

	# Step 9: Build DailySettlementRecord with deltas & driver_keys
	var prev_report: Dictionary = bank_state.daily_reports.back() as Dictionary if not bank_state.daily_reports.is_empty() else {}
	var deltas: Dictionary = {
		"net_profit_delta": net_profit - int(prev_report.get("net_profit", 0)),
		"cash_delta": cash_end - int(prev_report.get("cash_reserves", cash_end)),
		"deposits_delta": dep_end - int(prev_report.get("customer_deposits", 0)),
		"loans_delta": loan_end - int(prev_report.get("loan_principal_outstanding", 0)),
	}
	var driver_keys: Array[String] = []
	if net_profit > 0:
		driver_keys.append("REPORT_DRIVER_PROFIT_UP")
	elif net_profit < 0:
		driver_keys.append("REPORT_DRIVER_PROFIT_DOWN")
	if credit_loss_total > 0:
		driver_keys.append("REPORT_DRIVER_CREDIT_LOSS")
	if liquidity_status != Enums.LiquidityStatus.SAFE:
		driver_keys.append("REPORT_DRIVER_LIQUIDITY_STRESS")
	if paid_staff > 0:
		driver_keys.append("REPORT_DRIVER_PAYROLL_COST")

	var record: Dictionary = {
		"day": day,
		"loan_interest_income": loan_int_inc,
		"deposit_interest_expense": dep_int_exp,
		"net_interest_income": net_interest_income,
		"fee_income": fee_inc_day,
		"staff_cost": paid_staff,
		"facility_cost": paid_facility,
		"department_cost": paid_dept,
		"operating_expense": opex_total,
		"credit_loss_expense": credit_loss_total,
		"event_expense": event_exp_total,
		"operating_profit": operating_profit,
		"net_profit": net_profit,
		"cash_reserves": cash_end,
		"loan_principal_outstanding": loan_end,
		"customer_deposits": dep_end,
		"equity_capital": eq_end,
		"retained_earnings": ret_end,
		"liquidity_ratio": liquidity_ratio,
		"liquidity_status": liquidity_status,
		"npl_ratio": npl_ratio,
		"warning_level": warning_level,
		"reputation": bank_state.reputation,
		"satisfaction": bank_state.satisfaction,
		"awareness": bank_state.awareness,
		"awareness_delta": awareness_gain,
		"deltas": deltas,
		"driver_keys": driver_keys,
	}

	# Step 10: Commit settlement state
	bank_state.daily_reports.append(record)
	bank_state.settled_days.append(day)
	bank_state.last_settled_day = day
	bank_state.day_phase = Enums.DayPhase.SETTLED
	return Result.succeed(record)
