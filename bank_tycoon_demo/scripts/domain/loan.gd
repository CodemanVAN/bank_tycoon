class_name LoanInstance
extends RefCounted

## Pure domain entity tracking an originated bank loan.

var loan_id: String = ""
var customer_id: String = ""
var principal_original: int = 0
var principal_outstanding: int = 0
var annual_rate_bps: int = 650
var term_days: int = 30
var days_elapsed: int = 0
var credit_score: int = 70
var risk_grade: int = Enums.RiskGrade.B
var collateral_value: int = 0
var days_past_due: int = 0
var status: int = Enums.LoanStatus.ACTIVE
var originated_day: int = 1
var last_accrued_day: int = 0
var total_interest_paid_minor: int = 0
var total_principal_repaid_minor: int = 0
var written_off_minor: int = 0


func is_active() -> bool:
	return (
		status == Enums.LoanStatus.ACTIVE or status == Enums.LoanStatus.DELINQUENT
	) and principal_outstanding > 0


func is_npl() -> bool:
	return (
		status == Enums.LoanStatus.DELINQUENT
		or status == Enums.LoanStatus.DEFAULTED
		or days_past_due > 0
	) and principal_outstanding > 0


func get_risk_grade_code() -> String:
	return Enums.risk_grade_to_string(risk_grade)


func apply_repayment(amount_minor: int) -> Result:
	if amount_minor <= 0:
		return Result.fail(&"ERR_INVALID_REPAYMENT_AMOUNT", "ERR_INVALID_REPAYMENT_AMOUNT", {"amount_minor": amount_minor})
	if not is_active():
		return Result.fail(&"ERR_LOAN_NOT_ACTIVE", "ERR_LOAN_NOT_ACTIVE", {"loan_id": loan_id, "status": status})

	var applied: int = mini(amount_minor, principal_outstanding)
	principal_outstanding -= applied
	total_principal_repaid_minor += applied
	days_past_due = 0
	if principal_outstanding == 0:
		status = Enums.LoanStatus.REPAID
	else:
		status = Enums.LoanStatus.ACTIVE
	return Result.succeed({
		"loan_id": loan_id,
		"applied_minor": applied,
		"principal_outstanding": principal_outstanding,
		"status": status,
	})


func write_off(amount_minor: int = -1) -> Result:
	if status == Enums.LoanStatus.WRITTEN_OFF or status == Enums.LoanStatus.REPAID:
		return Result.fail(&"ERR_LOAN_ALREADY_CLOSED", "ERR_LOAN_ALREADY_CLOSED", {"loan_id": loan_id})
	if amount_minor >= 0 and amount_minor < principal_outstanding:
		principal_outstanding -= amount_minor
		written_off_minor += amount_minor
		status = Enums.LoanStatus.DEFAULTED
		return Result.succeed({
			"loan_id": loan_id,
			"written_off_minor": amount_minor,
			"principal_outstanding": principal_outstanding,
			"status": status,
		})
	var loss: int = principal_outstanding
	written_off_minor += loss
	principal_outstanding = 0
	status = Enums.LoanStatus.WRITTEN_OFF
	return Result.succeed({
		"loan_id": loan_id,
		"written_off_minor": loss,
		"principal_outstanding": 0,
		"status": status,
	})


func to_dict() -> Dictionary:
	return {
		"loan_id": loan_id,
		"customer_id": customer_id,
		"principal_original": principal_original,
		"principal_outstanding": principal_outstanding,
		"annual_rate_bps": annual_rate_bps,
		"term_days": term_days,
		"days_elapsed": days_elapsed,
		"credit_score": credit_score,
		"risk_grade": risk_grade,
		"collateral_value": collateral_value,
		"days_past_due": days_past_due,
		"status": status,
		"originated_day": originated_day,
		"last_accrued_day": last_accrued_day,
		"total_interest_paid_minor": total_interest_paid_minor,
		"total_principal_repaid_minor": total_principal_repaid_minor,
		"written_off_minor": written_off_minor,
	}


static func from_dict(data: Dictionary) -> Result:
	var loan := LoanInstance.new()
	loan.loan_id = str(data.get("loan_id", ""))
	if loan.loan_id.is_empty():
		return Result.fail(&"INVALID_LOAN_ID", "ERR_INVALID_LOAN_ID", {})
	loan.customer_id = str(data.get("customer_id", ""))
	loan.principal_original = maxi(0, int(data.get("principal_original", 0)))
	loan.principal_outstanding = maxi(0, int(data.get("principal_outstanding", 0)))
	loan.annual_rate_bps = maxi(0, int(data.get("annual_rate_bps", 650)))
	loan.term_days = maxi(1, int(data.get("term_days", 30)))
	loan.days_elapsed = maxi(0, int(data.get("days_elapsed", 0)))
	loan.credit_score = clampi(int(data.get("credit_score", 70)), 0, 100)
	loan.risk_grade = clampi(int(data.get("risk_grade", Enums.RiskGrade.B)), Enums.RiskGrade.A, Enums.RiskGrade.D)
	loan.collateral_value = maxi(0, int(data.get("collateral_value", 0)))
	loan.days_past_due = maxi(0, int(data.get("days_past_due", 0)))
	loan.status = clampi(
		int(data.get("status", Enums.LoanStatus.ACTIVE)),
		Enums.LoanStatus.PENDING_APPROVAL,
		Enums.LoanStatus.REJECTED
	)
	loan.originated_day = maxi(1, int(data.get("originated_day", 1)))
	loan.last_accrued_day = maxi(0, int(data.get("last_accrued_day", 0)))
	loan.total_interest_paid_minor = maxi(0, int(data.get("total_interest_paid_minor", 0)))
	loan.total_principal_repaid_minor = maxi(0, int(data.get("total_principal_repaid_minor", 0)))
	loan.written_off_minor = maxi(0, int(data.get("written_off_minor", 0)))
	return Result.succeed(loan)
