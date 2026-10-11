local _, TEF = ...
local H, U, S = {}, TEF.UI, TEF.Safety
TEF.HUD = H
-- Visual-only, unprotected frames. No secure click proxy or input authority.
local function texture(parent, layer)
    local ok,t=U:Invoke(parent,"CreateTexture",nil,layer or "ARTWORK")
    return ok and t or nil
end
local function atlas(t,name)
    local ok,info=S.Call("C_Texture.GetAtlasInfo",name)
    if not ok or not S.Public(info,"table") then return false end
    return U:Call(t,"SetAtlas",name,false)
end
function H:Card(x,size,primary)
    local f=U:Frame(primary and "Button" or "Frame",self.frame,nil)
    U:Paint(f,"SetSize",size,size); U:Paint(f,"SetPoint","TOPLEFT",self.frame,"TOPLEFT",x,-8)
    local bg=texture(f,"BACKGROUND"); U:Paint(bg,"SetAllPoints",f)
    if not atlas(bg,"UI-HUD-ActionBar-IconFrame-Background") then U:Paint(bg,"SetColorTexture",0.08,0.10,0.15,1) end
    local icon=texture(f); U:Paint(icon,"SetPoint","TOPLEFT",f,"TOPLEFT",3,-3)
    U:Paint(icon,"SetPoint","BOTTOMRIGHT",f,"BOTTOMRIGHT",-3,3); U:Paint(icon,"SetTexCoord",.08,.92,.08,.92)
    local borderFrame=U:Frame("Frame",f); U:Call(borderFrame,"SetAllPoints",f)
    local border=texture(borderFrame,"OVERLAY"); U:Paint(border,"SetPoint","TOPLEFT",f,"TOPLEFT",0,0)
    U:Paint(border,"SetSize",size+1,size)
    if not atlas(border,"UI-HUD-ActionBar-IconFrame") then
        U:Paint(border,"SetTexture","Interface\\Buttons\\UI-ActionButton-Border")
        U:Paint(border,"SetVertexColor",.96,.78,.18,1)
    end
    local ok,mask=U:Invoke(f,"CreateMaskTexture",nil,"ARTWORK")
    if ok and atlas(mask,"UI-HUD-ActionBar-IconFrame-Mask") then
        U:Call(mask,"SetPoint","CENTER",f,"CENTER",0,0); U:Call(mask,"SetSize",size*1.5,size*1.5)
        U:Call(icon,"AddMaskTexture",mask); U:Call(bg,"AddMaskTexture",mask)
    end
    local clipped=U:Frame("Frame",f); U:Call(clipped,"SetAllPoints",f); U:Call(clipped,"SetClipsChildren",true)
    local cooldown=U:Frame("Cooldown",clipped,"CooldownFrameTemplate")
    U:Call(cooldown,"SetAllPoints",icon); U:Call(cooldown,"SetHideCountdownNumbers",true)
    U:Call(cooldown,"SetDrawBling",false); U:Call(cooldown,"SetDrawEdge",false)
    local texts=U:Frame("Frame",f); U:Call(texts,"SetAllPoints",f)
    U:Call(clipped,"SetFrameLevel",2); U:Call(cooldown,"SetFrameLevel",3)
    U:Call(borderFrame,"SetFrameLevel",5); U:Call(texts,"SetFrameLevel",22)
    local key=U:Text(texts,3,-3,size-6,"GameFontNormalSmall"); U:Call(key,"SetJustifyH","RIGHT")
    local charge=U:Text(texts,3,-size+17,size-6,"GameFontNormalSmall"); U:Call(charge,"SetJustifyH","RIGHT")
    local cd=U:Text(texts,3,-size/2+6,size-6,"GameFontNormalSmall"); U:Call(cd,"SetJustifyH","CENTER")
    local overlay=texture(texts,"OVERLAY"); U:Call(overlay,"SetAllPoints",icon); U:Call(overlay,"SetColorTexture",1,1,1,0)
    U:Call(borderFrame,"EnableMouse",false); U:Call(clipped,"EnableMouse",false); U:Call(texts,"EnableMouse",false)
    local card={frame=f,textParent=texts,size=size,icon=icon,border=border,overlay=overlay,cooldown=cooldown,key=key,chargeText=charge,cooldownText=cd,
        state=U:Text(texts,4,-size+17,size-8,"GameFontNormalSmall"),
        meta=U:Text(f,0,-size-20,size+10,"GameFontHighlightSmall"),
        label=U:Text(texts,4,-4,size-8,"GameFontDisableSmall")}
    if primary then
        U:Call(f,"RegisterForClicks","LeftButtonUp","RightButtonUp")
        U:Call(f,"SetScript","OnClick",function(_,rawButton)
            U:Guard(function()
                if self.dragging then return end
                local button=S.Public(rawButton,"string")
                if button=="LeftButton" then TEF_ToggleDispatchIntent()
                elseif button=="RightButton" then U:OpenSettings() end
            end)
        end)
        U:Call(f,"SetScript","OnEnter",function()
            card.hover=true; self:RefreshState()
            U:Call(GameTooltip,"SetOwner",f,"ANCHOR_RIGHT")
            U:Call(GameTooltip,"AddLine","TACTIC ECHO FOREVER")
            U:Call(GameTooltip,"AddLine","左键：派发启/停；右键：设置",1,1,1)
            U:Call(GameTooltip,"AddLine","当前：" .. TEF.Runtime:GetViewState().label,.7,.8,.9)
            U:Call(GameTooltip,"AddLine","不会直接施法",.7,.7,.7); U:Call(GameTooltip,"Show")
        end)
        U:Call(f,"SetScript","OnLeave",function() card.hover=false; card.pressed=false; self:RefreshState(); U:Call(GameTooltip,"Hide") end)
        U:Call(f,"SetScript","OnMouseDown",function() card.pressed=true; self:RefreshState() end)
        U:Call(f,"SetScript","OnMouseUp",function() card.pressed=false; self:RefreshState() end)
    end
    return card
