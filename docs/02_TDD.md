# 02 — 技术设计文档（TDD）

**目标引擎：** Godot 4.7.2 Stable  
**语言：** GDScript（静态类型优先）  
**渲染：** 2D、Compatibility 渲染器优先；只使用 2D 场景与 UI  
**逻辑基准：** 固定步长模拟，渲染帧率与模拟时间解耦

## 1. 技术目标

1. 实时经营在不同帧率下得到一致结果。
2. 领域逻辑可脱离场景树运行和测试。
3. 内容（部门/政策/事件/特质）可通过原版数据或 Mod 数据注册。
4. UI 只呈现状态、发送命令，不直接修改领域状态。
5. 存档能跨版本迁移；Mod 缺失时能明确告警。
6. 资产和 UI 支持像素级清晰显示。

## 2. 技术选型

| 领域 | 方案 | 原因/约束 |
|---|---|---|
| 引擎 | Godot 4.7.2 Stable | 固定稳定版本；不在项目中途升级到 Beta |
| 脚本 | GDScript 静态类型 | 原生编辑器体验，适合小团队/AI Agent |
| 场景 | PackedScene + Node | 表现层节点可复用 |
| 静态定义 | Godot Resource（原版）+ JSON（Mod） | 统一转换成领域 Definition |
| 运行状态 | Typed GDScript RefCounted/Resource 数据类 | 不绑定 SceneTree |
| 存档 | JSON v1 + 原子替换/备份 | 易于调试、迁移和 Mod 兼容 |
| 翻译 | PO/MO（原版）+ JSON 字典（Mod） | 支持 gettext 翻译工作流 |
| Mod | 文件夹/ZIP + JSON + PNG/音频；后续评估 PCK | 首发不执行任意代码 |
| 测试 | GDScript 单元/集成测试（可先自建轻量 Runner） | 金融规则和迁移逻辑必须可重复验证 |

## 3. 分层架构

### 3.1 Presentation

负责 Node、Sprite、TileMapLayer、动画、输入、摄像机和 Control UI。它不决定贷款是否通过，也不直接扣款。

### 3.2 Application

负责用例流程和跨系统编排，例如 `OpenBranchForDay`、`AssignEmployeeToStation`、`SubmitLoanDecision`、`SetPolicy`、`RunDailySettlement`。负责把用户意图转为领域命令，并整理结果反馈给 UI。

### 3.3 Domain

包含 BankState、Employee、Customer、DepartmentInstance、Loan、Ledger、PolicyState、EventState 等核心规则。不得引用 `Node`、`Control`、`SceneTree` 或具体 UI 脚本。

### 3.4 Infrastructure

文件系统、存档、Mod 加载、翻译字典、随机种子持久化、配置和日志。

### 3.5 依赖方向

`Presentation -> Application -> Domain`；`Infrastructure` 通过接口/适配器向 Application 提供内容和持久化能力。Domain 不依赖 Presentation 或 Infrastructure。

## 4. 推荐目录结构

```text
res://
├── addons/                     # 仅经批准的插件
├── assets/
│   ├── characters/             # spritesheets、头像
│   ├── environment/            # 地面、墙体、建筑、家具
│   ├── ui/                     # 原生像素 UI 素材
│   ├── icons/                  # 图标
│   ├── vfx/                    # 状态、提示和效果
│   ├── fonts/                  # 像素字体
│   └── audio/                  # 音乐/音效
├── data/
│   ├── departments/            # 原版静态定义
│   ├── policies/
│   ├── events/
│   ├── employees/
│   ├── customers/
│   └── products/
├── localization/
│   ├── messages.pot
│   ├── zh_CN.po
│   ├── en.po
│   └── ja.po
├── scenes/
│   ├── boot/
│   ├── menus/
│   ├── gameplay/
│   ├── world/
│   ├── actors/
│   ├── stations/
│   └── ui/
├── scripts/
│   ├── app/                    # use cases、command handlers
│   ├── domain/                 # 纯领域模型
│   ├── simulation/             # GameClock、客户/员工模拟、队列
│   ├── infrastructure/        # save、mod、localization、logging
│   ├── presentation/           # view controllers、UI adapters
│   └── shared/                 # 类型、常量、ID、结果对象
├── tests/
│   ├── unit/
│   ├── integration/
│   └── scenarios/
└── docs/
```

