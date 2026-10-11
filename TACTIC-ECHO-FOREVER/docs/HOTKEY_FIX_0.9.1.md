# TEF 0.9.1 快捷键保存与恢复

用户报告上一版快捷键无效、reload后录入消失。修复开始时只读TEF_DB为0.8.2/S49，dispatch.hotkey为空；交付核对时文件已由游戏更新为0.9.0/S51（16:15:27），hotkey仍为空。后一文件SHA256为2AD2332C38F0D47DEDF8C5FB9600112807648164E295D8BA222424207CF2AC4B，不是0.9.1实机验证。源码确认“录入”只写EditBox，未提交TEF_DB，须另外点击应用；这条容易误判已保存。另有绑定生命周期缺口：仅ADDON_LOADED尝试应用，没有PLAYER_LOGIN与UPDATE_BINDINGS重核。没有实机证明后者就是本次无效的唯一原因。

0.9.1按键录入成功后直接保存TEF_DB.dispatch.hotkey并申请应用；手输字符串仍须点击“保存”或回车。Esc保留原绑定，冲突/未知不替换保存值。按键录入时启用键盘捕获并阻止传播；快捷键只执行已有TEF_TOGGLE_DISPATCH命令，控制唯一派发意图，不直接施法、不改技能绑定、宏、CVar或SaveBindings。

沿用原TE“保存偏好与临时override分离、战斗延迟”的方法，但保持TEF原来的SetOverrideBinding→Bindings.xml控制命令，不新增隐藏施法按钮。恢复时在ADDON_LOADED、PLAYER_LOGIN、PLAYER_ENTERING_WORLD、UPDATE_BINDINGS与脱战事件尝试；调用受保护绑定API只在明确脱战。已经验证的同一键只读核对，不清除或重装；同步事件有重入保护，避免自身绑定刷新形成循环。

GetBindingAction含override核对当前命令，Clear/Set调用失败、返回Secret/false、读回未知或失配，不提示已生效。合法保存偏好与实际应用状态分开显示，恢复失败不会清空已保存键。未设置、冲突、等待脱战、应用/验证失败均固定分类记录，不保存API原值或异常全文。此前空值无法推断恢复，需用户重新录入一次。

178项Lua5.1模拟通过，包括实际UI录入回调立即保存、组合键/取消/冲突、手输回车/按钮、白名单reload重建、setter静默失败与Secret、刷新幂等及恢复、同步重入、战斗延迟和登录前失败后重试。原0.9.0序列编辑与次数测试保留。游戏加载、真实键位触发、reload后是否恢复仍未实机验收。

短测：脱战 `/tef stop` → `/reload` → `/tefui`，确认0.9.1。总览选择手动启停、关闭自动启动，点击“录入”后按一个未占用组合键（如未被绑定的Ctrl+Shift+F8），须显示已保存及已生效。关闭设置，按一次开、再按一次停，HUD应改变意图状态；没有目标时可显示阻断，但第二次仍须停。正常reload，再看同一键仍在且已生效，复按两次。最后 `/tef stop` 正常reload/退出，回复“已落盘”。不要求先做0.9.0的序列实测。
