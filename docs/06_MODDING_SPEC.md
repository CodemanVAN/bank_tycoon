# 06 — Mod 系统技术规范

## 1. 目标和阶段

### 首发 Mod（数据型）

允许添加：部门、政策、事件、员工特质、客户类型、金融产品、场景配置、图标/头像/家具图片、音效和 Mod 翻译。

### 暂不开放

- 任意 GDScript/C# 执行。
- 修改核心经济公式或访问任意文件路径。
- 修改项目脚本或覆盖原版代码。
- Mod 运行时网络请求。

后续如开放脚本 Mod，必须采用明确权限模型、单独启用开关、版本 API 和安全提示；不能假设 ResourcePack 就是沙盒。

## 2. Mod 目录

```text
user://mods/
├── com.example.extra_departments/
│   ├── manifest.json
│   ├── content/
│   │   ├── departments.json
│   │   ├── policies.json
│   │   └── events.json
│   ├── localization/
│   │   ├── zh_CN.json
│   │   ├── en.json
│   │   └── ja.json
│   └── assets/
│       ├── icons/
│       └── portraits/
└── another_mod.zip
```

游戏应支持文件夹和 ZIP 两种形式。ZIP 内容解压/读取时必须校验路径和资源大小；防止路径穿越、解压炸弹和异常大图。

## 3. Manifest 规范 v1

```json
{
  "schema_version": 1,
  "id": "com.example.extra_departments",
  "name_key": "MOD_EXTRA_DEPARTMENTS_NAME",
  "version": "1.0.0",
  "game_version_min": "0.1.0",
  "game_version_max": "0.x",
  "author": "Example Author",
  "description_key": "MOD_EXTRA_DEPARTMENTS_DESC",
  "dependencies": [],
  "conflicts": [],
  "load_after": [],
  "content": {
    "departments": "content/departments.json",
    "policies": "content/policies.json",
    "events": "content/events.json"
  },
  "localization_dir": "localization",
  "asset_dir": "assets"
}
```

实际 parser 允许可选字段缺省；所有必填字段由 Schema 校验。Mod ID 使用反向域名风格；内容 ID 必须采用 `{mod_id}:{local_id}` 命名空间。

## 4. 加载流程

1. 扫描 `user://mods/`。
2. 识别目录和 ZIP。
3. 读取 Manifest；校验 JSON、Schema 版本和游戏版本。
4. 校验 Mod ID 唯一、依赖存在、冲突规则和循环依赖。
5. 计算确定性加载顺序：依赖顺序优先，再按 Mod ID 字典序，除非用户指定 load order。
6. 读取内容数据并执行 Schema 校验。
7. 检查内容 ID 冲突、引用是否有效、翻译 Key 是否完整。
8. 将有效内容转换成 Domain Definition 并注册到 ContentRegistry。
9. 生成 Mod 加载报告；无效 Mod 不部分注册，避免半加载状态。

## 5. ID 和覆盖规则

- 原版 ID 示例：`department.hr`、`policy.prudent_lending`、`event.customer_complaint`。
- Mod ID 示例：`com.example.extra_departments:department.ai_research`。
- 禁止 Mod 覆盖原版 ID。
- Mod 之间相同 ID 默认冲突并拒绝后加载的冲突内容；不做静默覆盖。
- 依赖必须显式写在 Manifest。
- 存档保存 Mod ID、版本和内容 Schema 版本。

## 6. 数据型效果 API

允许白名单效果，不允许脚本表达式。

第一版操作：

- `add`：增加数值。
- `multiply`：按整数倍率/固定点倍率修改目标。
- `set`：设置受允许控制的值。
- `unlock`：解锁已注册功能/内容。
- `modify_chance`：修改已定义事件池概率权重。
- `trigger_event`：触发已注册事件（须符合冷却/触发条件）。

`target` 只能来自白名单，例如：

- `staff.productivity_bps`
- `service.teller_duration_bps`
- `customer.deposit_growth_bps`
- `bank.reputation_points`
- `loan.default_risk_bps`
- `liquidity.required_buffer_bps`

数值范围必须设上限，防止溢出或无意义的无限倍率。效果结算统一经过 ModifierService，不允许各领域脚本自行遍历 Mod 数据。

## 7. 事件数据要求

- trigger condition 使用有限结构（`day_at_least`、`department_exists`、`policy_adopted`、`metric_above`、`cooldown_elapsed`）。
- 事件选项使用有限 effect list。
- 不允许在 JSON 中加入条件代码字符串或 GDScript 片段。
- 事件链通过 `next_event_id` 显式连接。
- 事件触发概率和冷却期必须经过合法范围校验。

## 8. 图片资产安全与导入

- 允许 PNG；首版推荐不允许 SVG/脚本资源。
- 校验扩展名、文件头、像素尺寸、总字节数。
- 图片最大尺寸建议 2048 x 2048（可按资产类型再降低）。
- 防止资源路径访问 Mod 目录之外。
- 资产加载失败时使用内置占位图并显示日志。

## 9. 用户体验

Mod 管理器显示：名称、作者、版本、描述、兼容状态、依赖、冲突、启用状态、加载错误。修改 Mod 启用状态需要重新加载内容数据库；对现有存档可能有影响时给出提醒。

## 10. 存档兼容

- 保存当前启用 Mod 的 ID/版本清单。
- 加载存档时对比当前安装清单。
- 缺少 Mod 时：先尝试只读加载已知字段；若缺失内容影响关键运行状态，阻止继续并给出明确恢复建议。
- 不允许静默删除未知部门/政策/员工特质。
- Mod 版本升级通过内容迁移钩子或兼容规则处理；无迁移时标记风险。

## 11. 测试

- 正常 Mod 加载。
- 缺字段/错误类型/超范围数值。
- 重复 ID/循环依赖/缺失依赖。
- ZIP 路径穿越和超大文件。
- 缺少翻译 Key。
- Mod 引用不存在的部门/事件/政策。
- 存档缺 Mod、Mod 降级和 Mod 升级。
