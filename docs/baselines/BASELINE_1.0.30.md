# Tactic Echo 1.0.30 基线：HUD CD 数字连续性修复

- 仅修 HUD 冷却数字的呈现连续性；不修改 AutoBurst、TEAP、TEK 或输入门禁。
- 直接动作条在共享 GCD 与自身 CD 同时存在时，优先保留已确认的自身 CD。
- HUD 已读取到的真实 CD 数字会在同一卡片遭遇一次 API 数值不可读时连续显示，直至 API 重同步、CD 结束或卡片身份变更。
- 不使用 Tooltip/Base CD 伪造直接动作条的实际 CD；无法获得或延续安全数值时仍显示空白而非错误数字。
