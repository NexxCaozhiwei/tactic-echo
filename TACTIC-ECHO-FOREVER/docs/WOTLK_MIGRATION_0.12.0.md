当前0.12.1：用户明确授权取消APL GCD条件与61304查询；其他条件不变。失败身份采用原4096共享预算，取消重复128失败上限。以下旧版本GCD限制作为历史记录，按本条覆盖。详见docs/PRODUCTION_0.12.1.md。

# WotLK规则逐条迁移清单

三个模板属于同一MAGE_FOREVER_60 Class Pack，手动选择，不使用现代专精或猜测天赋。源文件完整保留，JSON不在游戏内执行。

KEEP保留、ADAPT明确适配、DROP源停用或范围外、BLOCKED未闭合。所有可执行技能仍要求公开已学/可用/资源双布尔/范围/自身CD/GCD。未知零Token。

ADAPT：AoE调用还要求手动多目标场景，visible count不是实际命中数；普通最终填充默认依源模板，显式选择覆盖只修改最终填充位置，不解除上层条件。火焰原AoE调用关闭仍保持关闭。气定只保留在奥术AoE原位置。

|模板/列表/行|技能|分类|原因|原条件|
|---|---|---|---|---|
|arcane:aoe:1|arcane_explosion|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|target.within10|
|arcane:aoe:2|presence_of_mind|KEEP|PUBLIC_CONDITIONS||
|arcane:aoe:3|blizzard|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED||
|arcane:aoe:4|flamestrike|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED||
|arcane:default:1|counterspell|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|arcane:default:2|spellsteal|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|arcane:default:3|remove_curse|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|arcane:default:4|fire_ward|DROP|OUTSIDE_COMBAT_DPS_SCOPE|talent.incanters_absorption.enabled & buff.incanters_absorption.down & action.global_thermal_sapper_charge.ready|
|arcane:default:5|global_thermal_sapper_charge|DROP|OUTSIDE_COMBAT_DPS_SCOPE|talent.incanters_absorption.enabled & buff.incanters_absorption.down & buff.fire_ward.up|
|arcane:default:6|potion|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|arcane:default:7|arcane_power|KEEP|PUBLIC_CONDITIONS||
|arcane:default:8|icy_veins|KEEP|PUBLIC_CONDITIONS||
|arcane:default:9|mirror_image|KEEP|PUBLIC_CONDITIONS||
|arcane:default:10|use_items|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|arcane:default:11|call_action_list|ADAPT|MANUAL_SCENE_VISIBLE_COUNT|active_enemies > 2|
|arcane:default:12|arcane_missiles|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|debuff.arcane_blast.stack = 4 & ( buff.missile_barrage.up &#124;&#124; prev_gcd.6.arcane_blast )|
|arcane:default:13|arcane_barrage|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|debuff.arcane_blast.stack = 4 & buff.missile_barrage.down & moving|
|arcane:default:14|arcane_blast|ADAPT|EXPLICIT_FILLER_OVERRIDE_OR_SOURCE_FALLBACK||
|arcane:default:15|replenish_mana|DROP|OUTSIDE_COMBAT_DPS_SCOPE|mana.pct < 70|
|arcane:default:16|evocation|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|mana.pct < 10|
|arcane:precombat:1|arcane_brilliance|DROP|OUTSIDE_COMBAT_DPS_SCOPE|raid & buff.arcane_brilliance.down|
|arcane:precombat:2|arcane_intellect|DROP|OUTSIDE_COMBAT_DPS_SCOPE|! raid & buff.arcane_brilliance.down & buff.arcane_intellect.down|
|arcane:precombat:3|mage_armor|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:2T10:1|fireball|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|(debuff.living_bomb.remains > 6 or debuff.living_bomb.down) & (buff.pushing_the_limit.remains > (cast_time +latency) ) & (buff.heating_up.down or (buff.heating_up.up & buff.hot_streak.down ) )|
|fire:2T10:2|pyroblast|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.heating_up.up & buff.hot_streak.up|
|fire:default:1|nitro_boosts|DROP|OUTSIDE_COMBAT_DPS_SCOPE|defile_target_is_me|
|fire:default:2|counterspell|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:default:3|spellsteal|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:default:4|mirror_image|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|down|
|fire:default:5|combustion|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|down & (debuff.living_bomb.remains > 6  or debuff.living_bomb.down) & ((buff.quad_core.up & buff.magic_damage_increase.up) or (buff.quad_core.remains < 7 & buff.magic_damage_increase.down) or buff.magic_damage_increase.remains > 5 or target.health.pct < 36)|
|fire:default:6|icy_veins|KEEP|PUBLIC_CONDITIONS||
|fire:default:7|flame_cap|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:default:8|potion|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:default:9|use_items|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:default:10|living_bomb|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|target.time_to_die > 12 & debuff.living_bomb.down|
|fire:default:11|call_action_list|DROP|SOURCE_DISABLED|active_enemies > 2|
|fire:default:12|call_action_list|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|buff.combustion.up|
|fire:default:13|pyroblast|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.hot_streak.up & buff.magic_damage_increase.remains <( action.fireball.cast_time +latency )|
|fire:default:14|call_action_list|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|buff.pushing_the_limit.up|
|fire:default:15|pyroblast|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.hot_streak.up|
|fire:default:16|fire_blast|KEEP|PUBLIC_CONDITIONS|moving|
|fire:default:17|frostfire_bolt|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|glyph.frostfire.enabled|
|fire:default:18|fireball|ADAPT|EXPLICIT_FILLER_OVERRIDE_OR_SOURCE_FALLBACK||
|fire:precombat:1|arcane_brilliance|DROP|OUTSIDE_COMBAT_DPS_SCOPE|raid & buff.arcane_brilliance.down|
|fire:precombat:2|arcane_intellect|DROP|OUTSIDE_COMBAT_DPS_SCOPE|! raid & buff.arcane_brilliance.down & buff.arcane_intellect.down|
|fire:precombat:3|molten_armor|DROP|OUTSIDE_COMBAT_DPS_SCOPE|buff.unique_armor.down|
|fire:precombat:4|focus_magic|DROP|OUTSIDE_COMBAT_DPS_SCOPE|group & active_dot.focus_magic = 0|
|fire:aoe:1|blast_wave|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|target.within10|
|fire:aoe:2|flamestrike|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.firestarter.up|
|fire:aoe:3|dragons_breath|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|target.within12|
|fire:aoe:4|blizzard|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED||
|fire:combustion:1|hyperspeed_acceleration|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|fire:combustion:2|fireball|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|buff.heating_up.up & buff.hot_streak.up|
|fire:combustion:3|pyroblast|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.heating_up.up & buff.hot_streak.up|
|fire:combustion:4|pyroblast|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.hot_streak.up|
|fire:combustion:5|fireball|KEEP|PUBLIC_CONDITIONS||
|frost:default:1|counterspell|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|frost:default:2|spellsteal|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|frost:default:3|mirror_image|KEEP|PUBLIC_CONDITIONS||
|frost:default:4|summon_water_elemental|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|! glyph.eternal_water.enabled|
|frost:default:5|icy_veins|KEEP|PUBLIC_CONDITIONS||
|frost:default:6|arcane_power|KEEP|PUBLIC_CONDITIONS||
|frost:default:7|flame_cap|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|frost:default:8|potion|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|frost:default:9|cold_snap|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|use_cold_snap & buff.icy_veins.down & cooldown.icy_veins.remains > 60|
|frost:default:10|use_items|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|frost:default:11|deep_freeze|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|( debuff.frozen.up &#124;&#124; buff.fingers_of_frost.stack = 1 ) & ( action.frostfire_bolt.in_flight &#124;&#124; action.frostbolt.in_flight )|
|frost:default:12|frostbolt|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|buff.fingers_of_frost.up & talent.deep_freeze.enabled & cooldown.deep_freeze.remains < cast_time * buff.fingers_of_frost.stack|
|frost:default:13|frostfire_bolt|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|buff.brain_freeze.react|
|frost:default:14|blizzard|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|active_enemies > 2 & ! moving|
|frost:default:15|cone_of_cold|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|active_enemies > 2 & target.within10 & moving|
|frost:default:16|arcane_explosion|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|active_enemies > 2 & target.within10 & moving|
|frost:default:17|fire_blast|BLOCKED|SOURCE_CONDITION_UNSUPPORTED|moving & target.within20|
|frost:default:18|best_mana_potion|DROP|OUTSIDE_COMBAT_DPS_SCOPE||
|frost:default:19|replenish_mana|DROP|OUTSIDE_COMBAT_DPS_SCOPE|mana.pct < 70|
|frost:default:20|evocation|BLOCKED|ABILITY_SEMANTICS_UNVERIFIED|mana.pct < 30|
|frost:default:21|frostbolt|ADAPT|EXPLICIT_FILLER_OVERRIDE_OR_SOURCE_FALLBACK||
|frost:precombat:1|arcane_brilliance|DROP|OUTSIDE_COMBAT_DPS_SCOPE|raid & buff.arcane_brilliance.down|
|frost:precombat:2|arcane_intellect|DROP|OUTSIDE_COMBAT_DPS_SCOPE|! raid & buff.arcane_brilliance.down & buff.arcane_intellect.down|
|frost:precombat:3|conjure_mana_gem|DROP|OUTSIDE_COMBAT_DPS_SCOPE|mana_gem_charges < 2|
|frost:precombat:4|molten_armor|DROP|OUTSIDE_COMBAT_DPS_SCOPE|buff.unique_armor.down|
|frost:precombat:5|summon_water_elemental|DROP|OUTSIDE_COMBAT_DPS_SCOPE|! pet.active & glyph.eternal_water.enabled|
|frost:precombat:6|focus_magic|DROP|OUTSIDE_COMBAT_DPS_SCOPE|group & active_dot.focus_magic = 0|
|frost:precombat:7|pyroblast|DROP|OUTSIDE_COMBAT_DPS_SCOPE|boss|

## 条件能力

SUPPORTED：公开known/usable/power_ok/in_range、自身CD/GCD的公开0/0证据、实际人才rank、公开移动布尔。
ADAPT：active_enemies改为有界可见敌人观察且要求手动multi。
UNVERIFIED/BLOCKED：Aura/Debuff、层数、proc、冷却剩余秒数、target.withinN、血量/法力百分比、TTD、飞行中法术、prev_gcd、glyph、装备套装/工程物品、pet、未来预测。未删原条件，不以未知=false宣称等价。

来源SHA256：
```json
{
  "HEKILI_WOTLK_MAGE_APL_EXTRACTED.md": "0E2E99A7C462AE4A0751943C82E656689DD738A77BC5C3C0708D427503027254",
  "HEKILI_WOTLK_MAGE_TO_TEF_AUDIT.md": "1F6297A312091AEA43D49EB9B3E57FC8FE0EC74158BEB1F62000E734762718F9",
  "mage_arcane_wotlk.json": "7F35ECAD2DC54A111D3032EB5930464D3F76A353CC64CE40CA9CD06C64538CE0",
  "mage_fire_wotlk.json": "EB095F9DE02DAEBD16F178A8EFC7C87349105D40F3C098BDC59D8E20452FDA9C",
  "mage_frost_wotlk.json": "BC9D036171EA0064C7F18F36C04800C1682AFCB58F5367972A58C45307106E9B"
}
```
