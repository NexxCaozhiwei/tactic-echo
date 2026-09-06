# Tactic Echo 1.5.7 基线

继承 1.5.6；修复角色饰品宏的 item 子类型被误判为账号宏索引。

- 实机只读输出：动作槽 33“饰一”为 `macro 32 item`，动作槽 34“饰二”为 `macro 144`；13 号装备 ItemID 为 250215，旧解析返回 `actionbar_inventory_slot_not_found`。
- `item` 子类型必须先于数字宏索引路径处理，不能把 32 当成宏索引或代表 SpellID，也不以该数字读取 opaque 名称。
- 复用当前动作条精确名称、唯一当前宏索引及已解析正文的恢复路径。槽位 13/14、单物品 use 正文和既有 item sequence 仍需后续共享语义匹配；同名歧义、无名称、正文不可读、双饰品槽位不授权。
- 无 item 子类型的有效 numeric macro index 仍只读取同一索引，失败不得扫描替代；“饰二”重复两行 use 14 不等于双饰品宏。
- 不修改用户宏、按键、AutoBurst 计划或输入门控，不硬编码角色名、宏名、动作槽或 ItemID。HUD 与自动注入共享修复后的 resolver。
- 新增精确截图形态的失败复现与修复回归、角色宏第 23/24 项、歧义/无名称/双饰品/无按键以及指定物品宏兼容测试。

本地验证：全量 pytest 758 passed、7 skipped、17 subtests passed；随后补充单物品兼容用例，宏专项共 10 项通过。TEK unittest 227 项、AddOn unittest 243 项、52 个 Lua 语法、compileall 和基线契约均通过；部署不等于客户端实机验收。
