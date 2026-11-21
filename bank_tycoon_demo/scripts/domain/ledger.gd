class_name Ledger
extends RefCounted

## Strict 11-account double-entry accounting ledger.

const ACCOUNT_TYPES: Dictionary = {
	&"cash_reserves": Enums.AccountType.ASSET,
	&"loan_principal_outstanding": Enums.AccountType.ASSET,
	&"customer_deposits": Enums.AccountType.LIABILITY,
	&"equity_capital": Enums.AccountType.EQUITY,
	&"retained_earnings": Enums.AccountType.EQUITY,
	&"loan_interest_income": Enums.AccountType.INCOME,
	&"fee_income": Enums.AccountType.INCOME,
	&"deposit_interest_expense": Enums.AccountType.EXPENSE,
	&"operating_expense": Enums.AccountType.EXPENSE,
	&"credit_loss_expense": Enums.AccountType.EXPENSE,
	&"event_expense": Enums.AccountType.EXPENSE,
}

var _balances: Dictionary = {}
var _entries: Array[JournalEntry] = []
var _daily_summaries: Dictionary = {}
var _next_entry_id: int = 1


func _init() -> void:
	for acct: StringName in ACCOUNT_TYPES.keys():
		_balances[acct] = 0


static func is_debit_normal(account: StringName) -> bool:
	var acct_type: int = int(ACCOUNT_TYPES.get(account, -1))
	return acct_type == Enums.AccountType.ASSET or acct_type == Enums.AccountType.EXPENSE


func post_entry(
	day: int,
	minute: int,
	ref_id: String,
	description_key: String,
	lines: Array[Dictionary]
) -> Result:
	if lines.size() < 2:
		return Result.fail(
			&"LEDGER_TOO_FEW_LINES",
			"ERR_LEDGER_TOO_FEW_LINES",
			{"count": lines.size()}
		)

	var debit_total: int = 0
	var credit_total: int = 0
	var normalized_lines: Array[Dictionary] = []

	for raw_line in lines:
		if not raw_line.has("account") or not raw_line.has("side") or not raw_line.has("amount_minor"):
			return Result.fail(&"LEDGER_MALFORMED_LINE", "ERR_LEDGER_MALFORMED_LINE", {})

		var acct: StringName = StringName(str(raw_line["account"]))
		if not ACCOUNT_TYPES.has(acct):
			return Result.fail(
				&"LEDGER_UNKNOWN_ACCOUNT",
				"ERR_LEDGER_UNKNOWN_ACCOUNT",
				{"account": String(acct)}
			)

		var side: String = str(raw_line["side"])
		if side != "debit" and side != "credit":
			return Result.fail(
				&"LEDGER_INVALID_SIDE",
				"ERR_LEDGER_INVALID_SIDE",
				{"side": side}
			)

		var raw_amt: Variant = raw_line["amount_minor"]
		if typeof(raw_amt) != TYPE_INT:
			return Result.fail(
				&"LEDGER_INVALID_AMOUNT",
				"ERR_LEDGER_INVALID_AMOUNT",
				{"amount": str(raw_amt)}
			)
		var amt: int = int(raw_amt)
		if amt <= 0 or amt > BalanceConfig.MAX_SAFE_MONEY_MINOR:
			return Result.fail(
				&"LEDGER_INVALID_AMOUNT",
				"ERR_LEDGER_INVALID_AMOUNT",
				{"amount_minor": amt}
			)

		if side == "debit":
			debit_total += amt
		else:
			credit_total += amt

		normalized_lines.append({
			"account": acct,
			"side": side,
			"amount_minor": amt,
		})

	if debit_total != credit_total:
		return Result.fail(
			&"LEDGER_UNBALANCED",
			"ERR_LEDGER_UNBALANCED",
			{"debit": debit_total, "credit": credit_total}
		)

	# Apply validated deltas atomically
	for line in normalized_lines:
		var acct: StringName = line["account"] as StringName
		var side: String = str(line["side"])
		var amt: int = int(line["amount_minor"])
		var current_bal: int = int(_balances.get(acct, 0))
		if is_debit_normal(acct):
			_balances[acct] = current_bal + amt if side == "debit" else current_bal - amt
		else:
			_balances[acct] = current_bal + amt if side == "credit" else current_bal - amt

	var entry := JournalEntry.new(_next_entry_id, day, minute, ref_id, description_key, normalized_lines)
	_next_entry_id += 1
	_entries.append(entry)
	while _entries.size() > BalanceConfig.MAX_JOURNAL_ENTRIES:
		_entries.pop_front()

	var summary: Dictionary = _daily_summaries.get(day, {
		"day": day,
		"entry_count": 0,
		"debit_volume": 0,
		"credit_volume": 0,
	})
	summary["entry_count"] = int(summary["entry_count"]) + 1
	summary["debit_volume"] = int(summary["debit_volume"]) + debit_total
	summary["credit_volume"] = int(summary["credit_volume"]) + credit_total
	_daily_summaries[day] = summary

	return Result.succeed(entry)


func get_balance(account: StringName) -> int:
	return int(_balances.get(account, 0))


func get_all_balances() -> Dictionary:
	return _balances.duplicate()


