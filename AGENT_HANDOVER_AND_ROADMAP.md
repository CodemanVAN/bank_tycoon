# AGENT_HANDOVER_AND_ROADMAP.md — 星海银行 (Starway Bank / Bank Tycoon) 多 Agent 研发交接与路线图总纲

> **用途**：本文件是面向后续加入开发的所有 AI Agent 与开发者的**交接主索引与开发路标（Single Handover Reference）**。任何新 Agent 接手任务前，请先阅读 [`AGENTS.md`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/AGENTS.md) 和本文件。

---

## 1. 本次对话产生的记录文件目录与归档索引

本次「星海银行 (Starway Bank)」Godot 4.7.2 垂直切片可玩 Demo 开发过程中产生的所有规划文档、多代理协作记录、测试报告、截图与对话日志完整路径如下：

### 1.1 项目仓库内持久化核心文档（推荐后续 Agent 优先读取）

| 仓库相对路径 | 绝对路径 | 说明 |
|---|---|---|
| [`AGENTS.md`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/AGENTS.md) | `d:\project\Bank_Tycoon_Production_Kit_v0.1.0\Bank_Tycoon_Production_Kit\AGENTS.md` | 全局强制工程约束（分层边界、整数货币/基点、零硬编码文本、禁止第三方插件） |
| [`AGENT_HANDOVER_AND_ROADMAP.md`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/AGENT_HANDOVER_AND_ROADMAP.md) | `d:\project\Bank_Tycoon_Production_Kit_v0.1.0\Bank_Tycoon_Production_Kit\AGENT_HANDOVER_AND_ROADMAP.md` | **本文件**：当前进度、文件索引、架构契约、测试基线与后续多 Agent 待办 TODO |
| [`bank_tycoon_demo/docs/TEAM_CONTRACTS.md`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/bank_tycoon_demo/docs/TEAM_CONTRACTS.md) | `...\bank_tycoon_demo\docs\TEAM_CONTRACTS.md` | 多 Agent 并行开发模块所有权边界、5 大 Autoload 接口签名、事件总线契约 |
| [`docs/12_DECISION_LOG.md`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/docs/12_DECISION_LOG.md) | `...\docs\12_DECISION_LOG.md` | 已更新 `ADR-005`（星海银行现代科技蓝 UI + 暖木像素大厅）与 `ADR-006`（1280×720 `canvas_items` + 世界层 Nearest 整数倍缩放） |
| [`tasks/IMPLEMENTATION_BACKLOG.md`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/tasks/IMPLEMENTATION_BACKLOG.md) | `...\tasks\IMPLEMENTATION_BACKLOG.md` | 原始 `BT-000` ~ `BT-029` 任务拆解清单 |
| [`bank_tycoon_demo/docs/screenshots/`](file:///d:/project/Bank_Tycoon_Production_Kit_v0.1.0/Bank_Tycoon_Production_Kit/bank_tycoon_demo/docs/screenshots) | `...\bank_tycoon_demo\docs\screenshots\` | 5 张 Godot 4.7.2 实机渲染验证截图（主菜单、像素大厅 HUD、财务图表、部门协同、日终报告） |

### 1.2 本次主会话 Artifact 与完整日志目录

- **主会话 ID**：`a4eb7699-7f21-4ceb-b6c2-f70bb5c64bab`
- **Artifact 根目录**：`C:\Users\18249\.gemini\antigravity\brain\a4eb7699-7f21-4ceb-b6c2-f70bb5c64bab`
  - [`implementation_plan.md`](file:///C:/Users/18249/.gemini/antigravity/brain/a4eb7699-7f21-4ceb-b6c2-f70bb5c64bab/implementation_plan.md)：经用户确认批准的 7 模块完整技术实施计划。
  - [`walkthrough.md`](file:///C:/Users/18249/.gemini/antigravity/brain/a4eb7699-7f21-4ceb-b6c2-f70bb5c64bab/walkthrough.md)：Demo 交付验收总结报告与实机截图走查。
  - `screenshot_01_main_menu.png` ~ `screenshot_05_daily_report.png`：实机渲染截图。
  - `scratch/contact.png`：60 张程序化像素资产拼图总览表。
  - `.system_generated/logs/transcript.jsonl`（及 `transcript_full.jsonl`）：主会话完整步骤轨迹日志。

### 1.3 子代理（Subagents）会话记录与 Teamwork 归档目录

| 角色 / 模块 | 会话 ID (`conversationId`) | 日志 / 归档路径 | 交付成果 |
|---|---|---|---|
| **Teamwork 协调与 E2E 测试工程** | `c711d5c1-f908-4b22-b3d4-ede889d48e2c` | `C:\Users\18249\.gemini\antigravity\scratch\teamwork\c711d5c1-f908-4b22-b3d4-ede889d48e2c\.agents\teamwork\` | `PROJECT.md`、`TEST_INFRA.md`、M1 60 张像素 PNG + 12 个 WAV、M2 纯领域核心（351 项断言）、Tier 1–4 共 108 项黑盒 E2E 测试套件 |
| **M3 数据、本地化与 5 大 Autoload 专责代理** | `185f6f56-d807-4ca6-9bd4-94a517c56a26` | `C:\Users\18249\.gemini\antigravity\brain\185f6f56-d807-4ca6-9bd4-94a517c56a26\.system_generated\logs\transcript.jsonl` | `data/*.json`、566 键三语 JSON + `.po/.pot`、5 大 Autoload、`tests/unit/test_infra.gd`（88/88 通过） |
| **M4 固定步长模拟与应用命令层专责代理** | `e773a403-869f-4c2f-a3cf-729b921fa2cf` | `C:\Users\18249\.gemini\antigravity\brain\e773a403-869f-4c2f-a3cf-729b921fa2cf\.system_generated\logs\transcript.jsonl` | `GameClock`、`EmployeeDispatcher`、`BranchSimulation`、`DomainEventBus`、`BankCommandService`、`SimulationHost`、`tests/integration/test_sim_app.gd`（81/81 通过） |
| **M5 2.5D 等距像素银行大厅专责代理** | `98270f11-7483-423a-9d8d-6f0bf6c242ae` | `C:\Users\18249\.gemini\antigravity\brain\98270f11-7483-423a-9d8d-6f0bf6c242ae\.system_generated\logs\transcript.jsonl` | `IsoGrid` (`AStarGrid2D`)、`PixelCamera2D`、`ServiceStationView`、`ActorView`、`BankWorld`、`tests/unit/test_world.gd`（507/507 通过） |
| **M6 星海蓝主菜单、HUD、抽屉与弹窗专责代理** | `5d26230b-fc74-4b0d-abef-5f1a231f269b` | `C:\Users\18249\.gemini\antigravity\brain\5d26230b-fc74-4b0d-abef-5f1a231f269b\.system_generated\logs\transcript.jsonl` | `StarwayTheme`、`UiI18n`、`MainMenu`、`GameRoot`、`TopBar`、`LeftNavigation`、`RightInspector`、`BottomBar`、6 大管理抽屉（含 `_draw` 财务趋势图）、3 大弹窗、`DailyReportOverlay` |

---

## 2. 本地工具链与标准验证命令

> [!IMPORTANT]
> 多个 Agent 并行访问同一个 Godot 工程目录时，`.godot/` 缓存会被并发读写。**所有 Agent 必须通过 `bank_tycoon_demo/tools/godot.ps1` 运行 Godot**（内置系统级全局命名互斥锁 `Global\StarwayBankGodotRunner`）。

- **Godot 4.7.2 Stable 控制台可执行程序**：
  `D:\project\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Godot 4.7.2 Stable GUI 可执行程序**：
  `D:\project\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
- **Python 环境**：`Python 3.14.4` + `Pillow (PIL)`

### 标准命令速查表

```powershell
# 1. 重新生成 60 张调色板锁定像素 PNG 资产（幂等、确定性 SHA-256）
python bank_tycoon_demo/tools/generate_pixel_assets.py

# 2. 重新生成 12 个 16-bit 44.1kHz PCM WAV 音频资产（1 首 BGM + 11 种 SFX）
python bank_tycoon_demo/tools/generate_audio_assets.py

# 3. 合并各模块三语分片 (*.zh_CN.json / *.en.json / *.ja.json) 生成总表与 gettext .pot/.po
python bank_tycoon_demo/tools/build_po.py

# 4. Godot 资源导入与全局类缓存刷新（新增或重命名 class_name 后必跑）
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --import

# 5. 运行全量主测试套件（含 Tier 1-4 共 108 项黑盒 E2E 与 30 天确定性模拟）
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --script res://tests/run_tests.gd

# 6. 单独运行各分层单元/集成测试
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --script res://tests/unit/test_domain.gd
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --script res://tests/unit/test_infra.gd
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --script res://tests/integration/test_sim_app.gd
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --script res://tests/unit/test_world.gd

# 7. 120 帧启动冒烟测试
powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 --quit-after 120
```

---

## 3. 当前已完成工作进度与代码结构图

### 3.1 `bank_tycoon_demo/` 完整目录结构

```text
bank_tycoon_demo/
├── project.godot                       # Godot 4.7.2, GL Compatibility, 1280x720 canvas_items, 5 Autoloads
├── default_bus_layout.tres             # Master / BGM / SFX 三总线音频布局
├── docs/
│   ├── TEAM_CONTRACTS.md               # 模块接口契约与并行开发规范
│   └── screenshots/                    # 5 张实机运行验收截图
├── tools/
│   ├── godot.ps1                       # 带全局互斥锁的 Godot 4.7.2 Headless 运行器
│   ├── generate_pixel_assets.py        # 程序化像素资产生成器 (60 PNGs)
│   ├── generate_audio_assets.py        # 程序化音频合成器 (12 WAVs)
│   └── build_po.py                     # 多语言 JSON 分片合并与 gettext PO/POT 生成器
├── assets/
│   ├── environment/                    # 17 张 2:1 等距地砖、剖面墙、4帧星海喷泉、柜台、信贷桌、金库门、ATM、绿植
│   ├── characters/                     # 6 名员工 + 6 类客户 4x4 动画帧表 (96x128) 及 32x32 头像 (共 24 张)
│   ├── icons/                          # 19 张 16x16 / 24x24 科技蓝 UI 与状态像素图标
│   └── audio/                          # bgm_starway_lobby.wav + 11 个交互/业务 SFX
├── data/
│   ├── departments.json                # 4 大核心部门 (operations, hr, credit, risk)
│   ├── policies.json                   # 2 条互斥 3 节点国策路线 (稳健 vs 激进，共 6 项)
│   ├── events.json                     # 10 个事件（含 3 阶段房地产繁荣->降温->信贷压力宏观事件链）
│   ├── traits.json                     # 6 种员工特质
│   └── customers.json                  # 6 类客户画像与业务权重
├── localization/
│   ├── core.{zh_CN,en,ja}.json         # 核心领域与内容翻译分片
│   ├── sim.{zh_CN,en,ja}.json          # 模拟与运营日志翻译分片
│   ├── world.{zh_CN,en,ja}.json        # 2.5D 世界层气泡与特效翻译分片
│   ├── hud.{zh_CN,en,ja}.json          # 顶栏/导航/检视器/底栏/主菜单翻译分片
│   ├── panels.{zh_CN,en,ja}.json       # 6 大抽屉/3 大弹窗/日终报告翻译分片
│   ├── {zh_CN,en,ja}.json              # 合并后的完整三语字典 (566 Keys)
│   └── messages.pot, {zh_CN,en,ja}.po  # 标准 gettext 翻译文件
├── scripts/
│   ├── shared/                         # 纯数据与工具类 (零 Node 依赖)
│   │   ├── content_id.gd               # 命名空间 ID 校验 (^[a-z0-9_.-]+:[a-z0-9_.-]+$)
│   │   ├── result.gd                   # 统一返回结构 Result (ok, error_code, error_key, error_params, data)
│   │   ├── enums.gd                    # 全局枚举与映射
│   │   ├── balance_config.gd           # 集中经济与模拟平衡常量
│   │   ├── domain_event.gd             # 领域事件 DTO
│   │   └── format_service.gd           # 货币(分->元)、基点(bps->%)、时间(HH:MM)格式化
│   ├── domain/                         # 纯领域核心 (RefCounted, 零 Node/SceneTree 依赖)
│   │   ├── rng_streams.gd              # 确定性随机数子流 (customer/event/market/candidate_rng)
│   │   ├── journal_entry.gd            # 复式记账凭证行与借贷平衡校验
│   │   ├── ledger.gd                   # 11 科目双分录账本 (Assets == Liabilities + Equity + Income - Expense)
│   │   ├── finance_engine.gd           # 存取款、放贷、信用评分、10 步幂等日终结算与报告生成
│   │   ├── employee.gd                 # 员工实体、7 维属性、疲劳、换岗适应期与状态机
│   │   ├── customer.gd                 # 客户实体、耐心衰减与状态机
│   │   ├── loan.gd                     # 贷款实体与生命周期
│   │   ├── service_request.gd          # 服务请求与严格优先级队列排序
│   │   ├── modifier_service.gd         # 白名单效果聚合器 (add -> multiply -> set + 上下限钳制 + 部门协同)
│   │   ├── department_service.gd       # 部门成立、升级、能力解锁与协同判定
│   │   ├── policy_service.gd           # 国策前置条件、策略点消耗与互斥分支校验
│   │   ├── event_engine.gd             # 条件触发、冷却期、权重抽取与 next_event_id 事件链推进
│   │   └── bank_state.gd               # 银行根状态聚合与完整 JSON 序列化/反序列化
│   ├── autoload/                       # 严格限定的 5 个全局服务
│   │   ├── localization_service.gd     # 4 级回退翻译服务 + 防覆盖保护
│   │   ├── content_registry.gd         # 原版 JSON 与 user://mods (目录/ZIP) 安全加载器
│   │   ├── audio_service.gd            # BGM 循环播放 + 8 路 SFX 池 + 音量持久化
│   │   ├── save_service.gd             # 原子 JSON v1 存档 (.tmp 校验 -> .bak 轮换 -> 损坏自动回退)
│   │   └── game_session.gd             # 会话生命周期与全局设置同步
│   ├── simulation/                     # 实时模拟层
│   │   ├── game_clock.gd               # 固定步长累加器 (0x/1x/2x/3x, MAX_TICKS_PER_FRAME=5)
│   │   ├── employee_dispatcher.gd      # 可解释派工评分与运营部 Lv.2 自动提权
│   │   └── branch_simulation.gd        # 固定 8 步 minute_tick 营业日循环
│   ├── app/                            # 应用编排与命令层
│   │   ├── domain_event_bus.gd         # 领域事件总线 (domain_event_emitted + event_published)
│   │   ├── bank_command_service.gd     # 17 个业务写命令 + 4 个可用性查询接口
│   │   └── simulation_host.gd          # 挂载于 GameRoot 下的模拟宿主与 HUD 快照生成
│   └── presentation/                   # 表现层 (2.5D 世界 + 星海蓝 UI)
│       ├── world/                      # iso_grid.gd, pixel_camera_2d.gd, service_station_view.gd, actor_view.gd, bank_world.gd
│       └── ui/                         # starway_theme.gd, ui_i18n.gd, main_menu.gd, game_root.gd, top_bar.gd, left_navigation.gd, right_inspector.gd, bottom_bar.gd, finance_chart.gd, daily_report_overlay.gd, toast_bar.gd, drawers/*, modals/*
├── scenes/
│   ├── menus/main_menu.tscn
│   ├── gameplay/game_root.tscn
│   ├── world/bank_world.tscn
│   └── ui/daily_report_overlay.tscn
└── tests/
    ├── run_tests.gd                    # 自动化总测试入口
    ├── unit/                           # test_domain.gd (351), test_infra.gd (88), test_world.gd (507)
    ├── integration/                    # test_sim_app.gd (81)
    └── e2e/                            # run_e2e_tests.gd, e2e_harness.gd, test_tier1..4.gd (108 项 E2E 测试)
```

### 3.2 对照 `tasks/IMPLEMENTATION_BACKLOG.md` 的完成状态映射

| Backlog 任务 ID | 任务名称 | 当前状态 | 对应实现文件与测试覆盖 |
|---|---|:---:|---|
| `BT-000` | Godot 工程初始化 | **已完成** | `bank_tycoon_demo/project.godot`, `default_bus_layout.tres`, `starter_project/` 原样保留 |
| `BT-001` | 核心类型与 ID 规范 | **已完成** | `scripts/shared/content_id.gd`, `result.gd`, `enums.gd`, `domain_event.gd` |
| `BT-002` | 主世界场景与像素相机 | **已完成** | `scenes/world/bank_world.tscn`, `bank_world.gd`, `pixel_camera_2d.gd` (`Nearest` + 1x/2x/3x 整数缩放) |
| `BT-003` | 交互设施和逻辑导航网格 | **已完成** | `iso_grid.gd` (`18×12` 2:1 等距 + `AStarGrid2D`), `service_station_view.gd` |
| `BT-004` | 角色占位与基础动画 | **已完成** | `actor_view.gd` + 12 套 `4×4` 角色 SpriteSheet (`Idle/Walk/Work/Talk`) + 12 张 32×32 头像 |
| `BT-005` | `GameClock` 固定步长 | **已完成** | `scripts/simulation/game_clock.gd` (`0x/1x/2x/3x`, `MAX_TICKS_PER_FRAME=5`, 0.25s/1.0s 切换) |
| `BT-006` | Customer/Employee 领域状态机 | **已完成** | `scripts/domain/employee.gd`, `customer.gd` |
| `BT-007` | `ServiceRequest` 队列 | **已完成** | `scripts/domain/service_request.gd` (`VIP > PRIORITY > NORMAL > time > id`) |
| `BT-008` | `EmployeeDispatcher` | **已完成** | `scripts/simulation/employee_dispatcher.gd` |
| `BT-009` | 客户完整大厅链路 | **已完成** | `scripts/simulation/branch_simulation.gd` (进门->寻路->排队->服务->入账->离开/超时退场) |
| `BT-010` | `Ledger` 双分录账本 | **已完成** | `scripts/domain/ledger.gd`, `journal_entry.gd` (11 科目强平衡校验，500 条上限) |
| `BT-011` | `FinanceEngine` | **已完成** | `scripts/domain/finance_engine.gd` (整数分、基点利率 `round_div`、信用评分) |
| `BT-012` | `DailySettlement` 与报告 DTO | **已完成** | `finance_engine.gd::run_daily_settlement` (10 步幂等日终结算与归因报告) |
| `BT-013` | 招聘与候选人系统 | **已完成** | `bank_command_service.gd::hire_candidate/train_employee/rest_employee/fire_employee` |
| `BT-014` | 部门定义/实例与管理 | **已完成** | `department_service.gd`, `data/departments.json` (运营/HR/信贷/风控 Lv.1–3 机制解锁) |
| `BT-015` | `ModifierService` 与部门协同 | **已完成** | `modifier_service.gd` (`add->multiply->set` + `HR+运营`、`信贷+风控` 协同) |
| `BT-016` | Policy 系统 | **已完成** | `policy_service.gd`, `data/policies.json` (稳健 vs 激进 2 条互斥 3 节点路线) |
| `BT-017` | 事件调度器与事件链 | **已完成** | `event_engine.gd`, `data/events.json` (10 个事件含 3 阶段房地产宏观事件链) |
| `BT-018` | 主 HUD 与 Inspector | **已完成** | `game_root.gd`, `top_bar.gd`, `left_navigation.gd`, `right_inspector.gd`, `bottom_bar.gd` |
| `BT-019` | 招聘/部门/政策/事件/贷款弹窗与抽屉 | **已完成** | `scripts/presentation/ui/drawers/*`, `modals/*`, `finance_chart.gd` (`_draw` 趋势图) |
| `BT-020` | 日终报告 UI | **已完成** | `scenes/ui/daily_report_overlay.tscn`, `daily_report_overlay.gd` |
| `BT-021` | `SaveService` 原子存档 | **已完成** | `scripts/autoload/save_service.gd` (`save_version=1`, `.tmp`->`.bak` 原子轮换与损坏恢复) |
| `BT-022` | 原版多语言 | **已完成** | `localization_service.gd`, `localization/*.{json,po,pot}` (`zh_CN`/`en`/`ja` 566 Keys) |
| `BT-023` | Mod Manifest / `ContentRegistry` | **已完成** | `scripts/autoload/content_registry.gd` (支持文件夹与 `.zip` Mod、Kahn 拓扑排序) |
| `BT-024` | Mod 安全和兼容测试 | **已完成** | 路径穿越、禁用脚本/SVG、`eval` 拦截、重复 ID、悬空引用、整包原子回滚、缺 Mod 存档告警 |
| `BT-025` | 30 天 End-to-End 场景 | **已完成** | `E2E_T4_01` ~ `E2E_T4_08` (30 天确定性重放一致性、零崩溃、每日账平) |
| `BT-026..029` | Phase 7 内容扩展（非 MVP） | **待开发 (TODO)** | 见下方第 4 节多 Agent 后续开发任务包规划 |

### 3.3 当前自动化测试基线（任何新 Agent 提交前必须保持 100% 绿灯）

| 测试套件 | 运行脚本 | 用例 / 断言数 | 当前状态 |
|---|---|---:|---|
| 领域层单元测试 (M2) | `res://tests/unit/test_domain.gd` | **351 项断言** | **351 / 351 PASS** |
| 基础设施与 Mod/存档/多语言测试 (M3) | `res://tests/unit/test_infra.gd` | **88 项断言** | **88 / 88 PASS** |
| 实时模拟与应用命令集成测试 (M4) | `res://tests/integration/test_sim_app.gd` | **81 项断言** | **81 / 81 PASS** |
| 2.5D 等距世界与相机寻路测试 (M5) | `res://tests/unit/test_world.gd` | **507 项断言** | **507 / 507 PASS** |
| 黑盒需求驱动 E2E 测试套件 (Tier 1–4) | `res://tests/run_tests.gd` | **108 个端到端场景** | **108 / 108 PASS** |

---

## 4. 后续开发 TODO 与多 Agent 并行分派路标

当前核心垂直切片 Demo 已全部交付并验证通过。后续演进可拆分为 **6 个互不冲突的独立工作包（Work Packages, WP-A ~ WP-F）**，你可以直接将任意一个 `WP-x` 复制分派给对应的 AI Agent 并行开发。

### WP-A：内置可视化 Mod 管理器与自定义设置扩展（UI + Infra 扩展）
- **目标**：在主菜单与暂停菜单新增可视化「Mod 管理器（Mod Manager）」弹窗，展示 `ContentRegistry.reload_all()` 返回的 `ModLoadReport`（已加载 Mod、作者、版本、依赖、被拒绝 Mod 及具体原因），支持一键刷新 Mod 列表。
- **负责文件边界**：
  - 新增 `bank_tycoon_demo/scripts/presentation/ui/modals/mod_manager_modal.gd`
  - 修改 `main_menu.gd`、`pause_save_settings_modal.gd` 增加入口按钮
  - 新增 `localization/panels.{zh_CN,en,ja}.json` 中的 `UI_MOD_MGR_*` 翻译键并运行 `python bank_tycoon_demo/tools/build_po.py`
- **验收标准**：能可视化显示 `examples/mod_template` 的加载状态与被拒 Mod 的错误原因；`godot.ps1 --script res://tests/run_tests.gd` 保持 108/108 通过。

### WP-B：大厅角色四方向行走、员工拖拽派工手势与视觉细节深化（World 2D 扩展）
- **目标**：
  1. 在 `bank_world.gd` / `actor_view.gd` 中支持鼠标**直接将员工 Actor 拖拽到目标柜台 (`ServiceStationView`)** 完成 `assign_employee_to_station` 命令（拖拽失败时通过 `ToastBar` 显示翻译原因并播放 `sfx_ui_error`）；
  2. 根据移动方向向量自动镜像/切换角色朝向，丰富柜台办理时的金币/文件粒子反馈与喷泉光晕细节。
- **负责文件边界**：
  - `bank_tycoon_demo/scripts/presentation/world/actor_view.gd`、`bank_world.gd`、`service_station_view.gd`
  - `bank_tycoon_demo/tests/unit/test_world.gd`
- **验收标准**：支持点击选中指派与拖拽指派双路径；`test_world.gd` 与 `run_tests.gd` 100% 通过。

### WP-C：进阶部门扩展（市场营销部、信息科技部、合规部、企业金融部 — 对接 `BT-027`）
- **目标**：在 `data/departments.json`、`department_service.gd`、`modifier_service.gd` 和 `bank_world.gd` 中扩展第 2 批部门：
  - `core:department.marketing`（市场营销部）：提升高价值/VIP 客户到访率，与企业金融部产生协同；
  - `core:department.it`（信息科技部）：激活大厅 ATM 自助终端自动分流小额存取款请求，降低柜台排队压力（`IT + 运营` 协同）；
  - `core:department.compliance`（合规部）：自动识别并拦截 `suspicious` 可疑客户高风险交易，获得监管奖励并规避合规处罚事件。
- **负责文件边界**：
  - `bank_tycoon_demo/data/departments.json`、`data/events.json`
  - `bank_tycoon_demo/scripts/domain/department_service.gd`、`modifier_service.gd`
  - `bank_tycoon_demo/scripts/simulation/branch_simulation.gd`（ATM 自助分流与合规拦截逻辑）
  - `bank_tycoon_demo/localization/core.{zh_CN,en,ja}.json`
- **验收标准**：新部门完全符合 `schemas/department.schema.json`；原 4 大核心部门测试不受影响；新增单元测试验证 ATM 自动分流与可疑客户拦截。

### WP-D：第三条国策路线「数字金融科技（Fintech Banking）」与候选人互动面试（策略深度扩展）
- **目标**：
  1. 在 `data/policies.json` 与 `policies_drawer.gd` 中新增第 3 条互斥策略分支 **数字金融科技路线**（`core:policy.digital_onboarding` -> `core:policy.algorithmic_credit` -> `core:policy.open_banking_ecosystem`）；
  2. 在 `employees_drawer.gd` 中增加候选人「简短面试问答」交互（揭示候选人隐藏特质 `traits.json` 并影响入职期望薪资）。
- **负责文件边界**：
  - `bank_tycoon_demo/data/policies.json`
  - `bank_tycoon_demo/scripts/domain/policy_service.gd`
  - `bank_tycoon_demo/scripts/presentation/ui/drawers/policies_drawer.gd`、`employees_drawer.gd`
  - `bank_tycoon_demo/localization/core.{zh_CN,en,ja}.json`、`panels.{zh_CN,en,ja}.json`
- **验收标准**：3 条国策路线两两互斥、各自拥有 3 个递进节点；`run_tests.gd` 108/108 通过。

### WP-E：竞争对手银行与市场份额系统（对接 `BT-026`）
- **目标**：引入 2–3 家 AI 竞争对手银行（如「磐石储蓄银行」「极光数字银行」），按日动态调整竞争存款/贷款利率；玩家在「财务/市场」面板可观察市场平均利率与本行存款竞争力指数，触发挖角与利率战事件。
- **负责文件边界**：
  - 新增 `bank_tycoon_demo/scripts/domain/market_competitor_service.gd`（纯 `RefCounted`，零 Node 依赖）
  - 在 `BankState` 中序列化 `competitors: Array[Dictionary]`（保持 `from_dict` 向后兼容缺省字段）
  - 在 `finance_drawer.gd` 或独立 `market_drawer.gd` 中展示市场利率对比曲线。
- **验收标准**：遵守 `scripts/domain/` 零 Node 约束；旧存档缺省 `competitors` 字段可平滑加载；30 天模拟保持 100% 确定性。

### WP-F：沙盒/挑战目标模式与成就系统（对接 `BT-029`）
- **目标**：在 `MainMenu`「新游戏」流程支持选择经营模式：
  1. **30 天标准挑战**（达成目标净资产、满意度与不良率评级，第 30 天日终弹出完整评级通关证书）；
  2. **自由无尽沙盒**（可自定义初始资金、无限天数）；
  3. **危机挽救剧本**（初始高不良率与低流动性，限时扭亏为盈）。
- **负责文件边界**：
  - `bank_tycoon_demo/scripts/domain/milestone_service.gd`
  - `bank_tycoon_demo/scripts/presentation/ui/main_menu.gd`、`daily_report_overlay.gd`
- **验收标准**：各剧本均通过 `GameSession.start_new_game` 启动，不破坏现有默认参数的测试兼容性。

---

## 5. 给新加入 Agent 的标准启动提示词模板

当你需要指派一个新的 AI Agent 执行上述任一任务包时，可以直接复制以下提示词：

```text
请先阅读根目录的 `AGENTS.md`、`AGENT_HANDOVER_AND_ROADMAP.md` 以及 `bank_tycoon_demo/docs/TEAM_CONTRACTS.md`。
本次请负责实现 `AGENT_HANDOVER_AND_ROADMAP.md` 第 4 节中的【WP-X：<填入任务包名称>】。

严格约束：
1. 只修改该任务包授权边界内的文件，不触碰 `starter_project/`。
2. `scripts/domain/` 与 `scripts/shared/` 必须保持纯 `RefCounted`（零 Node / SceneTree / UI 依赖）。
3. 所有玩家可见文本必须写入 `localization/*.{zh_CN,en,ja}.json` 并运行 `python bank_tycoon_demo/tools/build_po.py` 同步 `.po/.pot`。
4. 所有 Godot 命令必须通过 `powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 <args>` 执行。
5. 完成后必须运行 `godot.ps1 --import` 和 `godot.ps1 --script res://tests/run_tests.gd`，确保原有 108 项 E2E 测试与你新增的测试 100% 通过。
```
