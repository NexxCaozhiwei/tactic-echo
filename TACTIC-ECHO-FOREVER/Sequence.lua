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
        current = current or self.index, next = nextStep or self.index,
        kind = kind, reason = reason, spellID = spellID,
        scene = self.scene,
        event = observed[event] and event or nil }
    self.lastReason = reason
end

local function configuration(config)
    if type(config) ~= "table" or #config == 0 or #config > 32 then return nil end
    local steps = {}
    for i, row in ipairs(config) do
        if type(row) ~= "table" then return nil end
        local id = S.ID(row.spellID)
        local name = S.Public(row.name, "string")
        local pending = row.unverified == true and row.spellID == 0 and type(row.matchIDs)=="table" and #row.matchIDs==0
        if pending and name and #name>0 and #name<=128 then
            steps[i]={name=name,spellID=0,matches={},unverified=true}
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
        steps[i] = {name = name, spellID = id, matches = matches}
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
    local position
    if type(db.position) == "table" then
        local x = S.Public(db.position.x, "number")
        local y = S.Public(db.position.y, "number")
        if x and y and math.abs(x) <= 10000 and math.abs(y) <= 10000 then position = {x=x,y=y} end
    end
    -- Rebuild a scalar whitelist for old history; don't carry arbitrary DB fields.
    local clean = {schema=1, version=TEF.Version, session=oldSession + 1,
        loop=looping == true, position=position, diagnostics={}, evicted=0}
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
                        research=TEF.Research and TEF.Research.CleanSummary(S.Field(r,"research","table")) or nil}
                end
            end
        end
    end
    local evicted = S.Public(db.evicted, "number")
    if evicted and evicted >= 0 and evicted % 1 == 0 then clean.evicted = evicted end
    local self = setmetatable({db=clean,session=clean.session,generation=1,index=1,
        running=false,completed=false,seen={},seenCount=0,associations={},associationCount=0,
        steps=configuration(config)}, Engine)
    if TEF.Profiles then TEF.Profiles:Initialize(self, db) end
    self:Log("lifecycle", "LOGIN_PAUSED")
    if not self.steps then self:Log("error", "CONFIG_INVALID") end
    return self
end

function Engine:Invalidate(reason)
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
    self.index, self.completed = 1, false
    self.running = self.steps ~= nil
end
function Engine:Pause()
    self.running = false
    self:Invalidate("PAUSE")
end
function Engine:Resume()
    self:Invalidate("RESUME")
    self.running = self.steps ~= nil and not self.completed
end
function Engine:Reset()
    self.running = false
    self:Invalidate("RESET")
    self.index, self.completed = 1, false
end
function Engine:SetLoop(value)
    self.db.loop = value == true
    self:Log("lifecycle", self.db.loop and "LOOP_ON" or "LOOP_OFF")
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
        if event == "UNIT_SPELLCAST_SUCCEEDED" then log("duplicate", "DUPLICATE_SUCCESS", spellID)
        else log("observed", "CONSUMED_IDENTITY_EVENT", spellID) end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_START" then
        -- SENT observes initiation only; no target argument is consumed.
        if not self.associations[guid] then
            if self.associationCount >= 256 then
                self.running=false; self:Invalidate("ASSOCIATION_CAPACITY_PAUSED"); return
            end
            self.associationCount=self.associationCount+1
            self.associations[guid] = {generation=generation,spellID=spellID,index=self.index}
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
    if not a or a.generation ~= generation or a.spellID ~= spellID or a.index ~= self.index then
        log("ignored", "NO_CURRENT_INITIATION", spellID); return
    end
    if a.failed then log("ignored", "FAILED_INITIATION", spellID); return end
    -- Never evict success tombstones: on saturation fail closed until reload.
    if self.seenCount >= 4096 then
        self.running=false; self:Invalidate("IDENTITY_CAPACITY_PAUSED"); return
    end
    self.seen[guid], self.seenCount = true, self.seenCount+1
    self.associations[guid]=nil; self.associationCount=self.associationCount-1
    local current, following = self.index, self.index+1
    if following > #self.steps then
        if self.db.loop then following=1
        else following=current; self.completed=true; self.running=false end
        log("completed", self.db.loop and "LOOP_COMPLETED" or "COMPLETED", spellID, current, following)
    else log("match", "CURRENT_MATCH", spellID, current, following) end
    self.index=following
    -- No polling, scheduled advance, cast-state write, or automatic input.
end
