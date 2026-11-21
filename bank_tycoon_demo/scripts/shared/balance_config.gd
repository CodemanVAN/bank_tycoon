class_name BalanceConfig
extends RefCounted

## Centralized economic, simulation, and modifier bounds configuration.

# Initial branch parameters
const INITIAL_EQUITY_CAPITAL_MINOR: int = 20_000_000
const DEFAULT_DEPOSIT_RATE_BPS: int = 200
const DEFAULT_LOAN_BASE_RATE_BPS: int = 650
const INITIAL_REPUTATION: int = 50
const INITIAL_SATISFACTION: int = 75
const INITIAL_STRATEGY_POINTS: int = 10

# Monetary and interest rate constants
const BPS_DENOMINATOR: int = 10_000
const DAYS_PER_YEAR: int = 365
const MIN_DEPOSIT_RATE_BPS: int = 0
const MAX_DEPOSIT_RATE_BPS: int = 1_000
const MIN_LOAN_RATE_BPS: int = 100
const MAX_LOAN_RATE_BPS: int = 2_000
const MAX_SAFE_MONEY_MINOR: int = 1_000_000_000_000_000

# Clock and business hours
const BUSINESS_OPEN_MINUTE: int = 540
const BUSINESS_CLOSE_MINUTE: int = 1_020
const BUSINESS_DURATION_MINUTES: int = 480
const MINUTES_PER_DAY: int = 1_440
const MAX_TICKS_PER_FRAME: int = 5
const VALID_SPEED_MULTIPLIERS: Array[int] = [0, 1, 2, 3]

# Liquidity, NPL, and credit scoring
const LIQUIDITY_SAFE_BPS: int = 15_000
const LIQUIDITY_CAUTION_BPS: int = 10_000
const NEAR_TERM_WITHDRAWAL_RATIO_BPS: int = 4_000
const MIN_NEAR_TERM_WITHDRAWAL_FLOOR_MINOR: int = 100_000
const NPL_WARNING_BPS: int = 500
const NPL_CRITICAL_BPS: int = 1_200
const LOAN_AUTO_APPROVAL_LIMIT_MINOR: int = 500_000
const CREDIT_BASE_SCORE: int = 55
const CREDIT_GRADE_A_MIN: int = 80
const CREDIT_GRADE_B_MIN: int = 65
const CREDIT_GRADE_C_MIN: int = 50

const PD_BPS_BY_GRADE: Dictionary = {
	"A": 100,
	"B": 300,
	"C": 700,
	"D": 1_500,
}

const LGD_BPS_BY_GRADE: Dictionary = {
	"A": 2_500,
	"B": 4_000,
	"C": 5_500,
	"D": 7_500,
}

# Operations, HR, and Ledger limits
const MAX_JOURNAL_ENTRIES: int = 500
const DEFAULT_DAILY_FACILITY_RENT_MINOR: int = 20_000
const DEFAULT_RECRUIT_COST_MINOR: int = 50_000
const DEFAULT_TRAINING_COST_MINOR: int = 30_000
const DEFAULT_ADAPTATION_DAYS: int = 3
const SYNERGY_ADAPTATION_DAYS: int = 1
const OVERLOAD_FATIGUE_THRESHOLD: int = 80
const OVERNIGHT_FATIGUE_RECOVERY: int = 25
const REST_FATIGUE_RECOVERY_PER_MIN: int = 2

const BASE_SERVICE_MINUTES: Dictionary = {
	"cash_deposit": 6,
	"cash_withdrawal": 7,
	"transfer": 8,
	"personal_loan_application": 14,
	"business_meeting": 18,
	"complaint": 12,
}

const BASE_SERVICE_FEE_MINOR: Dictionary = {
	"cash_deposit": 0,
	"cash_withdrawal": 0,
	"transfer": 1_500,
	"personal_loan_application": 5_000,
	"business_meeting": 8_000,
	"complaint": 0,
}

const SERVICE_REQUIRED_SKILL: Dictionary = {
	"cash_deposit": "teller",
	"cash_withdrawal": "teller",
	"transfer": "teller",
	"personal_loan_application": "loan_officer",
	"business_meeting": "manager",
	"complaint": "teller",
}

# Whitelisted modifier target bounds
const MODIFIER_BOUNDS: Dictionary = {
	"staff.productivity_bps": {"min": 2_500, "max": 30_000},
	"service.teller_duration_bps": {"min": 2_500, "max": 30_000},
	"customer.deposit_growth_bps": {"min": 0, "max": 30_000},
	"bank.reputation_points": {"min": 0, "max": 100},
	"loan.default_risk_bps": {"min": 0, "max": 10_000},
	"liquidity.required_buffer_bps": {"min": 0, "max": 30_000},
}

const VALID_MODIFIER_OPERATIONS: Array[String] = [
	"add",
	"multiply",
	"set",
	"unlock",
	"modify_chance",
]

const VALID_EVENT_CONDITIONS: Array[String] = [
	"day_at_least",
	"department_exists",
	"policy_adopted",
	"metric_above",
	"cooldown_elapsed",
]

# Structured event chain delays (days)
const EVENT_CHAIN_DELAY_DAYS: Dictionary = {
	"core:event.real_estate_cooling": 2,
	"core:event.real_estate_credit_stress": 3,
}

# Event option domain impacts outside schema effect targets
const EVENT_DOMAIN_IMPACTS: Dictionary = {
	"core:event.real_estate_boom:aggressive_expand": {
		"duration_days": 5,
		"satisfaction_delta": 2,
		"strategy_points_delta": 2,
		"macro_risk_choice": "aggressive",
	},
	"core:event.real_estate_boom:prudent_cap": {
		"duration_days": 5,
		"satisfaction_delta": 1,
		"strategy_points_delta": 1,
		"macro_risk_choice": "prudent",
	},
	"core:event.real_estate_cooling:tighten_credit": {
		"duration_days": 4,
		"strategy_points_delta": 1,
	},
	"core:event.real_estate_cooling:hold_course": {
		"duration_days": 4,
	},
	"core:event.real_estate_credit_stress:emergency_provision": {
		"duration_days": 4,
		"macro_stress_provision_minor": 150_000,
		"satisfaction_delta": -2,
	},
	"core:event.real_estate_credit_stress:restructure_books": {
		"duration_days": 4,
		"cash_delta_minor": -100_000,
		"macro_stress_provision_minor": 80_000,
	},
}

const POLICY_METRIC_REQUIREMENTS: Dictionary = {}


static func calc_department_upgrade_cost(initial_cost_minor: int, current_level: int) -> int:
	if initial_cost_minor <= 0:
		return 0
	return (initial_cost_minor * (current_level + 1) + 1) / 2
