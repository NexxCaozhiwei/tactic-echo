# TEF 0.8.2

用户明确覆盖旧版全局移动门禁与失败永久停机策略。学习TE SignalFrame普通推荐和TEK手动优先：持续当前候选、临时阻断/让权后恢复、失败不计步且原步重核尝试。未发起候选被顺序外读条撤回时释放等待；已发起当前步保持成功关联。移动不是全局派发资格，公开target/range/usable、读条/引导存在性、真实精确绑定及Secret边界仍保守。

TEAP v3和TEK Windows门禁不变，不改TE/TEK/WTF、不增加宏/APL/输入通道。版本同步VERSION/Config/TOC/Bootstrap/CHANGELOG，旧基线保留。141项Lua5.1、6 decoder/dry-run、3精确编码、1预算、2手动恢复互操作，仓库pytest789/skip7/subtests17、TEK234/AddOn244/mock2，baseline/compileall/Lua语法通过。安装20文件SHA256核对，16加载入口、Interface16001、单层ZIP，旧TEF完整备份。

本轮读取0.8.0/S46与后续0.8.1/S47：后者已有移动恢复与旧失败隔离部分记录，仍不是0.8.2实机证据。原逻辑学习与差异见TACTIC-ECHO-FOREVER/docs/TE_DISPATCH_PARITY_0.8.2.md，短测见PRODUCTION_0.8.2.md。