end
function H:Layout()
    if not self.frame then return end
    if U:Combat()~=false then self.pending=true; return end
    self.pending=false; U:Paint(self.frame,"SetScale",self.engine.db.hud.scale)
    TEF.HudStyles:Apply(self)
end
function H:Create(e)
    self.engine=e; self.frame=U:Frame("Frame",UIParent,nil,"TEF_DeliveryHUD")
    if not self.frame then return end
    U:Paint(self.frame,"SetSize",244,121); U:Paint(self.frame,"SetPoint","CENTER",UIParent,"CENTER",e.db.hud.x or 0,e.db.hud.y or -155)
    U:Paint(self.frame,"SetClampedToScreen",true); U:Paint(self.frame,"SetMovable",true)
    U:Paint(self.frame,"EnableMouse",true); U:Paint(self.frame,"RegisterForDrag","LeftButton")
    U:Paint(self.frame,"SetScript","OnDragStart",function()
        if U:Combat()==false and not self.engine.db.hud.locked then self.dragging=true; U:Call(self.frame,"StartMoving") end
    end)
    U:Paint(self.frame,"SetScript","OnDragStop",function()
        if not self.dragging then return end
        self.dragging=false; U:Call(self.frame,"StopMovingOrSizing")
        local ok,rawX,rawY=U:Invoke(self.frame,"GetCenter")
        local parentOK,rawPX,rawPY=U:Invoke(UIParent,"GetCenter")
        local scaleOK,rawScale=U:Invoke(self.frame,"GetEffectiveScale")
        local parentScaleOK,rawParentScale=U:Invoke(UIParent,"GetEffectiveScale")
        local x=ok and S.Public(rawX,"number"); local y=ok and S.Public(rawY,"number")
        local px=parentOK and S.Public(rawPX,"number"); local py=parentOK and S.Public(rawPY,"number")
        local scale=scaleOK and S.Public(rawScale,"number"); local parentScale=parentScaleOK and S.Public(rawParentScale,"number")
        if not x or not y or not px or not py or not scale or not parentScale or scale<=0 or parentScale<=0 then return end
        x=x-px*parentScale/scale; y=y-py*parentScale/scale
        if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then self.engine.db.hud.x=x; self.engine.db.hud.y=y end
    end)
    self.cards={self:Card(8,64,true),self:Card(84,44),self:Card(140,44)}
    self.name=U:Text(self.frame,8,-80,230,"GameFontHighlightSmall")
    self.status=U:Text(self.frame,8,-99,230,"GameFontHighlightSmall")
    U:Call(self.frame,"SetScript","OnUpdate",function(_,rawElapsed)
        local elapsed=S.Public(rawElapsed,"number")
        if not elapsed or elapsed<0 then return end
        self.elapsed=(self.elapsed or 0)+elapsed
        if self.elapsed>=.25 then self.elapsed=self.elapsed%.25; self:VisualTick() end
    end)
    self:Layout(); self:Refresh()
