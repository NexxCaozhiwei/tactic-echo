import json,hashlib,shutil
from pathlib import Path
import argparse
r=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Import user-supplied WotLK references as non-executable source data')
parser.add_argument('--source',type=Path,default=r/'docs/references/wotlk')
src=parser.parse_args().source
out=r/'docs/references/wotlk';out.mkdir(parents=True,exist_ok=True)
files=['HEKILI_WOTLK_MAGE_APL_EXTRACTED.md','HEKILI_WOTLK_MAGE_TO_TEF_AUDIT.md','mage_arcane_wotlk.json','mage_fire_wotlk.json','mage_frost_wotlk.json']
hashes={}
for name in files:
 if (src/name).resolve()!=(out/name).resolve(): shutil.copy2(src/name,out/name)
 hashes[name]=hashlib.sha256((src/name).read_bytes()).hexdigest().upper()
def lua(v):
 if isinstance(v,bool):return 'true' if v else 'false'
 if isinstance(v,(int,float)):return str(v)
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
 if isinstance(v,dict):return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
 raise TypeError(v)
allowed={'fireball','frostbolt','arcane_blast','arcane_missiles','fire_blast','arcane_explosion','arcane_power','presence_of_mind','icy_veins','mirror_image'}
drop={'counterspell','spellsteal','remove_curse','fire_ward','nitro_boosts','global_thermal_sapper_charge','potion','use_items','flame_cap','hyperspeed_acceleration','best_mana_potion','replenish_mana','conjure_mana_gem','arcane_brilliance','arcane_intellect','mage_armor','molten_armor','focus_magic'}
templates={};audit=[]
for template in ['arcane','fire','frost']:
 raw=json.loads((src/f'mage_{template}_wotlk.json').read_text(encoding='utf-8-sig'))
 lists={}
 for listname,entries in raw['payload']['lists'].items():
  rows=[]
  for index,item in sorted(entries.items(),key=lambda x:int(x[0])):
   action=item['action'];criteria=item.get('criteria','');terms=[];status='KEEP';reason='PUBLIC_CONDITIONS'
   if not item.get('enabled',False):status='DROP';reason='SOURCE_DISABLED'
   elif action in drop or listname=='precombat':status='DROP';reason='OUTSIDE_COMBAT_DPS_SCOPE'
   elif action not in allowed and action!='call_action_list':status='BLOCKED';reason='ABILITY_SEMANTICS_UNVERIFIED'
   elif criteria=='moving':terms=[{'op':'moving'}]
   elif criteria=='active_enemies > 2':terms=[{'op':'enemy_count','min':3},{'op':'scene','equals':'multi'}];status='ADAPT';reason='MANUAL_SCENE_VISIBLE_COUNT'
   elif criteria:status='BLOCKED';reason='SOURCE_CONDITION_UNSUPPORTED'
   if any(item.get(k) for k in ['line_cd','cycle_targets','use_while_casting','use_off_gcd']) and status in ['KEEP','ADAPT']:
    status='BLOCKED';reason='SOURCE_EXECUTION_METADATA_UNSUPPORTED'
   row={'id':f'{template}:{listname}:{index}','action':action,'criteria':criteria,'enabled':item.get('enabled',False),'status':status,'reason':reason,'if_all':terms}
   if action=='call_action_list':row['call']=item.get('list_name','')
   if action in ['arcane_power','presence_of_mind','fire_blast','arcane_explosion']:terms.append({'op':'config','key':action})
   if action in ['arcane_power','presence_of_mind']:terms.append({'op':'talent_known','key':action})
   if listname=='default' and not criteria and action=={'arcane':'arcane_blast','fire':'fireball','frost':'frostbolt'}[template]:
    if status=='KEEP':row['fallback']=True;row['status']='ADAPT';row['reason']='EXPLICIT_FILLER_OVERRIDE_OR_SOURCE_FALLBACK'
   rows.append(row);audit.append({'template':template,'list':listname,**row})
  lists[listname]=rows
 templates[template]={'name':raw['name'],'lists':lists}
p=r/'APL/Packs/Mage/Rules.lua'
p.write_text('local _,TEF=...\nlocal A=TEF.APL\n-- Generated from user-supplied WotLK JSON. Criteria are display-only, never executable.\nA.Packs.MAGE.templates='+lua(templates)+'\nA.RuleActions={"fireball","frostbolt","scorch","arcane_missiles","fire_blast","pyroblast","arcane_power","presence_of_mind","arcane_explosion","arcane_blast","icy_veins","mirror_image"}\n',encoding='utf-8')
(out/'sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
doc=['# WotLK规则逐条迁移清单','', '三个模板属于同一MAGE_FOREVER_60 Class Pack，手动选择，不使用现代专精或猜测天赋。源文件完整保留，JSON不在游戏内执行。','', 'KEEP保留、ADAPT明确适配、DROP源停用或范围外、BLOCKED未闭合。所有可执行技能仍要求公开已学/可用/资源双布尔/范围/自身CD；用户授权0.12.1取消GCD。其他未知零Token。','', 'ADAPT：AoE调用还要求手动多目标场景，visible count不是实际命中数；普通最终填充默认依源模板，显式选择覆盖只修改最终填充位置，不解除上层条件。火焰原AoE调用关闭仍保持关闭。气定只保留在奥术AoE原位置。','', '|模板/列表/行|技能|分类|原因|原条件|','|---|---|---|---|---|']
for row in audit:doc.append(f"|{row['id']}|{row['action']}|{row['status']}|{row['reason']}|{row['criteria'].replace('|','&#124;')}|")
doc+=['','## 条件能力','', 'SUPPORTED：公开known/usable/power_ok/in_range、自身CD的公开0/0证据（GCD不检测）、实际人才rank、公开移动布尔。','ADAPT：active_enemies改为有界可见敌人观察且要求手动multi。','UNVERIFIED/BLOCKED：Aura/Debuff、层数、proc、冷却剩余秒数、target.withinN、血量/法力百分比、TTD、飞行中法术、prev_gcd、glyph、装备套装/工程物品、pet、未来预测。未删原条件，不以未知=false宣称等价。','', '来源SHA256：', '```json',json.dumps(hashes,indent=2),'```']
(r/'docs/WOTLK_MIGRATION_0.12.0.md').write_text('\n'.join(doc)+'\n',encoding='utf-8')
print('rules',len(audit),{k:sum(x['status']==k for x in audit) for k in ['KEEP','ADAPT','DROP','BLOCKED']})
