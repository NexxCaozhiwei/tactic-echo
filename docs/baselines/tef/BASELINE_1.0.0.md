# TEF 1.0.0 首个发布基线

本版本冻结0.14.3的现有行为，版本推进不增加运行能力。TE AddOn仍1.5.12，TEF在codex/tef独立开发；首个TEF GitHub Release使用tef-v1.0.0标签，并包含同提交构建的TEK Windows客户端及完整源码。

TEF独立TEF_DB和安装目录、Class Pack、自定义单体/多目标优先级、人工16步骤/每步1～99次、四种循环方式、HUD和配置界面、F5独立启停、三种运行模式及唯一TEAP v3/TEK派发链均继承现状。自定义APL冷却数值检查默认关闭，显式启用才保守判断；CDM精确目录公开状态与UNKNOWN边界保持，不宣称Aura真值或自身ready。旧模板的BLOCKED/UNKNOWN及支持范围不放宽。

客户端验收范围为无限服1.60.1/build70338/Interface16001/zhCN。S76取得战斗候选、10条请求、4条匹配成功收据及Bindings警告消失的保留证据；不将AddOn请求当Windows SendInput次数。未完成的5019固定N次交接、其他职业APL、自动敌人数切场景、精确距离及Secret蓝量条件不宣称已实测通过。完整限制见TACTIC-ECHO-FOREVER/docs/PRODUCTION_1.0.0.md。

发布构建复用既有TEK构建器，独立dist子目录避免替换正在运行的客户端。发布包只含安装文件、TEK.exe、公开示例配置、说明与构建摘要；不得含用户WTF/SavedVariables、日志或本机设置。源码包含一个项目根目录，不含EXE、缓存、生成目录或本机配置。
