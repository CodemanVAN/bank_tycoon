# 03 — 银行经济与账务规范

## 1. 设计目标

用玩家能够理解的方式呈现银行经营的基本逻辑，不追求真实银行全量监管和复杂会计科目。每个经济变量必须有明确来源、用途、反馈和可解释的玩家决策。

## 2. 数值单位

- 货币：以最小货币单位保存为整数，例如 `money_minor: int`（若默认币种为 CNY，可视为分；UI 格式化为元）。
- 利率：整数基点 `rate_bps: int`；100 bps = 1%，425 bps = 4.25%。
- 百分比：存储为整数或基点，不用浮点百分比作为财务真值。
- 时间：整数游戏分钟。
- 满意度/声誉/员工属性：整数 0–100。
- 计算可能超出 32-bit 范围，金额使用 Godot `int`（64-bit）并对极端输入做范围校验。

## 3. 银行资产负债表（简化）

### 资产 Assets

- 现金与可用准备金 `cash_reserves`
- 贷款余额 `loan_principal_outstanding`
- 流动性证券/投资资产 `securities_value`（MVP 可简化）

### 负债 Liabilities

- 客户存款 `customer_deposits`
- 批发融资/紧急融资 `borrowings`（MVP 可暂不开放）

### 权益 Equity

- 初始股本 `equity_capital`
- 累计留存收益 `retained_earnings`

基础恒等式：

`Assets = Liabilities + Equity`

必须通过 Ledger 双分录保证每笔交易借贷平衡。存款是银行负债，不是银行收入；贷款本金是资产，不是当期利润。

## 4. 收入和成本

### 收入

- 贷款利息收入。
- 可用证券/投资收益（MVP 可先不做投资市场）。
- 账户/转账/企业服务手续费。
- 后续资产管理/咨询服务费。

### 成本

- 存款利息支出。
- 融资成本。
- 员工工资和培训费用。
- 房租、设备和维护。
- 营销支出。
- 信用损失/坏账准备。
- 后续合规和系统运营支出。

### 日净利息收入

`net_interest_income = loan_interest_income + asset_interest_income - deposit_interest_expense - funding_interest_expense`

### 日经营利润（抽象）

`operating_profit = net_interest_income + fee_income - staff_cost - facility_cost - marketing_cost - admin_cost`

### 日净利润

`net_profit = operating_profit - credit_loss_expense - event_expense - other_one_off_costs`

所有公式由 FinanceEngine 维护；UI 只能读取计算结果。

## 5. 利息计提

对于按年利率计息的本金：

`daily_interest_minor = round_div(principal_minor * annual_rate_bps, 10_000 * 365)`

- 使用整数运算并明确舍入规则（推荐四舍五入或银行家舍入，项目必须统一）。
- 贷款与存款分别计提。
- 不能因游戏速度 1x/2x/3x 改变利息；利息只按游戏日结算。
- 实际计息可以在每日结算时做，实时 UI 使用估算值并标注“预计”。

## 6. 客户存款模型

### 存款增长

当客户完成存款业务时：现金/准备金资产增加，客户存款负债增加。存款增长受以下影响：

- 存款利率竞争力。
- 客户满意度与银行声誉。
- 营销政策。
- 分行客群和宏观经济。
- 银行风险/稳定性。

### 存款流失

受客户满意度、竞争对手利率、声誉危机、挤兑传闻和宏观事件影响。流失的存款减少现金/准备金资产与客户存款负债。提现业务不得被当作费用；它是资产和负债同步减少。

## 7. 贷款模型

贷款至少包含：

- `loan_id`
- `customer_id`
- `principal_original`
- `principal_outstanding`
- `annual_rate_bps`
- `term_days`
- `risk_grade`
- `collateral_value`（可选）
- `days_past_due`
- `status`

贷款审批分为客户信用、银行风险偏好、当前资金和部门流程。MVP 用简化评分：

`credit_score = clamp(base_score + income_factor + history_factor + collateral_factor - macro_risk - debt_load, 0, 100)`

具体因子必须在 `BalanceConfig` 或测试数据中配置，不能藏在贷款 UI 脚本内。

违约/坏账发生由信用评分、经济周期、贷款类型、政策和随机种子共同影响；高风险贷款增加预期损失，不应由纯随机直接一夜清零。

## 8. 流动性风险

可用流动性比率（游戏指标，不是法律监管口径）：

`liquidity_ratio = available_liquid_assets / expected_near_term_withdrawals`

UI 显示安全/关注/危险等级，具体阈值由平衡表配置。例如：
- 安全：>= 1.5
- 关注：1.0–1.49
- 危险：< 1.0

玩家可以保留更多现金/流动性资产，但这会降低可用于贷款或投资的资金收益。

## 9. 信用风险

- 不良贷款率：`npl_ratio = non_performing_loan_balance / total_loan_balance`
- 预期损失近似：`expected_credit_loss = exposure * probability_of_default * loss_given_default`
- MVP 可以按贷款风险等级查表得到 PD 与 LGD，再在结算时生成抽象损失。
- 风控部门降低错误审批和风险暴露，但不能保证永不违约。
- 宏观衰退提高违约风险；稳健政策降低风险暴露但限制增长。

## 10. 资金流和双分录示例

### 存款 1,000 元

- 借：现金/准备金资产 +1,000
- 贷：客户存款负债 +1,000
- 利润影响：0

### 发放贷款 10,000 元

- 借：贷款资产 +10,000
- 贷：现金/准备金资产 -10,000（在借贷账簿实现时按相应方向记账）
- 利润影响：本金放款本身不是收入；未来利息才形成收入。

### 计提存款利息 10 元

- 借：利息支出 +10
- 贷：客户存款负债 +10
- 当期利润减少 10。

具体 Ledger 借贷方向以实现时的账户类型规范为准；每笔 Journal Entry 必须平衡，不能只修改某个余额字段。

## 11. 日终结算顺序

1. 停止新客户进入并处理营业收尾规则。
2. 对所有活跃贷款/存款计提当日利息。
3. 计算工资、加班、租金、设备和部门成本。
4. 处理当日完成的手续费业务。
5. 计算逾期、违约和信用损失。
6. 更新客户满意度、声誉、员工疲劳和离职风险。
7. 更新银行指标和资产负债表。
8. 检查流动性/资本预警。
9. 记录 `DailySettlementRecord`。
10. 生成日终报告并允许玩家进入下一日。

## 12. 财务界面必须说明

- 本日收入分类和成本分类。
- 净利息收入、手续费收入、运营成本、信用损失、净利润。
- 存款、贷款、现金/准备金、权益资本。
- 流动性状态和 NPL 状态。
- 与昨日相比的主要变化以及驱动原因。

不允许仅显示单一“今日赚了多少钱”而隐藏风险。
