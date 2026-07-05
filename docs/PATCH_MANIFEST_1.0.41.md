# 1.0.41 P4.4 直接覆盖补丁清单

## 变更目标

用真实盾组件可见性、单位施法事件和直接 API 重建严格自动打断资格；移除 P4.3 的临时“忽略钢条”探测资格；保留 P4.3 已验证的稳定 reaction candidate 交付和 TEK 去重。

## 覆盖文件

- `AGENTS.md`
- `docs/baselines/BASELINE_1.0.41.md`
- `CHANGELOG.md`
- `HANDOFF.md`
- `README.md`
- `VERSION`
- `addon/!TacticEcho/!TacticEcho.toc`
- `addon/!TacticEcho/Core/Bootstrap.lua`
- `addon/!TacticEcho/Signal/SignalFrame.lua`
- `addon/!TacticEcho/Tactics/AutoReaction.lua`
- `addon/!TacticEcho/Tactics/ReactionInterruptEvents.lua`
- `addon/!TacticEcho/Tactics/ReactionObservation.lua`
- `addon/!TacticEcho/Tactics/TacticalAdvisors.lua`
- `addon/!TacticEcho/UI/ControlPanel.lua`
- `docs/P4.4_NATIVE_SHIELD_REVALIDATION_TEST.md`
- `tests/unit/test_reaction_control_p3_contract.py`
- `tests/unit/test_reaction_control_p4_contract.py`

## 安装说明

解压至现有项目根目录并选择覆盖。之后将更新后的 `addon/!TacticEcho` 覆盖到 WoW 实际 AddOns 目录并 `/reload`。

本版没有改动 TEK 可执行逻辑；运行 P4.3 TEK.exe 的用户无需因 P4.4 重新构建。若当前仍是早于 P4.3 的 TEK.exe，则应先按既有流程运行 `TEKEXEBUILD.CMD`。
