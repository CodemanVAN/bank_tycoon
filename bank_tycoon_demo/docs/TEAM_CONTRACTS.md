# Starway Bank Demo — Team Contracts (single source of truth for parallel work)

All workers MUST read: `../../AGENTS.md` (global rules), this file, and the approved plan
`C:\Users\18249\.gemini\antigravity\brain\a4eb7699-7f21-4ceb-b6c2-f70bb5c64bab\implementation_plan.md`.
Design references: `../../docs/01_GDD.md`, `02_TDD.md`, `03_ECONOMY_SPEC.md`, `05_UI_UX_SPEC.md`,
`06_MODDING_SPEC.md`, `07_LOCALIZATION_AND_SAVE.md`, `../../schemas/*.schema.json`,
art: `../../art/01_visual/starway_bank_modern_tech_blue_master_reference.png`, `../../art/02_tokens/*`.

Project root: `bank_tycoon_demo/` (Godot 4.7.2, GDScript static typing, 1280x720 canvas_items).

## 0. Hard rules for every worker

1. **Run Godot ONLY through** `powershell -NoProfile -ExecutionPolicy Bypass -File bank_tycoon_demo/tools/godot.ps1 <args>`
   (it adds `--headless --path`, and serializes runs with a mutex — the `.godot/` cache is shared).
   After adding/renaming any `class_name` script run `godot.ps1 --import` once so the class cache updates.
2. **Never run git** (the coordinator checkpoints). Never touch `starter_project/`.
3. **Only edit files you own** (table §1). Need a change elsewhere? Post on the board @owner with the exact
   request. Tiny compile-fix in someone else's file is allowed only if it blocks you — announce it.
4. Domain (`scripts/domain`, `scripts/shared`) stays pure `RefCounted`: no Node / SceneTree / Input / UI.
   Existing domain unit tests (`tests/unit/test_domain.gd`, 351 asserts) must keep passing.
5. Every player-facing string goes through `LocalizationService.tr_key("KEY", {params})` — no literals in
   scenes/scripts (numbers via `FormatService`). Keys are UPPER_SNAKE with module prefix.
6. Money = integer minor units (`*_minor`, 100 minor = ¥1), rates = integer bps. Ledger only via FinanceEngine.
7. UI never mutates state directly: call `SimulationHost.command_service.<command>()` → `Result`.
   Show `Result.error_key` (translated) to the player on failure.
8. Logs: `push_warning/push_error("[Module] ...")`; no print spam (tests may print).
9. Done = your scripts parse, your tests pass via godot.ps1, and you posted a short report on the board.

## 1. Ownership

| Worker | Owns (create/edit) |
|---|---|
| infra | `data/*.json`, `localization/core.*.json`, `localization/*.po|*.pot`, `scripts/autoload/*`, `tools/build_po.py`, `tests/unit/test_infra.gd` |
| sim | `scripts/simulation/*`, `scripts/app/*`, `scripts/domain/*` + `scripts/shared/*` (maintainer; keep unit tests green), `localization/sim.*.json`, `tests/integration/*` |
| world | `scripts/presentation/world/*`, `scenes/world/*`, `tools/generate_pixel_assets.py` + `assets/environment|characters|icons/*` (additive), `localization/world.*.json`, `tests/unit/test_world.gd` |
| hud | `scripts/presentation/ui/starway_theme.gd`, `main_menu.gd`, `game_root.gd`, `top_bar.gd`, `left_navigation.gd`, `right_inspector.gd`, `bottom_bar.gd`, `audio_feedback.gd`, `pause_menu.gd`, `settings_panel.gd`, `toast.gd`; `scenes/menus/*`, `scenes/gameplay/*`, `scenes/ui/hud/*`, `scenes/ui/modals/pause_menu.tscn`, `localization/hud.*.json`, `tools/generate_audio_assets.py` |
| panels | `scripts/presentation/ui/drawers/*`, `scripts/presentation/ui/modals/*` (except pause/settings), `scripts/presentation/ui/daily_report_overlay.gd`, `scripts/presentation/ui/widgets/*`; `scenes/ui/drawers/*`, `scenes/ui/modals/*` (except pause_menu), `scenes/ui/daily_report_overlay.tscn`, `localization/panels.*.json` |
| qa | `tests/run_tests.gd`, `tests/e2e/*` (fixes to test bugs only, documented), `tests/qa_*`; reports bugs to owners |

## 2. Localization (infra implements, everyone contributes)

- Fragment files: `res://localization/<module>.<locale>.json`, module ∈ {core, sim, world, hud, panels},
  locale ∈ {zh_CN, en, ja}. Flat `{ "KEY": "text with {param}" }`. Each owner writes all 3 locales.
