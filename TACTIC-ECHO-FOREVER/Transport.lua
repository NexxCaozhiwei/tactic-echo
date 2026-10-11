local _, TEF = ...
local S, T = TEF.Safety, {enabled=false,freshness=0,sequence=0,blocks={}}
TEF.Transport = T
function T:Fail(reason)
    self.enabled=false
    if TEF.Dispatch then TEF.Dispatch:Cancel("TEK_SIGNAL_FAILED") end
    if self.frame then TEF.UI:Call(self.frame,"Hide") end
    self.engine:Log("error",reason)
    return false
end
local function xor(a,b)
    local value,power=0,1
    for _=1,16 do
        if a%2~=b%2 then value=value+power end
        a=math.floor(a/2); b=math.floor(b/2); power=power*2
    end
    return value
end
function T.Encode(session,sequence,freshness,state,token,inCombat)
    local fields={84,69,3,state,session%256,math.floor(session/256),sequence%256,
        math.floor(sequence/256),freshness%256,math.floor(freshness/256),
        0,token and 2 or 0,token and 132 or 0,token and 100 or 0,
        token and token%256 or 0,token and math.floor(token/256) or 0,
        token and (inCombat and 1 or 0) or (state==2 and 0 or 2)}
    local crc=65535
    for _,value in ipairs(fields) do
        crc=xor(crc,value*256)
        for _=1,8 do
            local high=crc>=32768
            crc=(crc*2)%65536
            if high then crc=xor(crc,4129) end
        end
    end
    fields[18],fields[19],fields[20]=crc%256,math.floor(crc/256),165
    return fields
end
function T:Paint()
    local e=self.engine
    self.sequence=(self.sequence+1)%65536; self.freshness=(self.freshness+1)%65536
    local token,inCombat
    if TEF.Dispatch then token,inCombat=TEF.Dispatch:Packet() end
    self.fields=T.Encode(e.session%65536,self.sequence,self.freshness,token and 1 or (e.running and 0 or 2),token,inCombat)
    for i,value in ipairs(self.fields) do
        if not TEF.UI:Call(self.blocks[i],"SetColorTexture",value/255,1-value/255,17/255,1) then
            -- A partial strip is not retained as a verified signal.
            return self:Fail("TRANSPORT_PAINT_FAILED")
        end
    end
    return true
end
function T:Initialize(engine)
    self.engine=engine; self.enabled=false
end
function T:SetEnabled(value)
    if not value then
        if TEF.Dispatch then TEF.Dispatch:Cancel("TEK_TRANSPORT_OFF") end
        self.enabled=false
        if self.frame then TEF.UI:Call(self.frame,"Hide") end
        self.engine:Log("lifecycle","TRANSPORT_OFF"); return true
    end
    self.enabled=false
    if self.frame then TEF.UI:Call(self.frame,"Hide") end
    if not self.frame then
        self.frame=TEF.UI:Frame("Frame",UIParent,nil,"TEF_ProtocolStrip")
        if not self.frame then return self:Fail("TRANSPORT_FRAME_FAILED") end
        TEF.UI:Call(self.frame,"Hide")
        TEF.UI:Call(self.frame,"SetFrameStrata","TOOLTIP")
        for i=1,20 do
            local ok,texture=TEF.UI:Invoke(self.frame,"CreateTexture",nil,"ARTWORK")
            if not ok then return self:Fail("TRANSPORT_TEXTURE_FAILED") end
            self.blocks[i]=texture
        end
        -- One protocol heartbeat only. No API state sampling or step advance.
        local scriptOK=TEF.UI:Call(self.frame,"SetScript","OnUpdate",function(_,rawElapsed)
            if not self.enabled then return end
            local elapsed=S.Public(rawElapsed,"number")
            if not elapsed or elapsed<0 then self:SetEnabled(false); return end
            self.elapsed=(self.elapsed or 0)+elapsed
            if self.elapsed>=0.05 then
                self.elapsed=self.elapsed%0.05
                if not self:Paint() then return end
            end
        end)
        if not scriptOK then return self:Fail("TRANSPORT_SCRIPT_FAILED") end
    end
    local ok,raw=TEF.UI:Invoke(UIParent,"GetEffectiveScale")
    local scale=ok and S.Public(raw,"number")
    if not scale or scale<=0 then
        TEF.UI:Call(self.frame,"Hide"); self.engine:Log("unknown","TRANSPORT_SCALE_UNKNOWN"); return false
    end
    local cell,margin=math.ceil(8/scale),math.ceil(8/scale)
    if not TEF.UI:Call(self.frame,"SetSize",cell*20,cell)
        or not TEF.UI:Call(self.frame,"ClearAllPoints")
        or not TEF.UI:Call(self.frame,"SetPoint","TOPLEFT",UIParent,"TOPLEFT",margin,-margin) then return self:Fail("TRANSPORT_LAYOUT_FAILED") end
    for i,texture in ipairs(self.blocks) do
        if not TEF.UI:Call(texture,"SetSize",cell,cell)
            or not TEF.UI:Call(texture,"ClearAllPoints")
            or not TEF.UI:Call(texture,"SetPoint","TOPLEFT",self.frame,"TOPLEFT",(i-1)*cell,0) then return self:Fail("TRANSPORT_LAYOUT_FAILED") end
    end
    self.elapsed=0
    self.enabled=true
    if not self:Paint() then return false end
    if not TEF.UI:Call(self.frame,"Show") then return self:Fail("TRANSPORT_SHOW_FAILED") end
    self.engine:Log("lifecycle","TRANSPORT_OBSERVATION_ON")
    return true
end
