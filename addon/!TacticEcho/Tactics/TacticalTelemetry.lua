-- Local-only advisory trace. It is opt-in for explicit diagnostics only;
-- normal HUD or monitor-page operation must not allocate SavedVariables
-- telemetry every refresh.
local TE = _G.TacticEcho

local TacticalTelemetry = {}
TE.TacticalTelemetry = TacticalTelemetry

local function enabled()
    local db = TacticEchoDB or {}
    local settings = db.settings or {}
    return settings.diagnosticsEnabled == true
end

local function store()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tacticalTelemetry = TacticEchoDB.tacticalTelemetry or { records = {} }
    return TacticEchoDB.tacticalTelemetry
end

function TacticalTelemetry:Record(snapshot)
    if enabled() ~= true or type(snapshot) ~= "table" then return end
    local primary = snapshot.primary or {}
    local interrupt = snapshot.interrupt or {}
    local defensives = snapshot.defensives or {}
    local monitor = primary.monitor or {}
    local record = {
        elapsed = type(GetTime) == "function" and GetTime() or 0,
        spellID = primary.spellID,
        primaryState = primary.state,
        primaryReason = primary.reason,
        binding = primary.binding,
        interruptActive = interrupt.active == true,
        targetCasting = monitor.targetCasting == true,
        targetCastSpellID = nil,
        targetCastDangerous = monitor.targetCastDangerous == true,
        targetInterruptible = monitor.targetInterruptibleKnown == true and monitor.targetInterruptible == true or nil,
        playerHealthCritical = monitor.playerHealthCritical == true,
        defensiveSeverity = defensives.severity,
        defensiveCount = #(defensives.items or {}),
    }
    local db = store()
    local records = db.records
    local last = records[#records]
    if last and last.spellID == record.spellID and last.primaryState == record.primaryState
        and last.interruptActive == record.interruptActive and last.targetCasting == record.targetCasting
        and last.defensiveSeverity == record.defensiveSeverity then
        return
    end
    records[#records + 1] = record
    while #records > 60 do table.remove(records, 1) end
    db.last = record
end

function TacticalTelemetry:GetLast()
    return store().last
end
