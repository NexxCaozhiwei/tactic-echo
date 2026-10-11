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
function H:Card(x,size)
    local f=U:Frame("Frame",self.frame,nil)
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
    return {frame=f,icon=icon,cooldown=cooldown,key=key,chargeText=charge,cooldownText=cd,
        state=U:Text(texts,4,-size+17,size-8,"GameFontNormalSmall"),
        meta=U:Text(f,0,-size-20,size+10,"GameFontHighlightSmall"),
        label=U:Text(texts,4,-4,size-8,"GameFontDisableSmall")}
end
function H:Layout()
    if not self.frame then return end
    if U:Combat()~=false then self.pending=true; return end
    self.pending=false; U:Paint(self.frame,"SetScale",self.engine.db.hud.scale)
end
function H:Create(e)
    self.engine=e; self.frame=U:Frame("Frame",UIParent,"BackdropTemplate","TEF_DeliveryHUD")
    if not self.frame then return end
    U:Paint(self.frame,"SetSize",244,145); U:Paint(self.frame,"SetPoint","CENTER",UIParent,"CENTER",e.db.hud.x or 0,e.db.hud.y or -155)
    U:Paint(self.frame,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8"})
    U:Paint(self.frame,"SetBackdropColor",.01,.02,.035,.15)
    U:Paint(self.frame,"SetClampedToScreen",true); U:Paint(self.frame,"SetMovable",true)
    U:Paint(self.frame,"EnableMouse",true); U:Paint(self.frame,"RegisterForDrag","LeftButton")
    U:Paint(self.frame,"SetScript","OnDragStart",function()
        if U:Combat()==false and not e.db.hud.locked then U:Call(self.frame,"StartMoving") end
    end)
    U:Paint(self.frame,"SetScript","OnDragStop",function()
        U:Call(self.frame,"StopMovingOrSizing")
        local ok,rawX,rawY=U:Invoke(self.frame,"GetCenter")
        local parentOK,rawPX,rawPY=U:Invoke(UIParent,"GetCenter")
        local scaleOK,rawScale=U:Invoke(self.frame,"GetEffectiveScale")
        local parentScaleOK,rawParentScale=U:Invoke(UIParent,"GetEffectiveScale")
        local x=ok and S.Public(rawX,"number"); local y=ok and S.Public(rawY,"number")
        local px=parentOK and S.Public(rawPX,"number"); local py=parentOK and S.Public(rawPY,"number")
        local scale=scaleOK and S.Public(rawScale,"number"); local parentScale=parentScaleOK and S.Public(rawParentScale,"number")
        if not x or not y or not px or not py or not scale or not parentScale or scale<=0 or parentScale<=0 then return end
        x=x-px*parentScale/scale; y=y-py*parentScale/scale
        if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then e.db.hud.x=x; e.db.hud.y=y end
    end)
    self.cards={self:Card(8,64),self:Card(84,44),self:Card(140,44)}
    self.name=U:Text(self.frame,8,-80,230,"GameFontHighlightSmall")
    self.status=U:Text(self.frame,8,-99,230,"GameFontHighlightSmall")
    self.pause=U:Button(self.frame,"启/停",4,-119,55,function() TEF_RunToggle() end)
    self.permission=U:Button(self.frame,"许可关",63,-119,55,function() TEF_PermissionToggle() end)
    U:Button(self.frame,"派发",122,-119,55,function() TEF_RequestCurrent() end)
    U:Button(self.frame,"设置",181,-119,55,function() U:OpenSettings() end)
    U:Call(self.frame,"SetScript","OnUpdate",function(_,rawElapsed)
        local elapsed=S.Public(rawElapsed,"number")
        if not elapsed or elapsed<0 then return end
        self.elapsed=(self.elapsed or 0)+elapsed
        if self.elapsed>=.2 then self.elapsed=self.elapsed%.2; self:Refresh() end
    end)
    self:Layout(); self:Refresh()
end
function H:Refresh(cooldownEvent)
    local e=self.engine; if not self.frame then return end
    local castLabel
    for _,entry in ipairs({{"UnitCastingInfo","施法"},{"UnitChannelInfo","引导"}}) do
        local ok,raw=S.Call(entry[1],"player")
        if ok and S.Public(raw,"string") then castLabel=entry[2] end
    end
    for i,card in ipairs(self.cards) do
        local index=e.index+i-1
        if e.db.loop and e.steps and index>#e.steps then index=(index-1)%#e.steps+1 end
        local step=e.steps and e.steps[index]
        if i>1 and (e.completed or not e.db.hud.preview) then step=nil end
        local view=step and S.Spell(step.spellID,step.name)
        if not U:Paint(card.icon,"SetTexture",view and view.icon or TEF.Placeholder) then U:Call(card.icon,"SetTexture",TEF.Placeholder) end
        U:Paint(card.label,"SetText",step and (i==1 and "主键" or "练习") or "")
        U:Paint(card.state,"SetText",step and (i==1 and castLabel or e.completed and "完成" or not e.running and "暂停" or i==1 and "推荐" or "随后") or "")
        if TEF.Presentation then TEF.Presentation:Paint(card,step,cooldownEvent) end
    end
    local step=e.steps and e.steps[e.index]
    local view=step and S.Spell(step.spellID,step.name)
    U:Paint(self.name,"SetText",e.completed and "完成" or (view and view.name or "未解析"))
    local mode=TEF.Dispatch and TEF.Dispatch.pending and "TEK派发请求" or "手动"
    U:Paint(self.status,"SetText",mode .. " | " .. (e.scene=="multi" and "多目标" or "单体") .. " | " .. e.index .. "/" .. (e.steps and #e.steps or 0) .. " | " .. (e.completed and "完成" or e.running and "运行" or "暂停"))
    U:Paint(self.pause,"SetText",e.running and "暂停" or "开始")
    U:Paint(self.permission,"SetText",TEF.Dispatch.enabled and "许可开" or "许可关")
end
