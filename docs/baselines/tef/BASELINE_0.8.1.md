# TEF 0.8.1

继承0.8.0统一Runtime与独立HUD/TEUI。S45已观察单纯移动临时阻断恢复，但失败事件按ID误停；移动期间公开失败改为保留意图与原步恢复，迟到移动身份有界隔离；静止失败仅当前代次/步骤/SpellID/GUID起始关联匹配才关闭意图。未知身份/移动检测保守零Token，Secret不比较/不保存。容量满额fail-closed，reload不恢复旧请求或身份。

不改变TEAP v3、TEK输入门禁、direct exact binding、SUCCEEDED计步或CD/GCD展示边界，不改TE/TEK/WTF。132项Lua5.1模拟，仓库pytest789/skip7/subtests17，TEK234/AddOn244/mock2，baseline/compileall/Lua语法/TOC与加载列表验证。部署20文件逐文件SHA256，已有TEF完整备份、未知文件保留。新版实机验收见TACTIC-ECHO-FOREVER/docs/PRODUCTION_0.8.1.md。