## 5. 场景与节点组织

主游戏场景建议：

```text
GameRoot (Node2D)
├── World (Node2D)
│   ├── FloorLayer (TileMapLayer)
│   ├── DecorationLayer (Node2D)
│   ├── YSortedActors (Node2D, y_sort_enabled = true)
│   │   ├── Employees (Node2D)
│   │   ├── Customers (Node2D)
│   │   ├── FurnitureInstances (Node2D)
│   │   └── ServiceStations (Node2D)
│   ├── Effects (Node2D)
│   └── Camera2D
├── SimulationHost (Node)
│   ├── BranchDayController
│   ├── CustomerSimulation
│   ├── EmployeeSimulation
│   ├── QueueSimulation
│   └── EventSimulation
└── UI (CanvasLayer)
    ├── TopBar
    ├── LeftNavigation
    ├── RightInspector
    ├── EventOverlay
    ├── BottomTimeline
    └── DailyReportOverlay
```

注意：该结构是组织建议，不要求把每个子系统都创建为一个 Node。纯逻辑类可由 SimulationHost 持有。

## 6. Autoload

建议首版只使用以下全局服务：

| 名称 | 职责 | 不负责 |
|---|---|---|
| `GameSession` | 当前会话、当前银行状态引用、开始/结束会话 | 具体经济计算 |
| `ContentRegistry` | 原版和 Mod 静态定义查询 | 修改游戏运行状态 |
| `SaveService` | 存档/读档/迁移/备份 | 决定领域规则 |
| `LocalizationService` | Mod 翻译 Key 查询与回退 | UI 布局 |
| `AudioService` | 声音播放入口 | 游戏事件逻辑 |

Simulation Manager 属于 GameRoot，不设置为全局 Autoload。

## 7. 模拟时钟和时间推进

### 7.1 时间模型

- `current_day: int`，从 1 开始。
- `current_minute_of_day: int`，0–1439。
- 营业：09:00（540）至 17:00（1020）。
- `speed_multiplier` 取 0、1、2、3；0 表示暂停。
- 默认 1x：1 个游戏分钟约 1 秒真实时间，标准 480 分钟营业日约 8 分钟。
- 速度倍率只影响模拟 Tick 累积速度，不影响模拟公式。

### 7.2 固定步长

`GameClock` 累积真实 `delta`，达到本速度下的一个模拟分钟后发出 `minute_tick`。同一帧如需补多个 Tick，必须按顺序逐个执行；设置最大补帧 Tick 数，避免卡顿恢复时无限追帧。暂停时不发出 Tick。

伪代码：

```gdscript
const REAL_SECONDS_PER_GAME_MINUTE: float = 1.0
var accumulator: float = 0.0
var speed_multiplier: int = 1

func _process(delta: float) -> void:
    if speed_multiplier <= 0:
        return
    accumulator += delta * float(speed_multiplier)
    while accumulator >= REAL_SECONDS_PER_GAME_MINUTE:
        accumulator -= REAL_SECONDS_PER_GAME_MINUTE
        simulation_step()
```

该伪代码是思路示例；正式实现需处理暂停时残余累积、上限追帧和单元测试。更稳妥的实现可将 `speed_multiplier` 计入阈值而不是乘法累积，但两者不可混用。

### 7.3 处理顺序

每个模拟分钟固定顺序：

1. 更新当日时间与日程触发器。
2. 生成符合条件的新客户/事件。
3. 更新队列和服务请求。
4. 运行员工/服务点分配。
5. 推进服务处理进度。
6. 完成业务并通过 Ledger 写入账务。
7. 更新疲劳、耐心、满意度和风险计时器。
8. 触发阈值事件并发布领域事件。

顺序固定，且通过测试确保重放一致。

## 8. 确定性和随机数

- 新存档生成 `world_seed: int`。
- Random 使用显式 Seed，不在不同系统各自创建不可追踪的随机数源。
- 建议按用途派生子流：`customer_rng`、`event_rng`、`market_rng`，避免 UI 动画消耗随机数后改变事件序列。
- 所有概率抽样只在模拟 Tick/明确的事件处理期间调用。
- 重放测试需要保存玩家命令序列与 Seed。

## 9. 客户、员工和任务系统

### 9.1 服务请求作为统一工作单位

`ServiceRequest` 建议字段：

