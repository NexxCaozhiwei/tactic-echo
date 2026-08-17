# P5 宏身份锚定实机验收

## 目的

验证同名宏（尤其中文“打断”）不再影响 `反制射击` 多行宏的识别。P5 只能把当前动作条所引用的 numeric macro index 视为宏身份；同名账号/角色宏不会被借用。

## 准备

1. 将以下宏放在**当前可见 Blizzard 默认动作条**，绑定受支持实体键位：

```lua
#showtooltip
/stopcasting
/cast [@focus,nodead] 反制射击
/cleartarget
/targetenemy
/cast 反制射击
/targetlasttarget
```

2. 将该宏分别命名为 `打断`、`DDD`，两种名称都应得到一致结果。
3. 可额外创建另一枚同名 `打断` 宏（账号宏或角色宏均可），但它不要包含 `反制射击`；此项用于验证不再发生按名字错配。

## 验收步骤

1. 覆盖 AddOn，游戏内 `/reload`。
2. 执行 `/tecache refresh`，打开自动打断的动作条映射。
3. `反制射击` 应显示为焦点/当前目标的宏内目标路由，且改名 `打断` 与 `DDD` 的结果相同。
4. 若未识别，执行 `/temapping p5_macro_identity`，保存退出后查看 `TacticEchoDB.diagnostics.mappingExport`：
   - `macroIdentitySource = "action_info_id"`；
   - `macroActionInfoMacroIndex` 为动作条实际引用索引；
   - `macroIdentityVerified = true` 表示同一 numeric index 已成功取到正文；
   - `macroActionInfoReadAttempts` 为 1～3；
   - 不得出现宏正文。
5. 若动作条 index 连续三次都无法取得正文，应当看到 `macro_body_unavailable` / `macro_body_unavailable_action_info_id`，且**不得**因为另一枚同名宏而被识别为可自动打断。

## 不在本验收范围

- 不改变 P4.4 钢条/可打断资格；
- 不测试自动目标、鼠标移动或宏分支解释；
- 不需要重新构建 TEK.exe。
