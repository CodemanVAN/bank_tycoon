# 12 — 设计与技术决策记录（ADR）

| ID | 决策 | 状态 | 原因 |
|---|---|---|---|
| ADR-001 | 使用 Godot 4.7.2 Stable | Accepted | 当前稳定版；避免使用 4.8 Beta |
| ADR-002 | GDScript 静态类型优先 | Accepted | 降低跨模块耦合和 AI 生成代码错误 |
| ADR-003 | 2D 16-bit inspired Pixel Art | Accepted | 用户选择像素风作为正式风格基准 |
| ADR-004 | 正视角 3/4 俯视银行剖面视图（32×20 正交矩形网格） | Accepted (Updated) | 统一所有正视角像素家具/墙面/角色与地板透视（替代早期 45° 斜菱形地板），保留大厅空间可读性与直观的水平/垂直扩建手感 |
| ADR-005 | 正式视觉与 UI 采用「星海银行 Starway Bank」现代科技蓝配色体系，搭配暖木/米白像素大厅 | Accepted (Updated) | UI 采用深空海军蓝（`#081B36`）、暗夜面板（`#0B2D5B`）、科技蓝（`#1F6FEB`）、青色高光（`#00C6FF`）与金融金/成长绿/警示红语义色（`#FFC857`/`#35C978`/`#E74C3C`），场景室内以暖木/米白/绿植平衡冷色 UI（参考 `art/01_visual/starway_bank_modern_tech_blue_master_reference.png`、`art/02_tokens/` 与 `art/03_guidelines/art_direction.md`） |
| ADR-006 | 1280×720 逻辑分辨率 + `canvas_items` (`expand`) + `World` 层 `CanvasItem.TEXTURE_FILTER_NEAREST` 与 `PixelCamera2D` 1x/2x/3x 整数缩放 | Accepted (Updated) | 在 1080p/2K 显示器上同时保证中英日现代 HUD 高密度可读性与 2.5D 像素大厅锐利颗粒感（UI 流畅缩放，`World` 层独立保持 `TEXTURE_FILTER_NEAREST` 与 1x/2x/3x 整数倍相机缩放） |
| ADR-007 | 固定步长模拟，与渲染帧率分离 | Accepted | 保证暂停/加速和确定性测试 |
| ADR-008 | Domain 与 Scene/UI 分离 | Accepted | 支持可测试、可扩展架构 |
| ADR-009 | 首发 Mod 采用数据型 JSON/ZIP/PNG | Accepted | 面向普通玩家，降低代码执行风险 |
| ADR-010 | 原版 PO/MO，Mod JSON 翻译 | Accepted | 兼顾 gettext 工作流和运行时 Mod 内容 |
| ADR-011 | 存档保存领域数据，不序列化整个场景树 | Accepted | 便于迁移、调试和 Mod 兼容 |
| ADR-012 | 财务金额整数最小单位，利率基点整数 | Accepted | 避免浮点误差和账务不一致 |
| ADR-013 | 第一阶段单分行，不做复杂全城经营 | Accepted | 优先验证大厅实时运营和组织成长 |

## 尚待通过试玩确认

- `1280×720` `canvas_items` (`expand`) 在 1080p/2K/超宽屏下的 HUD 信息密度与留白比例是否舒适（已替代原 `640x360` 草案）。
- Demo 默认采用试玩营业节奏 `0.25s/min`（1x 约 2 分钟/营业日，3x 约 40 秒/日），并在设置菜单提供 GDD 标准节奏 `1.0s/min`（1x 约 8 分钟/日）切换开关；待试玩确认正式版默认档位（两种模式均基于固定步长 `minute_tick`，不影响经济结果）。
- 主场景 2:1 轻等距 `AStarGrid2D` 在大厅拥挤时的寻路清晰度与点击选中手感。
- 银行币种默认 CNY 还是虚构币种；当前文档以 CNY/通用金融符号作示例。
