# 08 — 美术资产生产与导入流水线

## 1. 资产生产策略

AI 用于生成概念图、单体家具、角色姿势参考和 SpriteSheet 初稿；人工/工具流程负责清理、切片、对齐、透明边缘检查、动画整理和游戏内验证。Godot 负责 UI、数字、文字和动态状态。

## 2. 资产分层

- `reference/`：概念图、Moodboard、AI 参考板；不直接进入运行时。
- `production/`：经过像素检查、切片与命名的最终资源。
- `godot_import/`：Godot 导入后资源与 `.import` 元数据，由引擎生成。

项目仓库可保留生产资产源文件；概念图仅用于方向说明。

## 3. 推荐目录

```text
art/
├── reference/
├── characters/
│   ├── employees/
│   ├── customers/
│   └── portraits/
├── environment/
│   ├── tiles/
│   ├── walls/
│   ├── doors_windows/
│   └── exteriors/
├── furniture/
├── stations/
├── icons/
├── ui/
└── vfx/
```

## 4. 文件命名

格式：`{category}_{subject}_{state_or_variant}_{index}.{ext}`。

例：
- `char_teller_idle_down_01.png`
- `char_customer_walk_left_01.png`
- `furn_counter_straight_01.png`
- `tile_floor_ivory_center_01.png`
- `icon_department_hr_16.png`
- `ui_panel_cream_9slice.png`

文件名使用英文小写 snake_case；展示名称由翻译 Key 提供。

## 5. 资产记录表

所有正式资产应记录：Asset ID、文件路径、类型、画布尺寸、帧数、帧宽高、锚点、光源方向、调色板版本、生成/作者来源、许可证/使用权检查、是否验收。

## 6. Godot 导入规范

- 像素 Sprite 使用 Nearest 纹理过滤。
- 关闭不适用的有损压缩；UI/精细 Sprite 保持无损。
- 不对角色 Sprite 自动生成模糊 mipmap。
- SpriteSheets 使用明确的 HFrames/VFrames 或 SpriteFrames 资源。
- 贴图尺寸和帧布局必须在 metadata 中可追溯。
- 每批资产导入后，至少在主场景中检查 1x/2x/3x 和多个窗口尺寸。

## 7. 角色动画验收

- 同一角色所有动作保持轮廓、衣服、脸部和尺寸一致。
- Walk 循环首尾无明显跳帧。
- Work 动作不改变人物身高/锚点。
- 人物在地面上脚底锚点一致。
- 不发生透明边缘光晕、孤立脏像素或不统一像素密度。

## 8. 概念图索引

| 文件 | 作用 | 是否正式资产 |
|---|---|---|
| `00_selected_pixel_art_style_reference.png` | 用户选定的像素风格来源图；参考角色比例、场景密度和 UI 分区 | 否，参考图 |
| `01_gameplay_green_palette_direction.png` | 新配色方向下的主经营画面概念 | 否，参考图 |
| `02_system_and_ui_moodboard.png` | 系统面板、事件和政策树的布局参考 | 否，参考图；其蓝紫配色不作为最终规范 |
| `03_asset_and_interface_moodboard.png` | 资产分类、人物/设施/面板的构成参考 | 否，参考图；以 Art Bible 调色板为准 |
| `04_full_game_design_moodboard.png` | 产品整体构成、场景与技术内容汇总参考 | 否，参考图；不是可读规格文档 |

## 9. 生产优先级

P0：主大厅地面/墙体/柜台/入口/等待区/员工和客户占位角色。  
P1：基础人物 Idle/Walk/Work、队列设施、图标、主 UI 面板。  
P2：部门专属空间、头像、事件插图和政策图标。  
P3：分行外观、VIP 装饰、特殊客户和高级部门视觉。

## 10. 生成式美术的边界

- AI 生成概念图不得当作真实游戏内 UI 图。
- AI 生成文字通常有误，必须移除或不使用。
- 需要透明背景的素材必须检查 alpha channel。
- 对有版权/商标风险的内容使用原创形象，不要求模仿在售游戏的具体角色或 UI。
- 在制作每一类素材前先完成一张通过验收的 Gold Master，后续以它为一致性参考。
