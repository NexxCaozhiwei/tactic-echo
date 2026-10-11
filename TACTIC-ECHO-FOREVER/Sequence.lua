local _, TEF = ...
local S = TEF.Safety
local Engine = {}
Engine.__index = Engine
TEF.Engine = Engine

local observed = {
    UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_FAILED_QUIET = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}
TEF.Events = observed

function Engine:Log(kind, reason, spellID, current, nextStep, event)
    local d = self.db.diagnostics
    if #d >= 128 then table.remove(d, 1); self.db.evicted = self.db.evicted + 1 end
    d[#d + 1] = { session = self.session, generation = self.generation,
        cycle=TEF.Runtime and TEF.Runtime.e==self and TEF.Runtime.cycle or nil,
        request=TEF.Runtime and TEF.Runtime.e==self and TEF.Runtime.requestSerial or nil,
        current = current or self.index, next = nextStep or self.index,
        castCount=self.stepCasts or 0, requiredCasts=self.steps and self.steps[self.index] and self.steps[self.index].repeatCount or nil,
        kind = kind, reason = reason, spellID = spellID,
        scene = self.scene, version=TEF.Version,
        event = observed[event] and event or nil }
    self.lastReason = reason
end

local function configuration(config)
    if type(config) ~= "table" or #config == 0 or #config > 16 then return nil end
    local steps = {}
    for i, row in ipairs(config) do
        if type(row) ~= "table" then return nil end
        local id = S.ID(row.spellID)
        local name = S.Public(row.name, "string")
        local repeats, reason=S.Field(row,"repeatCount","number")
        if reason=="NO_DATA" then repeats=1 end
        if not repeats or repeats<1 or repeats>99 or repeats%1~=0 then return nil end
        local pending = row.unverified == true and row.spellID == 0 and type(row.matchIDs)=="table" and #row.matchIDs==0
        if pending and name and #name>0 and #name<=128 then
            steps[i]={name=name,spellID=0,matches={},unverified=true,repeatCount=repeats}
        else
        if not id or id==7268 or not name or #name == 0 or #name > 128 or type(row.matchIDs) ~= "table"
            or #row.matchIDs == 0 or #row.matchIDs > 16 then return nil end
        local matches = {}
        for _, raw in ipairs(row.matchIDs) do
            local match = S.ID(raw)
            -- Channel tick is deliberately forbidden even in manual configuration.
            if not match or match == 7268 then return nil end
            matches[match] = true
        end
        steps[i] = {name = name, spellID = id, matches = matches,repeatCount=repeats}
        end
    end
    return steps
end
Engine.Validate = configuration

