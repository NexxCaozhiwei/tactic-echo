-- Optional, session-local performance diagnostics and short error circuit.
-- Disabled by default. When disabled, hot-path counters return immediately and
-- no SavedVariables writes occur. The circuit breaker remains available for API
-- boundaries so one repeated fault cannot execute twenty times per second.
local TE = _G.TacticEcho

local Diagnostics = {
    enabled = false,
    counters = {},
    milliseconds = {},
    currentSecond = { startedAt = 0, counters = {}, milliseconds = {} },
    lastSecond = { elapsed = 0, counters = {}, milliseconds = {} },
    circuits = {},
    faultThreshold = 3,
    circuitSeconds = 1.00,
}
TE.PerformanceDiagnostics = Diagnostics

local function nowSeconds()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function nowMilliseconds()
    if type(debugprofilestop) == "function" then
        local ok, value = pcall(debugprofilestop)
        if ok and type(value) == "number" then return value end
    end
    return nowSeconds() * 1000
end

local function copyMap(source)
    local out = {}
    for key, value in pairs(source or {}) do out[key] = value end
    return out
end

local function ensureSettings()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.settings = type(TacticEchoDB.settings) == "table" and TacticEchoDB.settings or {}
    local setting = TacticEchoDB.settings.performanceDiagnostics
    if type(setting) ~= "boolean" then
        setting = false
        TacticEchoDB.settings.performanceDiagnostics = false
    end
    Diagnostics.enabled = setting
    return setting
end

local function rollSecond(self, current)
    local window = self.currentSecond
    if window.startedAt == 0 then window.startedAt = current; return end
    local elapsed = current - window.startedAt
    if elapsed < 1 then return end
    self.lastSecond = {
        elapsed = elapsed,
        counters = copyMap(window.counters),
        milliseconds = copyMap(window.milliseconds),
    }
    window.startedAt = current
    window.counters = {}
    window.milliseconds = {}
end

function Diagnostics:IsEnabled()
    if type(TacticEchoDB) == "table" and type(TacticEchoDB.settings) == "table"
        and type(TacticEchoDB.settings.performanceDiagnostics) == "boolean" then
        self.enabled = TacticEchoDB.settings.performanceDiagnostics
    end
    return self.enabled == true
end

function Diagnostics:SetEnabled(enabled)
    ensureSettings()
    enabled = enabled == true
    TacticEchoDB.settings.performanceDiagnostics = enabled
    self.enabled = enabled
    return enabled
end

function Diagnostics:Reset()
    self.counters = {}
    self.milliseconds = {}
    self.currentSecond = { startedAt = nowSeconds(), counters = {}, milliseconds = {} }
    self.lastSecond = { elapsed = 0, counters = {}, milliseconds = {} }
    self.circuits = {}
end

function Diagnostics:Count(name, amount)
    if not self:IsEnabled() then return end
    name = tostring(name or "unknown")
    amount = tonumber(amount) or 1
    local current = nowSeconds()
    rollSecond(self, current)
    self.counters[name] = (self.counters[name] or 0) + amount
    local counters = self.currentSecond.counters
    counters[name] = (counters[name] or 0) + amount
end

function Diagnostics:Begin(name)
    if not self:IsEnabled() then return nil end
    return { name = tostring(name or "unknown"), startedAt = nowMilliseconds() }
end

function Diagnostics:Finish(token)
    if type(token) ~= "table" or not self:IsEnabled() then return end
    local elapsed = math.max(0, nowMilliseconds() - (tonumber(token.startedAt) or nowMilliseconds()))
    local name = token.name or "unknown"
    local current = nowSeconds()
    rollSecond(self, current)
    self.milliseconds[name] = (self.milliseconds[name] or 0) + elapsed
    local values = self.currentSecond.milliseconds
    values[name] = (values[name] or 0) + elapsed
end

local function errorSignature(value)
    local text = tostring(value or "unknown_error")
    if #text > 160 then text = text:sub(1, 160) end
    return text
end

