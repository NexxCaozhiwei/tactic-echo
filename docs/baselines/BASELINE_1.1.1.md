# Tactic Echo 1.1.1 基线：自动启停待命状态

## 当前策略语义

- 默认 `pause_out_of_combat` 策略对外命名为“自动启停”。
- 自动启停下，未进战斗或脱战导致的非派发帧仍使用 TEAP `paused`，但原因码必须是 `out_of_combat_auto_standby`，显示层必须渲染为“待命”。
- 手动 `/te pause`、HUD 主键暂停和 `close_out_of_combat` 脱战停止仍显示为“暂停”，不得混同为待命。
- `/tepolicy auto` 与 `/tepolicy pause` 均可选择自动启停；旧 SavedVariables 中的 `pause_out_of_combat` 继续兼容。

## 不变边界

- 不新增 TEAP/TEK 协议状态；`paused` 仍是非派发安全状态。
- 自动打断继续生产硬暂停，不生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- AutoBurst 任何 `inCombat=false` 帧仍不得创建或保留 plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。
- HUD、Tooltip、诊断和待命状态不得创建 Token、改写官方推荐或请求输入。

## 文档归档

- 所有 `BASELINE_<版本>.md` 只允许位于 `docs/baselines/`。
- 所有 `PATCH_MANIFEST*` 只允许位于 `docs/patch-manifests/`。

## 验收

- `tests/unit/test_login_ready_fast_sampling_contract.py`
- `tests/unit/test_state_display_unification_contract.py`
- `tests/unit/test_primary_runtime_state_presentation_contract.py`
- `tests/unit/test_compact_teui_and_build_contract.py`
