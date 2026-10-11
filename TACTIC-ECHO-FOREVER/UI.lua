local _, TEF = ...
local S, UI = TEF.Safety, {}
TEF.UI = UI

function UI:Invoke(object, method, ...)
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end
function UI:Call(object, method, ...)
    local ok=self:Invoke(object,method,...); return ok
end
function UI:Error()
    if not self.errorLogged then self.errorLogged=true; self.engine:Log("display","UI_CALL_FAILED") end
end
function UI:Paint(object,method,...)
    if not self:Call(object,method,...) then self:Error(); return false end
    return true
end
function UI:Frame(kind,parent,template,name)
    local ok,f=pcall(CreateFrame,kind,name,parent,template)
    if not ok then self:Error(); return nil end
    return f
end
function UI:Text(parent,x,y,width,template)
    local ok,t=self:Invoke(parent,"CreateFontString",nil,"OVERLAY",template or "GameFontHighlight")
    if not ok then self:Error(); return nil end
    self:Paint(t,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:Paint(t,"SetWidth",width); self:Paint(t,"SetJustifyH","LEFT")
    return t
end
function UI:Button(parent,label,x,y,width,callback)
    local b=self:Frame("Button",parent,"UIPanelButtonTemplate")
    self:Paint(b,"SetSize",width or 85,25); self:Paint(b,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:Paint(b,"SetText",label)
    self:Paint(b,"SetScript","OnClick",function()
        local ok=pcall(callback)
        if not ok then TEF.Runtime:Fault("UI_CALLBACK_FAILED"); self:Error() end
        self:Refresh()
    end)
    return b
end
function UI:Backdrop(frame)
    self:Paint(frame,"SetBackdrop",{bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,
        insets={left=4,right=4,top=4,bottom=4}})
    self:Paint(frame,"SetBackdropColor",0.04,0.06,0.09,0.94)
    self:Paint(frame,"SetClampedToScreen",true)
end
function UI:Combat()
    local ok,raw=S.Call("InCombatLockdown")
    if not ok then return nil end
    return S.Public(raw,"boolean")
end
function UI:Layout()
    if TEF.HUD then TEF.HUD:Layout() end
    if self:Combat()~=false then self.layoutPending=true; return end
    self.layoutPending=false
    self:Paint(self.frame,"SetScale",self.engine.db.hud.scale)
end
function UI:Refresh()
    if TEF.HUD then TEF.HUD:Refresh() end
    local e=self.engine
    if not self.frame then return end
    local step=e.steps and e.steps[e.index]
    local view
    if step and step.unverified then
        view=S.Spell(step.name,step.name); view.name=step.name .. "（成功ID待核验）"
    elseif step then view=S.Spell(step.spellID,step.name)
    else view={name=TEF.APL:IsActive(e) and TEF.APL.Trace:Waiting(e) or "配置无效（未解析）",icon=TEF.Placeholder,reason="CONFIG_INVALID",iconReason="CONFIG_INVALID"} end
    if not self:Paint(self.icon,"SetTexture",view.icon) then self:Paint(self.icon,"SetTexture",TEF.Placeholder) end
    self:Paint(self.name,"SetText",view.name)
    local scene=e.scene=="multi" and "多目标" or "单体"
    local status=e.completed and "完成" or (e.running and "运行" or "暂停")
    self:Paint(self.progress,"SetText",e.index .. "/" .. (e.steps and #e.steps or 0) .. "  ·  " .. scene .. "练习 · 次数 " .. (e.stepCasts or 0) .. "/" .. (step and step.repeatCount or 1))
    self:Paint(self.status,"SetText","手动  |  " .. scene .. "  |  " .. status)
    self:Paint(self.pause,"SetText",e.running and "暂停" or "继续")
    self:Paint(self.loop,"SetChecked",e.db.loop)
    self:Paint(self.detail,"SetText","ID " .. (step and step.spellID or 0) .. "  ·  " .. (e.lastReason or "LOGIN_PAUSED"))
    for i,card in ipairs(self.previews) do
        local n=e.index+i
        if e.db.loop and e.steps and n>#e.steps then n=(n-1)%#e.steps+1 end
        local nextStep=e.steps and not e.completed and e.db.hud.preview and not TEF.APL:IsActive(e) and e.steps[n]
        local preview=nextStep and (nextStep.unverified and S.Spell(nextStep.name,nextStep.name) or S.Spell(nextStep.spellID,nextStep.name))
        self:Paint(card.icon,"SetTexture",preview and preview.icon or TEF.Placeholder)
        self:Paint(card.label,"SetText",nextStep and ("随后 " .. n .. " · ID " .. nextStep.spellID) or "—")
    end
    local key=view.reason .. ":" .. (view.iconReason or "UNKNOWN") .. ":" .. e.index .. ":" .. e.scene
    if key~=self.lastResolution then
        self.lastResolution=key
        e:Log("display","SPELL_" .. view.reason,step and step.spellID>0 and step.spellID or nil)
    end
    if self.settingsOpen then self:RefreshPage() end
end
function UI:OpenSettings()
    if self:Combat()~=false then self.engine:Log("ignored","SETTINGS_COMBAT_BLOCKED"); return end
    -- Opening settings revokes the execution epoch, never user intent.
    self.settingsOpen=true
    TEF.Runtime:Suspend("RUNTIME_SETTINGS_STANDBY","standby")
    if not self.settings then self:CreateSettings() end
    self:Paint(self.settings,"Show"); self:ShowPage(self.page or "overview")
end
function UI:CloseSettings()
    self.captureHotkey=false; self.settingsOpen=false
    self:Paint(self.settings,"Hide")
    TEF.Runtime:Reconcile("SETTINGS_CLOSED")
    self:Refresh()
end
function UI:ShowPage(key)
    self.drafts=self.drafts or {}
    if self.page=="profiles" and self.loadedScene and self.editor then
        local ok,raw=self:Invoke(self.editor,"GetText")
        local draft=ok and S.Public(raw,"string")
        if draft and #draft<=4096 then self.drafts[(self.loadedProfile or "unknown") .. ":" .. self.loadedScene]=draft end
    end
    self.page=key
    if self.pageTitles then self:Paint(self.pageHeading,"SetText",self.pageTitles[key] or "设置") end
    for name,nav in pairs(self.navigation or {}) do
        self:Paint(nav,"SetText",(name==key and "|cffffcf45" or "|cffb8c6dc") .. (self.pageTitles[name] or name) .. "|r")
    end
    for name,panel in pairs(self.pages) do self:Paint(panel,name==key and "Show" or "Hide") end
    if key=="profiles" then
        self.editScene=self.editScene or self.engine.scene
        self.loadedScene=self.editScene
        self.loadedProfile=self.engine.profileKey
        self:Paint(self.editor,"SetText",self.drafts[(self.loadedProfile or "unknown") .. ":" .. self.editScene] or TEF.Profiles:Text(self.engine,self.editScene))
    end
    self:RefreshPage()
    if key=="profiles" then self:RefreshSequenceEditor(true) end
end
function UI:RefreshPage()
    local e=self.engine
    if self.RefreshControls then self:RefreshControls() end
    if self.page=="overview" then
        if self.hotkeyMessage and not self.captureHotkey then self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status()) end
        local v=TEF.Runtime:GetViewState()
        self:Paint(self.overviewBadge,"SetText",v.label .. " · " .. (v.intent and "派发意图开启" or "派发意图关闭"))
        self:Paint(self.readouts.overview,"SetText",(v.source=="apl" and "MAGE_FOREVER_60" or e.profileKey or "职业未解析") .. " · " .. (e.scene=="multi" and "多目标" or "单体")
            .. " · " .. (v.source=="apl" and "法师 APL" or v.source=="code" and "代码序列" or "人工序列") .. "\n" .. (v.source=="apl" and (e.aplTrace and e.aplTrace.reason or "等待启动采样") or ("步骤 " .. e.index .. "/" .. (e.steps and #e.steps or 0) .. " · 固定练习不保证ready")))
    elseif self.page=="profiles" then
        if self.loadedProfile~=e.profileKey then self:ShowPage("profiles"); return end
        self:Paint(self.readouts.profiles,"SetText",(e.profileKey or "职业未解析") .. " · 编辑：" .. (self.editScene=="multi" and "多目标" or "单体")
            .. "\n每套最多16步，每步1–99次；保存后暂停并重置。")
        self:RefreshSequenceEditor()

    elseif self.page=="customapl" then
        self:RefreshCustomAPL()
    elseif self.page=="apl" then
        local text=TEF.APL.Trace:View(e)
        local provider=TEF.APL.State
        text=text .. "\n来源：" .. TEF.Recommendation:Source(e) .. " · 天赋读取：" .. (provider.talentProvider or "尚未采样")
        if self.aplLedger then
            local ledger=TEF.APL:Ledger(e)
            self:Paint(self.aplLedger,"SetText",ledger)
            local _,lines=ledger:gsub("\n","")
            self:Paint(self.aplLedgerChild,"SetHeight",math.max(120,(lines+1)*32))
        end
        self:Paint(self.readouts.apl,"SetText",text)
    elseif self.page=="scene" then
        self:Paint(self.readouts.scene,"SetText","切换重置并暂停；自动判定仅旁路观察。\n可见敌方≥3建议多目标，≤1单体，2保持。\n1秒内两次不同采样；未知撤回。计数不等于命中。\n以下是采样时结果，不代表当前状态。\n\n" .. TEF.Research:View())
    elseif self.page=="hud" then
        self:Paint(self.readouts.hud,"SetText","缩放：" .. e.db.hud.scale .. " · 位置：" .. (e.db.hud.locked and "已锁定" or "可拖动")
            .. "\n后续两步：" .. (e.db.hud.preview and "显示" or "关闭") .. "\n主卡左键启停、右键设置，不直接施法。")
    elseif self.page=="looping" then
        local labels={none="不循环",normal="普通循环",target="切目标重置循环",combat="脱战重置循环"}
        self:Paint(self.readouts.looping,"SetText","当前模式：" .. (labels[e.db.loopMode] or "未知") .. " · " .. (e.db.loop and "循环开启" or "循环关闭"))
    elseif self.page=="tek" then
        self:Paint(self.readouts.tek,"SetText","TEAP v3 · 输出：" .. (TEF.Transport.enabled and "开启" or "关闭")
            .. "\nTEK许可：" .. (TEF.Dispatch.enabled and "开启" or "关闭")
            .. "\n连续执行（只读）：" .. (TEF.Dispatch.continuous and "ACTIVE" or "OFF")
            .. "\n" .. (TEF.Dispatch.continuousReason or "CONTINUOUS_OFF"))
    elseif self.page=="diagnostics" then
        local pending=TEF.Dispatch.pending
        local lines={"会话 " .. e.session .. " / 代次 " .. e.generation .. " / 淘汰 " .. e.db.evicted,
            "Pending " .. (pending and "有" or "无") .. " · Continuous " .. (TEF.Dispatch.continuous and "ACTIVE" or "OFF"),
            "Binding " .. (pending and pending.binding.key or "—") .. " · " .. (TEF.Runtime.reason or "—")}
        for i=math.max(1,#e.db.diagnostics-4),#e.db.diagnostics do
            local r=e.db.diagnostics[i]
            lines[#lines+1]=(r.event or "-") .. "\n" .. r.reason .. " · ID " .. (r.spellID or 0) .. " · " .. r.current .. "→" .. r.next .. " · 请求 " .. (r.request or 0) .. " / 轮 " .. (r.cycle or 0)
        end
        self:Paint(self.readouts.diagnostics,"SetText",table.concat(lines,"\n"))
    end
end
function UI:CreateSettings()
    local e=self.engine
    local f=self:Frame("Frame",UIParent,"BackdropTemplate","TEF_Settings")
    self.settings=f; self.pages={}; self.readouts={}
    self:Paint(f,"SetSize",820,600); self:Paint(f,"SetPoint","CENTER",UIParent,"CENTER",0,0)
    self:Paint(f,"SetFrameStrata","DIALOG"); self:Backdrop(f)
    self:Paint(f,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    self:Paint(f,"SetBackdropColor",.025,.035,.055,.98); self:Paint(f,"SetBackdropBorderColor",.18,.24,.34,1)
    self:Paint(f,"SetMovable",true); self:Paint(f,"EnableMouse",true); self:Paint(f,"RegisterForDrag","LeftButton")
    self:Paint(f,"SetScript","OnDragStart",function() if self:Combat()==false then self:Call(f,"StartMoving") end end)
    self:Paint(f,"SetScript","OnDragStop",function() self:Call(f,"StopMovingOrSizing") end)
    self:Paint(self:Text(f,22,-18,600,"GameFontNormalLarge"),"SetText","战术回响 · FOREVER")
    self:Paint(self:Text(f,22,-43,600,"GameFontHighlightSmall"),"SetText","TEF " .. TEF.Version .. "  /  固定序列 · 职业APL · TEK派发")
    self:Button(f,"关闭",722,-16,75,function() self:CloseSettings() end)
    self:Paint(f,"SetScript","OnHide",function()
        if self.settingsOpen then self.settingsOpen=false; self.captureHotkey=false; TEF.Runtime:Reconcile("SETTINGS_CLOSED") end
    end)
    self.navigation={}; self.pageTitles={}
    self.pageHeading=self:Text(f,190,-78,595,"GameFontNormalLarge")
    local tabs={{"overview","派发总览"},{"profiles","推荐配置"},{"apl","职业APL"},{"customapl","自定义APL"},{"scene","场景与验证"},{"hud","HUD外观"},{"tek","高级TEK"},{"diagnostics","诊断/测试"},{"looping","循环/重置"},{"labels","标签样式"}}
    for i,tab in ipairs(tabs) do
        local key=tab[1]
        self.pageTitles[key]=tab[2]
        self.navigation[key]=self:Button(f,tab[2],18,-78-(i-1)*42,145,function() self:ShowPage(key) end)
        local panel=self:Frame("Frame",f)
        self.pages[key]=panel
        self:Paint(panel,"SetSize",610,470); self:Paint(panel,"SetPoint","TOPLEFT",f,"TOPLEFT",190,-112)
        self.readouts[key]=self:Text(panel,4,-4,580)
    end
    self:CreateCustomAPLEditor(self.pages.customapl)
    local function button(page,label,x,y,w,fn) return self:Button(self.pages[page],label,x,y,w,fn) end
    local function selectEditor(key) self.editScene=key; self:ShowPage("profiles") end
    button("profiles","单体配置",4,-42,115,function() selectEditor("single") end)
    button("profiles","多目标配置",129,-42,115,function() selectEditor("multi") end)
    local scroll=self:Frame("ScrollFrame",self.pages.profiles,"UIPanelScrollFrameTemplate")
    self:Paint(scroll,"SetPoint","TOPLEFT",self.pages.profiles,"TOPLEFT",8,-138); self:Paint(scroll,"SetSize",550,226)
    self.editorScroll=scroll
    local editor=self:Frame("EditBox",scroll)
    self.editor=editor
    self:Paint(editor,"SetSize",530,226); self:Paint(editor,"SetMultiLine",true)
    self:Paint(editor,"SetAutoFocus",false); self:Paint(editor,"SetMaxLetters",4096)
    self:Paint(editor,"SetFontObject",ChatFontNormal or GameFontHighlight)
    self:Paint(editor,"SetScript","OnTextChanged",function()
        local ok,raw=self:Invoke(editor,"GetText")
        local value=ok and S.Public(raw,"string")
        if value and #value<=4096 then
            local _,lines=value:gsub("\n","")
            self:Paint(editor,"SetHeight",math.max(210,math.min(600,(lines+2)*18)))
        end
    end)
    self:Paint(editor,"SetScript","OnEscapePressed",function() self:Paint(editor,"ClearFocus") end)
    self:Paint(scroll,"SetScrollChild",editor)
    self.editorMessage=self:Text(self.pages.profiles,4,-414,555)
    button("profiles","保存配置",4,-377,120,function()
        local ok,raw=self:Invoke(editor,"GetText")
        local rows=ok and self:DraftRows()
        local saved,reason=false,"CONFIG_INVALID"
        if rows then saved,reason=TEF.Profiles:Save(e,self.editScene,rows) end
        if saved then self.drafts[(e.profileKey or "unknown") .. ":" .. self.editScene]=nil end
        self:Paint(self.editorMessage,"SetText",saved and "已保存；当前练习已暂停并重置。" or ("未保存：" .. reason))
        self:Paint(editor,"ClearFocus")
    end)
    button("profiles","采用已观察变形术ID",134,-377,220,function()
        local saved,reason=false,"SCENE_NOT_CURRENT"
        if self.editScene==e.scene then saved,reason=TEF.Profiles:ConfirmObserved(e) end
        self:Paint(self.editorMessage,"SetText",saved and "已按本会话公开成功ID保存；重新开始再施法。" or ("未保存：" .. reason))
        if saved then self.drafts[(e.profileKey or "unknown") .. ":" .. self.editScene]=nil; self:Paint(editor,"SetText",TEF.Profiles:Text(e,self.editScene)) end
    end)
    button("scene","切换单体",4,-345,115,function() TEF.Profiles:Select(e,"single") end)
    button("scene","切换多目标",129,-345,115,function() TEF.Profiles:Select(e,"multi") end)
    self:CreateSectionCard(self.pages.overview,"派发状态",0,0,580,100)
    self.overviewBadge=self:CreateStatusBadge(self.pages.overview,15,-38,370)
    self.intentToggle=self:CreateToggleRow(self.pages.overview,"派发启/停",15,-67,540,
        function() return TEF.Runtime:IsDispatchIntentEnabled() end,function() TEF_ToggleDispatchIntent() end)
    self:CreateSectionCard(self.pages.overview,"运行模式",0,-112,580,80)
    self.modeControls=self:CreateSegmentedControl(self.pages.overview,{{"auto","自动启停"},{"manual","手动启停"},{"stop","脱战后停止"}},12,-150,556,
        function() return e.db.dispatch.mode end,function(value) TEF.Runtime:SetMode(value) end)
    self:CreateToggleRow(self.pages.overview,"登录/reload自动启动（创建新意图）",12,-207,556,
        function() return e.db.dispatch.autoStart end,function(value) e.db.dispatch.autoStart=value end)
    self:CreateSectionCard(self.pages.overview,"派发启停快捷键",0,-250,580,100)
    self:CreateHotkeyRow(self.pages.overview,14,-285,550)
    self:CreateToggleRow(self.pages.overview,"临时覆盖已有绑定（不改原生绑定）",14,-348,550,
        function() return e.db.dispatch.hotkeyOverride end,function(v) e.db.dispatch.hotkeyOverride=v; TEF.Hotkeys:Apply() end)
    self:CreateSectionCard(self.pages.overview,"当前配置",0,-390,580,74)
    self:Paint(self.readouts.overview,"ClearAllPoints")
    self:Paint(self.readouts.overview,"SetPoint","TOPLEFT",self.pages.overview,"TOPLEFT",14,-421)
    self.loopModeControls=self:CreateSegmentedControl(self.pages.looping,{{"none","不循环"},{"normal","普通循环"},{"target","切目标重置"},{"combat","脱战重置"}},0,-42,580,
        function() return e.db.loopMode end,function(v) TEF.Runtime:SetLoopMode(v) end)
    self:CreateHintText(self.pages.looping,"普通循环：末步完成后回到首步，持续练习。\n切目标重置：同样循环；每次目标变化（含清空）回首步、次数清零。\n脱战重置：同样循环；退出战斗回首步、次数清零。\n重置使旧施法关联与派发失效；手动停止不会被事件重新开启。\n自动启停仍脱战待命，脱战后停止模式仍清除启用意图。\n切换循环模式会重置并停止；关闭设置后需主动开启。",0,-100,580)
    TEF.HudStyles:BuildUI(self,self.pages.labels)
    self:CreateSequenceEditor(self.pages.profiles)
    self.sourceSelect=self:CreateSegmentedControl(self.pages.profiles,{{"manual","人工"},{"code","代码"},{"apl","APL"}},260,-42,294,
        function() return TEF.Recommendation:Source(e,self.editScene) end,
        function(value)
            local ok,reason=TEF.Recommendation:SetSource(e,value,self.editScene)
            self:SequenceMessage(ok and "来源已切换并停止；关闭设置后主动开启。" or ("来源未切换：" .. reason))
        end)
    self:CreateSelectRow(self.pages.apl,"手选构筑模板（不是现代专精；不猜天赋流派）",{{"arcane","奥术"},{"fire","火焰"},{"frost","冰霜"},{"custom","自定义"}},0,-6,580,
        function() return e.db.apl.template end,function(v) TEF.APL:Configure(e,"template",v) end)
    self:CreateSelectRow(self.pages.apl,"最终填充覆盖（依模板=保留源顺序）",{{"auto","依模板"},{"fireball","火球"},{"frostbolt","寒冰箭"},{"scorch","灼烧"},{"arcane_missiles","飞弹"},{"arcane_blast","奥冲"}},0,-70,580,
        function() return e.db.apl.filler end,function(v) TEF.APL:Configure(e,"filler",v) end)
    for i,row in ipairs({{"arcane_power","奥术强化"},{"presence_of_mind","气定神闲"},{"fire_blast","移动火焰冲击"}}) do
        local key,label=row[1],row[2]
        self:CreateToggleRow(self.pages.apl,label .. "（只在源规则位置）",0,-134-(i-1)*28,580,
            function() return e.db.apl[key] end,function(v) TEF.APL:Configure(e,key,v) end)
    end
    self:Paint(self:Text(self.pages.apl,0,-229,290),"SetText","填充覆盖精确ID（留空=自动解析）")
    local exact=self:Frame("EditBox",self.pages.apl,"InputBoxTemplate"); self.aplExactID=exact
    self:Paint(exact,"SetSize",105,24); self:Paint(exact,"SetPoint","TOPLEFT",self.pages.apl,"TOPLEFT",300,-222)
    self:Paint(exact,"SetAutoFocus",false); self:Paint(exact,"SetMaxLetters",10)
    self:Paint(exact,"SetScript","OnEditFocusGained",function() self.aplExactEditing=true end)
    self:Paint(exact,"SetScript","OnEditFocusLost",function() self.aplExactEditing=false end)
    button("apl","保存ID",425,-222,140,function()
        local ok,raw=self:Invoke(exact,"GetText"); local text=ok and S.Public(raw,"string")
        local id=text and text:match("^%d+$") and S.ID(tonumber(text))
        if text=="" then TEF.APL:Configure(e,"exactID",nil)
        elseif id then TEF.APL:Configure(e,"exactID",id) else e:Log("ignored","APL_EXACT_ID_INVALID") end
        self:Paint(exact,"ClearFocus")
    end)
    self.controls[#self.controls+1]=function()
        local id=e.db.apl.exactIDs[e.db.apl.filler]
        if not self.aplExactEditing then self:Paint(exact,"SetText",id and tostring(id) or "") end
    end
    self:Paint(self.readouts.apl,"ClearAllPoints"); self:Paint(self.readouts.apl,"SetPoint","TOPLEFT",self.pages.apl,"TOPLEFT",0,-260)
    self:Paint(self.readouts.apl,"SetFontObject",GameFontHighlightSmall)
    local aplScroll=self:Frame("ScrollFrame",self.pages.apl,"UIPanelScrollFrameTemplate")
    self:Paint(aplScroll,"SetPoint","TOPLEFT",self.pages.apl,"TOPLEFT",0,-310); self:Paint(aplScroll,"SetSize",550,120)
    local ledger=self:Frame("Frame",aplScroll); self.aplLedgerChild=ledger
    self:Paint(ledger,"SetSize",530,2600); self:Paint(aplScroll,"SetScrollChild",ledger)
    self.aplLedger=self:Text(ledger,0,0,530,"GameFontHighlightSmall")
    self:CreateHintText(self.pages.apl,"下方可滚动查看全部原规则、条件、迁移状态；BLOCKED不执行。配置修改停止派发。",0,-448,580)
    self:CreateSectionCard(self.pages.hud,"HUD缩放",0,-85,580,90)
    self.hudSlider=self:CreateSliderRow(self.pages.hud,"缩放",14,-116,550,.6,1.8,.1,
        function() return e.db.hud.scale end,function(value) e.db.hud.scale=value; self:Layout() end)
    self:CreateToggleRow(self.pages.hud,"锁定位置",12,-198,556,function() return e.db.hud.locked end,function(value) e.db.hud.locked=value end)
    self:CreateToggleRow(self.pages.hud,"显示后续预览",12,-242,556,function() return e.db.hud.preview end,function(value) e.db.hud.preview=value end)
    button("hud","恢复位置",12,-294,140,function()
        if self:Combat()~=false then return end
        e.db.position=nil; self:Paint(self.frame,"ClearAllPoints"); self:Paint(self.frame,"SetPoint","CENTER",UIParent,"CENTER",0,0)
        e.db.hud.x=nil; e.db.hud.y=nil
        self:Paint(TEF.HUD.frame,"ClearAllPoints"); self:Paint(TEF.HUD.frame,"SetPoint","CENTER",UIParent,"CENTER",0,-155)
    end)
    self:CreateHintText(self.pages.hud,"左键主卡切换派发意图，右键打开设置。\n空白区域可拖动；战斗中布局变更延后。",12,-346,550)
    self:CreateSectionCard(self.pages.tek,"高级能力门禁",0,-138,580,132)
    self.signalToggle=self:CreateToggleRow(self.pages.tek,"TEAP输出",12,-176,556,function() return e.db.dispatch.signal end,function(v) TEF.Runtime:SetSignal(v) end)
    self.permissionToggle=self:CreateToggleRow(self.pages.tek,"TEK请求许可",12,-220,556,function() return e.db.dispatch.permission end,function(v) TEF.Runtime:SetPermission(v) end)
    self:CreateHintText(self.pages.tek,"正常使用只需主卡或派发启停。以上是高级门禁。\n设置期间零Token，关闭后按模式恢复新请求。\n固定练习不保证ready。只保留一个信号源。\nTEK等待事件时可能重复输入；插件不证明已连接。",12,-300,550)
    self:CreateDivider(self.pages.diagnostics,4,-277,560)
    self.testReset=button("diagnostics","重置并停止",4,-299,150,function() TEF.Runtime:Reset() end)
    self.testSingle=button("diagnostics","单步派发测试",165,-299,150,function() TEF_RequestCurrent() end)
    -- Settings always block input. Keep this developer action visibly disabled.
    self:SetControlEnabled(self.testSingle,false)
    button("diagnostics","旁路采样",326,-299,140,function() TEF.Research:Sample(e) end)
    self:CreateToggleRow(self.pages.diagnostics,"完成后循环（实验）",4,-342,556,function() return e.db.loop end,function(v) e:SetLoop(v) end)
    self:CreateHintText(self.pages.diagnostics,"单步测试在设置打开时会被拒绝。关闭设置后 /tef dispatch。\n单步不撤销自动请求；设置内重置明确关闭用户意图。",4,-394,550)
    for _,panel in pairs(self.pages) do self:Paint(panel,"Hide") end
end
function UI:Create(engine)
    self.engine=engine; self.previews={}
    local f=self:Frame("Frame",UIParent,"BackdropTemplate","TEF_PracticePanel")
    self.frame=f; self:Paint(f,"SetSize",390,285); self:Backdrop(f)
    local pos=engine.db.position or {x=0,y=0}
    self:Paint(f,"SetPoint","CENTER",UIParent,"CENTER",pos.x,pos.y)
    self:Paint(f,"SetMovable",true); self:Paint(f,"EnableMouse",true); self:Paint(f,"RegisterForDrag","LeftButton")
    self:Paint(f,"SetScript","OnDragStart",function()
        if not engine.db.hud.locked and self:Combat()==false then self:Paint(f,"StartMoving") end
    end)
    self:Paint(f,"SetScript","OnDragStop",function()
        self:Paint(f,"StopMovingOrSizing")
        local ok,_,_,_,rx,ry=self:Invoke(f,"GetPoint",1)
        if ok then
            local x,y=S.Public(rx,"number"),S.Public(ry,"number")
            if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then engine.db.position={x=x,y=y} end
        end
    end)
    self:Paint(self:Text(f,16,-12,355,"GameFontNormal"),"SetText","TEF " .. TEF.Version .. " · 双场景练习")
    local made,icon=self:Invoke(f,"CreateTexture",nil,"ARTWORK")
    if made then self.icon=icon; self:Paint(icon,"SetSize",62,62); self:Paint(icon,"SetPoint","TOPLEFT",f,"TOPLEFT",18,-43)
    else self:Error() end
    self.name=self:Text(f,92,-45,278,"GameFontNormalLarge")
    self.progress=self:Text(f,92,-75,278)
    self.detail=self:Text(f,18,-117,355,"GameFontHighlightSmall")
    for i=1,2 do
        local got,texture=self:Invoke(f,"CreateTexture",nil,"ARTWORK")
        if not got then self:Error() end
        self:Paint(texture,"SetSize",30,30); self:Paint(texture,"SetPoint","TOPLEFT",f,"TOPLEFT",18+(i-1)*177,-142)
        self.previews[i]={icon=texture,label=self:Text(f,55+(i-1)*177,-150,135,"GameFontHighlightSmall")}
    end
    self:Button(f,"开始",18,-188,78,function() TEF.Runtime:Start(true) end)
    self.pause=self:Button(f,"继续",106,-188,78,function() TEF_ToggleDispatchIntent() end)
    self:Button(f,"重置",194,-188,78,function() TEF.Runtime:Reset() end)
    self:Button(f,"设置",282,-188,85,function() self:OpenSettings() end)
    self.loop=self:Frame("CheckButton",f,"UICheckButtonTemplate")
    self:Paint(self.loop,"SetPoint","TOPLEFT",f,"TOPLEFT",16,-222)
    self:Paint(self.loop,"SetScript","OnClick",function()
        local ok,raw=self:Invoke(self.loop,"GetChecked")
        local value=ok and S.Public(raw,"boolean")
        if value~=nil then engine:SetLoop(value) end
        self:Refresh()
    end)
    self:Paint(self:Text(f,48,-229,160,"GameFontHighlightSmall"),"SetText","完成后循环")
    self:Button(f,"单体 / 多目标",220,-225,145,function()
        TEF.Profiles:Select(engine,engine.scene=="single" and "multi" or "single")
    end)
    self.status=self:Text(f,18,-261,355,"GameFontNormal")
    self:Layout(); self:Refresh()
end
