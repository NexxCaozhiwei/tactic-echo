# TEF 0.5.0 HUD / TEUI移植与TEK兼容

参考源码：TE UI/TacticalIconButton.lua、TacticalHudLayout.lua、TacticalHudStyles.lua、ControlPanel.lua。独立实现，不调用TE内部函数，不读取TE配置，不加载退役功能。

本次移植的结构：64px主卡与44px练习预览横向排列；原生IconFrame背景、3px内缩图标、圆角遮罩、裁剪冷却平面、独立上层Atlas边框、最高层文本。主键/练习来源左上，真实键位右上，CD纯秒数居中，充能右下，推荐/暂停/施法/引导状态左下；名称及常驻进度/请求状态位于下方。紧凑工具行保留人工启停、许可、请求、设置。低透明背景代替大面积控制面板。原测试窗口仍由/tef test打开。

TEUI移植：独立/tefui入口，820x600可拖动设置中心，标题/版本区、145px侧栏、选中高亮、页标题与内容区；配置草稿、六个现有功能页及运行开关保留。当前练习预览不是TE AutoBurst，不显示HAD或声称自动注入资格。所有状态和冷却仅展示，布局战斗内延期。

TEF继续输出TEAP v3，不另造TEFAP。TE和TEF的颜色、magic、长度、CRC、commit及BindingToken编码统一，现阶段只能保留一个信号源。TEK共享定位与运行解码新增有实测整帧CRC依据的1.2伽马映射，同时保留原始颜色模式。三个固定头字节选择映射；红/绿互补颜色恢复字节，固定蓝色校验保留。实机1色阶量化歧义仅允许检查最多64种组合，必须恰有一帧通过完整CRC/magic/commit，否则拒绝；不扩大颜色容差。损坏、其它变换和超限均拒绝。无新协议位、不修改Hook/前台/手动让权/限频/重放门禁、不修改客户端CVar。

安装后先/reload确认0.5.0和默认暂停，再启动新版桌面TEK UI联动。先看paused/observation帧可识别，再按每步人工派发测试。TEKinputSent与游戏SUCCEEDED分别核对。此版本不是自动APL或自动循环请求，HUD不证明技能ready。TEK生产客户端已重新打包，但真实SendInput、不同显示伽马以及新HUD实机外观仍需验收；只支持标准颜色和实测1.2变换。

本次追加验收：新版HUD/TEUI已实际加载并查看；新版生产TEK已识别TEF，用户主动请求后Windows SendInput返回成功（键1/2/3）。用户主观外观确认、其它显示变换和游戏成功计步仍分别验收。详见VALIDATION.md。
