# 测试策略

## 自动测试

在项目根目录执行：

```bash
PYTHONPATH="$PWD" python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

再执行：

```bash
python scripts/verify-baseline-contract.py --repo-root .
```

AddOn 还要做 Lua 词法/编译检查、TOC 路径检查，并扫描 HUD/Tactics 文件，确认它们没有直接 `RegisterEvent()`。构建机存在 `texluac` 或 `luac` 时，应对全部 AddOn Lua 追加语法检查。

当前契约覆盖：TEAP v3 Token、未知 ActionCode、帧新鲜度、物理输入让权、限频、前台保护、环境 TTL、宏只读边界、默认动作条缓存、secret-number 降级、Burst Window Helper、队列 HUD 组件、固定槽位、防抖、独立防御队列和显示层不修改派发链路。

## 人工门禁

WoW UI 行为、原生 atlas/遮罩、拖拽保存、Windows 多屏/DPI、实际 `SendInput`、第三方动作条、各职业/专精战术数据均不应由离线测试替代。详见 [PRIORITY_A_MANUAL_CALIBRATION.md](PRIORITY_A_MANUAL_CALIBRATION.md)。
