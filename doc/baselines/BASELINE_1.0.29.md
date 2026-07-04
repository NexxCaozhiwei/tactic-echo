# Tactic Echo 1.0.29 基线：统一 HUD 自定义 CD 文本与直接动作条真实计时

## 范围

本版修复 1.0.27 的展示型回退：为避免覆盖/天赋变体将真实动作条 60 秒 CD 错读为 120 秒，旧版把所有直接动作条技能强制切换为 Blizzard 原生数字。该回退绕过了 HUD 的字体、颜色、缩放和位置设置，造成爆发、打断/控制、防御/生存模块与饰品样式不一致，部分卡片还会没有 CD 数字。

本版只修改 HUD 冷却数据来源与数字呈现；不修改 AutoBurst 多步骤队列、简易/集中预检、窗口识别、四帧 handoff、TEAP、TEK、BindingToken、输入门禁或派发节奏。

## HUD 冷却显示契约

- 只有用户显式选择 `原生（不可调整）` 的 `duration` 文本模式时，才显示 Blizzard 原生 DurationObject 数字。
- 用户选择 `自定义` 文本模式时，所有模块继续使用 HUD 可配置的数字样式；包括主键、爆发、打断、控制、防御、生存、药水与饰品。
- 原生 DurationObject 仍可保留转盘与动画，但不再强制接管直接动作条技能的数字文本。
- 因此爆发、打断/控制、防御/生存会再次遵从各自模块的字体、颜色、大小、位置和显示开关；饰品继续使用其原有自定义样式。

## 直接动作条真实数值来源

- 对 resolver 已验证的直接、可信、默认动作条按钮，若动作条公开 API 能安全提供明确的**非 GCD 自身 CD 数值**，`IconState:Collect()` 会将该数值作为 HUD 自定义文本的权威来源：`cooldownSource=actionbar_numeric`。
- 该数值会覆盖同一技能残留、覆盖或天赋变体导致的旧 SpellID / Tooltip 基础 CD。示例：Spell API 临时读为 120 秒，而当前动作条真实 CD 为 60 秒时，HUD 自定义数字显示动作条真实的 60 秒计时。
- 共享 GCD、队列窗口、短时数值、秘密/不透明数值、宏猜测、非直接按钮与不可信按钮都不能形成 `actionbar_numeric` 自身 CD。
- 若直接动作条只给出布尔自身 CD、但未给出可安全读取的数值，HUD 不会伪造静态基础 CD 数字；会保留原生转盘或等待下一次可信数值采样。

## GCD 行为

- 主键与 Burst-window 的纯共享 GCD 继续隐藏数字与 GCD 转盘，保持 1.0.27 的修复目标。
- 共享 GCD 不会被转换为技能自身 CD，也不会被送入 AutoBurst 的 CD 跳过、预检或成功确认逻辑。
- 饰品 13/14 的通用 GCD 隔离保持原样；真实饰品自身 CD 仍用 HUD 可配置文本显示。

## 验证

- `PYTHONPATH=. python -m pytest -q`：`521 passed, 3 subtests passed`
- `python scripts/verify-baseline-contract.py --repo-root .`
- `PYTHONPATH=. python -m compileall -q tek tools`
- 所有 TOC Lua 文件经 `texluac -p`，共 43 个文件。
