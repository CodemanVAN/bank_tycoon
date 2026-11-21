class_name UiI18n
extends RefCounted

## UI Localization, Asset, and Content Fallback Helper.
## Always delegates to LocalizationService.tr_key(key, params) first, and provides a 3-locale
## fallback cache (from res://localization/*.json + built-in core/hud/panels table) so that
## even before LocalizationService finishes scanning or for dynamic keys, no Label or Button
## ever displays a raw "UI_*" or "DEPT_*" key.

static var _disk_cache_loaded: bool = false
static var _disk_tables: Dictionary = {
	"zh_CN": {},
	"en": {},
	"ja": {},
}

const BUILTIN_FALLBACKS: Dictionary = {
	"zh_CN": {
		"UI_MAIN_MENU_TITLE": "星海银行",
		"UI_MAIN_MENU_SUBTITLE": "现代科技蓝 · 像素分行实时经营模拟",
		"UI_MAIN_MENU_NEW_GAME": "新游戏",
		"UI_MAIN_MENU_CONTINUE": "继续游戏",
		"UI_MAIN_MENU_LOAD_SAVE": "读取存档",
		"UI_MAIN_MENU_SETTINGS": "游戏设置",
		"UI_MAIN_MENU_QUIT": "退出游戏",
		"UI_MAIN_MENU_VERSION": "星海银行核心系统 v0.1.0 · Godot 4.7.2",
		"UI_TOPBAR_BANK_NAME": "星海银行",
		"UI_TOPBAR_CASH": "现金准备",
		"UI_TOPBAR_TODAY_PROFIT": "预计日净利",
		"UI_TOPBAR_SATISFACTION": "满意度",
		"UI_TOPBAR_REPUTATION": "声誉",
		"UI_TOPBAR_EMPLOYEES": "在职员工",
		"UI_TOPBAR_DAY": "第 {day} 天",
		"UI_TOPBAR_TIME": "时间 {time}",
		"UI_TOPBAR_SPEED_PAUSE": "暂停 0x",
		"UI_TOPBAR_SPEED_1X": "1x",
		"UI_TOPBAR_SPEED_2X": "2x",
		"UI_TOPBAR_SPEED_3X": "3x",
		"UI_TOPBAR_ACTION_OPEN_BRANCH": "开始今日营业",
		"UI_TOPBAR_ACTION_IN_BUSINESS": "营业进行中",
		"UI_TOPBAR_ACTION_CLOSING": "日终收尾中",
		"UI_TOPBAR_ACTION_NEXT_DAY": "日终结算 / 下一天",
		"UI_TOPBAR_BTN_SAVE_SETTINGS": "存档 / 设置",
		"UI_PHASE_PRE_OPEN": "开门前准备",
		"UI_PHASE_OPEN": "营业中",
		"UI_PHASE_CLOSING": "收尾结算中",
		"UI_PHASE_SETTLED": "今日已结算",
		"PHASE_PRE_OPEN": "开门前准备",
		"PHASE_OPEN": "营业中",
		"PHASE_CLOSING": "收尾结算中",
		"PHASE_SETTLED": "今日已结算",
		"LIQUIDITY_SAFE": "流动性安全",
		"LIQUIDITY_CAUTION": "流动性关注",
		"LIQUIDITY_DANGER": "流动性危险",
		"ROLE_TELLER": "柜员",
		"ROLE_LOAN_OFFICER": "信贷专员",
		"ROLE_MANAGER": "分行经理",
		"ROLE_ANALYST": "风险分析师",
		"EMP_STATE_AVAILABLE": "待命",
		"EMP_STATE_MOVING": "移动中",
		"EMP_STATE_WORKING": "办理业务中",
		"EMP_STATE_BREAK": "休息恢复中",
		"EMP_STATE_OVERLOADED": "超负荷疲劳",
		"EMP_STATE_OFF_DUTY": "下班休整",
		"EMP_NAME_STARTER_1": "林星瑶",
		"EMP_NAME_STARTER_2": "周辰海",
		"CAND_NAME_1": "陈沐阳",
		"CAND_NAME_2": "苏晴雪",
		"CAND_NAME_3": "顾景行",
		"SERVICE_CASH_DEPOSIT": "现金存款",
		"SERVICE_CASH_WITHDRAWAL": "现金取款",
		"SERVICE_TRANSFER": "跨行转账",
		"SERVICE_PERSONAL_LOAN_APPLICATION": "个人贷款申请",
		"SERVICE_BUSINESS_MEETING": "企业信贷洽谈",
		"SERVICE_COMPLAINT": "客户投诉处理",
		"CUSTOMER_REGULAR_NAME": "普通储户",
		"CUSTOMER_SALARIED_NAME": "工薪族客户",
		"CUSTOMER_BORROWER_NAME": "个人借贷客户",
		"CUSTOMER_SMB_NAME": "中小企业主",
		"CUSTOMER_VIP_NAME": "高净值贵宾",
		"CUSTOMER_SUSPICIOUS_NAME": "高风险可疑客户",
		"CUST_TYPE_REGULAR": "普通储户",
		"CUST_TYPE_SALARIED": "工薪族客户",
		"CUST_TYPE_BORROWER": "个人借贷客户",
		"CUST_TYPE_SMB": "中小企业主",
		"CUST_TYPE_VIP": "高净值贵宾",
		"CUST_TYPE_SUSPICIOUS": "高风险可疑客户",
		"DEPT_OPERATIONS_NAME": "运营管理部",
		"DEPT_OPERATIONS_DESC": "优化大厅柜台动线与业务处理流程，降低客户排队等待时长。",
		"DEPT_OPERATIONS_LV1": "Lv.1：全行柜台基础服务时长缩短 8%",
		"DEPT_OPERATIONS_LV2": "Lv.2：解锁 VIP 与高优客户队列自动优先调度",
		"DEPT_OPERATIONS_LV3": "Lv.3：解锁客户投诉自动安抚与高效分流机制",
		"DEPT_HR_NAME": "人力资源部",
		"DEPT_HR_DESC": "拓展高端金融人才招聘渠道，提供系统化员工培训与疲劳关怀。",
		"DEPT_HR_LV1": "Lv.1：解锁扩展候选人人才池与岗位匹配度展示",
		"DEPT_HR_LV2": "Lv.2：解锁员工专项技能培训与属性成长提升",
		"DEPT_HR_LV3": "Lv.3：夜间疲劳恢复效率 +10，解锁人才自动补充",
		"DEPT_CREDIT_NAME": "信贷业务部",
		"DEPT_CREDIT_DESC": "统筹个人与中小企业信贷投放，提升生息资产规模与审批效率。",
		"DEPT_CREDIT_LV1": "Lv.1：解锁信贷专柜高效放款与基础额度审批",
		"DEPT_CREDIT_LV2": "Lv.2：解锁低风险优质小额贷款自动审批放款",
		"DEPT_CREDIT_LV3": "Lv.3：解锁差异化贷款利率定价与大额信贷授信",
		"DEPT_RISK_NAME": "风险管理部",
		"DEPT_RISK_DESC": "建立精准信用评分模型与贷后催收体系，严控不良率与违约损失。",
		"DEPT_RISK_LV1": "Lv.1：贷款审批台显示申请人精确信用分与违约概率",
		"DEPT_RISK_LV2": "Lv.2：高风险贷款预警拦截，全行违约概率降低",
		"DEPT_RISK_LV3": "Lv.3：宏观压力缓冲与坏账核销损失率 (LGD) 降低 25%",
		"POLICY_PRUDENT_LENDING_NAME": "审慎放贷准则",
		"POLICY_PRUDENT_LENDING_DESC": "严格审核借款人偿债能力，贷款违约风险降低，声誉小幅提升。",
		"POLICY_LIQUIDITY_FIRST_NAME": "流动性优先战略",
		"POLICY_LIQUIDITY_FIRST_DESC": "强化现金准备金安全垫，提升储户信心与抗挤兑能力。",
		"POLICY_CUSTOMER_TRUST_NAME": "百年储户信任",
		"POLICY_CUSTOMER_TRUST_DESC": "树立稳健可靠品牌形象，自然存款流入与客户满意度持续增长。",
		"POLICY_HIGH_RATE_ACQUISITION_NAME": "高息揽储攻势",
		"POLICY_HIGH_RATE_ACQUISITION_DESC": "以激进利率快速吸收市场存款，扩大可放贷资金池。",
		"POLICY_MARKET_PENETRATION_NAME": "区域市场渗透",
		"POLICY_MARKET_PENETRATION_DESC": "大力拓展个人与企业客群，大厅客流与业务量显著攀升。",
		"POLICY_CREDIT_EXPANSION_NAME": "全面信贷扩张",
		"POLICY_CREDIT_EXPANSION_DESC": "放宽信贷投放门槛以追求高额利差收益，但潜在违约风险上升。",
		"EVENT_REAL_ESTATE_BOOM_TITLE": "区域房地产市场过热繁荣",
		"EVENT_REAL_ESTATE_BOOM_DESC": "周边商业地产价格连创历史新高，大量开发商与按揭客户涌入分行申请大额信贷。",
		"EVENT_OPT_AGGRESSIVE_EXPAND": "顺势激进扩表放贷（策略点+2，满意度+2，埋下后续周期风险）",
		"EVENT_OPT_PRUDENT_CAP": "维持审慎授信上限（策略点+1，满意度+1，控制敞口）",
		"EVENT_REAL_ESTATE_COOLING_TITLE": "地产市场降温与流动性收紧",
		"EVENT_REAL_ESTATE_COOLING_DESC": "宏观调控政策出台，地产成交量迅速萎缩，部分杠杆借款人出现现金流紧张。",
		"EVENT_OPT_TIGHTEN_CREDIT": "立即收紧信贷并追加抵押要求（策略点+1，降低违约冲击）",
		"EVENT_OPT_HOLD_COURSE": "维持现有信贷规模不变（不干预当前业务，但面临后续信用压力）",
		"EVENT_REAL_ESTATE_CREDIT_STRESS_TITLE": "地产信贷违约潮压力测试",
		"EVENT_REAL_ESTATE_CREDIT_STRESS_DESC": "前期高杠杆贷款进入集中兑付期，部分企业客户面临资金链断裂风险。",
		"EVENT_OPT_EMERGENCY_PROVISION": "计提专项风险拨备金（满意度-2，稳住账面信用风险）",
		"EVENT_OPT_RESTRUCTURE_BOOKS": "投入资金开展债务重组（支出¥1,000，缓解违约损失）",
		"ERR_INSUFFICIENT_CASH": "现金准备金不足，无法执行该操作",
		"ERR_INSUFFICIENT_STRATEGY_POINTS": "可用策略点不足",
		"ERR_POLICY_PREREQUISITE_MISSING": "尚未采用前置政策，无法解锁该节点",
		"ERR_POLICY_BRANCH_CONFLICT": "与已采用的互斥战略路线冲突",
		"ERR_POLICY_EXCLUSIVE_CONFLICT": "与同组互斥政策冲突",
		"ERR_POLICY_ALREADY_ADOPTED": "该政策已经采用",
		"ERR_DEPT_ALREADY_EXISTS": "该部门已经成立",
		"ERR_DEPT_MAX_LEVEL": "该部门已达到最高等级",
		"ERR_DEPT_LOCKED": "尚未满足该部门的解锁条件",
		"ERR_EMPLOYEE_ON_BREAK": "员工正在休息中，暂无法指派任务",
		"ERR_EMPLOYEE_BUSY": "员工当前正在办理业务中",
	},
	"en": {
		"UI_MAIN_MENU_TITLE": "Starway Bank",
		"UI_MAIN_MENU_SUBTITLE": "Modern Tech-Blue · Pixel Branch Simulation",
		"UI_MAIN_MENU_NEW_GAME": "New Game",
		"UI_MAIN_MENU_CONTINUE": "Continue",
		"UI_MAIN_MENU_LOAD_SAVE": "Load Save",
		"UI_MAIN_MENU_SETTINGS": "Settings",
		"UI_MAIN_MENU_QUIT": "Quit",
		"UI_MAIN_MENU_VERSION": "Starway Core Banking OS v0.1.0 · Godot 4.7.2",
		"UI_TOPBAR_BANK_NAME": "Starway Bank",
		"UI_TOPBAR_CASH": "Cash Reserves",
		"UI_TOPBAR_TODAY_PROFIT": "Est. Daily Net",
		"UI_TOPBAR_SATISFACTION": "Satisfaction",
		"UI_TOPBAR_REPUTATION": "Reputation",
		"UI_TOPBAR_EMPLOYEES": "Staff",
		"UI_TOPBAR_DAY": "Day {day}",
		"UI_TOPBAR_TIME": "Time {time}",
		"UI_TOPBAR_SPEED_PAUSE": "Pause 0x",
		"UI_TOPBAR_SPEED_1X": "1x",
		"UI_TOPBAR_SPEED_2X": "2x",
		"UI_TOPBAR_SPEED_3X": "3x",
		"UI_TOPBAR_ACTION_OPEN_BRANCH": "Open Branch",
		"UI_TOPBAR_ACTION_IN_BUSINESS": "Branch Open",
		"UI_TOPBAR_ACTION_CLOSING": "Closing Queue",
		"UI_TOPBAR_ACTION_NEXT_DAY": "Settle / Next Day",
		"UI_TOPBAR_BTN_SAVE_SETTINGS": "Save / Settings",
		"UI_PHASE_PRE_OPEN": "Pre-Open Prep",
		"UI_PHASE_OPEN": "Open for Business",
		"UI_PHASE_CLOSING": "Closing & Settlement",
		"UI_PHASE_SETTLED": "Day Settled",
		"PHASE_PRE_OPEN": "Pre-Open Prep",
		"PHASE_OPEN": "Open for Business",
		"PHASE_CLOSING": "Closing & Settlement",
		"PHASE_SETTLED": "Day Settled",
		"LIQUIDITY_SAFE": "Liquidity Safe",
		"LIQUIDITY_CAUTION": "Liquidity Caution",
		"LIQUIDITY_DANGER": "Liquidity Danger",
		"ROLE_TELLER": "Teller",
		"ROLE_LOAN_OFFICER": "Loan Officer",
		"ROLE_MANAGER": "Branch Manager",
		"ROLE_ANALYST": "Risk Analyst",
		"EMP_STATE_AVAILABLE": "Available",
		"EMP_STATE_MOVING": "Moving",
		"EMP_STATE_WORKING": "In Service",
		"EMP_STATE_BREAK": "On Break",
		"EMP_STATE_OVERLOADED": "Overloaded",
		"EMP_STATE_OFF_DUTY": "Off Duty",
		"EMP_NAME_STARTER_1": "Elena Lin",
		"EMP_NAME_STARTER_2": "Marcus Zhou",
		"CAND_NAME_1": "Liam Chen",
		"CAND_NAME_2": "Claire Su",
		"CAND_NAME_3": "Arthur Gu",
		"SERVICE_CASH_DEPOSIT": "Cash Deposit",
		"SERVICE_CASH_WITHDRAWAL": "Cash Withdrawal",
		"SERVICE_TRANSFER": "Wire Transfer",
		"SERVICE_PERSONAL_LOAN_APPLICATION": "Personal Loan Application",
		"SERVICE_BUSINESS_MEETING": "Commercial Credit Meeting",
		"SERVICE_COMPLAINT": "Customer Complaint Resolution",
		"CUSTOMER_REGULAR_NAME": "Regular Depositor",
		"CUSTOMER_SALARIED_NAME": "Salaried Client",
		"CUSTOMER_BORROWER_NAME": "Personal Borrower",
		"CUSTOMER_SMB_NAME": "SMB Owner",
		"CUSTOMER_VIP_NAME": "VIP Client",
		"CUSTOMER_SUSPICIOUS_NAME": "High-Risk Client",
		"CUST_TYPE_REGULAR": "Regular Depositor",
		"CUST_TYPE_SALARIED": "Salaried Client",
		"CUST_TYPE_BORROWER": "Personal Borrower",
		"CUST_TYPE_SMB": "SMB Owner",
		"CUST_TYPE_VIP": "VIP Client",
		"CUST_TYPE_SUSPICIOUS": "High-Risk Client",
		"DEPT_OPERATIONS_NAME": "Operations Department",
		"DEPT_OPERATIONS_DESC": "Streamlines lobby counter workflows and reduces customer service turnaround times.",
		"DEPT_OPERATIONS_LV1": "Lv.1: Base counter service duration reduced by 8%",
		"DEPT_OPERATIONS_LV2": "Lv.2: Unlocks automatic VIP and priority queue routing",
		"DEPT_OPERATIONS_LV3": "Lv.3: Unlocks automated complaint de-escalation",
		"DEPT_HR_NAME": "Human Resources Dept",
		"DEPT_HR_DESC": "Expands talent recruitment channels, professional staff training, and fatigue care.",
		"DEPT_HR_LV1": "Lv.1: Unlocks extended candidate pool and role fit insights",
		"DEPT_HR_LV2": "Lv.2: Unlocks specialized staff skill training programs",
		"DEPT_HR_LV3": "Lv.3: Overnight fatigue recovery +10 and auto-staffing support",
		"DEPT_CREDIT_NAME": "Credit Department",
		"DEPT_CREDIT_DESC": "Manages retail and SMB loan origination to grow interest-earning assets.",
		"DEPT_CREDIT_LV1": "Lv.1: Unlocks dedicated loan desk origination workflow",
		"DEPT_CREDIT_LV2": "Lv.2: Unlocks automatic approval for low-risk Grade A/B loans",
		"DEPT_CREDIT_LV3": "Lv.3: Unlocks advanced loan pricing and higher credit limits",
		"DEPT_RISK_NAME": "Risk Management Dept",
		"DEPT_RISK_DESC": "Deploys quantitative credit scoring models and loss-mitigation safeguards.",
		"DEPT_RISK_LV1": "Lv.1: Reveals exact applicant credit score and PD% in underwriting",
		"DEPT_RISK_LV2": "Lv.2: Early warning on high-risk loans and lower default rates",
		"DEPT_RISK_LV3": "Lv.3: Macro stress buffer and 25% reduction in loss given default (LGD)",
		"POLICY_PRUDENT_LENDING_NAME": "Prudent Lending Standards",
		"POLICY_PRUDENT_LENDING_DESC": "Strict underwriting discipline lowers loan default risk and improves reputation.",
		"POLICY_LIQUIDITY_FIRST_NAME": "Liquidity First Doctrine",
		"POLICY_LIQUIDITY_FIRST_DESC": "Maintains strong cash reserve buffers against withdrawal shocks.",
		"POLICY_CUSTOMER_TRUST_NAME": "Depositor Trust Charter",
		"POLICY_CUSTOMER_TRUST_DESC": "Long-term institutional trust drives steady organic deposit growth.",
		"POLICY_HIGH_RATE_ACQUISITION_NAME": "High-Yield Deposit Drive",
		"POLICY_HIGH_RATE_ACQUISITION_DESC": "Aggressively attracts market deposits to rapidly expand lendable funds.",
		"POLICY_MARKET_PENETRATION_NAME": "Regional Market Penetration",
		"POLICY_MARKET_PENETRATION_DESC": "Expands retail and SMB outreach, boosting daily customer arrivals.",
		"POLICY_CREDIT_EXPANSION_NAME": "Aggressive Credit Expansion",
		"POLICY_CREDIT_EXPANSION_DESC": "Maximizes loan book growth and net interest income with higher risk exposure.",
		"EVENT_REAL_ESTATE_BOOM_TITLE": "Regional Real Estate Boom",
		"EVENT_REAL_ESTATE_BOOM_DESC": "Property valuations are surging, bringing a wave of high-value mortgage and developer loan requests.",
		"EVENT_OPT_AGGRESSIVE_EXPAND": "Aggressively expand real estate lending (+2 SP, +2 Sat, higher cycle risk)",
		"EVENT_OPT_PRUDENT_CAP": "Enforce prudent exposure caps (+1 SP, +1 Sat, controlled risk)",
		"EVENT_REAL_ESTATE_COOLING_TITLE": "Real Estate Market Cooling",
		"EVENT_REAL_ESTATE_COOLING_DESC": "Property transactions are slowing down and leveraged borrowers face tighter cash flows.",
		"EVENT_OPT_TIGHTEN_CREDIT": "Tighten credit standards and collateral rules (+1 SP, lower default impact)",
		"EVENT_OPT_HOLD_COURSE": "Hold current lending course (No immediate disruption, higher stress ahead)",
		"EVENT_REAL_ESTATE_CREDIT_STRESS_TITLE": "Property Credit Stress Wave",
		"EVENT_REAL_ESTATE_CREDIT_STRESS_DESC": "High-leverage property loans enter repayment stress as regional liquidity tightens.",
		"EVENT_OPT_EMERGENCY_PROVISION": "Book emergency risk provision (-2 Sat, stabilizes credit book)",
		"EVENT_OPT_RESTRUCTURE_BOOKS": "Fund proactive debt restructuring (-¥1,000 cash, mitigates defaults)",
		"ERR_INSUFFICIENT_CASH": "Insufficient cash reserves to complete this action",
		"ERR_INSUFFICIENT_STRATEGY_POINTS": "Insufficient Strategy Points available",
		"ERR_POLICY_PREREQUISITE_MISSING": "Required prerequisite policy has not been adopted yet",
		"ERR_POLICY_BRANCH_CONFLICT": "Conflicts with an already adopted mutually exclusive doctrine branch",
		"ERR_POLICY_EXCLUSIVE_CONFLICT": "Conflicts with a mutually exclusive policy in the same group",
		"ERR_POLICY_ALREADY_ADOPTED": "This policy has already been adopted",
		"ERR_DEPT_ALREADY_EXISTS": "This department is already established",
		"ERR_DEPT_MAX_LEVEL": "This department has already reached its maximum level",
		"ERR_DEPT_LOCKED": "Department unlock conditions are not met yet",
		"ERR_EMPLOYEE_ON_BREAK": "Staff member is currently on break",
		"ERR_EMPLOYEE_BUSY": "Staff member is currently busy serving a customer",
	},
	"ja": {
		"UI_MAIN_MENU_TITLE": "スターウェイ銀行",
		"UI_MAIN_MENU_SUBTITLE": "モダンテックブルー · ピクセル銀行経営シミュレーション",
		"UI_MAIN_MENU_NEW_GAME": "新規ゲーム",
		"UI_MAIN_MENU_CONTINUE": "コンティニュー",
		"UI_MAIN_MENU_LOAD_SAVE": "セーブ読込",
		"UI_MAIN_MENU_SETTINGS": "設定",
		"UI_MAIN_MENU_QUIT": "終了",
		"UI_MAIN_MENU_VERSION": "スターウェイ基幹システム v0.1.0 · Godot 4.7.2",
		"UI_TOPBAR_BANK_NAME": "スターウェイ銀行",
		"UI_TOPBAR_CASH": "現金準備",
		"UI_TOPBAR_TODAY_PROFIT": "予想日次純益",
		"UI_TOPBAR_SATISFACTION": "顧客満足度",
		"UI_TOPBAR_REPUTATION": "信用評価",
		"UI_TOPBAR_EMPLOYEES": "行員数",
		"UI_TOPBAR_DAY": "{day}日目",
		"UI_TOPBAR_TIME": "時刻 {time}",
		"UI_TOPBAR_SPEED_PAUSE": "一時停止 0x",
		"UI_TOPBAR_SPEED_1X": "1x",
		"UI_TOPBAR_SPEED_2X": "2x",
		"UI_TOPBAR_SPEED_3X": "3x",
		"UI_TOPBAR_ACTION_OPEN_BRANCH": "本日の営業開始",
		"UI_TOPBAR_ACTION_IN_BUSINESS": "営業中",
		"UI_TOPBAR_ACTION_CLOSING": "締め処理中",
		"UI_TOPBAR_ACTION_NEXT_DAY": "日次決算 / 翌日へ",
		"UI_TOPBAR_BTN_SAVE_SETTINGS": "セーブ / 設定",
		"UI_PHASE_PRE_OPEN": "開店準備中",
		"UI_PHASE_OPEN": "営業中",
		"UI_PHASE_CLOSING": "閉店・締め処理中",
		"UI_PHASE_SETTLED": "本日決算完了",
		"PHASE_PRE_OPEN": "開店準備中",
		"PHASE_OPEN": "営業中",
		"PHASE_CLOSING": "閉店・締め処理中",
		"PHASE_SETTLED": "本日決算完了",
		"LIQUIDITY_SAFE": "流動性安全",
		"LIQUIDITY_CAUTION": "流動性注意",
		"LIQUIDITY_DANGER": "流動性危険",
		"ROLE_TELLER": "窓口係",
		"ROLE_LOAN_OFFICER": "融資担当",
		"ROLE_MANAGER": "支店長",
		"ROLE_ANALYST": "リスク分析官",
		"EMP_STATE_AVAILABLE": "待機中",
		"EMP_STATE_MOVING": "移動中",
		"EMP_STATE_WORKING": "接客業務中",
		"EMP_STATE_BREAK": "休憩中",
		"EMP_STATE_OVERLOADED": "過労状態",
		"EMP_STATE_OFF_DUTY": "退勤・休養",
		"EMP_NAME_STARTER_1": "リン・セイヨウ",
		"EMP_NAME_STARTER_2": "シュウ・シンカイ",
		"CAND_NAME_1": "チェン・ボクヨウ",
		"CAND_NAME_2": "スー・セイセツ",
		"CAND_NAME_3": "グー・ケイコウ",
		"SERVICE_CASH_DEPOSIT": "現金預入",
		"SERVICE_CASH_WITHDRAWAL": "現金引出",
		"SERVICE_TRANSFER": "振込・送金",
		"SERVICE_PERSONAL_LOAN_APPLICATION": "個人ローン申請",
		"SERVICE_BUSINESS_MEETING": "法人融資相談",
		"SERVICE_COMPLAINT": "苦情対応",
		"CUSTOMER_REGULAR_NAME": "一般預金者",
		"CUSTOMER_SALARIED_NAME": "給与所得者",
		"CUSTOMER_BORROWER_NAME": "個人借入顧客",
		"CUSTOMER_SMB_NAME": "中小企業経営者",
		"CUSTOMER_VIP_NAME": "VIP富裕層顧客",
		"CUSTOMER_SUSPICIOUS_NAME": "高リスク要注意顧客",
		"CUST_TYPE_REGULAR": "一般預金者",
		"CUST_TYPE_SALARIED": "給与所得者",
		"CUST_TYPE_BORROWER": "個人借入顧客",
		"CUST_TYPE_SMB": "中小企業経営者",
		"CUST_TYPE_VIP": "VIP富裕層顧客",
		"CUST_TYPE_SUSPICIOUS": "高リスク要注意顧客",
		"DEPT_OPERATIONS_NAME": "業務運営部",
		"DEPT_OPERATIONS_DESC": "窓口オペレーションを最適化し、顧客の待ち時間と処理時間を短縮します。",
		"DEPT_OPERATIONS_LV1": "Lv.1：全窓口の基本処理時間を 8% 短縮",
		"DEPT_OPERATIONS_LV2": "Lv.2：VIP・優先顧客の自動優先ルーティングを解放",
		"DEPT_OPERATIONS_LV3": "Lv.3：苦情の自動鎮静化・効率化メカニズムを解放",
		"DEPT_HR_NAME": "人事部",
		"DEPT_HR_DESC": "優秀な金融人材の採用枠を拡大し、専門研修と疲労ケアを提供します。",
		"DEPT_HR_LV1": "Lv.1：採用候補者プールの拡大と適性表示を解放",
		"DEPT_HR_LV2": "Lv.2：行員の専門スキルトレーニングを解放",
		"DEPT_HR_LV3": "Lv.3：夜間の疲労回復 +10、人材自動補充サポートを解放",
		"DEPT_CREDIT_NAME": "融資審査部",
		"DEPT_CREDIT_DESC": "個人および中小企業向け融資を統括し、収益資産と審査効率を高めます。",
		"DEPT_CREDIT_LV1": "Lv.1：専用融資カウンターの効率的実行フローを解放",
		"DEPT_CREDIT_LV2": "Lv.2：低リスク優良ローンの自動承認・実行を解放",
		"DEPT_CREDIT_LV3": "Lv.3：高度な金利プライシングと与信枠拡大を解放",
		"DEPT_RISK_NAME": "リスク管理部",
		"DEPT_RISK_DESC": "精密な信用スコアリングと債権回収体制を構築し、貸倒損失を抑制します。",
		"DEPT_RISK_LV1": "Lv.1：審査画面で精密な信用スコアと予想デフォルト率を表示",
		"DEPT_RISK_LV2": "Lv.2：高リスク案件の事前警告とデフォルト率低減",
		"DEPT_RISK_LV3": "Lv.3：マクロストレス緩和およびデフォルト時損失率 (LGD) を 25% 低減",
		"POLICY_PRUDENT_LENDING_NAME": "堅実融資基準",
		"POLICY_PRUDENT_LENDING_DESC": "厳格な与信審査により貸倒リスクを低減し、銀行の信用評価を高めます。",
		"POLICY_LIQUIDITY_FIRST_NAME": "流動性最優先ドクトリン",
		"POLICY_LIQUIDITY_FIRST_DESC": "現金準備金の安全バッファーを強化し、預金者の信頼を確保します。",
		"POLICY_CUSTOMER_TRUST_NAME": "預金者信頼憲章",
		"POLICY_CUSTOMER_TRUST_DESC": "長期的な信頼ブランドを確立し、自然預金流入と満足度を向上させます。",
		"POLICY_HIGH_RATE_ACQUISITION_NAME": "高金利預金獲得キャンペーン",
		"POLICY_HIGH_RATE_ACQUISITION_DESC": "魅力的な預金金利で市場資金を急速に吸収し、貸出原資を拡大します。",
		"POLICY_MARKET_PENETRATION_NAME": "地域市場浸透戦略",
		"POLICY_MARKET_PENETRATION_DESC": "個人・法人顧客への営業を強化し、来店客数と取引量を増やします。",
		"POLICY_CREDIT_EXPANSION_NAME": "積極与信拡大路線",
		"POLICY_CREDIT_EXPANSION_DESC": "融資基準を緩和して高い利ざや収益を追求しますが、信用リスクが上昇します。",
		"EVENT_REAL_ESTATE_BOOM_TITLE": "地域不動産市場の過熱ブーム",
		"EVENT_REAL_ESTATE_BOOM_DESC": "周辺の不動産価格が高騰し、開発業者や住宅ローン顧客からの大口融資申請が急増しています。",
		"EVENT_OPT_AGGRESSIVE_EXPAND": "積極的に不動産融資を拡大する（戦略P+2、満足度+2、将来リスク増）",
		"EVENT_OPT_PRUDENT_CAP": "慎重な与信上限を維持する（戦略P+1、満足度+1、リスク抑制）",
		"EVENT_REAL_ESTATE_COOLING_TITLE": "不動産市場の冷却と流動性逼迫",
		"EVENT_REAL_ESTATE_COOLING_DESC": "市場取引が急速に縮小し、高レバレッジの借入人に資金繰りの悪化が見られます。",
		"EVENT_OPT_TIGHTEN_CREDIT": "与信基準を引き締め担保要件を強化する（戦略P+1、貸倒衝撃を緩和）",
		"EVENT_OPT_HOLD_COURSE": "現在の融資方針を維持する（当面の影響なし、後続ストレス増大）",
		"EVENT_REAL_ESTATE_CREDIT_STRESS_TITLE": "不動産融資デフォルト波のストレステスト",
		"EVENT_REAL_ESTATE_CREDIT_STRESS_DESC": "高レバレッジ案件の返済期日が集中し、一部法人の資金繰り破綻リスクが顕在化しています。",
		"EVENT_OPT_EMERGENCY_PROVISION": "緊急貸倒引当金を計上する（満足度-2、信用不安を鎮静化）",
		"EVENT_OPT_RESTRUCTURE_BOOKS": "資金を投じて債務再編を実施する（現金-¥1,000、貸倒損失を軽減）",
		"ERR_INSUFFICIENT_CASH": "現金準備金が不足しているため実行できません",
		"ERR_INSUFFICIENT_STRATEGY_POINTS": "戦略ポイントが不足しています",
		"ERR_POLICY_PREREQUISITE_MISSING": "前提となる方針がまだ採用されていません",
		"ERR_POLICY_BRANCH_CONFLICT": "既に採用された排他的な戦略ルートと競合します",
		"ERR_POLICY_EXCLUSIVE_CONFLICT": "同一グループの排他方針と競合します",
		"ERR_POLICY_ALREADY_ADOPTED": "この方針は既に採用されています",
		"ERR_DEPT_ALREADY_EXISTS": "この部門は既に設立されています",
		"ERR_DEPT_MAX_LEVEL": "この部門は既に最大レベルに達しています",
		"ERR_DEPT_LOCKED": "部門の解放条件をまだ満たしていません",
		"ERR_EMPLOYEE_ON_BREAK": "行員は現在休憩中です",
		"ERR_EMPLOYEE_BUSY": "行員は現在接客業務中です",
	},
}


