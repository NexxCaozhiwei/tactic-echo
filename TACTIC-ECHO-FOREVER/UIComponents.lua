local _,TEF=...
local U,S=TEF.UI,TEF.Safety
-- Independent TEUI-style components. Presentation holds no input authority.
U.controls={}
function U:Guard(callback,...)
    local ok=pcall(callback,...)
    if not ok then
        if TEF.Runtime and TEF.Runtime.e==self.engine then TEF.Runtime:Fault("UI_CALLBACK_FAILED") end
        self:Error()
    end
    return ok
end
function U:CreateActionButton(parent,label,x,y,width,callback)
    local b=self:Frame("Button",parent,"BackdropTemplate")
    b.tefControlEnabled=true
    self:Paint(b,"SetSize",width or 120,28); self:Paint(b,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:Paint(b,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    self:Paint(b,"SetBackdropColor",.07,.10,.15,1); self:Paint(b,"SetBackdropBorderColor",.21,.29,.39,1)
    self:Paint(b,"SetNormalFontObject",GameFontHighlightSmall)
    self:Paint(b,"SetText",label)
    self:Paint(b,"SetScript","OnEnter",function() if b.tefControlEnabled then self:Call(b,"SetBackdropColor",.12,.20,.28,1) end end)
    self:Paint(b,"SetScript","OnLeave",function() self:SetControlEnabled(b,b.tefControlEnabled) end)
    self:Paint(b,"SetScript","OnClick",function() if b.tefControlEnabled then self:Guard(callback); self:Refresh() end end)
    return b
end
function U:SetControlEnabled(button,enabled)
    button.tefControlEnabled=enabled==true
    self:Paint(button,enabled==true and "Enable" or "Disable")
    if enabled==true and button.tefControlSelected==true then
        self:Paint(button,"SetBackdropColor",.08,.23,.20,1)
        self:Paint(button,"SetBackdropBorderColor",.25,.85,.65,1)
    else
        self:Paint(button,"SetBackdropColor",enabled==true and .07 or .035,enabled==true and .10 or .045,enabled==true and .15 or .06,1)
        self:Paint(button,"SetBackdropBorderColor",enabled==true and .21 or .10,enabled==true and .29 or .13,enabled==true and .39 or .17,1)
    end
end
function U:CreateSectionCard(parent,title,x,y,width,height)
    -- Page text must be above its decoration. A child backdrop Frame has a
    -- higher frame level than the parent's FontStrings and obscures them.
    local ok,bg=self:Invoke(parent,"CreateTexture",nil,"BACKGROUND")
    if not ok then self:Error(); return end
    self:Paint(bg,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(bg,"SetSize",width,height)
    self:Paint(bg,"SetColorTexture",.04,.06,.095,.92)
    for _,edge in ipairs({{x,y,width,1},{x,y-height+1,width,1},{x,y,1,height},{x+width-1,y,1,height}}) do
        local made,line=self:Invoke(parent,"CreateTexture",nil,"BORDER")
        if made then
            self:Paint(line,"SetPoint","TOPLEFT",parent,"TOPLEFT",edge[1],edge[2])
            self:Paint(line,"SetSize",edge[3],edge[4]); self:Paint(line,"SetColorTexture",.13,.19,.27,1)
        else self:Error() end
    end
    self:Paint(self:Text(parent,x+12,y-10,width-24,"GameFontNormal"),"SetText",title)
    return bg
end
function U:CreateHintText(parent,text,x,y,width)
    local t=self:Text(parent,x,y,width,"GameFontHighlightSmall")
    self:Paint(t,"SetText",text); self:Paint(t,"SetTextColor",.60,.68,.78,1); return t
end
function U:CreateDivider(parent,x,y,width)
    local ok,t=self:Invoke(parent,"CreateTexture",nil,"BACKGROUND")
    if not ok then return end
    self:Paint(t,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(t,"SetSize",width,1)
    self:Paint(t,"SetColorTexture",.16,.22,.30,1); return t
end
function U:CreateToggleRow(parent,label,x,y,width,getter,setter)
    self:Paint(self:Text(parent,x,y-6,width-95),"SetText",label)
    local b=self:CreateActionButton(parent,"",x+width-85,y,85,function() setter(not getter()) end)
    local function sync()
        local enabled=getter()==true
        b.tefControlSelected=enabled
        self:Paint(b,"SetText",enabled and "开启" or "关闭")
        self:SetControlEnabled(b,b.tefControlEnabled)
    end
    self.controls[#self.controls+1]=sync; sync(); return b
end
function U:CreateSegmentedControl(parent,choices,x,y,width,getter,setter)
    local out={}; local cell=(width-(#choices-1)*6)/#choices
    for i,choice in ipairs(choices) do
        local value,label=choice[1],choice[2]
        local b=self:CreateActionButton(parent,label,x+(i-1)*(cell+6),y,cell,function() setter(value) end)
        out[value]=b
        self.controls[#self.controls+1]=function()
            local active=getter()==value
            b.tefControlSelected=active
            self:Paint(b,"SetText",active and ("|cff80ffcc● " .. label .. "|r") or label)
            self:SetControlEnabled(b,b.tefControlEnabled)
        end
    end
    return out
end
function U:CreateSelectRow(parent,label,choices,x,y,width,getter,setter)
    self:Paint(self:Text(parent,x,y,width),"SetText",label)
    return self:CreateSegmentedControl(parent,choices,x,y-25,width,getter,setter)
end
function U:CreateSliderRow(parent,label,x,y,width,min,max,step,getter,setter)
    local text=self:Text(parent,x,y,width)
    local slider=self:Frame("Slider",parent,"OptionsSliderTemplate")
    self:Paint(slider,"SetPoint","TOPLEFT",parent,"TOPLEFT",x+8,y-25); self:Paint(slider,"SetSize",width-16,18)
    self:Paint(slider,"SetMinMaxValues",min,max); self:Paint(slider,"SetValueStep",step); self:Paint(slider,"SetObeyStepOnDrag",true)
    local syncing=false
    self:Paint(slider,"SetScript","OnValueChanged",function(_,raw)
        local v=S.Public(raw,"number")
        if syncing or not v or v<min or v>max then return end
        self:Guard(setter,math.floor(v/step+.5)*step); self:Refresh()
    end)
    self.controls[#self.controls+1]=function()
        local value=getter(); self:Paint(text,"SetText",label .. "  " .. string.format("%.1f",value))
        syncing=true; self:Paint(slider,"SetValue",value); syncing=false
    end
    return slider
end
function U:CreateStatusBadge(parent,x,y,width)
    local text=self:Text(parent,x,y,width,"GameFontNormalLarge")
    return text
end
function U:CreateHotkeyRow(parent,x,y,width)
    local box=self:Frame("EditBox",parent,"InputBoxTemplate","TEF_HotkeyEditor")
    self:Paint(box,"SetSize",165,26); self:Paint(box,"SetPoint","TOPLEFT",parent,"TOPLEFT",x+5,y)
    self:Paint(box,"SetAutoFocus",false); self:Paint(box,"SetMaxLetters",40)
    self:Paint(box,"EnableKeyboard",true)
    self:Paint(box,"SetText",self.engine.db.dispatch.hotkey)
    self.hotkey,self.hotkeyMessage=box,self:Text(parent,x,y-38,width)
    local function submit(raw)
        TEF.Hotkeys:Set(raw)
        self:Paint(box,"SetText",self.engine.db.dispatch.hotkey)
        self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status())
        self:Paint(box,"ClearFocus")
    end
    self:Paint(box,"SetScript","OnKeyDown",function(editor,key)
        self:Call(editor,"SetPropagateKeyboardInput",not self.captureHotkey)
        self:Guard(function()
            if not self.captureHotkey then return end
            local done,captured=TEF.Hotkeys:Capture(editor,key)
            if done then
                self.captureHotkey=false
                if captured then submit(captured)
                else self:Paint(box,"SetText",self.engine.db.dispatch.hotkey); self:Paint(self.hotkeyMessage,"SetText","录入已取消，原快捷键保留。") end
            end
        end)
    end)
    self:Paint(box,"SetScript","OnEnterPressed",function()
        self:Guard(function() local ok,raw=self:Invoke(box,"GetText"); if ok then submit(raw) end end)
    end)
    self:Paint(box,"SetScript","OnEscapePressed",function()
        self.captureHotkey=false; self:Paint(box,"SetText",self.engine.db.dispatch.hotkey); self:Paint(box,"ClearFocus")
    end)
    self.captureHotkeyButton=self:CreateActionButton(parent,"录入",x+185,y,70,function()
        self.captureHotkey=true; self:Call(box,"SetPropagateKeyboardInput",false); self:Paint(box,"SetFocus")
        self:Paint(self.hotkeyMessage,"SetText","按下组合键即保存并应用；Esc取消。")
    end)
    self.applyHotkeyButton=self:CreateActionButton(parent,"保存",x+265,y,70,function()
        local ok,raw=self:Invoke(box,"GetText"); if ok then submit(raw) end
    end)
    self.clearHotkeyButton=self:CreateActionButton(parent,"清除",x+345,y,70,function() submit("") end)
    self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status())
    return box
end
function U:RefreshControls()
    for _,sync in ipairs(self.controls) do self:Guard(sync) end
end
-- Old test panel uses the same visual/action primitive without owning runtime.
U.Button=U.CreateActionButton