- `LocalizationService` loads every `*.zh_CN.json|*.en.json|*.ja.json` under `res://localization/`.
  Fallback: Mod(current) → vanilla(current) → en → raw key + one warning per missing key.
- `infra` owns core keys: all content `name_key/description_key/title_key/label_key`, `ERR_*` keys for every
  `Result.error_key` used in domain/app, `LEDGER_*`, person names `PERSON_NAME_01..40`,
  `EMP_NAME_STARTER_1/2`, `CAND_NAME_1..3`, service types `SERVICE_<TYPE>` (e.g. `SERVICE_CASH_DEPOSIT`),
  customer types `CUSTOMER_<TYPE>_NAME`, roles `ROLE_<ROLE>` (TELLER, LOAN_OFFICER, MANAGER, ANALYST),
  trait `TRAIT_*_NAME/_DESC`, department level unlock text `DEPT_<X>_LV1..3`, risk grades, liquidity status
  `LIQUIDITY_SAFE|CAUTION|DANGER`, day phases `PHASE_PRE_OPEN|OPEN|CLOSING|SETTLED`.
- `tools/build_po.py` (infra) merges fragments into `messages.pot`, `zh_CN.po`, `en.po`, `ja.po` (gettext mirror).

## 3. Content data (infra) — `res://data/*.json` (arrays), validated against `../../schemas`

`departments.json` (4: `core:department.operations|hr|credit|risk`), `policies.json` (6: conservative
`core:policy.prudent_lending → liquidity_first → customer_trust`, aggressive `core:policy.high_rate_acquisition →
market_penetration → credit_expansion`; prerequisites chain; mutually exclusive branches), `events.json` (≥10,
incl. chain `core:event.real_estate_boom` (options `aggressive_expand`, `prudent_cap`, next → cooling) →
`core:event.real_estate_cooling` (`tighten_credit`, `hold_course`, next → credit_stress) →
`core:event.real_estate_credit_stress` (`emergency_provision`, `restructure_books`)), `traits.json`, `customers.json`
(types `regular, salaried, borrower, smb, vip, suspicious` with service weights, patience, amount ranges).
Name keys: `DEPT_OPERATIONS_NAME`, `POLICY_PRUDENT_LENDING_NAME`, `EVENT_REAL_ESTATE_BOOM_TITLE`, option
`label_key` + `<label_key>_DESC` hint. Read `scripts/domain/*` to match fields actually consumed.

`ContentRegistry.get_content_defs() -> Dictionary` returns
`{"departments": Array, "policies": Array, "events": Array, "traits": Array, "customers": Array}` (core + valid mods).
This dict is what domain/app functions call `content_defs`.

## 4. Autoload APIs (infra) — exact names, see also PROJECT contract

- `LocalizationService`: `signal locale_changed(new_locale: String)`, `get_locale()`, `set_locale(locale)`,
  `tr_key(key, params := {})`, `register_mod_translations(mod_id, locale, entries)`, `clear_mod_translations()`,
  `get_available_locales() -> PackedStringArray`.
- `ContentRegistry`: `reload_all(mods_root := "user://mods") -> Dictionary` (ModLoadReport: `loaded_mods`,
  `rejected_mods` [{id, path, reasons}], `errors`, `counts`), `get_definition(id)`, `get_all_by_type(kind)`
  (kind singular or plural), `get_department_def/policy_def/event_def/trait_def/customer_def(id)`,
  `get_loaded_mod_dependencies()`, `get_content_defs()`. Loads core on `_ready()`.
- `AudioService`: `play_bgm(track := "bgm_starway_lobby", fade := 0.5)`, `stop_bgm(fade := 0.3)`,
  `play_sfx(name)` (names = wav basenames without ext, e.g. `sfx_ui_click`), `set_bus_volume(bus, linear)`,
  `get_bus_volume(bus)`, `set_muted(b)`, `is_muted()`. Settings persisted in `user://settings.json`.
- `SaveService`: `SAVE_VERSION = 1`, `save_slot(slot, bank_state, metadata := {}) -> Result`,
  `load_slot(slot) -> Result` (data: `{bank_state, metadata, used_backup, mod_warnings}`), `list_slots() ->
  Array[Dictionary]` (each: `slot_id, exists, day, cash_minor, bank_name, saved_at_utc, save_version`),
  `delete_slot(slot) -> Result`, `get_slot_path(slot)`. Slots: `autosave, slot_01, slot_02, slot_03`.
