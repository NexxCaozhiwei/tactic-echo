-- Pure read-only recommendation queue. Queue records never alter the official
-- primary recommendation, TEAP bytes, binding token, or TEK dispatch path.
local TE = _G.TacticEcho
local Queue = {}
TE.RecommendationQueue = Queue

local DEFAULT = { "emergency", "interrupt", "primary", "burst", "control", "mobility", "candidate" }
local PRESETS = {
    output_first = { "emergency", "interrupt", "primary", "burst", "control", "mobility", "candidate" },
    safety_first = { "emergency", "interrupt", "mobility", "control", "burst", "primary", "candidate" },
}
local VALID = {}
for _, bucket in ipairs(DEFAULT) do VALID[bucket] = true end

local function normalizedOrder(order)
    local normalized, seen = {}, {}
    for _, bucket in ipairs(type(order) == "table" and order or {}) do
        if VALID[bucket] and not seen[bucket] then
            normalized[#normalized + 1] = bucket
            seen[bucket] = true
        end
    end
    for _, bucket in ipairs(DEFAULT) do
        if not seen[bucket] then normalized[#normalized + 1] = bucket end
    end
    return normalized
end

function Queue:GetOrder(settings)
    local custom = settings and settings.queueOrder
    if type(custom) == "table" and #custom > 0 then return normalizedOrder(custom) end
    local preset = settings and settings.queuePriorityPreset
    return normalizedOrder(PRESETS[preset] or DEFAULT)
end

local function record(bucket, item, reason, source, urgency)
    if not item or not item.spellID then return nil end
    return {
        bucket = bucket,
        spellID = item.spellID,
        spellName = item.spellName,
        spellIcon = item.spellIcon,
        binding = item.binding,
        item = item,
        reason = reason,
        source = source or "tactical_readonly",
        urgency = urgency or 0,
        advisoryOnly = bucket ~= "primary",
    }
end

function Queue:Build(snapshot, settings)
    snapshot, settings = snapshot or {}, settings or {}
    local by = {}
    local defensive = snapshot.defensives or {}
    if defensive.active and defensive.items and defensive.items[1] then
        by.emergency = record("emergency", defensive.items[1], defensive.notice or "防御条件成立", defensive.healthSource or defensive.source, defensive.severity == "emergency" and 100 or 70)
    end
    local interrupt = snapshot.interrupt or {}
    if interrupt.active and interrupt.suggestion then
        by.interrupt = record("interrupt", interrupt.suggestion, interrupt.notice or "目标正在读条", interrupt.source or "target_cast", 95)
    end
    if snapshot.primaryDisplay and snapshot.primaryDisplay.spellID then
        by.primary = record("primary", snapshot.primaryDisplay, snapshot.primaryDisplay.reasonText or "官方主推荐", "C_AssistedCombat", 60)
        by.primary.advisoryOnly = false
    end
    local advisory = snapshot.advisory or {}
    for key, bucket in pairs({ burst = "burst", control = "control", mobility = "mobility" }) do
        local section = advisory[key] or {}
        if section.active and section.items and section.items[1] then
            by[bucket] = record(bucket, section.items[1], section.notice or "战术条件成立", section.source or key, bucket == "control" and 75 or 50)
        end
    end
    local history = snapshot.history or {}
    if history.items and history.items[1] then
        by.candidate = record("candidate", history.items[1], history.notice or "会话预测", history.source, 10)
    end
    local order = self:GetOrder(settings)
    local items = {}
    for _, bucket in ipairs(order) do
        if by[bucket] then items[#items + 1] = by[bucket] end
    end
    return { schema = 2, items = items, order = order, source = "read_only_queue" }
end
