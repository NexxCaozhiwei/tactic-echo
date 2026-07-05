# Tactic Echo 1.0.50 P5.5 基线：双 action-info 宏身份兼容与 P4.3 动作链恢复

## 本轮实机失败的直接证据

最新 SavedVariables 显示，当前可见打断按钮位于槽位 `60`，类型为 `macro`，具有真实键位 `` ` `` 与 `BindingToken=20`。同一按钮的动作 API 返回打断技能 `147362`，但宏正文/有效 numeric macro index 不可读。

P5.4 已让读条完成兼容资格：

```text
compatibilityEvidenceSamples = 3
compatibilityEvidenceAge >= 0.40
confirmationReason = compat_active_cast_no_hard_steel
```

但随后连续记录：

```text
reason = macro_managed_target_target_unverifiable
bindingToken = 0
```

没有任何 `dispatchOrigin=reaction`。

根因不是钢条或冷却门控，而是 P5.4 只接受 `macroAssociation=action_info_represented_spell`。当前客户端把同一可见宏按钮匹配为 `action_info_macro_spell`，因此 P5.4 的 target-only transport 路由没有注册，流程落回旧目标管理宏拒绝分支。

## P5.5 规则

### 1. 双 action-info 精确身份

正文/索引不可读时，只要当前可见默认动作栏宏按钮满足以下全部条件，就可登记 target-only P4.3 transport：

- 按钮 action type 为 `macro`；
- 当前请求的打断 SpellID 与该动作 API 的精确身份一致；
- 身份来源为以下任一项：
  - `action_info_represented_spell`；
  - `action_info_macro_spell`；
- 当前按钮已有真实 BindingToken；
- 当前宏正文确实不可读，且没有 `macro_semantic_identity_ambiguous`。

对应路由分别记录：

```text
action_info_represented_spell_compat
action_info_macro_spell_compat
```

两条路径都只针对当前实际按钮的 `target` transport。它们不按宏名恢复正文、不枚举宏列表猜测当前绑定、不推断 `focus` 或 `mouseover` 分支，也不用于 AutoBurst。

### 2. 钢条与冷却规则不变

兼容候选仍需：

- 同一 `castKey` 的 3 次不同 shared-observation；
- 首样本后的 0.40 秒钢条稳定窗口；
- 写入候选前重新读取事件缓存；
- 不存在 API 明确不可打断、真实可见盾、`NOT_INTERRUPTIBLE`、native 明确不可打断或 native scalar/method 钢条嫌疑。

候选路由建立后，仍以 TEK 实际会按下的 action slot 做只读 CD 采样。已知非 GCD 自身 CD 时：

```text
reason = interrupt_action_cooldown
bindingToken = 0
kind = none
```

不得生成 reaction candidate 或占用主键。

## 宏兼容性

本版扩大的是当前实际动作栏宏的既有兼容，不修改任何宏文本、宏发现、绑定、手动使用、TEAP、TEK 或输入门禁。宏列表中存在的其他宏不参与该 target transport 的身份推断。
