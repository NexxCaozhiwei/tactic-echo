local _,TEF=...
local A=TEF.APL
A:Register({schema=1,id="MAGE_FOREVER_60",class="MAGE",levelCap=60,
 requires={"spellKnown","spellUsable","powerOk","ownCooldown"},
 optional={"enemyCount","talentRanks","manaBand"},lists={precombat={},default={},single={},aoe={},cooldowns={},mana={},utility={}}})
