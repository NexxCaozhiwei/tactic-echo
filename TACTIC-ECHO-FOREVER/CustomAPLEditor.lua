local _,T=...
local U,S,C=T.UI,T.Safety,T.APL.Custom
function U:CustomMessage(text) self:Paint(self.customMessage,"SetText",text) end
function U:CustomRow() return self.customDraft and self.customDraft[self.customSelected or 1] end
function U:CommitCustomNumbers()
 local row=self:CustomRow(); if not row then return true end
 local values={}
 for field,box in pairs(self.customNumbers or {}) do
  local ok,raw=self:Invoke(box,"GetText"); local text=ok and S.Public(raw,"string")
  if text==nil then return false end
  if text~="" then
   local n=text:match("^%d+%.?%d*$") and tonumber(text)
   local limit=field=="manaValue" and 100 or field=="distanceValue" and 2000 or field=="cdmSpellID" and 2147483647 or 40
   if not n or n>limit or ((field=="enemyMin" or field=="enemyMax" or field=="cdmSpellID") and n%1~=0)
    or (field=="cdmSpellID" and n<=0) then self:CustomMessage("数值无效：蓝量0～100%、距离0～2000码、敌人数0～40整数、CDM合法ID。"); return false end
   values[field]=n
  end
 end
 if values.enemyMin and values.enemyMax and values.enemyMin>values.enemyMax then self:CustomMessage("敌人数下限不能超过上限。"); return false end
 row.enemyMin,row.enemyMax=values.enemyMin,values.enemyMax
 row.manaValue,row.distanceValue,row.cdmSpellID=values.manaValue,values.distanceValue,values.cdmSpellID
 if (row.manaOp and row.manaOp~="any" and not row.manaValue) or (row.distanceOp and row.distanceOp~="any" and not row.distanceValue) then
  self:CustomMessage("已启用的比较条件必须填写阈值。"); return false
 end
 return true
