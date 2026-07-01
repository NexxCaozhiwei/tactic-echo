# Windows 构建 `TEK.exe`

在项目根目录双击 `TEKEXEBUILD.CMD`。该文件是唯一的 Windows 构建入口。

该入口会：

1. 检查 64 位 Python 3.11+；
2. 安装 `requirements-windows.txt` 中缺失依赖；
3. 运行基线合同、pytest、`tek/tests`、`tests/unit` 和 Python 编译检查；发现 `texluac` 或 `luac` 时追加 Lua 语法检查；
4. 在隔离的 `build\tek-stage-*` 目录执行 PyInstaller；
5. 尝试发布到 `dist\TEK.exe`。

## 产物锁定处理

若旧 `dist\TEK.exe` 被占用，脚本只会尝试停止**路径精确匹配**该文件的旧 TEK 进程。无法安全替换时，旧文件保留，新产物输出为：

```text
dist\TEK.new.exe
```

或带时间戳的等价回退文件。脚本不会自动删除 AddOn 的旧目录或任意第三方文件。

## 手工验收

构建成功不等于实机输入已通过。按以下命令执行受限验收：

```powershell
.\scripts\verify-tek-sendinput.ps1 -TekExe .\dist\TEK.exe
```

它先验证 Notepad，再验证 WoW 前台与非前台保护；不要跳过 [PRIORITY_A_MANUAL_CALIBRATION.md](PRIORITY_A_MANUAL_CALIBRATION.md) 的完整清单。
