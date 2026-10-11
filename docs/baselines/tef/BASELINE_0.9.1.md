# TEF 0.9.1

继承0.9.0的每套16步骤、每步次数、拖拽/ID编辑与5019保护。修复快捷键录入只留在输入框：成功录入即保存TEF_DB并应用，手输保存/回车；冲突不覆盖，Esc取消。启动命令仍TEF_TOGGLE_DISPATCH、唯一Runtime.intent，不新建施法输入路径。

登录、进入世界、绑定更新、脱战重核临时override；明确脱战才变更，已验证同键幂等及同步事件重入保护。GetBindingAction含override读回精确命令，setter失败/false/Secret/未知不报成功。保存偏好与实际生效状态明确区分。只用TEF自己的数据，不写SaveBindings/动作条/宏/CVar，不改TE/TEK/WTF。

178项Lua5.1模拟与TOC17入口/XML、6 TEK decoder/dry-run、3编码/1预算/2手动恢复互操作通过。必需仓库回归、baseline、compileall与Lua语法验证；21安装文件逐个SHA256核对、旧TEF完整备份、单层源码包。快捷键实际触发/reload及0.9.0编辑功能待实机；S49旧hotkey为空不能推断具体键。详见TACTIC-ECHO-FOREVER/docs/HOTKEY_FIX_0.9.1.md。
