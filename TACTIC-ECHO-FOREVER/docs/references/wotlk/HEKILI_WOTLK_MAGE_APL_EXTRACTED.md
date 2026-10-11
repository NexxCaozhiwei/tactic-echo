# WLK Hekili 法师内置 APL 解包结果

> 来源：用户提供的 WLK Hekili 插件压缩包。

三套内置 Pack 已按插件自身格式还原为结构化 Action Pack。以下内容忠实反映源文件，不代表无限服可直接使用。

## 奥术 Wowhead

- Author: `Hekili`
- Source: `https://www.wowhead.com/wotlk/guide/classes/mage/arcane/dps-rotation-cooldowns-abilities-pve`
- Description: 2023-09-24: Initial translation from Wowhead.

### `aoe`

1. **arcane_explosion** — enabled=`True` — `target.within10`
2. **presence_of_mind** — enabled=`True`
3. **blizzard** — enabled=`True`
4. **flamestrike** — enabled=`True`

### `default`

1. **counterspell** — enabled=`True`
2. **spellsteal** — enabled=`True`
3. **remove_curse** — enabled=`True`
4. **fire_ward** — enabled=`True` — `talent.incanters_absorption.enabled & buff.incanters_absorption.down & action.global_thermal_sapper_charge.ready`
5. **global_thermal_sapper_charge** — enabled=`True` — `talent.incanters_absorption.enabled & buff.incanters_absorption.down & buff.fire_ward.up`
6. **potion** — enabled=`True`
7. **arcane_power** — enabled=`True`
8. **icy_veins** — enabled=`True`
9. **mirror_image** — enabled=`True`
10. **use_items** — enabled=`True` — description=Use any trinkets that aren't otherwise specified.
11. **call_action_list** — enabled=`True` — `active_enemies > 2` — list_name=aoe
12. **arcane_missiles** — enabled=`True` — `debuff.arcane_blast.stack = 4 & ( buff.missile_barrage.up || prev_gcd.6.arcane_blast )`
13. **arcane_barrage** — enabled=`True` — `debuff.arcane_blast.stack = 4 & buff.missile_barrage.down & moving`
14. **arcane_blast** — enabled=`True`
15. **replenish_mana** — enabled=`True` — `mana.pct < 70`
16. **evocation** — enabled=`True` — `mana.pct < 10`

### `precombat`

1. **arcane_brilliance** — enabled=`True` — `raid & buff.arcane_brilliance.down` — description=September 2023
2. **arcane_intellect** — enabled=`True` — `! raid & buff.arcane_brilliance.down & buff.arcane_intellect.down`
3. **mage_armor** — enabled=`True`

## 火焰(黑科研)

- Author: `风雪`
- Source: ``
- Description: 本循环由黑科力研究所【风雪】制作 20250731

### `2T10`

1. **fireball** — enabled=`True` — `(debuff.living_bomb.remains > 6 or debuff.living_bomb.down) & (buff.pushing_the_limit.remains > (cast_time +latency) ) & (buff.heating_up.down or (buff.heating_up.up & buff.hot_streak.down ) )`
2. **pyroblast** — enabled=`True` — `buff.heating_up.up & buff.hot_streak.up`

### `default`

1. **nitro_boosts** — enabled=`True` — `defile_target_is_me` — use_off_gcd=1; use_while_casting=1
2. **counterspell** — enabled=`True`
3. **spellsteal** — enabled=`True` — line_cd=spellsteal_cooldown
4. **mirror_image** — enabled=`True` — `down`
5. **combustion** — enabled=`True` — `down & (debuff.living_bomb.remains > 6  or debuff.living_bomb.down) & ((buff.quad_core.up & buff.magic_damage_increase.up) or (buff.quad_core.remains < 7 & buff.magic_damage_increase.down) or buff.magic_damage_increase.remains > 5 or target.health.pct < 36)` — use_off_gcd=1
6. **icy_veins** — enabled=`True`
7. **flame_cap** — enabled=`True`
8. **potion** — enabled=`True`
9. **use_items** — enabled=`True` — description=Use any trinkets that aren't otherwise specified.
10. **living_bomb** — enabled=`True` — `target.time_to_die > 12 & debuff.living_bomb.down` — cycle_targets=1; max_cycle_targets=living_bomb_cap
11. **call_action_list** — enabled=`False` — `active_enemies > 2` — list_name=aoe
12. **call_action_list** — enabled=`True` — `buff.combustion.up` — list_name=combustion; description=燃烧buff
13. **pyroblast** — enabled=`True` — `buff.hot_streak.up & buff.magic_damage_increase.remains <( action.fireball.cast_time +latency )`
14. **call_action_list** — enabled=`True` — `buff.pushing_the_limit.up` — list_name=2T10
15. **pyroblast** — enabled=`True` — `buff.hot_streak.up`
16. **fire_blast** — enabled=`True` — `moving`
17. **frostfire_bolt** — enabled=`True` — `glyph.frostfire.enabled`
18. **fireball** — enabled=`True`