end
function H:Refresh(cooldownEvent)
    local e=self.engine; if not self.frame then return end
    self.metadata=self.metadata or {}
    for i,card in ipairs(self.cards) do
        local index=e.index+i-1
        if e.db.loop and e.steps and index>#e.steps then index=(index-1)%#e.steps+1 end
        local step=e.steps and e.steps[index]
        if i>1 and (e.completed or not e.db.hud.preview) then step=nil end
        local key=step and (step.spellID .. ":" .. step.name)
        local view=key and self.metadata[key]
        if step and not view then view=S.Spell(step.spellID,step.name); self.metadata[key]=view end
        if not U:Paint(card.icon,"SetTexture",view and view.icon or TEF.Placeholder) then U:Call(card.icon,"SetTexture",TEF.Placeholder) end
        U:Paint(card.label,"SetText",step and (i==1 and "主键" or "练习") or "")
        card.displayStep=step
        if TEF.Presentation then TEF.Presentation:Paint(card,step,cooldownEvent) end
    end
    local step=e.steps and e.steps[e.index]
    local view=step and self.metadata[step.spellID .. ":" .. step.name]
    U:Paint(self.name,"SetText",e.completed and "完成" or (view and view.name or "未配置推荐序列"))
    self:RefreshState()
end
H.colors={paused={.48,.52,.60},standby={.36,.78,.90},running={.22,.96,.56},blocked={.96,.72,.18},completed={.96,.83,.45},error={1,.25,.25}}
function H:RefreshState()
    if not self.frame or not self.cards then return end
    local e=self.engine; local v=TEF.Runtime:GetViewState()
    local step=e.steps and e.steps[e.index]
    if TEF.Runtime.e~=e then v={state=e.running and "running" or "paused",label=e.running and "推荐" or "暂停"} end
    if e.completed then v.state="completed"; v.label="完成" end
    local c=self.colors[v.state] or self.colors.paused
    local primary=self.cards[1]
    U:Paint(primary.border,"SetVertexColor",c[1],c[2],c[3],1)
    U:Paint(primary.overlay,"SetColorTexture",c[1],c[2],c[3],primary.pressed and .22 or primary.hover and .12 or .025)
    local castLabel
    for _,entry in ipairs({{"UnitCastingInfo","施法"},{"UnitChannelInfo","引导"}}) do
        local ok,raw=S.Call(entry[1],"player")
        if ok and S.Public(raw,"string") then castLabel=entry[2] end
    end
    for i,card in ipairs(self.cards) do U:Paint(card.state,"SetText",card.displayStep and (i==1 and (castLabel or v.label) or "随后") or "") end
    U:Paint(self.status,"SetText",v.label .. " | " .. (e.scene=="multi" and "多目标" or "单体") .. " | " .. e.index .. "/" .. (e.steps and #e.steps or 0) .. " · 次数 " .. (e.stepCasts or 0) .. "/" .. (step and step.repeatCount or 1))
end
function H:VisualTick()
    -- No spell/action/binding/presence reads in the visual fallback.
    for _,card in ipairs(self.cards or {}) do TEF.Presentation:Tick(card) end
end
