# 04 — 美术圣经（Art Bible）

## 1. 最终风格方向

**采用：16-bit inspired Pixel Art（16 位机能感像素美术）+ 俯视轻等距银行空间 + Q 版员工/客户。**

风格基准为 `art/reference/00_selected_pixel_art_style_reference.png`；配色调整方向以 `01_gameplay_green_palette_direction.png` 为准。其他 moodboard 仅用于观察面板布局、场景分区和信息密度，不覆盖本文件规定的调色板。

### 关键词

- crisp pixel clusters（清晰像素色块）
- warm, readable, slightly cozy financial world（温暖、易读、轻松的金融世界）
- isometric cutaway bank interior（轻等距剖面银行内部）
- consistent sprite scale and outline（统一精灵比例和轮廓）
- restrained highlights, no glossy realism（克制高光，不做写实光泽）

### 禁止方向

- 不要 3D 渲染、照片级写实、矢量扁平插画或平滑渐变。
- 不要每张素材采用不同像素密度、不同视角或不同光源。
- 不要把按钮、文字、数字、进度条、菜单、UI 数据烘焙进背景图。
- 不要让生成图的模糊边缘或抗锯齿破坏像素颗粒。

## 2. 调色板（权威颜色）

原参考图的紫蓝色仅作风格来源；正式游戏采用更稳重、温暖的银行配色：

| Token | HEX | 用途 |
|---|---|---|
| `INK_GREEN` | `#203A34` | 主 UI 深色底、顶部栏、文字反色底 |
| `DEEP_FOREST` | `#2B4B40` | 深层面板、建筑主结构、重点容器 |
| `SAGE` | `#83A58B` | 正向状态、分区、次级强调 |
| `MINT_PALE` | `#C8D9C8` | 选中/可用背景、轻提示 |
| `WARM_IVORY` | `#F2E9D7` | 主面板、地板和浅色背景 |
| `PAPER` | `#E5D7BD` | 次级面板、纸张和卡片 |
| `BRASS` | `#D4A653` | 金融、金币、升级、重要行动 |
| `TERRACOTTA` | `#C96E55` | 危险、警告、投诉/风险 |
| `CHARCOAL` | `#343B36` | 轮廓、正文深色文字 |
| `GREY_GREEN` | `#9A9F90` | 禁用、次级信息、背景设施 |

### 配色比例

- 60% 暖象牙白/纸色（空间与面板主体）。
- 25% 深森林绿/墨绿（框架、顶栏、主要 UI）。
- 10% 鼠尾草绿/浅薄荷（状态和次级强调）。
- 5% 黄铜金/砖红（关键操作和警告）。

颜色必须有语义：绿色表示稳定/正向，金色表示价值/升级/高优先级，砖红表示危险/风险，灰绿表示禁用或低优先级。不能仅靠颜色表达关键信息，必须配图标或文字。

## 3. 像素技术规范

### 画布和逻辑分辨率

- 逻辑 Viewport：`640 x 360`（16:9）。
- 窗口默认：`1280 x 720`；运行时可调整窗口大小。
- 1080p 以 3x 整数缩放呈现。
- Godot：Stretch Mode `viewport`；Scale Mode `integer`；Aspect 推荐 `expand`，UI 使用锚点适配额外面积。
- 默认纹理过滤：Nearest；不要对像素 Sprite 使用线性过滤。
- 2D 位置尽量像素对齐；避免非整数缩放和不必要的旋转。

### 世界网格

- 逻辑格：16 x 16 px 基础单位。
- 视觉地面等距菱形建议 32 x 16 px；家具可使用 32/48/64 px 的组合画布。
- 人物基础帧建议 16 x 24 或 20 x 28 px；重要角色可用 24 x 32 px，但需保持比例一致。
- 主场景通过多个模块组合，不生成一张完整不可编辑的大背景。

### 轮廓与阴影

- 统一 1 px 深色轮廓；近景大型物件可用局部 2 px 强调。
- 光源统一从左上方；阴影向右下方。
- 阴影颜色使用环境色深一档，不使用纯黑大面积填充。
- 高光克制，避免金属和玻璃过度写实。

## 4. 场景视角和图层

- 银行大厅采用俯视轻等距/2:1 视觉比例；墙体采用剖面/切开视图，确保室内可见。
- 地面、墙、门窗、柜台、家具、装饰、角色、前景遮挡分层。
- 角色和可遮挡家具统一 Y-sort；前景玻璃墙/树冠等放在独立前景层。
- 可交互设施拥有明确交互锚点和导航格。
- 主大厅至少包括：入口、普通柜台、排队区、等待区、客户经理桌、贷款服务点、后台办公室、保险库/现金区、植物/装饰。

## 5. 角色规范

### 角色类型

