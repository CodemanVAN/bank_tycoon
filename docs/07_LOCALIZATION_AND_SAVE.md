# 07 — 多语言与存档规范

## 1. 首发语言

- 简体中文：`zh_CN`（默认）
- 英语：`en`
- 日语：`ja`

所有玩家可见文本必须经翻译系统获取，不允许在场景、脚本或 JSON 内容数据中直接写展示文本。

## 2. 翻译架构

### 原版

使用 Godot gettext PO/MO 工作流：

```text
localization/
├── messages.pot
├── zh_CN.po
├── en.po
└── ja.po
```

脚本中使用 `tr("KEY")` 或 LocalizationService 包装函数。翻译 Key 不可复用为不同语义；需要上下文时使用带模块前缀的 Key。

### Mod

Mod 翻译使用 JSON 字典，键必须包含 Mod namespace 或在注册时由加载器补全 namespace：

```json
{
  "com.example.extra_departments:DEPT_AI_NAME": "人工智能研究部",
  "com.example.extra_departments:DEPT_AI_DESC": "负责银行智能化技术研发。"
}
```

### 查找顺序

1. 当前语言的 Mod 翻译。
2. 当前语言的原版翻译。
3. 英文回退。
4. Key 本身（开发模式）并写入缺失 Key 日志。

同一 Mod 的翻译不能覆盖其他 Mod 或原版 Key。

## 3. 翻译 Key 命名

建议：`UI_TOPBAR_DAY`、`DEPT_HR_NAME`、`DEPT_HR_DESC`、`EVENT_CUSTOMER_COMPLAINT_TITLE`、`POLICY_PRUDENT_LENDING_EFFECT_1`。Key 使用大写蛇形，模块前缀清晰。

## 4. 数字与格式

建立 FormatService，集中处理：

- 货币符号/币种和千位分隔。
- 日期、星期、游戏时间。
- 百分比、基点、利率。
- 正负数、缩写金额（K/M/B）。
- 复数形式（如 1 employee / 2 employees）。

不要通过字符串拼接方式组合句子。使用带参数的翻译模板。UI 文本容器允许换行和增长。

## 5. 字体与布局

- 选择含简体中文、日文假名/常用汉字、拉丁字符的字体或字体组合。
- 记录字体来源和许可证；不要从未授权字体仓库直接复制。
- 字体尺寸以 640x360 逻辑 viewport 实测。
- 检查中文、英文、日文长文案和特殊字符。
- 不能只用英文截图做 UI 验收。

## 6. 存档原则

- 存档保存领域状态，不保存节点树、Sprite 帧和 UI 打开状态（除非未来明确需要保存 UI 偏好）。
- 存档中持久对象都使用稳定 ID，不使用数组下标作为唯一身份。
- 保存 `save_version`、`game_version`、`world_seed`、当前日期/时间、银行状态、员工/客户、贷款、部门、政策、未结事件、必要历史、Mod 清单。
- JSON 可读性优先；大规模历史数据后续可分文件或二进制化，但必须保持迁移能力。

## 7. 存档路径

```text
user://saves/
├── slot_01.json
├── slot_01.bak
├── slot_02.json
└── autosave.json
```

通过 `ProjectSettings.globalize_path()` 或 Godot 文件 API 正确访问用户目录。不得写入 `res://`。

## 8. 存档写入流程

1. 在内存中生成纯数据快照。
2. 序列化为 JSON。
3. 写入临时文件 `slot_01.tmp`。
4. 检查文件写入和 JSON 结构。
5. 将现有存档轮换为 `.bak`。
6. 将临时文件替换为正式文件。
7. 写入失败时保留原存档并告知玩家。

自动存档建议：日终结算后；手动存档可在暂停状态下进行。营业中精确存档等模拟快照稳定后再实现。

## 9. 存档版本迁移

- 当前字段 `save_version`。
- 每次结构变化新增一个迁移步骤 `v1_to_v2`，不能直接把所有旧版本映射成最新版本。
- 迁移前先备份原文件。
- 未知字段应按策略保留或安全忽略，不可无声丢失关键数据。
- 迁移失败时允许玩家回滚 `.bak`。
- 每条迁移路径有自动化测试和固定 Fixture。

## 10. 最小 Save DTO 示例

```json
{
  "save_version": 1,
  "game_version": "0.1.0",
  "created_at_utc": "2026-11-20T12:00:00Z",
  "world_seed": 123456,
  "current_day": 12,
  "current_minute_of_day": 540,
  "currency_code": "CNY",
  "bank_state": {},
  "ledger_accounts": [],
  "employees": [],
  "customers": [],
  "loans": [],
  "departments": [],
  "policies": [],
  "active_events": [],
  "mod_dependencies": []
}
```

上面仅为结构示例；正式字段必须按领域模型定义，并通过版本化 Schema 验证。
