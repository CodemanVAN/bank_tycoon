class_name Enums
extends RefCounted

## Shared enumerations and canonical identifier mappings.

enum EmployeeState {
	AVAILABLE = 0,
	MOVING = 1,
	WORKING = 2,
	BREAK = 3,
	OVERLOADED = 4,
	OFF_DUTY = 5,
}

enum CustomerState {
	SPAWNING = 0,
	FINDING_SERVICE = 1,
	WAITING = 2,
	IN_SERVICE = 3,
	COMPLETED = 4,
	LEAVING = 5,
}

enum ServiceType {
	CASH_DEPOSIT = 0,
	CASH_WITHDRAWAL = 1,
	TRANSFER = 2,
	PERSONAL_LOAN_APPLICATION = 3,
	BUSINESS_MEETING = 4,
	COMPLAINT = 5,
}

enum AccountType {
	ASSET = 0,
	LIABILITY = 1,
	EQUITY = 2,
	INCOME = 3,
	EXPENSE = 4,
}

enum LoanStatus {
	PENDING_APPROVAL = 0,
	ACTIVE = 1,
	DELINQUENT = 2,
	DEFAULTED = 3,
	REPAID = 4,
	WRITTEN_OFF = 5,
	REJECTED = 6,
}

enum RiskGrade {
	A = 0,
	B = 1,
	C = 2,
	D = 3,
}

enum DayPhase {
	PRE_OPEN = 0,
	OPEN = 1,
	CLOSING = 2,
	SETTLED = 3,
}

enum LiquidityStatus {
	SAFE = 0,
	CAUTION = 1,
	DANGER = 2,
}

enum EventSeverity {
	INFO = 0,
	WARNING = 1,
	CRITICAL = 2,
}

enum EmployeeRole {
	TELLER = 0,
	LOAN_OFFICER = 1,
	MANAGER = 2,
	ANALYST = 3,
}

enum QueuePriority {
	NORMAL = 0,
	PRIORITY = 1,
	VIP = 2,
}

enum RequestStatus {
	QUEUED = 0,
	ASSIGNED = 1,
	IN_PROGRESS = 2,
	COMPLETED = 3,
	CANCELLED = 4,
	TIMED_OUT = 5,
	PENDING_APPROVAL = 6,
}


static func service_type_to_id(st: int) -> StringName:
	match st:
		ServiceType.CASH_DEPOSIT:
			return &"cash_deposit"
		ServiceType.CASH_WITHDRAWAL:
			return &"cash_withdrawal"
		ServiceType.TRANSFER:
			return &"transfer"
		ServiceType.PERSONAL_LOAN_APPLICATION:
			return &"personal_loan_application"
		ServiceType.BUSINESS_MEETING:
			return &"business_meeting"
		ServiceType.COMPLAINT:
			return &"complaint"
		_:
			return &"cash_deposit"


static func id_to_service_type(type_id: StringName) -> int:
	match String(type_id):
		"cash_deposit":
			return ServiceType.CASH_DEPOSIT
		"cash_withdrawal":
			return ServiceType.CASH_WITHDRAWAL
		"transfer":
			return ServiceType.TRANSFER
		"personal_loan_application":
			return ServiceType.PERSONAL_LOAN_APPLICATION
		"business_meeting":
			return ServiceType.BUSINESS_MEETING
		"complaint":
			return ServiceType.COMPLAINT
		_:
			return ServiceType.CASH_DEPOSIT


static func risk_grade_to_string(grade: int) -> String:
	match grade:
		RiskGrade.A:
			return "A"
		RiskGrade.B:
			return "B"
		RiskGrade.C:
			return "C"
		RiskGrade.D:
			return "D"
		_:
			return "C"


static func string_to_risk_grade(code: String) -> int:
	match code.to_upper():
		"A":
			return RiskGrade.A
		"B":
			return RiskGrade.B
		"C":
			return RiskGrade.C
		"D":
			return RiskGrade.D
		_:
			return RiskGrade.C


static func employee_role_to_id(role: int) -> String:
	match role:
		EmployeeRole.TELLER:
			return "teller"
		EmployeeRole.LOAN_OFFICER:
			return "loan_officer"
		EmployeeRole.MANAGER:
			return "manager"
		EmployeeRole.ANALYST:
			return "analyst"
		_:
			return "teller"


static func id_to_employee_role(role_id: String) -> int:
	match role_id.to_lower():
		"teller":
			return EmployeeRole.TELLER
		"loan_officer":
			return EmployeeRole.LOAN_OFFICER
		"manager":
			return EmployeeRole.MANAGER
		"analyst":
			return EmployeeRole.ANALYST
		_:
			return EmployeeRole.TELLER
