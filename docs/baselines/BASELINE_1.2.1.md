# Tactic Echo 1.2.1 基线：HUD 标签样式设置恢复

## 变更范围

- HUD 设置页保留 1.2.0 的四页精简结构，并重新提供主键与 AutoBurst 卡的标签样式编辑。
- 可编辑文字限于快捷键、充能/可用次数、HUD 统一 CD 秒数和状态文字；每类文字可独立设置显示、字体、字号、缩放、锚点、颜色与横/纵偏移。
- 标签样式仍使用既有 `keyLabel`、`chargeLabel`、`cooldownText` 与 `stateText` 持久化字段；旧配置继续经 `Normalize` 迁移和约束。

## 不变边界

- 标签样式只影响 `TacticalIconButton` 的视觉渲染；不得建立 BindingToken、改写官方推荐、影响 AutoBurst 预检/计划、写 TEAP 或请求 TEK 输入。
- HUD 仍只显示主键与 AutoBurst 队列；候选历史、打断、控制、位移、防御和生存保持退役、隐藏或空输出。
- CD 仍由 HUD 徽标统一显示纯秒数，`DurationObject` 只绘制客户端原生转盘。
- 战斗中 HUD 容器和卡片的受保护显隐、透明度、缩放及布局保护保持 1.2.0 行为。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_hud_ui_options_contract.py tests/unit/test_teui_simplification_contract.py`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
