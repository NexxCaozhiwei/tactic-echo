# 惩戒骑爆发策略设计

## 1. 设计目标

爆发模块用于回答：“在不改变官方主动作的前提下，当前是否值得建议使用职业大招、主动饰品、药水或准备增益？”

它不是一套隐藏优先级表，也不是将多个动作打包为一键宏。

## 2. 数据模型

```text
BurstPolicy
  enabled
  majorCooldowns
  trinketsMode        off | advisory
  potionMode          off | advisory
  precombatReminder
  alignment           strict | loose
  maxAuxActionsPerWindow

BurstAction
  actionId
  kind                major_gcd | off_gcd | potion | precombat
  source              spell | equipment_slot | consumable
  cooldownGroup
  requiresCombat
  requiresManualVerification
  runtimeEligible
  defaultMode
  maxUsesPerWindow
  effectVerification

BurstPlan
  primaryAction
  auxCandidate
  mode
  windowId
  reasonCodes
  blockedReason
```

## 3. 行为规则

1. `primaryAction` 是现有官方推荐主动作，BurstPlanner 不得静默替换它。
2. 带 GCD 的职业大招若要执行，必须作为主动作路径的一部分处理。
3. `auxCandidate` 只表达一个辅助候选，第一版只做 advisory。
4. `windowId` 用于窗口内去重和记录；同一窗口不能重复建议同一辅助动作至超出上限。
5. 物品、药水和多形态技能如果没有人工验证，必须保留 `runtimeEligible=false`。
6. 合剂、食物、武器油等属于 precombat 提醒，不能进入战斗辅助输入。

## 4. 推荐理由代码示例

```text
major_cooldown_ready
alignment_strict_waiting
trinket_slot_13_ready
potion_ready
not_in_combat
target_invalid
shared_cooldown_active
manual_verification_required
window_limit_reached
policy_disabled
```

理由必须进入 UI、trace 或 SavedVariables，使用户能看到“为什么建议”“为什么不建议”。

## 5. 阶段划分

### 阶段 1：Advisory

- UI/trace 输出建议；
- 不改变 TEAP 主 ActionCode；
- 不增加 TEK 输入；
- 木桩或副本中验证建议时机。

### 阶段 2：单项受控输入（后续）

仅在单一物品/技能已经具备隐藏按钮、前台、窗口、预算、效果观察和人工证据时考虑。一次仅验证一个动作。

### 阶段 3：受控组合策略（远期）

只有在每个动作的效果确认、共享冷却、失败回退和安全边界均明确后才讨论；当前不立项。