员工岗位：柜员、客户经理、信贷专员、HR、风险分析员、主管。客户类型：普通储户、工薪客户、借款人、企业客户、VIP、可疑客户。

### 动作集

每个角色最低支持：
- Idle：站立/轻微呼吸（2–4 帧可循环）。
- Walk：四方向或 4 个等距方向（每方向 4–6 帧）。
- Work：柜台/办公/交谈动作（4–6 帧）。
- Talk：短暂对话姿态（2–4 帧）。

首版可减少方向数，但必须在角色资产规范里统一。不得为每个员工单独生成一套完全不同骨架。

### 角色差异化

以发型、肤色、衣服配色、配饰、年龄感和体型小幅变化组合生成。身份识别优先靠轮廓/配色，而不是细小面部细节。

## 6. 建筑和道具资产清单

第一批模块资产：

- 地板：象牙白砖、深绿地毯、VIP 地毯、墙角/边缘/转角。
- 墙体：内墙、外墙、玻璃幕墙、门、窗、入口标识。
- 服务设施：柜台直段/转角/窗口编号、客户经理桌、贷款咨询桌、排队隔离带。
- 家具：办公桌、椅子、沙发、茶几、文件柜、书架、电脑、打印机。
- 银行设施：保险库门、现金抽屉、ATM、自助终端、广告牌。
- 装饰：盆栽、挂画、时钟、灯、垃圾桶、公告栏。
- UI 图标：银行、现金、存款、贷款、客户、员工、部门、政策、事件、风险、时钟、暂停、速度、升级。

## 7. UI 美术规范

- UI 使用 Godot Control 节点绘制，背景切片/边框可以使用像素 9-patch。
- 面板主底：WARM_IVORY；标题栏/导航：INK_GREEN 或 DEEP_FOREST。
- 选中按钮使用 SAGE/MINT_PALE，主要行动用 BRASS，危险按钮用 TERRACOTTA。
- 边框建议 1 px 或 2 px，角部不做大量复杂装饰。
- 字体采用可读像素字体；中文必须选择包含常用汉字的字体文件并检查授权。
- 关键数值不小于 8 px 逻辑字高；重要指标使用更大字级。
- UI 的数字和文本必须动态绘制，不准使用图片中生成的假文字。

## 8. AI 美术资产生成规则

### 每次提示词应固定的要素

`16-bit pixel art, crisp pixel clusters, consistent 2:1 isometric top-down perspective, warm ivory and forest green palette, sage green and brass accents, one light source from upper-left, 1px dark outline, transparent background, no text, no UI, sprite-sheet aligned to a strict grid`。

### 负面要求

`no 3D render, no vector art, no photorealism, no soft blur, no painterly gradients, no purple dominant palette, no blue dominant interface, no embedded labels, no watermark, no inconsistent perspective`。

### 必须人工检查

- 角色轮廓、每帧中心点和画布尺寸。
- 透明背景边缘是否有脏像素。
- 是否混入非像素抗锯齿。
- 光源、地面方向、人物视角是否一致。
- 是否有 AI 伪文字或多余肢体。
- 是否获得可用于商业项目的生成工具授权，并记录资产来源。

**重要：** 概念图不等于 SpriteSheet；正式资产必须单体生成/切片、校正尺寸、像素清理、命名、导入后在 Godot 实际运行检查。

## 9. 推荐资产命名

`environment_floor_ivory_01.png`  
`furniture_teller_counter_straight_01.png`  
`character_teller_idle_down.png`  
`character_customer_walk_left.png`  
`icon_department_hr.png`  
`ui_panel_frame_cream_9slice.png`

不要将角色姓名或语言文本作为图片文件名的一部分。

## 10. AI 提示词模板

### 人物 SpriteSheet

> Create a strict pixel-art sprite sheet for a cozy bank-management game. One consistent chibi banker character, same outfit and proportions in every cell, 4 columns x 4 rows, equal cell size, transparent background. Rows: idle, walk, work at counter, talk. Use a 2:1 isometric top-down view, crisp clusters, 1px charcoal outline, upper-left lighting, forest green / warm ivory / sage / brass palette. No labels, no shadows outside cells, no border, no watermark.

### 家具 SpriteSheet

> Create a modular pixel-art asset sheet for an isometric bank interior. Separate objects aligned to a regular grid with generous transparent spacing: teller counter, desk, chair, computer, sofa, queue post, filing cabinet, ATM, vault door, potted plant. Consistent 2:1 isometric angle, warm ivory floor-compatible shading, forest green and brass accents, crisp 1px outline. No text, no perspective changes, no background.

### 场景参考图

> Create an isometric cutaway pixel-art bank lobby screenshot reference for a management sim, with a busy teller row, waiting seats, manager office, a vault room, staff and customers. Use the official palette in this document, leave information panels blank or minimal, do not bake any UI labels or numbers into the art, 16:9 composition.