- `GameSession`: signals `session_started(bank_state)`, `session_ended()`, `settings_changed(settings)`;
  vars `bank_state: BankState`, `is_active`, `minute_duration_sec` (0.25 demo / 1.0 standard);
  `start_new_game(bank_name := "Starway Bank", world_seed := 20261121) -> BankState`,
  `load_from_slot(slot) -> Result`, `save_to_slot(slot) -> Result`, `end_session()`, `get_settings()`,
  `update_settings(patch)`; settings keys: `locale, minute_duration_sec, master_volume, bgm_volume, sfx_volume,
  muted, auto_pause_on_event`. Also `get_most_recent_slot() -> String` ("" if none) for "Continue".

## 5. Simulation / application (sim)

- `GameClock` (RefCounted): `speed: int` (0..3), `minute_duration_sec: float`, `advance(delta: float) -> int`
  (#ticks to run, ≤ `BalanceConfig.MAX_TICKS_PER_FRAME`; 0 when paused; leftover carried, overflow dropped).
- `BranchSimulation` (RefCounted): `tick_minute()` runs the fixed 8-step order (TDD §7.3). Day flow:
  `PRE_OPEN` (no ticks) → `open_branch_for_day()` → `OPEN` 09:00–17:00 (customers spawn) → `CLOSING`
  (no spawns, finish/flush queue, hard stop 18:00) → automatic settlement → `SETTLED` (no ticks) →
  `advance_to_next_day()` → `PRE_OPEN` next day.
- `DomainEventBus` (RefCounted): `signal event_published(event_type: StringName, payload: Dictionary)`,
  `publish(event_type, payload)`, plus `recent_log: Array[Dictionary]` (last 50: `{type, day, minute, key, params}`).
  Event types: `minute_ticked{day,minute}`, `day_started{day}`, `day_phase_changed{phase}`,
  `customer_arrived{customer_id}`, `service_started{request_id,customer_id,employee_id,station_id}`,
  `service_completed{request_id,customer_id,employee_id,station_id,service_type,amount_minor,fee_minor}`,
  `customer_left_unserved{customer_id}`, `loan_approval_requested{approval_id}`,
  `loan_approved{approval_id,loan_id}`, `loan_rejected{approval_id}`, `employee_hired{employee_id}`,
  `employee_fired{employee_id}`, `employee_assigned{employee_id,station_id}`, `station_toggled{station_id,is_open}`,
  `department_created{department_id}`, `department_upgraded{department_id,level}`, `policy_adopted{policy_id}`,
  `event_triggered{event_instance_id,event_id}`, `event_resolved{event_instance_id,option_id}`,
  `daily_settlement_completed{day,report}`, `speed_changed{speed}`, `rates_changed{deposit_bps,loan_bps}`,
  `alert{key,params,severity}` (severity 0 info/1 warning/2 critical), `state_reloaded{}`.
- `BankCommandService`: commands per PROJECT contract (`open_branch_for_day, advance_to_next_day, set_speed,
  assign_employee_to_station, toggle_station_open, set_queue_priority, hire_candidate, fire_employee,
  train_employee, rest_employee, create_department, upgrade_department, adopt_policy, approve_loan, reject_loan,
  resolve_event_option, set_interest_rates`) — all return `Result`, publish events on success.
  Plus read helpers: `can_create_department(id) -> Result`, `can_upgrade_department(id) -> Result`,
  `can_adopt_policy(id) -> Result`, `get_department_upgrade_cost(id) -> int` (for disabled-reason UI).
- `SimulationHost` (`extends Node`, child of GameRoot, NOT autoload): vars `bank_state, clock, simulation,
  command_service, event_bus, content_defs, modifiers`; `bind_session(state, defs)`, `step_simulation(delta)`
  (called from `_process` when bound; tests call it directly), `get_snapshot() -> Dictionary` with keys:
  `day, minute, phase, speed, cash_minor, deposits_minor, loans_minor, equity_minor, today_profit_minor
  (running estimate), satisfaction, reputation, strategy_points, employee_count, queue_length, waiting_customers,
  pending_approvals, active_events, liquidity_ratio_bps, liquidity_status (Enums.LiquidityStatus),
  npl_ratio_bps, deposit_rate_bps, loan_base_rate_bps`. Signal `snapshot_changed()` emitted at most once per frame
  after ticks/commands.
- Avatar ids for generated people must match `assets/characters/*.png`: employees `emp_teller_f, emp_teller_m,
  emp_credit, emp_risk, emp_ops, emp_hr`; customers `cust_<type>` for the 6 customer types.
- Balance target: with sensible play the bank is mildly profitable by day ~5, strategy points accrue so a first
  policy can be adopted around day 3–5 and a department created on day 1–3; events appear every ~2–3 days.

## 6. World (world)

`scenes/world/bank_world.tscn` root `BankWorld` (Node2D, `scripts/presentation/world/bank_world.gd`):
`signal entity_selected(entity_type: StringName, entity_id: String)` (`&"employee"|&"customer"|&"station"|&""`),
`bind_runtime(sim_host: SimulationHost)`, `focus_entity(type, id)`, `set_camera_zoom_step(step: int)` (1..3).
18x12 logical grid, 2:1 iso, `IsoGrid` (+ `AStarGrid2D`), Y-sort, Nearest filter, `PixelCamera2D`.
Stations from `bank_state.stations` (`grid_pos`). Actor positions/animations are derived from domain state
(presentation-only walking). Use `_unhandled_input` so HUD clicks never leak into the world. The visible play
area is the screen minus HUD (§7 tokens); center the lobby there. Floating "+¥" / emotion bubbles on events.

## 7. UI (hud + panels)

Theme: `StarwayTheme.build()` (apply on each scene root) + constants `StarwayTheme.BG_0…VIOLET_500`, layout
tokens `TOP_BAR_HEIGHT=56, LEFT_NAV_WIDTH=76, RIGHT_INSPECTOR_WIDTH=300, BOTTOM_BAR_HEIGHT=64`; type variations
`PanelCard, PanelHeader, PanelLarge, PanelBar, LabelTitle, LabelHero, LabelMuted, LabelGold, LabelPositive,
LabelNegative, LabelValue, ButtonPrimary, ButtonDanger, ButtonGold, ButtonGhost`. Icons in `res://assets/icons/`.

`scenes/gameplay/game_root.tscn` (hud), actual tree after the input fix (indentation = parent/child):
```text
GameRoot (Control, mouse_filter=IGNORE)
|- SimulationHost (Node)
|- WorldHost (Node2D)
|  `- BankWorld (instance of bank_world.tscn)
`- HUDLayer (CanvasLayer, layer=10)
   |- TopBar                (PanelContainer)
   |- LeftNavigation        (PanelContainer)
   |- RightInspector        (PanelContainer)
   |- BottomBar             (PanelContainer)
   |- DrawerContainer       (Control, IGNORE)  -> Overview/Finance/Employees/Departments/Policies/Events drawers
   |- ModalContainer        (Control, IGNORE)  -> ModalShield (Control, STOP, hidden), LoanApprovalModal,
   |                                              EventModal, PauseSaveSettingsModal
   |- DailyReportOverlay    (PanelContainer, 780x480 centred, STOP, hidden)
   `- ToastBar              (PanelContainer, 480x40, IGNORE, hidden)
```
On `_ready`: `host.bind_session(GameSession.bank_state, ContentRegistry.get_content_defs())`, then `_wire_signals()`.
`bind_session()` rebuilds the `DomainEventBus`, so `GameRoot._wire_event_bus()` re-connects `event_published` after
every bind (initial boot **and** save reload) with an `is_connected` guard.

### 7.1 HUD input hit-testing rules (mandatory — regression: "top bar buttons unclickable")

Godot GUI picking takes the **topmost non-IGNORE Control** under the pointer and then bubbles the event up that
control's **parent chain only**. `MOUSE_FILTER_PASS` never falls through to a lower *sibling*, so a full-screen PASS
container is a click black hole for everything drawn beneath it (this silently killed TopBar / LeftNavigation /
BottomBar / drawer buttons; GUI picking is what the regression proves — the world's `_unhandled_input` path is a
separate channel and was not claimed as verified-in-broken-state).

1. Full-screen layout-only Controls **must** be `mouse_filter = 2` (IGNORE) and state it explicitly in the `.tscn`:
   `GameRoot`, `DrawerContainer`, `ModalContainer`.
2. **PASS is forbidden** on any overlapping HUD container, full-screen or not. Overlay chrome that never takes input
   (e.g. the 480x40 `ToastBar`) is also IGNORE, so it cannot shadow the strip below it. Only real panels are `STOP`
   (default), and they are hidden (`visible = false`) when inactive — a hidden Control never participates in picking.
3. Modal blocking is owned by exactly one node: `ModalShield` (first child of `ModalContainer`, full-rect, `STOP`,
   default hidden). `GameRoot._sync_modal_shield()` toggles it from the four modal-ish panels' `visibility_changed`
   (not only `closed`), so every close path — close button, `open_pause_modal()` toggle, direct `visible = false` —
   restores click-through. Keep `ModalShield` **before** the modal siblings (reverse picking order gives panels priority).
4. `DailyReportOverlay` **is** part of the shield set: the HUD and the lobby are locked while the day report is open
   (it is shown at settlement, so a stray click must not move money or re-advance the day).
5. Any new full-screen HUD node must come with a `gui_get_hovered_control()` assertion in
   `tests/e2e/test_tier5_ui_input.gd`; `godot.ps1 --script res://tests/run_tests.gd` must stay green.

### 7.2 Snapshot-driven lists (drawers / modals)

Rows are rebuilt from `snapshot_changed`, which fires several times per second. Destroying a Button between its
`press` and `release` swallows the click ("needs several clicks"). Rules:

1. Only rebuild when the structural signature changed (`UiListRefresh.signature`); text-only updates must not rebuild.
2. Never rebuild while a button in the list is held (`UiListRefresh.any_button_held`): set a pending flag and flush it
   from `UiListRefresh.watch_release` / `watch_tree`.
3. Clear rows with `UiListRefresh.clear_children` (`queue_free`), never `free()` inside a signal handler.
4. Command handlers refresh via `refresh.call_deferred()`, not synchronously inside `pressed`.

### 7.3 Department placement (new construction flow)

- `departments_drawer.gd` emits `placement_requested(dept_id)`; it never calls `create_department` itself.
- `GameRoot` closes the drawer and calls `BankWorld.begin_department_placement(dept_id)`. `BankWorld` emits
  `department_placement_confirmed(dept_id, cell)` or `department_placement_cancelled()`; `GameRoot` then calls
  `BankCommandService.create_department(dept_id, cell)` and reports the `Result` via `ToastBar`.
- `BankWorld.is_valid_department_plot(cell, dept_id)` rejects: out of bounds, entrance / queue lanes
  (`PLACEMENT_EXTRA_RESERVED_CELLS`), solid cells (walls, stations, existing dept rooms) and plots occupied according
  to `DepartmentService.is_plot_free` (domain-owned uniqueness).
- `DepartmentInstance.grid_pos` is the single source of truth; `(-1, -1)` means "unplaced legacy save" and renders at
  the old `DEPT_ZONES` cell. Rooms are created/removed from `BankState`, not from a fixed list.
- World input uses the event position (`cell_from_screen_position`, camera-aware), never `get_global_mouse_position()`
  polling — the latter is not updated by `Viewport.push_input` and makes placement untestable headless.

### 7.4 Known follow-ups (still open)

- Department rooms are one tile. A multi-tile footprint needs an occupancy set shared with `is_plot_free`.
- `DEPT_ZONES[*].cell` now only serves unplaced legacy saves and mod departments without a style entry; remove it once
  a save migration has run.
- Mod-added departments get the default accent and the id as display name until the mod supplies `WORLD_DEPT_*` keys.
- `PLACEMENT_EXTRA_RESERVED_CELLS` tracks the lobby layout manually; update it together with any floor-plan change.



Panels contract (panels implements; hud instantiates by path):
- Drawers `scenes/ui/drawers/{finance,employees,departments,policies,events}_drawer.tscn`; root Control script
  provides `bind(host: SimulationHost) -> void`, `refresh() -> void`, `signal close_requested`. DrawerHost area:
  x=76..980, y=56..656 (between nav and inspector, above bottom bar). `refresh()` on `snapshot_changed` while visible.
- Modals `scenes/ui/modals/loan_approval_modal.tscn`, `scenes/ui/modals/event_modal.tscn`:
  `bind(host)`, `open_with(data: Dictionary)` (loan: `{approval_id}`; event: `{event_instance_id}`), `signal closed`.
- `scenes/ui/daily_report_overlay.tscn`: `bind(host)`, `show_report(report: Dictionary)`,
  `signal next_day_requested`. GameRoot handles it: `advance_to_next_day()` → `GameSession.save_to_slot("autosave")`
  → toast.
- Right inspector "selected employee" actions and bottom bar badges call the same commands / open the modals via
  GameRoot methods: `open_drawer(id: StringName)`, `close_drawer()`, `open_loan_modal(approval_id)`,
  `open_event_modal(event_instance_id)`, `show_toast(key, params, severity)`.
- SFX: hud's `audio_feedback.gd` subscribes to the event bus and plays SFX (cash on service_completed with
  amount, bell on customer_arrived (throttled), approve/reject, alert on event_triggered, day_complete, upgrade).
  UI buttons play `sfx_ui_click` via a shared helper `UiSfx.click()` (hud owns `scripts/presentation/ui/ui_sfx.gd`).
