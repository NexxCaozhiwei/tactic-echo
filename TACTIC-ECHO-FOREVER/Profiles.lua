local _, TEF = ...
local S, P = TEF.Safety, {}
TEF.Profiles = P

-- Detached, bounded configuration. Never import another AddOn's database.
function P:Clean(raw)
    local parent = S.Public(raw, "table")
    if not parent then return nil end
    local ok, length = pcall(function() return #parent end)
    if not ok or length < 1 or length > 32 then return nil end
    local rows = {}
    for i=1,length do
        local got, rawRow = pcall(function() return parent[i] end)
        local row = got and S.Public(rawRow, "table")
        if not row then return nil end
        local rawID = S.Field(row,"spellID","number")
        local id = S.ID(rawID)
        local name = S.Field(row,"name","string")
        local ids = S.Field(row,"matchIDs","table")
        local pending = S.Field(row,"unverified","boolean") == true and rawID == 0
        if (not id and not pending) or id==7268 or not name or #name < 1 or #name > 128 or not ids then return nil end
        local measured, size = pcall(function() return #ids end)
        if not measured or size > 16 or (size<1 and not pending) or (pending and size~=0) then return nil end
        local matches = {}
        for j=1,size do
            local read, value = pcall(function() return ids[j] end)
            local match = read and S.ID(value)
            if not match or match == 7268 then return nil end
            matches[j] = match
        end
        rows[i] = {name=name,spellID=id or 0,matchIDs=matches,unverified=pending or nil}
    end
    return rows
end

function P:Initialize(e, old)
    local scene = S.Field(old,"scene","string")
    if scene ~= "multi" then scene = "single" end
    local saved = S.Field(old,"profiles","table")
    e.db.profiles = {}
    for _, key in ipairs({"single","multi"}) do
        local raw = saved and S.Field(saved,key,"table")
        e.db.profiles[key] = self:Clean(raw) or self:Clean(TEF.ProfileDefaults[key])
    end
    local multi=e.db.profiles.multi
    if multi and #multi==2 and multi[1].unverified and multi[1].name=="变形术"
        and multi[2].spellID==5143 and #multi[2].matchIDs==1 and multi[2].matchIDs[1]==5143 then
        e.db.profiles.multi=self:Clean(TEF.ProfileDefaults.multi)
        e:Log("lifecycle","POLYMORPH_DEFAULT_MIGRATED",118)
    end
    e.scene, e.db.scene = scene, scene
    -- Explicit Engine.New(config) callers retain their own config. Bootstrap
    -- selects the saved profile separately; research never changes selection.
    e.db.schema = 2
    local hud = S.Field(old,"hud","table")
    local scale = hud and S.Field(hud,"scale","number")
    local locked = hud and S.Field(hud,"locked","boolean")
    local preview = hud and S.Field(hud,"preview","boolean")
    e.db.hud = {scale=scale and scale>=0.6 and scale<=1.8 and scale or 1,
        locked=locked==true, preview=preview~=false}
    local x=hud and S.Field(hud,"x","number"); local y=hud and S.Field(hud,"y","number")
    if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then e.db.hud.x=x; e.db.hud.y=y end
end

function P:Select(e, key)
    if key ~= "single" and key ~= "multi" then return false,"SCENE_INVALID" end
    local rows = self:Clean(e.db.profiles[key])
    if not rows then return false,"CONFIG_INVALID" end
    e:Reset() -- keeps success tombstones; old initiation can never take over.
    e.steps = TEF.Engine.Validate(rows)
    e.scene, e.db.scene = key, key
    e:Log("lifecycle","SCENE_CHANGED")
    return true
end

function P:Save(e, key, rows)
    if key ~= "single" and key ~= "multi" then return false,"SCENE_INVALID" end
    local clean = self:Clean(rows)
    if not clean then return false,"CONFIG_INVALID" end
    e:Reset()
    e.db.profiles[key] = clean
    if e.scene == key then e.steps = TEF.Engine.Validate(clean) end
    e:Log("lifecycle","CONFIG_SAVED")
    return true
end

function P:Text(e, key)
    local lines = {}
    for _, row in ipairs(e.db.profiles[key] or {}) do
        local ids = {}
        for _, id in ipairs(row.matchIDs) do ids[#ids+1] = tostring(id) end
        lines[#lines+1] = row.unverified and ("?" .. row.name) or (row.spellID .. ":" .. table.concat(ids,"/"))
    end
    return table.concat(lines,"\n")
end

function P:Parse(raw)
    local text = S.Public(raw,"string")
    if not text or #text>4096 then return nil,"CONFIG_INVALID" end
    local rows = {}
    for line in text:gmatch("[^\r\n]+") do
        local unresolved=line:match("^%?(.+)$")
        if unresolved then
            rows[#rows+1]={name=unresolved,spellID=0,matchIDs={},unverified=true}
        else
        local primary, rest = line:match("^%s*(%d+)%s*:%s*([%d/%s]+)%s*$")
        if not primary then primary=line:match("^%s*(%d+)%s*$"); rest=primary end
        if not primary then return nil,"CONFIG_INVALID" end
        local id = S.ID(tonumber(primary))
        if not id then return nil,"CONFIG_INVALID" end
        local ids = {}
        -- Explicit separators only: reject malformed/trailing empty matches.
        if rest:match("%d%s+%d") then return nil,"CONFIG_INVALID" end
        rest=rest:gsub("%s","")
        if rest:sub(1,1)=="/" or rest:sub(-1)=="/" or rest:find("//",1,true) then return nil,"CONFIG_INVALID" end
        for value in rest:gmatch("%d+") do ids[#ids+1]=tonumber(value) end
        rows[#rows+1]={name="技能 " .. id,spellID=id,matchIDs=ids}
        end
    end
    local clean=self:Clean(rows)
    return clean,clean and "CONFIG_VALID" or "CONFIG_INVALID"
end

function P:ConfirmObserved(e)
    local step=e.steps and e.steps[e.index]
    if not step or not step.unverified then return false,"NO_PENDING_STEP" end
    local generation,scene,index=e.generation,e.scene,e.index
    for i=#e.db.diagnostics,1,-1 do
        local row=e.db.diagnostics[i]
        if row.session==e.session and row.generation==e.generation and row.current==e.index
            and row.event=="UNIT_SPELLCAST_SUCCEEDED" and row.reason=="OUT_OF_SEQUENCE" and row.spellID then
            local view=S.Spell(row.spellID,step.name)
            if generation~=e.generation or scene~=e.scene or index~=e.index then return false,"STALE_GENERATION" end
            if view.reason=="PUBLIC" and view.name==step.name then
                local rows=self:Clean(e.db.profiles[e.scene])
                if not rows then return false,"CONFIG_INVALID" end
                rows[e.index]={name=step.name,spellID=row.spellID,matchIDs={row.spellID}}
                return self:Save(e,e.scene,rows)
            end
        end
    end
    return false,"NO_VERIFIED_NAME_SUCCESS"
end