function Diagnostics:IsCircuitOpen(key)
    key = tostring(key or "unknown")
    local entry = self.circuits[key]
    if type(entry) ~= "table" then return false end
    local current = nowSeconds()
    local openUntil = tonumber(entry.openUntil) or 0
    if openUntil <= 0 then return false end
    if current >= openUntil then
        entry.openUntil = 0
        entry.failures = 0
        return false
    end
    entry.suppressed = (entry.suppressed or 0) + 1
    self:Count("fault_suppressed")
    return true, entry.signature
end

function Diagnostics:RecordSuccess(key)
    local entry = self.circuits[tostring(key or "unknown")]
    if type(entry) == "table" then
        entry.failures = 0
        entry.signature = nil
        entry.openUntil = 0
    end
end

function Diagnostics:RecordFault(key, err)
    key = tostring(key or "unknown")
    local signature = errorSignature(err)
    local entry = self.circuits[key]
    if type(entry) ~= "table" then
        entry = { failures = 0, openUntil = 0, suppressed = 0 }
        self.circuits[key] = entry
    end
    if entry.signature == signature then
        entry.failures = (entry.failures or 0) + 1
    else
        entry.signature = signature
        entry.failures = 1
    end
    entry.lastAt = nowSeconds()
    self:Count("fault:" .. key)
    if entry.failures >= self.faultThreshold then
        entry.openUntil = entry.lastAt + self.circuitSeconds
        self:Count("circuit_opened:" .. key)
    end
    return signature
end

-- pcall is intentionally concentrated at module/API boundaries. Internal
-- normalization helpers remain direct calls and do not nest additional guards.
function Diagnostics:Guard(key, fn, ...)
    if type(fn) ~= "function" then return false, "callable_missing" end
    local open, signature = self:IsCircuitOpen(key)
    if open then return false, "circuit_open:" .. tostring(signature or key) end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then
        self:RecordSuccess(key)
        return true, a, b, c, d, e, f
    end
    self:RecordFault(key, a)
    return false, a
end

function Diagnostics:GetSnapshot()
    local current = nowSeconds()
    if self:IsEnabled() then rollSecond(self, current) end
    local circuits = {}
    for key, value in pairs(self.circuits) do
        circuits[key] = {
            failures = value.failures or 0,
            open = current < (tonumber(value.openUntil) or 0),
            openUntil = value.openUntil or 0,
            signature = value.signature,
            suppressed = value.suppressed or 0,
        }
    end
    return {
        schema = 1,
        enabled = self:IsEnabled(),
        counters = copyMap(self.counters),
        milliseconds = copyMap(self.milliseconds),
        lastSecond = {
            elapsed = self.lastSecond.elapsed or 0,
            counters = copyMap(self.lastSecond.counters),
            milliseconds = copyMap(self.lastSecond.milliseconds),
        },
        circuits = circuits,
    }
end

local function sortedPairs(source)
    local keys = {}
    for key in pairs(source or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local index = 0
    return function()
        index = index + 1
        local key = keys[index]
        if key then return key, source[key] end
    end
end

local function printSnapshot()
    local snapshot = Diagnostics:GetSnapshot()
    TE:Print("性能诊断：" .. (snapshot.enabled and "开启" or "关闭"))
    for name, value in sortedPairs(snapshot.lastSecond.counters) do
        TE:Print(string.format("最近 %.2fs  %s = %s", snapshot.lastSecond.elapsed or 0, name, tostring(value)))
    end
    for name, value in sortedPairs(snapshot.lastSecond.milliseconds) do
        TE:Print(string.format("最近 %.2fs  %s = %.3f ms", snapshot.lastSecond.elapsed or 0, name, tonumber(value) or 0))
    end
end

SLASH_TACTICECHOPERF1 = "/teperf"
SlashCmdList.TACTICECHOPERF = function(message)
    local command = tostring(message or ""):lower():match("^%s*(.-)%s*$")
    if command == "on" or command == "1" then
        Diagnostics:SetEnabled(true)
        TE:Print("性能诊断已开启；统计仅保存在本次会话内。")
    elseif command == "off" or command == "0" then
        Diagnostics:SetEnabled(false)
        TE:Print("性能诊断已关闭。")
    elseif command == "reset" then
        Diagnostics:Reset()
        TE:Print("性能诊断计数已重置。")
    else
        printSnapshot()
        TE:Print("命令：/teperf on | off | reset | show")
    end
end

ensureSettings()