end
function U:RefreshCustomAPL()
 local e=self.engine; local scene=self.customScene or e.scene
 if not self.customDraft or self.customClass~=e.classToken or self.customLoadedScene~=scene then
  self.customClass,self.customLoadedScene=e.classToken,scene
  self.customDraft=C.CleanRows(C:Rows(e,scene)); self.customSelected=1; self.customFormIndex=nil
 end
 self:Paint(self.readouts.customapl,"SetText",(e.classToken or "职业未知") .. " · 编辑" .. (scene=="multi" and "多目标" or "单体") .. " · " .. #self.customDraft .. "/16条（首版法师）")
 for i,w in ipairs(self.customWidgets) do
  local row=self.customDraft[i]; self:Paint(w.frame,row and "Show" or "Hide")
  if row then
   local view=S.Spell(row.spellID,tostring(row.spellID or "未解析"))
   self:Paint(w.name,"SetText",(i==self.customSelected and "|cffffcf45" or "") .. i .. ". " .. view.name .. " · ID " .. (row.spellID or "?") .. (row.enabled and "" or " · 已停用") .. "|r")
  end
 end
 self:Paint(self.customChild,"SetHeight",math.max(108,#self.customDraft*36))
 if self.customFormIndex~=self.customSelected then
  self.customFormIndex=self.customSelected
  local row=self:CustomRow()
  for field,box in pairs(self.customNumbers) do self:Paint(box,"SetText",row and row[field] and tostring(row[field]) or "") end
 end
 local row=self:CustomRow(); local snapshot=e.aplSnapshot
 local a=snapshot and snapshot.actions["custom_" .. (self.customSelected or 1)]
 local text="必需：已学、可用、资源足够、技能范围；冷却检查默认关闭。"
 if e.db.apl.template=="custom" and a and row and a.spellID==row.spellID and self.customLoadedScene==e.scene then
  local fresh=snapshot.generation==e.generation and snapshot.revision==(T.APL.State.revision or 0) and snapshot.receiptSerial==(e.receiptSerial or 0)
  text=text .. (fresh and "\n已保存规则最近观察：" or "\n旧记录（已过期，不授权派发）：")
  for _,field in ipairs({"known","usable","power_ok","in_range","ready","cdmActive"}) do text=text .. field .. "=" .. (a[field]==nil and "未知" or tostring(a[field])) .. " " end
  text=text .. "\n蓝量%=" .. tostring(snapshot.manaPercent) .. " (" .. (snapshot.manaReason or "未启用") .. ") 距离=" .. tostring(snapshot.distance) .. " (" .. (snapshot.distanceReason or "未启用") .. ") CDM=" .. (a.cdmReason or "未启用")
  for _,result in ipairs(e.aplTrace and e.aplTrace.rules or {}) do if result.rule=="custom:" .. self.customSelected then text=text .. "\n" .. result.result .. " · " .. result.reason end end
 else text=text .. "\n未采样或正在编辑；实时状态不作为已通过证据。" end
 text=text .. "\n冷却检查=" .. (row and row.requireReady and "开启" or "关闭") .. " · " .. (a and a.cooldownReason or "未采样")
 self:Paint(self.customState,"SetText",text)
end
function U:AddCustomSpell(id)
 if not self.customDraft then self:RefreshCustomAPL() end
 id=S.ID(id); if not id then self:CustomMessage("请输入公开合法技能ID。"); return false end
 if not self:CommitCustomNumbers() then return false end
 if #self.customDraft>=16 then self:CustomMessage("最多16条规则。"); return false end
 self.customDraft[#self.customDraft+1]={spellID=id,enabled=true,moving="any",activity="any",experimentalEnemies=false}
 self.customSelected=#self.customDraft; self:RefreshCustomAPL(); self:CustomMessage("已加入草稿；保存后生效。不猜等级ID。"); return true
end
function U:ReceiveCustomSpell()
 local fn=S.Resolve("GetCursorInfo")
 if not fn then self:CustomMessage("GetCursorInfo不可用，可手输ID。"); return false end
 local ok,kind,slot,__,rawID=pcall(fn)
 local public,classification=S.Public(kind,"string")
 if ok and classification=="NO_DATA" then return false end
 if ok and public=="action" then
  local actionSlot=S.ID(slot); local get=S.Resolve("GetActionInfo")
  if actionSlot and get then
   local read,actionType,id=pcall(get,actionSlot)
   if read and S.Public(actionType,"string")=="spell" then rawID=id; public="spell" end
  end
 end
 if not ok or public~="spell" then self.engine:Log("display","CUSTOM_CURSOR_KIND_UNVERIFIED"); self:CustomMessage("游标不是公开技能；宏/物品游标不作为技能ID。"); return false end
 local id,why=S.ID(rawID)
 if not id then self.engine:Log("display","CUSTOM_CURSOR_ID_UNVERIFIED"); self:CustomMessage("技能游标ID未解析：" .. (why or "UNKNOWN") .. "；可手输精确ID。"); return false end
 if not self:AddCustomSpell(id) then return false end
 S.Call("ClearCursor"); self:Refresh(); return true
end
function U:CreateCustomAPLEditor(parent)
 self:Paint(parent,"EnableMouse",true)
 self:Paint(parent,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveCustomSpell() end) end)
 local function action(text,x,y,w,fn) return self:CreateActionButton(parent,text,x,y,w,fn) end
 action("单体",0,-30,60,function() self.customScene="single"; self:RefreshCustomAPL() end)
 action("多目标",65,-30,70,function() self.customScene="multi"; self:RefreshCustomAPL() end)
 self.customID=self:SequenceInput(parent,145,-30,90)
 action("ID新增",245,-30,80,function()
  local ok,raw=self:Invoke(self.customID,"GetText"); local text=ok and S.Public(raw,"string")
  self:AddCustomSpell(text and text:match("^%d+$") and tonumber(text))
 end)
 local drop=action("拖入技能",335,-30,90,function() self:ReceiveCustomSpell() end)
 self.customDrop=drop
 self:Paint(drop,"RegisterForDrag","LeftButton")
 self:Paint(drop,"RegisterForClicks","LeftButtonUp")
 self:Paint(drop,"EnableMouse",true)
 self:Paint(drop,"SetScript","OnReceiveDrag",function()
  self:Guard(function()
   self:ReceiveCustomSpell()
  end)
 end)
 self.customSave=action("保存并选APL",435,-30,140,function()
  if not self:CommitCustomNumbers() then return end
  local ok,reason=C:Save(self.engine,self.customDraft,self.customLoadedScene,self.customClass)
  if ok then ok,reason=T.Recommendation:SetSource(self.engine,"apl",self.customLoadedScene) end
  self:CustomMessage(ok and "已保存并停止派发；关闭设置后主动开启。" or (reason or "保存失败"))
 end)
 local scroll=self:Frame("ScrollFrame",parent,"UIPanelScrollFrameTemplate")
 self:Paint(scroll,"SetPoint","TOPLEFT",parent,"TOPLEFT",0,-65); self:Paint(scroll,"SetSize",550,94)
 local child=self:Frame("Frame",scroll); self.customChild=child; self:Paint(child,"SetSize",530,108); self:Paint(scroll,"SetScrollChild",child)
 self.customWidgets={}
 for i=1,16 do
  local index=i; local frame=self:Frame("Frame",child)
  self:Paint(frame,"SetPoint","TOPLEFT",child,"TOPLEFT",0,-(i-1)*36); self:Paint(frame,"SetSize",530,32)
  self:Paint(frame,"EnableMouse",true)
  self:Paint(frame,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveCustomSpell() end) end)
  local name=self:Text(frame,0,-7,330,"GameFontHighlightSmall")
  self:CreateActionButton(frame,"编辑",330,-2,48,function() if self:CommitCustomNumbers() then self.customSelected=index; self:RefreshCustomAPL() end end)
  self:CreateActionButton(frame,"↑",383,-2,38,function() self:MoveCustomRule(index,-1) end)
  self:CreateActionButton(frame,"↓",425,-2,38,function() self:MoveCustomRule(index,1) end)
  self:CreateActionButton(frame,"删",467,-2,48,function()
   if self:CommitCustomNumbers() then table.remove(self.customDraft,index); self.customSelected=math.min(index,math.max(1,#self.customDraft)); self.customFormIndex=nil; self:RefreshCustomAPL() end
  end)
  self.customWidgets[i]={frame=frame,name=name}
 end
 local conditionScroll=self:Frame("ScrollFrame",parent,"UIPanelScrollFrameTemplate")
 self:Paint(conditionScroll,"SetPoint","TOPLEFT",parent,"TOPLEFT",0,-166); self:Paint(conditionScroll,"SetSize",550,220)
 local settings=self:Frame("Frame",conditionScroll); self:Paint(settings,"SetSize",530,740); self:Paint(conditionScroll,"SetScrollChild",settings)
 self:CreateToggleRow(settings,"当前规则启用",0,0,530,function() local r=self:CustomRow(); return r and r.enabled==true end,function(v) local r=self:CustomRow(); if r then r.enabled=v end end)
 self:CreateSelectRow(settings,"移动条件",{{"any","不限"},{"yes","移动中"},{"no","站定"}},0,-36,530,
  function() local r=self:CustomRow(); return r and r.moving or "any" end,function(v) local r=self:CustomRow(); if r then r.moving=v end end)
 self:CreateSelectRow(settings,"额外技能冷却活动信号（不是ready）",{{"any","不限"},{"active","活动"},{"inactive","非活动"}},0,-96,530,
  function() local r=self:CustomRow(); return r and r.activity or "any" end,function(v) local r=self:CustomRow(); if r then r.activity=v end end)
 self:CreateToggleRow(settings,"实验可见敌人数（非命中数）",0,-156,530,
  function() local r=self:CustomRow(); return r and r.experimentalEnemies end,function(v) local r=self:CustomRow(); if r then r.experimentalEnemies=v end end)
 self.customNumbers={enemyMin=self:SequenceInput(settings,300,-190,60),enemyMax=self:SequenceInput(settings,440,-190,60)}
 self:Paint(self:Text(settings,0,-197,285,"GameFontHighlightSmall"),"SetText","可见敌人数：下限/上限（空白不限）")
 self:Paint(self:Text(settings,370,-197,60,"GameFontHighlightSmall"),"SetText","～")
 local ops={{"any","不限"},{"lt","<"},{"le","≤"},{"eq","="},{"ne","≠"},{"ge","≥"},{"gt",">"}}
 for _,spec in ipairs({{"distance","目标距离（码）",-230,2000},{"mana","玩家蓝量（%）",-330,100}}) do
  local prefix,y=spec[1],spec[3]
  self:CreateSelectRow(settings,spec[2],ops,0,y,530,function() local r=self:CustomRow(); return r and r[prefix .. "Op"] or "any" end,function(v) local r=self:CustomRow(); if r then r[prefix .. "Op"]=v end end)
  self.customNumbers[prefix .. "Value"]=self:SequenceInput(settings,320,y-60,130)
  self:Paint(self:Text(settings,0,y-67,310,"GameFontHighlightSmall"),"SetText","阈值（公开数值才比较；UNKNOWN等待）")
 end
 self:CreateSelectRow(settings,"CDM观察类型（活动≠ready；增益非Aura真值）",{{"none","不限"},{"buff","增益活动"},{"cooldown","冷却活动"}},0,-430,530,
  function() local r=self:CustomRow(); return r and r.cdmKind or "none" end,function(v) local r=self:CustomRow(); if r then r.cdmKind=v end end)
 self:CreateSelectRow(settings,"CDM要求（帧缺失/Secret为未知）",{{"inactive","未活动"},{"active","活动中"}},0,-490,530,
  function() local r=self:CustomRow(); return r and r.cdmState or "inactive" end,function(v) local r=self:CustomRow(); if r then r.cdmState=v end end)
 self.customNumbers.cdmSpellID=self:SequenceInput(settings,320,-550,130)
 self:Paint(self:Text(settings,0,-557,310,"GameFontHighlightSmall"),"SetText","CDM目录SpellID（空白=当前技能ID）")
 self:Paint(self:Text(settings,0,-595,530,"GameFontHighlightSmall"),"SetText","例如推荐205，CDM填116；推荐143，CDM填133。仅观察目录身份，不增加施法成功别名。距离检查不可用/Secret时不猜码数；蓝量Secret时不比较。")
 self:CreateToggleRow(settings,"检查技能冷却数值（默认关闭；可能含GCD）",0,-650,530,
  function() local r=self:CustomRow(); return r and r.requireReady==true end,function(v) local r=self:CustomRow(); if r then r.requireReady=v end end)
 local stateScroll=self:Frame("ScrollFrame",parent,"UIPanelScrollFrameTemplate")
 self:Paint(stateScroll,"SetPoint","TOPLEFT",parent,"TOPLEFT",0,-394); self:Paint(stateScroll,"SetSize",550,44)
 local stateChild=self:Frame("Frame",stateScroll); self:Paint(stateChild,"SetSize",530,120); self:Paint(stateScroll,"SetScrollChild",stateChild)
 self.customState=self:Text(stateChild,0,0,530,"GameFontHighlightSmall")
 self.customMessage=self:Text(parent,0,-446,580,"GameFontHighlightSmall")
 self:CustomMessage("规则条件区可滚动；支持魔杖5019。保存后生效，公开值未知会明确等待。")
end
function U:MoveCustomRule(index,direction)
 if not self:CommitCustomNumbers() then return end
 local other=index+direction
 if other<1 or other>#self.customDraft then return end
 self.customDraft[index],self.customDraft[other]=self.customDraft[other],self.customDraft[index]
 self.customSelected=other; self.customFormIndex=nil; self:RefreshCustomAPL()
end
