# Tactic Echo 0.6.7 HUD / TEUI Polish Audit

## 修复范围

- TEUI 内容区滚动：所有设置页改为 ScrollFrame 子页，避免图标标签页内容被裁切。
- TEUI 紧凑态：仅保留标题栏、展开、关闭、运行状态和启动/暂停。
- HUD 观感：去除 HUD 标题文字；新增底纹透明度配置。
- HUD 按键标签：新增字型预设、字号、缩放、颜色、位置设置。
- 战术提示条件：打断、控制、防御/生存新增常驻/条件/高亮模式；防御阈值仅使用兼容源百分比。

## 安全边界

- 本次未改变官方主推荐、TEAP、BindingToken 或 TEK 派发链路。
- 防御血量阈值不读取 UnitHealth / UnitHealthMax；只消费 HealthCompatibility 兼容源上报的可选 percent 字段。
- 打断、控制、防御、生存仍为只读显示建议。

## 自动测试

- `PYTHONPATH=. pytest -q`：185 passed。
- `python -m unittest discover tests/unit -v`：54 passed。
- `PYTHONPATH=. python -m unittest discover -s tek/tests -v`：124 passed。
- `python -m compileall -q tek tests scripts`：通过。

## 未实机确认

- WoW 内 ScrollFrame 鼠标滚轮体验。
- HUD 底纹透明度与不同 UI 缩放组合。
- 各职业防御阈值兼容源接入。