function Engine.New(config, db)
    -- Only TEF's own data is accepted. No active state or event GUID is restored.
    db = type(db) == "table" and db or {}
    local oldSession = S.ID(db.session) or 0
    local looping = S.Public(db.loop, "boolean")
    local loopMode = S.Field(db,"loopMode","string")
    local validModes={none=true,normal=true,target=true,combat=true}
    if not validModes[loopMode] then loopMode=looping==true and "normal" or "none" end
    local position
    if type(db.position) == "table" then
        local x = S.Public(db.position.x, "number")
        local y = S.Public(db.position.y, "number")
        if x and y and math.abs(x) <= 10000 and math.abs(y) <= 10000 then position = {x=x,y=y} end
    end
    -- Rebuild a scalar whitelist for old history; don't carry arbitrary DB fields.
    local clean = {schema=1, version=TEF.Version, session=oldSession + 1,
        loop=loopMode~="none", loopMode=loopMode, position=position, diagnostics={}, evicted=0}
    local kinds = {transport=true, match=true, completed=true, deviation=true, ignored=true, unknown=true,
        lifecycle=true, duplicate=true, associated=true, observed=true, display=true, error=true}
    if type(db.diagnostics) == "table" then
        for i = math.max(1, #db.diagnostics - 127), #db.diagnostics do
            local r = db.diagnostics[i]
            if type(r) == "table" then
                local kind = S.Public(r.kind, "string")
                local reason = S.Public(r.reason, "string")
                local session, generation = S.ID(r.session), S.ID(r.generation)
                local current, following = S.ID(r.current), S.ID(r.next)
                local event = S.Public(r.event, "string")
                if kind and kinds[kind] and reason and #reason <= 80 and reason:match("^[A-Z_]+$")
                    and session and generation and current and following then
                    clean.diagnostics[#clean.diagnostics+1] = {kind=kind,reason=reason,
                        session=session,generation=generation,current=current,next=following,spellID=S.ID(r.spellID),
                        event=observed[event] and event or nil,
                        scene=S.Field(r,"scene","string")=="multi" and "multi" or "single",
                        version=S.Field(r,"version","string"),
                        cycle=S.Field(r,"cycle","number"),request=S.Field(r,"request","number"),
                        castCount=S.Field(r,"castCount","number"),requiredCasts=S.Field(r,"requiredCasts","number"),
                        research=TEF.Research and TEF.Research.CleanSummary(S.Field(r,"research","table")) or nil,
                        apl=TEF.APL and TEF.APL.Trace.Clean(S.Field(r,"apl","table")) or nil}
                end
            end
        end
    end
    local evicted = S.Public(db.evicted, "number")
    if evicted and evicted >= 0 and evicted % 1 == 0 then clean.evicted = evicted end
    local self = setmetatable({db=clean,session=clean.session,generation=1,index=1,stepCasts=0,
        running=false,completed=false,seen={},seenCount=0,associations={},associationCount=0,
        steps=configuration(config)}, Engine)
    if TEF.Profiles then TEF.Profiles:Initialize(self, db) end
    self:Log("lifecycle", "LOGIN_PAUSED")
    if not self.steps then self:Log("error", "CONFIG_INVALID") end
    return self
end

function Engine:Invalidate(reason)
    self.shootHandoff=nil
    -- Public initiation identities already accepted by Handle must stay retired
    -- across reset/pause. A late START must not recreate an old association in
    -- the new generation. Share the existing bounded identity budget.
    for guid in pairs(self.associations) do
        if not self.seen[guid] then
            if self.seenCount>=4096 then self.identitySaturated=true; break end
            self.seen[guid]="retired"; self.seenCount=self.seenCount+1
        end
    end
    if TEF.Runtime then TEF.Runtime:Invalidated(self) end
    if TEF.Dispatch then TEF.Dispatch:StopContinuous("CONTINUOUS_LIFECYCLE_STOP") end
    if TEF.Presentation then TEF.Presentation.cooldowns={}; TEF.Presentation.bindings={} end
    if TEF.Dispatch then TEF.Dispatch:Cancel("TEK_LIFECYCLE_INVALIDATED") end
    self.generation = self.generation + 1
    self.associations, self.associationCount = {}, 0
    if TEF.Research then TEF.Research:Invalidate() end
    -- Successful identities remain tombstones across pause/reset/restart.
    self:Log("lifecycle", reason)
end

function Engine:Start()
    self:Invalidate("START")
    self.index, self.completed, self.stepCasts = 1, false, 0
    self.running = self.steps ~= nil and not self.identitySaturated
end
function Engine:Pause()
    self.running = false
    self:Invalidate("PAUSE")
end
function Engine:Resume()
    self:Invalidate("RESUME")
    self.running = self.steps ~= nil and not self.completed and not self.identitySaturated
    -- Resume retains a selected action, but Packet still requires fresh live
    -- dependencies. Pause/reset snapshots fail generation checks until sampled.
    if TEF.APL and TEF.APL:IsActive(self) and self.aplSnapshot then self.aplSnapshot.generation=self.generation end
end
function Engine:Reset()
    self.running = false
    self:Invalidate("RESET")
    self.index, self.completed, self.stepCasts = 1, false, 0
end
function Engine:SetLoop(value)
    self.db.loop = value == true
    if not self.db.loop then self.db.loopMode="none"
    elseif self.db.loopMode=="none" then self.db.loopMode="normal" end
    self:Log("lifecycle", self.db.loop and "LOOP_ON" or "LOOP_OFF")
end
function Engine:SetLoopMode(mode)
    if mode~="none" and mode~="normal" and mode~="target" and mode~="combat" then return false end
    self.db.loopMode=mode; self.db.loop=mode~="none"
    self:Log("lifecycle","LOOP_MODE_" .. mode:upper()); return true
end

function Engine:Handle(generation, event, unitRaw, guidRaw, spellRaw)
    if not observed[event] then return end
    local function log(kind, reason, spellID, current, nextStep)
        self:Log(kind, reason, spellID, current, nextStep, event)
    end
    if generation ~= self.generation then log("ignored", "STALE_GENERATION"); return end
    -- Independently classify each field. Never persist any raw argument.
    local unit, ur = S.Public(unitRaw, "string")
    local spellID, sr = S.ID(spellRaw)
    local guid, gr = S.Identity(guidRaw)
    if generation ~= self.generation then log("ignored", "STALE_GENERATION"); return end
    if not unit then log("unknown", "UNIT_" .. ur); return end
    if unit ~= "player" then return end
    if not spellID then log("unknown", "SPELL_" .. sr); return end
    if not guid then log("unknown", "IDENTITY_" .. gr, spellID); return end
    if not self.running then log("ignored", "PAUSED_IGNORED", spellID); return end
    if self.seen[guid] then
        if self.seen[guid]=="retired" then log("ignored","RETIRED_IDENTITY",spellID)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then log("duplicate", "DUPLICATE_SUCCESS", spellID)
        else log("observed", "CONSUMED_IDENTITY_EVENT", spellID) end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_START" then
        if self.steps[self.index].matches[spellID] then self.shootHandoff=nil end
        -- SENT observes initiation only; no target argument is consumed.
        if not self.associations[guid] then
            if self.associationCount >= 256 then
                self.running=false; self:Invalidate("ASSOCIATION_CAPACITY_PAUSED"); return
            end
            self.associationCount=self.associationCount+1
            self.associations[guid] = {generation=generation,spellID=spellID,index=self.index,receiptSerial=self.receiptSerial or 0}
            log("associated", "PUBLIC_INITIATION", spellID)
        end
        return
    end
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_FAILED_QUIET" then
            local a = self.associations[guid]
            if a then a.failed=true end
        end
        log("observed", event, spellID)
        return
    end
    if spellID == 7268 then log("ignored", "CHANNEL_CHILD_IGNORED", spellID); return end
    if not self.steps[self.index].matches[spellID] then
        log("deviation", "OUT_OF_SEQUENCE", spellID); return
    end
    local a = self.associations[guid]
    if not a or a.generation ~= generation or a.spellID ~= spellID or a.index ~= self.index
        or a.receiptSerial~=(self.receiptSerial or 0) then
        log("ignored", "NO_CURRENT_INITIATION", spellID); return
    end
    if a.failed then log("ignored", "FAILED_INITIATION", spellID); return end
    -- Never evict success tombstones: on saturation fail closed until reload.
    if self.seenCount >= 4096 then
        self.running=false; self:Invalidate("IDENTITY_CAPACITY_PAUSED"); return
    end
    self.seen[guid], self.seenCount = true, self.seenCount+1
    self.receiptSerial=(self.receiptSerial or 0)+1
    self.associations[guid]=nil; self.associationCount=self.associationCount-1
    if TEF.APL and TEF.APL:IsActive(self) then
        self.stepCasts=0
        log("match","APL_MATCH",spellID,self.index,self.index)
        TEF.APL:Invalidate()
        return
    end
    self.stepCasts=self.stepCasts+1
    if self.stepCasts<self.steps[self.index].repeatCount then
        log("match","STEP_REPEAT_MATCH",spellID,self.index,self.index)
        return
    end
    local current, following = self.index, self.index+1
    if following > #self.steps then
        if self.db.loop then following=1
        else following=current; self.completed=true; self.running=false end
        log("completed", self.db.loop and "LOOP_COMPLETED" or "COMPLETED", spellID, current, following)
    else log("match", "CURRENT_MATCH", spellID, current, following) end
    self.index=following
    if spellID==5019 and not self.completed and following~=current
        and self.steps[following].spellID~=5019 then
        self.shootHandoff={generation=self.generation,index=following,receiptSerial=self.receiptSerial}
        log("observed","SHOOT_SUCCESS_HANDOFF",spellID,current,following)
    else self.shootHandoff=nil end
    if not self.completed then self.stepCasts=0 end
    -- No polling, scheduled advance, cast-state write, or automatic input.
end