static func _ensure_disk_cache() -> void:
	if _disk_cache_loaded:
		return
	_disk_cache_loaded = true
	var modules: Array[String] = ["hud", "panels", "core", "sim", "world"]
	var locales: Array[String] = ["zh_CN", "en", "ja"]
	for lc in locales:
		var target_dict: Dictionary = _disk_tables.get(lc, {}) as Dictionary
		if BUILTIN_FALLBACKS.has(lc):
			var fb: Dictionary = BUILTIN_FALLBACKS[lc] as Dictionary
			for k: Variant in fb.keys():
				target_dict[str(k)] = str(fb[k])
		for mod_name in modules:
			var path: String = "res://localization/%s.%s.json" % [mod_name, lc]
			if FileAccess.file_exists(path):
				var txt: String = FileAccess.get_file_as_string(path)
				var parsed: Variant = JSON.parse_string(txt)
				if parsed is Dictionary:
					var pd: Dictionary = parsed as Dictionary
					for k: Variant in pd.keys():
						target_dict[str(k)] = str(pd[k])
		_disk_tables[lc] = target_dict


static func get_locale() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var loc_node: Node = tree.root.get_node_or_null("LocalizationService")
		if loc_node != null and loc_node.has_method("get_locale"):
			return str(loc_node.call("get_locale"))
	return "zh_CN"