### `precombat`

1. **arcane_brilliance** — enabled=`True` — `raid & buff.arcane_brilliance.down` — description=September 2023
2. **arcane_intellect** — enabled=`True` — `! raid & buff.arcane_brilliance.down & buff.arcane_intellect.down`
3. **molten_armor** — enabled=`True` — `buff.unique_armor.down`
4. **focus_magic** — enabled=`True` — `group & active_dot.focus_magic = 0`

### `aoe`

1. **blast_wave** — enabled=`True` — `target.within10`
2. **flamestrike** — enabled=`True` — `buff.firestarter.up` — line_cd=8
3. **dragons_breath** — enabled=`True` — `target.within12`
4. **blizzard** — enabled=`True`

### `combustion`

1. **hyperspeed_acceleration** — enabled=`True` — use_off_gcd=1
2. **fireball** — enabled=`True` — `buff.heating_up.up & buff.hot_streak.up`
3. **pyroblast** — enabled=`True` — `buff.heating_up.up & buff.hot_streak.up`
4. **pyroblast** — enabled=`True` — `buff.hot_streak.up`
5. **fireball** — enabled=`True`

## 冰霜 Wowhead

- Author: `Hekili`
- Source: `https://www.wowhead.com/wotlk/guide/classes/mage/frost/dps-rotation-cooldowns-abilities-pve`
- Description: Mage: Frost
https://www.icy-veins.com/wotlk-classic/frost-mage-dps-pve-rotation-cooldowns-abilities
September 2023

### `default`

1. **counterspell** — enabled=`True`
2. **spellsteal** — enabled=`True` — line_cd=spellsteal_cooldown
3. **mirror_image** — enabled=`True`
4. **summon_water_elemental** — enabled=`True` — `! glyph.eternal_water.enabled`
5. **icy_veins** — enabled=`True`
6. **arcane_power** — enabled=`True`
7. **flame_cap** — enabled=`True`
8. **potion** — enabled=`True` — use_off_gcd=1
9. **cold_snap** — enabled=`True` — `use_cold_snap & buff.icy_veins.down & cooldown.icy_veins.remains > 60`
10. **use_items** — enabled=`True` — description=Use any trinkets that aren't otherwise specified.
11. **deep_freeze** — enabled=`True` — `( debuff.frozen.up || buff.fingers_of_frost.stack = 1 ) & ( action.frostfire_bolt.in_flight || action.frostbolt.in_flight )` — description=Use Deep Freeze to consume your last Fingers of Frost charge simultaneously with a Frostbolt or Frostfire Bolt.
12. **frostbolt** — enabled=`True` — `buff.fingers_of_frost.up & talent.deep_freeze.enabled & cooldown.deep_freeze.remains < cast_time * buff.fingers_of_frost.stack`
13. **frostfire_bolt** — enabled=`True` — `buff.brain_freeze.react`
14. **blizzard** — enabled=`True` — `active_enemies > 2 & ! moving`
15. **cone_of_cold** — enabled=`True` — `active_enemies > 2 & target.within10 & moving`
16. **arcane_explosion** — enabled=`True` — `active_enemies > 2 & target.within10 & moving`
17. **fire_blast** — enabled=`True` — `moving & target.within20`
18. **best_mana_potion** — enabled=`True` — use_off_gcd=1
19. **replenish_mana** — enabled=`True` — `mana.pct < 70` — use_off_gcd=1
20. **evocation** — enabled=`True` — `mana.pct < 30`
21. **frostbolt** — enabled=`True`

### `precombat`

1. **arcane_brilliance** — enabled=`True` — `raid & buff.arcane_brilliance.down` — description=September 2023
2. **arcane_intellect** — enabled=`True` — `! raid & buff.arcane_brilliance.down & buff.arcane_intellect.down`
3. **conjure_mana_gem** — enabled=`True` — `mana_gem_charges < 2`
4. **molten_armor** — enabled=`True` — `buff.unique_armor.down`
5. **summon_water_elemental** — enabled=`True` — `! pet.active & glyph.eternal_water.enabled`
6. **focus_magic** — enabled=`True` — `group & active_dot.focus_magic = 0`
7. **pyroblast** — enabled=`True` — `boss`
