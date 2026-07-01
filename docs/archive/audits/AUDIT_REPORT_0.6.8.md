# AUDIT REPORT — 0.6.8-wow-safe-hud-burst

## 实机反馈修复

1. `ProtocolMonitor.lua` 的 `Frame:RegisterEvent()` 仍触发 `ADDON_ACTION_FORBIDDEN`：已移除战术模块事件注册，改为 `OnUpdate` polling-safe。
2. `TacticalTelemetry.lua` 比较 `targetCastSpellID` 时触发 secret number：已停止保存/比较目标读条 SpellID。
3. TEUI 缩小态过大：已调整为 350×100，并仅保留运行控制。
4. HUD 视觉与交互：移除边框，官方推荐图标放在左上角并支持左键拖动 HUD。
5. HUD 文案：`打断·提示` / `防御·提示` 简化为 `打断` / `防御`。
6. 爆发设置：新增爆发策略和显示模式设置。

## 测试

- `pytest -q`：185 项通过。
- `python3 -m unittest discover -s tests/unit -q`：54 项通过。
- `python3 -m unittest discover -s tek/tests -q`：124 项通过。
- Python 编译检查通过。
- TOC 27 条 Lua 加载路径存在。

## 未验证

- WoW 客户端内无 taint 报错需用户实机 `/reload` 后确认。
- 打断/防御/爆发显示效果需实战确认。
