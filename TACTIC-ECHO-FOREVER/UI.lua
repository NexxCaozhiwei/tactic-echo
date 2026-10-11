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
        if not ok then self.engine:Pause(); self:Error() end
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
    else view={name="配置无效（未解析）",icon=TEF.Placeholder,reason="CONFIG_INVALID",iconReason="CONFIG_INVALID"} end
    if not self:Paint(self.icon,"SetTexture",view.icon) then self:Paint(self.icon,"SetTexture",TEF.Placeholder) end
    self:Paint(self.name,"SetText",view.name)
    local scene=e.scene=="multi" and "多目标" or "单体"
    local status=e.completed and "完成" or (e.running and "运行" or "暂停")
    self:Paint(self.progress,"SetText",e.index .. "/" .. (e.steps and #e.steps or 0) .. "  ·  " .. scene .. "练习")
    self:Paint(self.status,"SetText","手动  |  " .. scene .. "  |  " .. status)
    self:Paint(self.pause,"SetText",e.running and "暂停" or "继续")
    self:Paint(self.loop,"SetChecked",e.db.loop)
    self:Paint(self.detail,"SetText","ID " .. (step and step.spellID or 0) .. "  ·  " .. (e.lastReason or "LOGIN_PAUSED"))
    for i,card in ipairs(self.previews) do
        local n=e.index+i
        if e.db.loop and e.steps and n>#e.steps then n=(n-1)%#e.steps+1 end
        local nextStep=e.steps and not e.completed and e.db.hud.preview and e.steps[n]
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
    if TEF.Dispatch then TEF.Dispatch:Cancel("TEK_SETTINGS_OPEN") end
    if self:Combat()~=false then self.engine:Log("ignored","SETTINGS_COMBAT_BLOCKED"); return end
    -- Keep the public initiation receipt for the explicit Polymorph confirm
    -- button. Opening an editor cancels input eligibility (always zero here)
    -- but does not implicitly pause practice; applying any edit does reset.
    if not self.settings then self:CreateSettings() end
    self.settingsOpen=true; self:Paint(self.settings,"Show"); self:ShowPage(self.page or "overview")
end
function UI:ShowPage(key)
    self.drafts=self.drafts or {}
    if self.page=="profiles" and self.loadedScene and self.editor then
        local ok,raw=self:Invoke(self.editor,"GetText")
        local draft=ok and S.Public(raw,"string")
        if draft and #draft<=4096 then self.drafts[self.loadedScene]=draft end
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
        self:Paint(self.editor,"SetText",self.drafts[self.editScene] or TEF.Profiles:Text(self.engine,self.editScene))
    end
    self:RefreshPage()
end
function UI:RefreshPage()
    local e=self.engine
    if self.page=="overview" then
        self:Paint(self.readouts.overview,"SetText","TEF " .. TEF.Version .. "\n独立固定顺序练习 · 登录/reload默认暂停\n\n"
            .. "当前：" .. (e.scene=="multi" and "多目标" or "单体") .. " · " .. (e.running and "运行" or "暂停")
            .. "\n步骤：" .. e.index .. "/" .. (e.steps and #e.steps or 0) .. "\n\n显示提示不保证立即可施放。\n多目标配置是训练序列，不代表实际群攻效果。\n\n修改配置后重新开始；成功事件才推进。")
    elseif self.page=="profiles" then
        self:Paint(self.readouts.profiles,"SetText","编辑：" .. (self.editScene=="multi" and "多目标" or "单体")
            .. "\n每行一个精确ID；可写 主ID:匹配ID/匹配ID\n?变形术 表示尚未核验，保持该步，不自动跳过。\n最多32步；保存后暂停并重置。7268禁止。")
    elseif self.page=="scene" then
        self:Paint(self.readouts.scene,"SetText","切换重置并暂停；自动判定仅旁路观察。\n可见敌方≥3建议多目标，≤1单体，2保持。\n1秒内两次不同采样；未知撤回。计数不等于命中。\n以下是采样时结果，不代表当前状态。\n\n" .. TEF.Research:View())
    elseif self.page=="hud" then
        self:Paint(self.readouts.hud,"SetText","缩放：" .. e.db.hud.scale .. "\n位置：" .. (e.db.hud.locked and "已锁定" or "可拖动")
            .. "\n后续两步：" .. (e.db.hud.preview and "显示" or "关闭") .. "\n\n主图标只读，不点击施法。战斗内布局延后应用。")
    elseif self.page=="tek" then
        self:Paint(self.readouts.tek,"SetText","TEAP v3 · 输出：" .. (TEF.Transport.enabled and "开启" or "关闭")
            .. "\nTEK请求许可：" .. (TEF.Dispatch.enabled and "开启" or "关闭（默认）")
            .. "\n默认零Token观察帧，不恢复请求。\n\n/tef dispatch 或HUD派发当前。\n桌面TEK选择UI联动，无需验收脚本。\n等待游戏事件期间可能按限频重复发送。\n/tef tekstop 撤回；暂停/设置/事件也撤回。\n\n没有自动ready；请人工确认施放条件。\n只保留TEF一个信号源。\n插件不声称TEK已连接或真实发送成功。")
    elseif self.page=="diagnostics" then
        local lines={"会话 " .. e.session .. " / 代次 " .. e.generation .. " / 淘汰 " .. e.db.evicted}
        for i=math.max(1,#e.db.diagnostics-9),#e.db.diagnostics do
            local r=e.db.diagnostics[i]
            lines[#lines+1]=(r.event or "-") .. "\n" .. r.reason .. " · ID " .. (r.spellID or 0) .. " · " .. r.current .. "→" .. r.next
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
    self:Paint(self:Text(f,22,-43,600,"GameFontHighlightSmall"),"SetText","TEF " .. TEF.Version .. "  /  固定序列练习与TEK派发")
    self:Button(f,"关闭",722,-16,75,function() self.settingsOpen=false; self:Paint(f,"Hide") end)
    self.navigation={}; self.pageTitles={}
    self.pageHeading=self:Text(f,190,-78,595,"GameFontNormalLarge")
    local tabs={{"overview","总览"},{"profiles","推荐配置"},{"scene","场景与验证"},{"hud","HUD外观"},{"tek","TEK适配"},{"diagnostics","诊断"}}
    for i,tab in ipairs(tabs) do
        local key=tab[1]
        self.pageTitles[key]=tab[2]
        self.navigation[key]=self:Button(f,tab[2],18,-78-(i-1)*42,145,function() self:ShowPage(key) end)
        local panel=self:Frame("Frame",f)
        self.pages[key]=panel
        self:Paint(panel,"SetSize",610,470); self:Paint(panel,"SetPoint","TOPLEFT",f,"TOPLEFT",190,-112)
        self.readouts[key]=self:Text(panel,4,-4,580)
    end
    local function button(page,label,x,y,w,fn) return self:Button(self.pages[page],label,x,y,w,fn) end
    button("overview","开始",4,-250,100,function() e:Start() end)
    button("overview","暂停/继续",115,-250,110,function() if e.running then e:Pause() else e:Resume() end end)
    button("overview","重置",235,-250,100,function() e:Reset() end)
    local function selectEditor(key) self.editScene=key; self:ShowPage("profiles") end
    button("profiles","单体配置",4,-82,115,function() selectEditor("single") end)
    button("profiles","多目标配置",129,-82,115,function() selectEditor("multi") end)
    local scroll=self:Frame("ScrollFrame",self.pages.profiles,"UIPanelScrollFrameTemplate")
    self:Paint(scroll,"SetPoint","TOPLEFT",self.pages.profiles,"TOPLEFT",8,-116); self:Paint(scroll,"SetSize",455,210)
    local editor=self:Frame("EditBox",scroll)
    self.editor=editor
    self:Paint(editor,"SetSize",440,210); self:Paint(editor,"SetMultiLine",true)
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
    self.editorMessage=self:Text(self.pages.profiles,4,-375,505)
    button("profiles","保存配置",4,-337,120,function()
        local ok,raw=self:Invoke(editor,"GetText")
        local rows=ok and TEF.Profiles:Parse(raw)
        local saved,reason=false,"CONFIG_INVALID"
        if rows then saved,reason=TEF.Profiles:Save(e,self.editScene,rows) end
        if saved then self.drafts[self.editScene]=nil end
        self:Paint(self.editorMessage,"SetText",saved and "已保存；当前练习已暂停并重置。" or ("未保存：" .. reason))
        self:Paint(editor,"ClearFocus")
    end)
    button("profiles","采用已观察变形术ID",134,-337,220,function()
        local saved,reason=false,"SCENE_NOT_CURRENT"
        if self.editScene==e.scene then saved,reason=TEF.Profiles:ConfirmObserved(e) end
        self:Paint(self.editorMessage,"SetText",saved and "已按本会话公开成功ID保存；重新开始再施法。" or ("未保存：" .. reason))
        if saved then self.drafts[self.editScene]=nil; self:Paint(editor,"SetText",TEF.Profiles:Text(e,self.editScene)) end
    end)
    button("scene","切换单体",4,-345,115,function() TEF.Profiles:Select(e,"single") end)
    button("scene","切换多目标",129,-345,115,function() TEF.Profiles:Select(e,"multi") end)
    button("scene","旁路采样",254,-345,115,function() TEF.Research:Sample(e) end)
    button("hud","缩小",4,-145,90,function() e.db.hud.scale=math.max(0.6,e.db.hud.scale-0.1); self:Layout() end)
    button("hud","放大",104,-145,90,function() e.db.hud.scale=math.min(1.8,e.db.hud.scale+0.1); self:Layout() end)
    button("hud","锁定/解锁",204,-145,115,function() e.db.hud.locked=not e.db.hud.locked end)
    button("hud","后续预览",329,-145,115,function() e.db.hud.preview=not e.db.hud.preview end)
    button("hud","恢复位置",4,-185,115,function()
        if self:Combat()~=false then return end
        e.db.position=nil; self:Paint(self.frame,"ClearAllPoints"); self:Paint(self.frame,"SetPoint","CENTER",UIParent,"CENTER",0,0)
        e.db.hud.x=nil; e.db.hud.y=nil
        if TEF.HUD.frame then self:Paint(TEF.HUD.frame,"ClearAllPoints"); self:Paint(TEF.HUD.frame,"SetPoint","CENTER",UIParent,"CENTER",0,-155) end
    end)
    button("tek","显示/关闭协议信号",4,-245,190,function() TEF.Transport:SetEnabled(not TEF.Transport.enabled) end)
    button("tek","TEK请求许可启/停",204,-245,220,function() TEF_PermissionToggle() end)
    button("overview","练习启/停",345,-250,140,function() TEF_RunToggle() end)
    self:Paint(self:Text(self.pages.tek,4,-285,500),"SetText","许可默认关闭，reload不恢复。设置内不提交派发。\n关闭设置后，用原生按键设置中的TEF请求快捷键。\n桌面TEK选择UI联动；游戏置于前台。停止可用TEF停止快捷键。")
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
    self:Button(f,"开始",18,-188,78,function() engine:Start() end)
    self.pause=self:Button(f,"继续",106,-188,78,function() if engine.running then engine:Pause() else engine:Resume() end end)
    self:Button(f,"重置",194,-188,78,function() engine:Reset() end)
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
