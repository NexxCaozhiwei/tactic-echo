# Project Context

Current version: `1.0.44 P5`

Tactic Echo is a World of Warcraft AddOn plus the Windows TEK companion. The current development baseline is `1.0.44 P5`; historical baselines remain retained for audit only.

Use these current entry points first:

- `README.md` for the current architecture and safety contract.
- `HANDOFF.md` for the current implementation handoff.
- `TASKS.md` for active validation and known gaps.
- `DECISIONS.md` for current technical decisions.
- `CHANGELOG.md` and `docs/archive/` for historical notes.

Current dispatch path:

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3
-> TEK safety gates
-> SendInput
```

Macro behavior dynamically associates existing visible default-action-bar macros through Blizzard macro APIs first and broad read-only body semantics second. Phase 1.5 supports exactly one explicit trinket slot (`13` or `14`) as an injection action; conditions and branches remain Blizzard-owned, and AutoBurst confirms only the locked configured ActionRef result. In 1.0.14, Burst candidates use the same fresh-frame/global-rate scheduler as ordinary recommendations, while channel/empower remain explicit non-dispatch states.

## 1.0.20 持久前置窗口 handoff 围栏

实机记录显示，1.0.19 的单张 handoff hold 只存活约 18–32 ms，可能被 TEK 的约 50 ms 采样跨过。1.0.20 保留 `PreWindowCapture`，并将重新 armed 的前置窗口接管改为持久帧围栏：状态/事件 Refresh 先输出无 Token observation hold，但不消耗预算；随后必须输出 4 张 normal transport tick hold，下一张更新 freshness 的 Burst 帧才允许暴露注入 BindingToken。

capture 在无绑定、冷却快照暂态、重校验或计划创建失败时仍持有官方窗口，不得回退为普通窗口候选。capture 期间 Evaluate 异常时，AutoBurst 建立窗口离开锁，避免下一帧 fail-open。TEAP v3 不改，15/16 格仍只承载 BindingToken。

## 1.0.18 持久 Burst 与全 HUD 物品 GCD 隔离

SavedVariables 已定位到旧版本卡序列的真实路径：前置饰品恢复确认后，窗口仍因 `step_revalidate_timeout:official_window_cooldown_conflict` 中止。当前版本移除这类终止时限；计划建立后，官方推荐旋转仅记录 `official_window_departed_plan_latched`，不释放当前窗口。有效绑定的 UNKNOWN 冷却读数在 GCDGate 可分类时保持 Burst 候选并标记 `cooldownUncertain`，但绝不作为成功或跳过。

HUD 审计确认主、Burst、打断、控制、防御、药水卡全部复用 `TacticalIconButton.lua`。所有物品来源卡（itemID 或临时稳定装备槽位/物品类别）禁止原生 ActionBar/Item DurationObject 和 `gcdCooldown/61304` 公共 GCD 覆盖；只渲染归一化后的非 GCD 自身 CD。普通 SpellID 卡不变。

## 1.0.17 饰品 HUD 通用 GCD 隔离

装备饰品卡的主 CD 框继续优先使用当前 ItemID 自身冷却；此外，13/14 槽卡片不再渲染独立的通用 GCD 覆盖层。因此公共 GCD 不会以主 CD、数字、独立 `gcdCooldown` 转盘或 `61304` DurationObject 的形式出现在饰品卡上。该规则仅影响 HUD 呈现，不反馈到 AutoBurst、TEAP 或 TEK。

## 1.0.07 AutoBurst Field Corrections

The previous baseline distinguished explicit own cooldown from protected/ambiguous state, kept strict front-plan window ownership through unknown/revalidation and timeout, persisted one Burst candidate through confirmation, and used `UNIT_SPELLCAST_SUCCEEDED` only as an already-dispatched-step receipt. See `doc/baselines/BASELINE_1.0.07.md` and `docs/AUTOBURST_PHASE1.md` for that contract.

## 1.0.09 AutoBurst Generation Corrections

The active baseline rebases stale official-window observation state when `paused -> armed` resumes without an active plan or departure lock, so the first healthy frame can start the explicit `31884 -> 343527` pre/simple plan even if the official window icon was already visible. A front injection is now skip-eligible only after two independent, identity-matched live own-CD samples. Completed or aborted generations remain consumed until official recommendation departs. See `doc/baselines/BASELINE_1.0.09.md` for the current field-test contract.


## 1.0.10 Primary HUD Presentation

The main recommendation card no longer treats runtime pause as spell unavailability: it remains saturated and unmasked while showing “暂停”. A normal current-spell cast shows “施法”, while channel locks show the concise label “引导”. This is HUD-only and does not alter TEAP, TEK, bindings or AutoBurst. See `doc/baselines/BASELINE_1.0.10.md`.

## 1.0.11 Cooldown / Burst Confirmation

HUD countdown text now defaults to the configurable custom label path for main, burst, interrupt and defense modules; Blizzard DurationObjects remain the timer/swipe authority and show their own digits only in explicit native mode. A confirmed self-cooldown no longer greyscale-desaturates the icon. “校验” is reserved for the active AutoBurst injection/window step. Matching window success accepts declared, requested, matched and equivalent action-bar SpellIDs; a missed queue-window delivery can create one bounded retry after GCDGate reports READY. See `doc/baselines/BASELINE_1.0.11.md`.


## 1.0.12 Macro Association

Existing visible default-action-bar macros now resolve through a read-only semantic classifier. It accepts common `/cast`/`/use` syntax, conditional or semicolon branches, target modifiers including `@cursor`, helper lines and `/castsequence` references. The resolver maps only to the requested SpellID and never stores macro bodies in exports. TE continues to press only the player's existing binding; AutoBurst accepts the macro binding only when exact current-step confirmation is still possible.


## 1.0.13 Trinket Injection and TEUI Context Routes

Phase 1.5 permits exactly one explicit equipped trinket slot as a pre/post injection. It must resolve to an existing visible default-action-bar direct item button or a macro referencing one `/use 13` or `/use 14`; the plan locks current ItemID and confirms only its own non-GCD cooldown. Dual-slot macros, unknown state, gear changes and confirmation timeout fail closed. TEUI right-click routing and burst settings/style subpages are UI-only.


## 1.0.14 Unified Burst Delivery and Trinket Recovery

Burst transport no longer uses a stable-sequence one-shot or fixed window retry cap. The AddOn republishes the active action on fresh armed frames; TEK applies the same global rate limiter, freshness, manual-ownership, foreground and Hook gates used for official recommendations. Plan progression remains exact-confirmation-only.

Own-ready Burst actions are retained through `GCD_LOCKED`, `QUEUE_WINDOW` and `READY_NOW`; normal casts retain armed cadence, while channeling/empowering remain non-dispatch for all origins. A pre-window trinket pause/interrupt preserves a bounded recovery period; a later exact locked slot + ItemID non-GCD cooldown from a delayed or manual supplemental use advances the plan to the window.

## 1.0.15 Transport sequence and window conflict

Every fresh dispatchable armed frame receives a new TEAP transport sequence so that current and legacy TEK builds both apply the configured global rate policy. A logical Burst step still advances only from exact confirmation. If the official window recommendation conflicts with a transient `COOLDOWN/UNKNOWN` sample, AutoBurst creates a bounded plan and revalidates the window rather than rejecting the plan before the pre-action.


## 1.0.16 Trinket HUD GCD Presentation

Equipped trinket cards now keep the inventory slot/current ItemID cooldown as the presentation authority. A default action-bar button that only reports the shared spell GCD is not allowed to paint a trinket countdown. This is display-only; it does not alter AutoBurst confirmation or dispatch.


## 1.0.39 P3 reaction observation

- Current reaction-control stage is P3: read-only target/focus/mouseover/nameplate cast observation plus one HUD highlight (`interrupt > aoe control > single control`).
- P3 carries no input authority: no BindingToken, TEAP, TEK or SendInput changes; AutoBurst, HUD layout/labels/CD remain frozen.
- P5 replaces the P4.6 name-recovery fallback with numeric macro-index identity anchoring: duplicate macro names cannot supply another button's body. `/cast` token-to-SpellID association remains available. See `BASELINE_1.0.44.md`.
