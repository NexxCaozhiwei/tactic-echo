# WLK Hekili 法师 APL → TEF 迁移审计

> 目的：不是把 WLK Hekili 原样复制到 TEF，而是把它当作法师 APL 的规则来源与状态需求清单。

## 1. 已确认的源结构

Hekili 内置 Pack 的编码链：

```text
AceSerializer → LibDeflate → EncodeForPrint → Hekili:...
```

解包后每套 Pack 都包含 `lists`，每条规则主要包含 `action`、`criteria`、`enabled`，以及可选的 `list_name`、`line_cd`、`cycle_targets`、`use_off_gcd` 等字段。

## 2. 三套 Pack 规模

| Pack | 不同 action | 规则中出现的 action 次数 | 带 criteria 的规则 |
|---|---:|---:|---:|
| 奥术 Wowhead | 23 | 23 | 10 |
| 火焰(黑科研) | 24 | 33 | 23 |
| 冰霜 Wowhead | 26 | 28 | 18 |

## 3. APL 实际依赖的状态类型

### `action`

`action.fireball.cast_time`, `action.frostbolt.in_flight`, `action.frostfire_bolt.in_flight`, `action.global_thermal_sapper_charge.ready`

### `active_enemies`

`active_enemies`

### `boss`

`boss`

### `buff`

`buff.arcane_brilliance.down`, `buff.arcane_intellect.down`, `buff.brain_freeze.react`, `buff.combustion.up`, `buff.fingers_of_frost.stack`, `buff.fingers_of_frost.up`, `buff.fire_ward.up`, `buff.firestarter.up`, `buff.heating_up.down`, `buff.heating_up.up`, `buff.hot_streak.down`, `buff.hot_streak.up`, `buff.icy_veins.down`, `buff.incanters_absorption.down`, `buff.magic_damage_increase.down`, `buff.magic_damage_increase.remains`, `buff.magic_damage_increase.up`, `buff.missile_barrage.down`, `buff.missile_barrage.up`, `buff.pushing_the_limit.remains`, `buff.pushing_the_limit.up`, `buff.quad_core.remains`, `buff.quad_core.up`, `buff.unique_armor.down`

### `cast_time`

`cast_time`

### `cooldown`

`cooldown.deep_freeze.remains`, `cooldown.icy_veins.remains`

### `debuff`

`debuff.arcane_blast.stack`, `debuff.frozen.up`, `debuff.living_bomb.down`, `debuff.living_bomb.remains`

### `latency`

`latency`

### `mana`

`mana.pct`

### `mana_gem_charges`

`mana_gem_charges`

### `moving`

`moving`

### `pet`

`pet.active`

### `prev_gcd`

`prev_gcd.6.arcane_blast`

### `raid`

`raid`

### `talent`

`talent.deep_freeze.enabled`, `talent.incanters_absorption.enabled`

### `target`

`target.health.pct`, `target.time_to_die`, `target.within10`, `target.within12`, `target.within20`

## 4. 对 TEF 的含义

第一阶段 TEF 不应追求一次性支持全部 Hekili 条件。应给每个条件建立 capability 状态：`SUPPORTED / DERIVABLE / SECRET_VISUAL_CANDIDATE / UNSUPPORTED / UNVERIFIED`。

建议优先实现的公共条件：

- `action.<x>.known`
- `action.<x>.usable`
- `action.<x>.in_range`
- `action.<x>.power_ok`
- `gcd.ready`
- `active_enemies`（按 TEProbe 已验证的观察模型）
- `talent.<x>.enabled/rank`
- `moving`（若公开且稳定）

建议第二阶段处理：

- `mana.pct` → Secret/量化状态路线
- `cooldown.<x>.remains` → 不直接要求精确秒数，优先 Ready Secret Bool
- `buff/debuff` → 取决于无限服 Aura 能力
- `target.health.pct` → Secret/量化路线

暂不应承诺支持：

- `target.time_to_die`
- `action.<x>.in_flight`（若缺少可靠 combat log/事件）
- `prev_gcd.N.<x>` 的完整模拟
- Hekili 的未来状态预测/多步仿真
- WLK glyph/set bonus/工程道具等无限服未验证内容

## 5. 推荐迁移策略

```text
Hekili Pack
  ↓ 解包
Raw Action Lists
  ↓ 条件规范化
TEF Condition AST
  ↓ Capability Gate
支持的规则 → TEF Pack
不支持的规则 → 明确标记/禁用/降级
```

不要静默删除条件，也不要把未知条件当 false 后继续声称规则已等价迁移。

## 6. 法师架构建议

保留统一的 Mage 能力/天赋模型，同时允许多个“构筑 APL Pack”：Arcane、Fire、Frost、Arcane-Fire、Frost-Arcane 等。Pack 不是现代专精，而是天赋构筑规则模板。

Selector 应基于实际天赋分布和关键天赋，而不是 `GetSpecialization()`。

规则内部仍可继续检查具体 talent/known ability，避免仅凭构筑标签做硬切换。

## 7. 下一步

1. 把三个 JSON 当作原始参考数据保存，不直接运行。
2. 建立 Hekili 条件字段 → TEF Capability 的映射表。
3. 对照无限服实际法师技能/天赋表逐条标记 `KEEP / ADAPT / DROP / BLOCKED / UNVERIFIED`。
4. 先迁移一套最容易闭环的法师构筑，验证 State → APL → Recommendation。
5. 再处理 Secret Aura/Mana/Cooldown 状态。