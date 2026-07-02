# SimC Window / Inject Parser

面向 Tactic Echo 的离线数据采集工具。它解析 SimulationCraft 的 `ActionPriorityLists`，生成“窗口技能候选 / 注入技能候选 / 条件共现提示”的审核资料。

**它不会修改 AddOn、不会生成 BindingToken、不会写入 TEAP、不会触发 TEK 输入。**

## 数据来源策略

- `ActionPriorityLists/assisted_combat/*.simc`：窗口技能候选来源。
- `ActionPriorityLists/default/*.simc` 中的 `cooldown` / `burst` 列表：注入技能、饰品、药水、种族技能候选来源。
- 注入技能 `if=` 条件中对 `buff/debuff/cooldown/dot` 的引用：仅生成“可能搭配”的审核提示，不自动推断前置或后置顺序。

该策略与 TE 当前定义一致：**窗口技能是辅助战斗/推荐序列中的触发点；注入技能是玩家手动决定启用的大爆发、饰品、药水或种族技能。**

## 运行方式

### 方式一：已有本地 SimulationCraft 仓库

```bat
RUN_SIMC_WINDOW_INJECT.CMD "D:\source\simc"
```

也可以将 SimulationCraft 仓库目录拖到 `RUN_SIMC_WINDOW_INJECT.CMD` 上。

### 方式二：由工具下载官方仓库当前分支

双击运行：

```bat
RUN_SIMC_WINDOW_INJECT_DOWNLOAD.CMD
```

运行器使用 Windows CRLF 换行和 ASCII 控制流；会自动尝试 `py -3`，再尝试 `python`。若两者均不可用，会提示安装 Python 3.10+。下载只在明确执行该 CMD 时发生，默认分支为 `midnight`。下载后会缓存到本工具目录下的 `_cache`，可离线重复使用。

### 命令行筛选特定专精

```bat
py -3 simc_window_inject.py --simc-root "D:\source\simc" --spec paladin_retribution,mage_fire --out-dir output
```

## 输出文件

| 文件 | 用途 |
|---|---|
| `simc_window_inject_review.txt` | 可直接审阅的中文管道表。 |
| `simc_window_inject_candidates.json` | 全量结构化候选、APL 行号、条件、来源。 |
| `simc_window_inject_overrides.template.json` | 角色/专精人工确认模板。 |
| `simc_window_inject_review_seed.lua` | 只读 Lua 审核种子；无 SpellID，未加入 TOC。 |
| `simc_window_inject_source_manifest.json` | 输入 APL 文件 SHA-256、路径与 Git revision（可用时）。 |

## 审核与导入边界

1. 先审核 TXT / JSON；不要把候选列表直接当成真实 TE 数据库。
2. 为候选动作补充当前版本的 SpellID、天赋可用性、目标规则和实际动作条绑定。
3. 在 `overrides.template.json` 中确认 `include / exclude / pairs`。`pairs` 可表达：
   - `order: "pre"`：注入在窗口技能前；
   - `order: "post"`：注入在窗口技能后；
   - `readiness_mode: "all_ready" | "any_ready" | "min_ready"`。
4. 只有完成审核、SpellID 映射和后续专门的 TE 数据库导入步骤后，才可能进入 HUD 展示层；本工具不做该步骤。

## 兼容性

- Python 3.10+。
- 无第三方 Python 依赖。
- 支持传入 SimulationCraft 仓库根目录、`ActionPriorityLists` 目录，或 `default / assisted_combat` 子目录。
- 未知的未来职业/专精文件不会中断解析，会按文件名输出并标记为“未映射”。
