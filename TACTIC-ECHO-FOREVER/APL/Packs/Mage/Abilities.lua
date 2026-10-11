local _,TEF=...
TEF.APL={}
local A=TEF.APL
A.Abilities={}; A.AbilityNames={}
-- Names are semantic registrations, not spell/rank equivalence claims. IDs
-- other than the explicitly observed samples are resolved from this player's
-- public spellbook. Never use catalogue IDs as success-event aliases.
local rows={
 {"arcane_blast","奥术冲击","Arcane Blast","ARCANE","filler","enemy"},
 {"icy_veins","冰冷血脉","Icy Veins","FROST","cooldown","self"},
 {"mirror_image","镜像","Mirror Image","ARCANE","cooldown","self"},
 {"arcane_explosion","魔爆术","Arcane Explosion","ARCANE","aoe","self"},
 {"arcane_missiles","奥术飞弹","Arcane Missiles","ARCANE","channel","enemy",5143},
 {"arcane_power","奥术强化","Arcane Power","ARCANE","cooldown","self"},
 {"presence_of_mind","气定神闲","Presence of Mind","ARCANE","cooldown","self"},
 {"evocation","唤醒","Evocation","ARCANE","mana","self"},
 {"mana_shield","法力护盾","Mana Shield","ARCANE","defense","self"},
 {"fireball","火球术","Fireball","FIRE","filler","enemy",143},
 {"fire_blast","火焰冲击","Fire Blast","FIRE","instant","enemy",2136},
 {"scorch","灼烧","Scorch","FIRE","filler","enemy"},
 {"pyroblast","炎爆术","Pyroblast","FIRE","cast","enemy"},
 {"flamestrike","烈焰风暴","Flamestrike","FIRE","ground","ground"},
 {"blast_wave","冲击波","Blast Wave","FIRE","aoe","self"},
 {"combustion","燃烧","Combustion","FIRE","cooldown","self"},
 {"frostbolt","寒冰箭","Frostbolt","FROST","filler","enemy",205},
 {"cone_of_cold","冰锥术","Cone of Cold","FROST","cone","self"},
 {"blizzard","暴风雪","Blizzard","FROST","ground_channel","ground"},
 {"frost_nova","冰霜新星","Frost Nova","FROST","control","self"},
 {"ice_barrier","寒冰护体","Ice Barrier","FROST","defense","self"},
 {"cold_snap","急速冷却","Cold Snap","FROST","cooldown","self"},
 {"ice_block","寒冰屏障","Ice Block","FROST","defense","self"},
 {"polymorph","变形术","Polymorph","ARCANE","control","enemy",118},
 {"counterspell","法术反制","Counterspell","ARCANE","interrupt","enemy"},
 {"blink","闪现术","Blink","ARCANE","utility","self"},
 {"shoot","射击","Shoot","PHYSICAL","wand","enemy",5019},
 {"mage_armor","魔甲术","Mage Armor","ARCANE","armor","self"},
 {"frost_armor","霜甲术","Frost Armor","FROST","armor","self"},
 {"ice_armor","冰甲术","Ice Armor","FROST","armor","self"},
 {"arcane_intellect","奥术智慧","Arcane Intellect","ARCANE","buff","friendly"},
 {"arcane_brilliance","奥术光辉","Arcane Brilliance","ARCANE","buff","friendly"},
 {"amplify_magic","魔法增效","Amplify Magic","ARCANE","buff","friendly"},
 {"dampen_magic","魔法抑制","Dampen Magic","ARCANE","buff","friendly"},
 {"remove_lesser_curse","解除次级诅咒","Remove Lesser Curse","ARCANE","dispel","friendly"},
 {"detect_magic","侦测魔法","Detect Magic","ARCANE","utility","enemy"},
 {"slow_fall","缓落术","Slow Fall","ARCANE","utility","friendly"},
 {"fire_ward","防护火焰结界","Fire Ward","FIRE","defense","self"},
 {"frost_ward","防护冰霜结界","Frost Ward","FROST","defense","self"},
 {"conjure_water","造水术","Conjure Water","ARCANE","conjure","self"},
 {"conjure_food","造食术","Conjure Food","ARCANE","conjure","self"},
 {"conjure_mana_gem","制造法力宝石","Conjure Mana Gem","ARCANE","conjure","self"},
 {"conjure_mana_agate","制造法力玛瑙","Conjure Mana Agate","ARCANE","conjure","self"},
 {"conjure_mana_jade","制造法力翡翠","Conjure Mana Jade","ARCANE","conjure","self"},
 {"conjure_mana_citrine","制造法力黄水晶","Conjure Mana Citrine","ARCANE","conjure","self"},
 {"conjure_mana_ruby","制造法力红宝石","Conjure Mana Ruby","ARCANE","conjure","self"},
}
for _,r in ipairs(rows) do
 A.Abilities[r[1]]={key=r[1],name=r[2],englishName=r[3],school=r[4],type=r[5],target=r[6],
  observedID=r[7],idSource=r[7] and "FOREVER_OBSERVED_SAMPLE" or "PLAYER_SPELLBOOK_REQUIRED"}
 A.AbilityNames[r[2]]=r[1]; A.AbilityNames[r[3]]=r[1]
end
-- Inventory items and travel destinations are registered without guessed IDs.
A.Abilities.mana_gem={key="mana_gem",name="法力宝石（使用）",school="ARCANE",type="item",target="self",unsupported="ITEM_IDENTITY_NOT_IMPLEMENTED"}
A.Abilities.teleport={key="teleport",name="传送术（各城市）",school="ARCANE",type="travel",unsupported="TRAVEL_OUTSIDE_DPS"}
A.Abilities.portal={key="portal",name="传送门（各城市）",school="ARCANE",type="travel",unsupported="TRAVEL_OUTSIDE_DPS"}
