# Bank Tycoon / 银行大亨 — Production Kit

> 面向 Godot 4.7.2 的 2D 像素风银行经营模拟游戏设计与开发工程包。本文档包是项目的唯一设计基线（single source of truth），不是已经完成的游戏。

## 快速开始

1. 阅读本文件和根目录的 `AGENTS.md`。
2. 阅读 `docs/00_PRODUCT_BRIEF.md`、`docs/01_GDD.md`、`docs/02_TDD.md`。
3. 在 Godot 4.7.2 Stable 中打开 `starter_project/project.godot`，确认项目可运行。
4. 按 `tasks/IMPLEMENTATION_BACKLOG.md` 的任务顺序逐项让 AI Agent 开发；每个任务单独提交和验收，不要让 Agent 一次性实现整个游戏。
5. 开始制作正式美术前，先阅读 `docs/04_ART_BIBLE.md`。`art/reference/` 中所有图片均为视觉概念参考，不是可直接切片投入游戏的最终 SpriteSheet。

## 文件地图

| 路径 | 用途 |
|---|---|
| `AGENTS.md` | 给所有 AI 编程 Agent 的全局工作规则 |
| `AGENT_START_PROMPT.md` | 可直接复制给编程 Agent 的启动提示词 |
| `ART_REFERENCE_README.md` | 视觉参考图片索引与权威性说明 |
| `art/ASSET_MANIFEST.csv` | 概念图/美术资产清单 |
| `docs/00_PRODUCT_BRIEF.md` | 产品定位、约束和关键决策 |
| `docs/01_GDD.md` | 完整游戏设计：循环、经济、部门、员工、国策、事件、进度 |
| `docs/02_TDD.md` | Godot 架构、节点、模拟时钟、状态机、事件、数据流 |
| `docs/03_ECONOMY_SPEC.md` | 银行账务模型、经济公式、风险、结算规则 |
| `docs/04_ART_BIBLE.md` | 像素美术规范、调色板、尺寸、AI 素材提示词和验收标准 |
| `docs/05_UI_UX_SPEC.md` | 屏幕结构、交互原则、响应式布局和无障碍要求 |
| `docs/06_MODDING_SPEC.md` | Mod 目录、Manifest、内容 Schema、效果 API、安全规则 |
| `docs/07_LOCALIZATION_AND_SAVE.md` | 多语言、存档格式、版本迁移和兼容性 |
| `docs/08_ASSET_PIPELINE.md` | 美术资产目录、命名、导入与生产流程 |
| `docs/09_QA_ACCEPTANCE.md` | 自动化测试、功能验收和性能验收标准 |
| `docs/10_ROADMAP.md` | 分阶段开发路线、MVP 边界和里程碑 |
| `docs/11_AI_AGENT_WORKFLOW.md` | Agent 分段开发方法和任务模板 |
| `docs/12_DECISION_LOG.md` | 已确定的技术和设计决策记录 |
| `tasks/IMPLEMENTATION_BACKLOG.md` | 可直接分配给 Agent 的实施任务 |
| `schemas/` | Mod JSON Schema / 示例数据格式 |
| `examples/mod_template/` | 一个最小数据型 Mod 示例 |
| `starter_project/` | 可打开的 Godot 项目骨架，不含完整玩法实现 |
| `art/reference/` | 已生成的概念图和美术参考板 |

## 当前产品范围

- 2D、桌面优先、单机经营模拟。
- 日内实时经营（暂停 / 1x / 2x / 3x），日终结算推进长期经营。
- 从一间小型银行起步，招聘员工、建立部门、发展银行策略、应对宏观经济和事件。
- 支持原版简体中文、英语、日语；内容系统从设计上支持 Mod 多语言。
- 第一阶段 Mod 仅允许数据、图片和音频类内容；默认不执行第三方 GDScript。

## 版本和状态

- 文档版本：`0.1.0`（初版生产设计基线）
- 目标引擎：Godot `4.7.2-stable`
- 游戏名：`Bank Tycoon`（工作名称，正式名称待确认）
- 状态：设计与工程方案；`starter_project/` 只是启动骨架，当前制作环境未安装 Godot 可执行程序，因此尚未完成引擎内打开/运行验证。请在本机 Godot 4.7.2 Stable 中先验证 BT-000。

## 设计资料的权威顺序

如文档内容冲突，按以下顺序解决：

1. `docs/12_DECISION_LOG.md` 中状态为 Accepted 的决策。
2. `docs/01_GDD.md`、`docs/02_TDD.md` 中的系统规范。
3. 其他专题文档。
4. `art/reference/` 概念图片（仅用于视觉方向，不覆盖文字规范）。

任何 Agent 发现冲突，必须先在任务结果中指出，不得自行悄悄改变既定方向。
