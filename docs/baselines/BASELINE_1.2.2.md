# Tactic Echo 1.2.2 基线：HUD 设置中心打开修复

## 变更范围

- 1.2.1 恢复 HUD 标签样式编辑时遗漏 `createColorChoice` 控件，导致 HUD 页创建时调用未定义函数。
- 1.2.2 在既有 `createChoice` 之上恢复颜色选择器；快捷键、充能/可用次数、HUD CD 秒数和状态文字的颜色选项均可正常创建和写入已有样式字段。

## 不变边界

- 标签样式和颜色选择器只影响 HUD 呈现；不得创建 BindingToken、改写官方推荐、影响 AutoBurst、写 TEAP 或请求 TEK 输入。
- HUD 范围、CD 纯秒数、DurationObject 转盘和全部战斗保护约束继续遵循 1.2.1/1.2.0。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_hud_ui_options_contract.py -k "not interrupt_control_and_defensive_display_modes_are_configured"`
- 全部 AddOn Lua 文件通过 `luac -p`。