- `request_id: StringName`
- `customer_id: StringName`
- `service_type: StringName`
- `priority: int`
- `required_skill: StringName`
- `estimated_work_minutes: int`
- `remaining_work_units: int`
- `risk_level: int`
- `created_at_minute: int`
- `deadline_minute: int`
- `payload: Dictionary`（仅放业务参数，不放 UI 数据）

### 9.2 Dispatcher

根据服务技能、员工状态、部门权限、所在位置、预计完成时间和优先级选择合适员工。初版可以用规则评分：技能匹配 > 优先级 > 等待时间 > 距离；规则必须可解释、可测试。

### 9.3 状态机

Customer：`SPAWNING -> FINDING_SERVICE -> WAITING -> IN_SERVICE -> COMPLETED/LEAVING`。  
Employee：`OFF_DUTY / AVAILABLE / MOVING / WORKING / BREAK / OVERLOADED`。

视觉状态从领域状态映射，不直接承担业务真值。员工因路径不可达而无法抵达时，必须返回可诊断错误，不能静默卡住。

## 10. 世界坐标和寻路

- 采用 2:1 视觉比例的轻等距/俯视 2D 银行内部。
- 逻辑导航使用规则网格坐标；渲染阶段将格子坐标投影到等距屏幕坐标。
- 初版使用 `AStarGrid2D` 或离线生成的格点图；业务站点提供可达交互格。
- 地面用 TileMapLayer；家具、柜台和角色用独立场景。
- 对同一地面高度上的角色和家具启用 Y-sort；前景遮挡通过独立前景层处理。
- 不在第一版做自由旋转家具或复杂多层楼层寻路。

## 11. 命令和领域事件

### 命令（示例）

- `OpenBranchCommand`
- `AssignEmployeeCommand`
- `SetServicePriorityCommand`
- `OpenServiceStationCommand`
- `ApproveLoanCommand`
- `RejectLoanCommand`
- `CreateDepartmentCommand`
- `UpgradeDepartmentCommand`
- `AdoptPolicyCommand`
- `ResolveEventOptionCommand`

### 领域事件（示例）

- `CustomerArrived`
- `ServiceStarted`
- `ServiceCompleted`
- `CustomerLeftUnserved`
- `LoanApproved`
- `LoanDefaulted`
- `DepartmentCreated`
- `PolicyAdopted`
- `EmployeeHired`
- `EmployeeResigned`
- `DailySettlementCompleted`

命令表示请求；领域事件表示已发生事实。UI 可订阅领域事件刷新显示和显示通知。

## 12. 数据定义与运行实例

- `DepartmentDefinition` 与 `DepartmentInstance` 分离。
- `EmployeeDefinition`（模板/岗位候选规则）与 `EmployeeInstance` 分离。
- `PolicyDefinition` 与 `PolicyState` 分离。
- `EventDefinition` 与 `ActiveEventInstance` 分离。
- 内置定义通过 Resource 或加载器转换到标准领域 Definition。
- Mod JSON 由 Schema 校验后转换为相同 Definition。
- 运行时实例只引用稳定 ID，并保存影响游戏状态的数值。

## 13. 性能和规模目标（初始目标）

- MVP 同屏目标：最多 50 个可视员工/客户对象。
- 活跃模拟对象目标：最多 150 个客户/员工（不含历史档案）。
- 目标桌面：1080p 显示器，稳定 60 FPS；低端设备优先保证模拟正确性。
- 不在 `_process()` 每帧遍历全量历史客户/交易。
- 交易、事件和客户历史使用分页/有限长度日志或聚合统计。
- 性能优化以 Profiler 数据为依据，不提前引入 ECS/复杂线程。

## 14. 测试层级

- Unit：利息、账务借贷平衡、调度评分、政策前置条件、状态机转换。
- Integration：客户从进门到离开的完整任务；日终结算；创建部门后能力变化。
- Determinism：相同 Seed + 相同命令序列，关键结果完全一致。
- Migration：旧存档迁移与未知 Mod 内容处理。
- Visual smoke test：主场景、弹窗、长文本、多语言、不同窗口尺寸。

## 15. 官方资料

- Godot 发布档案：https://godotengine.org/download/archive/
- 多分辨率和整数缩放：https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html
- 运行时文件读写和 ZIP：https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html
- CanvasItem 纹理过滤：https://docs.godotengine.org/en/stable/classes/class_canvasitem.html