static func set_locale(new_locale: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var loc_node: Node = tree.root.get_node_or_null("LocalizationService")
		if loc_node != null and loc_node.has_method("set_locale"):
			loc_node.call("set_locale", new_locale)


static func connect_locale_changed(target: Object, method_name: StringName) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var loc_node: Node = tree.root.get_node_or_null("LocalizationService")
		if loc_node != null and loc_node.has_signal("locale_changed"):
			var cb := Callable(target, method_name)
			if not loc_node.is_connected("locale_changed", cb):
				loc_node.connect("locale_changed", cb)


static func _format_params(template: String, params: Dictionary) -> String:
	if params.is_empty():
		return template
	var out: String = template
	for k: Variant in params.keys():
		out = out.replace("{%s}" % str(k), str(params[k]))
	return out


static func _looks_like_untranslated_key(val: String, orig_key: String) -> bool:
	if val == orig_key:
		return true
	for prefix in ["UI_", "DEPT_", "POLICY_", "EVENT_", "ERR_", "ROLE_", "SERVICE_", "CUST_", "CUSTOMER_", "PHASE_", "LIQUIDITY_", "EMP_", "CAND_", "REPORT_", "LEDGER_"]:
		if val.begins_with(prefix):
			return true
	return false


static func tr_key(key: String, params: Dictionary = {}) -> String:
	if key.is_empty():
		return ""
	_ensure_disk_cache()
	var locale: String = get_locale()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var resolved: String = key
	if tree != null and tree.root != null:
		var loc_node: Node = tree.root.get_node_or_null("LocalizationService")
		if loc_node != null and loc_node.has_method("tr_key"):
			resolved = str(loc_node.call("tr_key", key, params))

	if not _looks_like_untranslated_key(resolved, key):
		return resolved

	var lc_table: Dictionary = _disk_tables.get(locale, _disk_tables["zh_CN"]) as Dictionary
	if lc_table.has(key):
		return _format_params(str(lc_table[key]), params)

	var en_table: Dictionary = _disk_tables.get("en", {}) as Dictionary
	if en_table.has(key):
		return _format_params(str(en_table[key]), params)

	var zh_table: Dictionary = _disk_tables.get("zh_CN", {}) as Dictionary
	if zh_table.has(key):
		return _format_params(str(zh_table[key]), params)

	# Guarantee no raw UI_* or DEPT_* key ever leaks to Label/Button text
	var clean: String = key
	if clean.contains(":"):
		var parts: PackedStringArray = clean.split(":", false, 1)
		if parts.size() == 2:
			clean = parts[1]
	for prefix in ["UI_", "DEPT_", "POLICY_", "EVENT_", "ERR_", "ROLE_", "SERVICE_", "CUST_", "CUSTOMER_", "PHASE_", "LIQUIDITY_", "EMP_", "CAND_", "REPORT_", "LEDGER_"]:
		if clean.begins_with(prefix):
			clean = clean.substr(prefix.length())
			break
	clean = clean.replace("_", " ").capitalize()
	match locale:
		"zh_CN":
			return _format_params("项目 · %s" % clean, params)
		"ja":
			return _format_params("項目 · %s" % clean, params)
		_:
			return _format_params("Item · %s" % clean, params)


static func tr_person_name(name_key: String) -> String:
	if name_key.is_empty():
		return ""
	if name_key.begins_with("PERSON_NAME_"):
		var num_str: String = name_key.substr(12)
		var locale: String = get_locale()
		var resolved: String = tr_key(name_key)
		if not resolved.begins_with("Item ·") and not resolved.begins_with("项目 ·") and not resolved.begins_with("項目 ·") and resolved != name_key:
			return resolved
		match locale:
			"en":
				return "Staff #%s" % num_str
			"ja":
				return "行員 #%s" % num_str
			_:
				return "星海员工 #%s" % num_str
	return tr_key(name_key)


static func tr_role(role_id: String) -> String:
	match role_id.to_lower():
		"teller":
			return tr_key("ROLE_TELLER")
		"loan_officer":
			return tr_key("ROLE_LOAN_OFFICER")
		"manager":
			return tr_key("ROLE_MANAGER")
		"analyst":
			return tr_key("ROLE_ANALYST")
		_:
			return tr_key("ROLE_TELLER")


static func tr_emp_state(state_enum: int) -> String:
	match state_enum:
		Enums.EmployeeState.AVAILABLE:
			return tr_key("EMP_STATE_AVAILABLE")
		Enums.EmployeeState.MOVING:
			return tr_key("EMP_STATE_MOVING")
		Enums.EmployeeState.WORKING:
			return tr_key("EMP_STATE_WORKING")
		Enums.EmployeeState.BREAK:
			return tr_key("EMP_STATE_BREAK")
		Enums.EmployeeState.OVERLOADED:
			return tr_key("EMP_STATE_OVERLOADED")
		Enums.EmployeeState.OFF_DUTY:
			return tr_key("EMP_STATE_OFF_DUTY")
		_:
			return tr_key("EMP_STATE_AVAILABLE")


static func tr_service_type(service_id: String) -> String:
	return tr_key("SERVICE_" + service_id.to_upper())


static func tr_customer_type(cust_type: String) -> String:
	return tr_key("CUSTOMER_" + cust_type.to_upper() + "_NAME")


static func tr_phase(phase_enum: int) -> String:
	match phase_enum:
		Enums.DayPhase.PRE_OPEN:
			return tr_key("UI_PHASE_PRE_OPEN")
		Enums.DayPhase.OPEN:
			return tr_key("UI_PHASE_OPEN")
		Enums.DayPhase.CLOSING:
			return tr_key("UI_PHASE_CLOSING")
		Enums.DayPhase.SETTLED:
			return tr_key("UI_PHASE_SETTLED")
		_:
			return tr_key("UI_PHASE_PRE_OPEN")


static func tr_liquidity_status(status_enum: int) -> String:
	match status_enum:
		Enums.LiquidityStatus.SAFE:
			return tr_key("LIQUIDITY_SAFE")
		Enums.LiquidityStatus.CAUTION:
			return tr_key("LIQUIDITY_CAUTION")
		Enums.LiquidityStatus.DANGER:
			return tr_key("LIQUIDITY_DANGER")
		_:
			return tr_key("LIQUIDITY_SAFE")


static func tr_priority(priority_enum: int) -> String:
	match priority_enum:
		Enums.QueuePriority.PRIORITY:
			return tr_key("UI_PRIORITY_PRIORITY")
		Enums.QueuePriority.VIP:
			return tr_key("UI_PRIORITY_VIP")
		_:
			return tr_key("UI_PRIORITY_NORMAL")


static func play_sfx(sfx_name: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var audio_node: Node = tree.root.get_node_or_null("AudioService")
		if audio_node != null and audio_node.has_method("play_sfx"):
			audio_node.call("play_sfx", sfx_name)


static func load_icon(icon_basename: String) -> Texture2D:
	var path: String = "res://assets/icons/%s.png" % icon_basename
	if ResourceLoader.exists(path):
		var tex: Resource = load(path)
		if tex is Texture2D:
			return tex as Texture2D
	return null


static func load_avatar(avatar_id: String) -> Texture2D:
	for candidate in [
		"res://assets/characters/%s_portrait.png" % avatar_id,
		"res://assets/characters/%s.png" % avatar_id,
		"res://assets/characters/emp_teller_m_portrait.png",
	]:
		if ResourceLoader.exists(candidate):
			var tex: Resource = load(candidate)
			if tex is Texture2D:
				return tex as Texture2D
	return null


static func get_effective_content_defs(sim_host: Node = null) -> Dictionary:
	if sim_host != null:
		var host_defs: Variant = sim_host.get("content_defs")
		if host_defs is Dictionary and not (host_defs as Dictionary).is_empty():
			var hd: Dictionary = host_defs as Dictionary
			if (hd.get("departments", []) as Array).size() > 0:
				return hd

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var reg: Node = tree.root.get_node_or_null("ContentRegistry")
		if reg != null:
			if reg.has_method("get_content_defs"):
				var cdefs: Variant = reg.call("get_content_defs")
				if cdefs is Dictionary and ((cdefs as Dictionary).get("departments", []) as Array).size() > 0:
					return cdefs as Dictionary
			elif reg.has_method("get_all_by_type"):
				var depts: Array = reg.call("get_all_by_type", &"departments") as Array
				if not depts.is_empty():
					return {
						"departments": depts,
						"policies": reg.call("get_all_by_type", &"policies"),
						"events": reg.call("get_all_by_type", &"events"),
						"traits": reg.call("get_all_by_type", &"traits"),
						"customers": reg.call("get_all_by_type", &"customers"),
					}

	return get_fallback_content_defs()


static func get_fallback_content_defs() -> Dictionary:
	return {
		"departments": [
			{
				"id": "core:department.operations",
				"name_key": "DEPT_OPERATIONS_NAME",
				"description_key": "DEPT_OPERATIONS_DESC",
				"initial_cost_minor": 200_000,
				"daily_cost_minor": 15_000,
				"max_level": 3,
				"unlock_keys": ["DEPT_OPERATIONS_LV1", "DEPT_OPERATIONS_LV2", "DEPT_OPERATIONS_LV3"],
				"effects": [{"target": "service.teller_duration_bps", "operation": "add", "value": -800, "scope": "global"}],
			},
			{
				"id": "core:department.hr",
				"name_key": "DEPT_HR_NAME",
				"description_key": "DEPT_HR_DESC",
				"initial_cost_minor": 220_000,
				"daily_cost_minor": 16_000,
				"max_level": 3,
				"unlock_keys": ["DEPT_HR_LV1", "DEPT_HR_LV2", "DEPT_HR_LV3"],
				"effects": [{"target": "staff.productivity_bps", "operation": "add", "value": 600, "scope": "global"}],
			},
			{
				"id": "core:department.credit",
				"name_key": "DEPT_CREDIT_NAME",
				"description_key": "DEPT_CREDIT_DESC",
				"initial_cost_minor": 300_000,
				"daily_cost_minor": 22_000,
				"max_level": 3,
				"unlock_keys": ["DEPT_CREDIT_LV1", "DEPT_CREDIT_LV2", "DEPT_CREDIT_LV3"],
				"effects": [{"target": "customer.deposit_growth_bps", "operation": "add", "value": 500, "scope": "global"}],
			},
			{
				"id": "core:department.risk",
				"name_key": "DEPT_RISK_NAME",
				"description_key": "DEPT_RISK_DESC",
				"initial_cost_minor": 280_000,
				"daily_cost_minor": 20_000,
				"max_level": 3,
				"unlock_keys": ["DEPT_RISK_LV1", "DEPT_RISK_LV2", "DEPT_RISK_LV3"],
				"effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": -600, "scope": "global"}],
			},
		],
		"policies": [
			{
				"id": "core:policy.prudent_lending",
				"name_key": "POLICY_PRUDENT_LENDING_NAME",
				"description_key": "POLICY_PRUDENT_LENDING_DESC",
				"cost_strategy_points": 3,
				"prerequisites": [],
				"exclusive_group": "conservative",
				"effects": [
					{"target": "loan.default_risk_bps", "operation": "add", "value": -500, "scope": "global"},
					{"target": "bank.reputation_points", "operation": "add", "value": 4, "scope": "global"},
				],
			},
			{
				"id": "core:policy.liquidity_first",
				"name_key": "POLICY_LIQUIDITY_FIRST_NAME",
				"description_key": "POLICY_LIQUIDITY_FIRST_DESC",
				"cost_strategy_points": 4,
				"prerequisites": ["core:policy.prudent_lending"],
				"exclusive_group": "conservative",
				"effects": [
					{"target": "liquidity.required_buffer_bps", "operation": "add", "value": -1500, "scope": "global"},
				],
			},
			{
				"id": "core:policy.customer_trust",
				"name_key": "POLICY_CUSTOMER_TRUST_NAME",
				"description_key": "POLICY_CUSTOMER_TRUST_DESC",
				"cost_strategy_points": 5,
				"prerequisites": ["core:policy.liquidity_first"],
				"exclusive_group": "conservative",
				"effects": [
					{"target": "customer.deposit_growth_bps", "operation": "add", "value": 1200, "scope": "global"},
					{"target": "bank.reputation_points", "operation": "add", "value": 8, "scope": "global"},
				],
			},
			{
				"id": "core:policy.high_rate_acquisition",
				"name_key": "POLICY_HIGH_RATE_ACQUISITION_NAME",
				"description_key": "POLICY_HIGH_RATE_ACQUISITION_DESC",
				"cost_strategy_points": 3,
				"prerequisites": [],
				"exclusive_group": "aggressive",
				"effects": [
					{"target": "customer.deposit_growth_bps", "operation": "add", "value": 1500, "scope": "global"},
				],
			},
			{
				"id": "core:policy.market_penetration",
				"name_key": "POLICY_MARKET_PENETRATION_NAME",
				"description_key": "POLICY_MARKET_PENETRATION_DESC",
				"cost_strategy_points": 4,
				"prerequisites": ["core:policy.high_rate_acquisition"],
				"exclusive_group": "aggressive",
				"effects": [
					{"target": "staff.productivity_bps", "operation": "add", "value": 1000, "scope": "global"},
				],
			},
			{
				"id": "core:policy.credit_expansion",
				"name_key": "POLICY_CREDIT_EXPANSION_NAME",
				"description_key": "POLICY_CREDIT_EXPANSION_DESC",
				"cost_strategy_points": 5,
				"prerequisites": ["core:policy.market_penetration"],
				"exclusive_group": "aggressive",
				"effects": [
					{"target": "customer.deposit_growth_bps", "operation": "add", "value": 2000, "scope": "global"},
					{"target": "loan.default_risk_bps", "operation": "add", "value": 400, "scope": "global"},
				],
			},
		],
		"events": [
			{
				"id": "core:event.real_estate_boom",
				"title_key": "EVENT_REAL_ESTATE_BOOM_TITLE",
				"description_key": "EVENT_REAL_ESTATE_BOOM_DESC",
				"weight": 10,
				"cooldown_days": 5,
				"conditions": [],
				"options": [
					{
						"id": "aggressive_expand",
						"label_key": "EVENT_OPT_AGGRESSIVE_EXPAND",
						"next_event_id": "core:event.real_estate_cooling",
						"effects": [{"target": "customer.deposit_growth_bps", "operation": "add", "value": 1000, "scope": "global"}],
					},
					{
						"id": "prudent_cap",
						"label_key": "EVENT_OPT_PRUDENT_CAP",
						"next_event_id": "core:event.real_estate_cooling",
						"effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": -300, "scope": "global"}],
					},
				],
			},
		],
		"traits": [],
		"customers": [],
	}