func get_balance_sheet_snapshot() -> Dictionary:
	var cash: int = get_balance(&"cash_reserves")
	var loans: int = get_balance(&"loan_principal_outstanding")
	var deposits: int = get_balance(&"customer_deposits")
	var equity_cap: int = get_balance(&"equity_capital")
	var retained: int = get_balance(&"retained_earnings")
	var loan_int: int = get_balance(&"loan_interest_income")
	var fee_inc: int = get_balance(&"fee_income")
	var dep_int: int = get_balance(&"deposit_interest_expense")
	var opex: int = get_balance(&"operating_expense")
	var credit_loss: int = get_balance(&"credit_loss_expense")
	var event_exp: int = get_balance(&"event_expense")

	var assets: int = cash + loans
	var liabilities: int = deposits
	var equity: int = equity_cap + retained
	var income: int = loan_int + fee_inc
	var expense: int = dep_int + opex + credit_loss + event_exp
	var net_income: int = income - expense
	var is_balanced: bool = (assets == liabilities + equity + net_income)

	var accounts_copy: Dictionary = {}
	for acct: StringName in ACCOUNT_TYPES.keys():
		accounts_copy[String(acct)] = get_balance(acct)

	return {
		"assets": assets,
		"liabilities": liabilities,
		"equity": equity,
		"income": income,
		"expense": expense,
		"net_income": net_income,
		"is_balanced": is_balanced,
		"accounts": accounts_copy,
	}


func get_entries(offset: int = 0, limit: int = 50) -> Array[JournalEntry]:
	var out: Array[JournalEntry] = []
	if offset < 0 or offset >= _entries.size() or limit <= 0:
		return out
	var end_idx: int = mini(_entries.size(), offset + limit)
	for i in range(offset, end_idx):
		out.append(_entries[i])
	return out


func get_entry_count() -> int:
	return _entries.size()


func get_daily_summary(day: int) -> Dictionary:
	if _daily_summaries.has(day):
		return (_daily_summaries[day] as Dictionary).duplicate(true)
	return {"day": day, "entry_count": 0, "debit_volume": 0, "credit_volume": 0}


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


func to_dict() -> Dictionary:
	var ser_balances: Dictionary = {}
	for acct: StringName in ACCOUNT_TYPES.keys():
		ser_balances[String(acct)] = str(int(_balances.get(acct, 0)))

	var ser_entries: Array[Dictionary] = []
	for e in _entries:
		ser_entries.append(e.to_dict())

	var ser_summaries: Dictionary = {}
	for k: Variant in _daily_summaries.keys():
		var sd: Dictionary = _daily_summaries[k] as Dictionary
		var copy_sd: Dictionary = sd.duplicate(true)
		copy_sd["debit_volume"] = str(int(sd.get("debit_volume", 0)))
		copy_sd["credit_volume"] = str(int(sd.get("credit_volume", 0)))
		if sd.has("net_income_delta"):
			copy_sd["net_income_delta"] = str(int(sd.get("net_income_delta", 0)))
		ser_summaries[str(k)] = copy_sd

	return {
		"balances": ser_balances,
		"entries": ser_entries,
		"daily_summaries": ser_summaries,
		"next_entry_id": _next_entry_id,
	}


static func from_dict(data: Dictionary) -> Result:
	if not data.has("balances") or not (data["balances"] is Dictionary):
		return Result.fail(&"INVALID_LEDGER_DATA", "ERR_INVALID_LEDGER_DATA", {"missing": "balances"})

	var ledger := Ledger.new()
	var raw_bal: Dictionary = data["balances"] as Dictionary
	for acct: StringName in ACCOUNT_TYPES.keys():
		var k: String = String(acct)
		ledger._balances[acct] = _parse_i64(raw_bal.get(k, 0), 0)

	ledger._next_entry_id = maxi(1, int(data.get("next_entry_id", 1)))

	var raw_entries: Variant = data.get("entries", [])
	if raw_entries is Array:
		for item in (raw_entries as Array):
			if item is Dictionary:
				var er: Result = JournalEntry.from_dict(item as Dictionary)
				if not er.ok:
					return er
				ledger._entries.append(er.data as JournalEntry)
		while ledger._entries.size() > BalanceConfig.MAX_JOURNAL_ENTRIES:
			ledger._entries.pop_front()

	var raw_sum: Variant = data.get("daily_summaries", {})
	if raw_sum is Dictionary:
		for dk: Variant in (raw_sum as Dictionary).keys():
			var d_int: int = int(str(dk).to_int())
			var sd: Variant = (raw_sum as Dictionary)[dk]
			if sd is Dictionary:
				var sdict: Dictionary = sd as Dictionary
				var restored_sum: Dictionary = {
					"day": _parse_i64(sdict.get("day", d_int), d_int),
					"entry_count": _parse_i64(sdict.get("entry_count", 0), 0),
					"debit_volume": _parse_i64(sdict.get("debit_volume", 0), 0),
					"credit_volume": _parse_i64(sdict.get("credit_volume", 0), 0),
				}
				if sdict.has("net_income_delta"):
					restored_sum["net_income_delta"] = _parse_i64(sdict.get("net_income_delta", 0), 0)
				ledger._daily_summaries[d_int] = restored_sum

	var snap: Dictionary = ledger.get_balance_sheet_snapshot()
	if not bool(snap.get("is_balanced", false)):
		return Result.fail(
			&"LEDGER_CORRUPTED_UNBALANCED",
			"ERR_LEDGER_CORRUPTED_UNBALANCED",
			snap
		)
	return Result.succeed(ledger)
