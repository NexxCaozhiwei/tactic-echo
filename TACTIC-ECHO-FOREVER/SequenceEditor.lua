local _,TEF=...
local U,S,P=TEF.UI,TEF.Safety,TEF.Profiles

function U:SequenceMessage(text)
    self:Paint(self.editorMessage,"SetText",text)
end
function U:DraftRows()
    local ok,raw=self:Invoke(self.editor,"GetText")
    local text=ok and S.Public(raw,"string")
    if text=="" then return {} end
    return text and P:Parse(text,32)
end
function U:WriteDraft(rows)
    self:Paint(self.editor,"SetText",P:RowsText(rows))
    self:RefreshSequenceEditor(true)
end
function U:AddSequenceSpell(rawID,index)
    local id=S.ID(rawID)
    if not id or id==7268 then self:SequenceMessage("未新增：精确技能ID无效或为引导子事件。"); return false end
    local rows=self:DraftRows()
    if not rows then self:SequenceMessage("请先修正高级文本中的无效配置。"); return false end
    if #rows>=16 then self:SequenceMessage("未新增：每套最多16个技能步骤。"); return false end
    local view=S.Spell(id,"技能 " .. id)
    local row={spellID=id,name=view.reason=="PUBLIC" and view.name or ("技能 " .. id),matchIDs={id},repeatCount=1}
    table.insert(rows,index and math.min(index,#rows+1) or #rows+1,row)
    self:WriteDraft(rows)
    self:SequenceMessage(view.reason=="PUBLIC" and "已加入草稿；仅匹配该精确ID，点击保存生效。" or "已加入精确ID，但技能信息未解析；请核对后保存。")
    return true
end
function U:EditSequenceRow(index,operation,value)
    local rows=self:DraftRows()
    if not rows or not rows[index] then return false end
    if operation=="delete" then table.remove(rows,index)
    elseif operation=="move" then
        local dest=index+value
        if dest<1 or dest>#rows then return false end
        rows[index],rows[dest]=rows[dest],rows[index]
    elseif operation=="count" then
        local text=S.Public(value,"string")
        local n=text and text:match("^%s*(%d+)%s*$") and tonumber(text)
        if not n or n<1 or n>99 then self:SequenceMessage("释放次数须为1–99的整数；草稿未改变。"); return false end
        if rows[index].repeatCount==n then return true end
        rows[index].repeatCount=n
    else return false end
    self:WriteDraft(rows); self:SequenceMessage("草稿已调整，点击保存生效。")
    return true
end
function U:ReceiveSequenceSpell(index)
    local fn=S.Resolve("GetCursorInfo")
    if not fn then self:SequenceMessage("拖入不可用：GetCursorInfo缺失。"); return false end
    -- Blizzard spell cursor carries the exact spell ID in its fourth result.
    -- Do not inspect/guess the second spellbook slot or other cursor payloads.
    local ok,rawKind,_,__,rawID=pcall(fn)
    local kind,kindReason=S.Public(rawKind,"string")
    local id,idReason=S.ID(rawID)
    if not ok or kind~="spell" or not id then
        self.engine:Log("display",not ok and "CURSOR_CALL_FAILED" or (kind~="spell" and "CURSOR_KIND_UNVERIFIED" or "CURSOR_ID_UNVERIFIED"))
        self:SequenceMessage("拖入未接纳：仅支持公开的技能游标及精确ID；可改用手输ID。")
        return false
    end
    if not self:AddSequenceSpell(id,index) then return false end
    local cleared=S.Call("ClearCursor")
    if not cleared then self.engine:Log("display","CURSOR_CLEAR_FAILED") end
    return true
end
function U:SequenceInput(parent,x,y,width)
    local box=self:Frame("EditBox",parent,"InputBoxTemplate")
    self:Paint(box,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(box,"SetSize",width,26)
    self:Paint(box,"SetAutoFocus",false); self:Paint(box,"SetMaxLetters",12)
    self:Paint(box,"SetScript","OnEscapePressed",function() self:Paint(box,"ClearFocus") end)
    return box
end
function U:RefreshSequenceEditor(force)
    if not self.sequenceRows then return end
    local ok,raw=self:Invoke(self.editor,"GetText")
    local text=ok and S.Public(raw,"string")
    if not force and text==self.sequenceRendered then return end
    self.sequenceRendered=text
    local rows=self:DraftRows()
    if rows and #rows>16 then self.sequenceAdvanced=true; self:SequenceMessage("旧配置超过16步，已保留。请在高级文本中缩减后保存。") end
    self:Paint(self.editorScroll,self.sequenceAdvanced and "Show" or "Hide")
    self:Paint(self.sequenceScroll,self.sequenceAdvanced and "Hide" or "Show")
    self:Paint(self.sequenceCount,"SetText",rows and (#rows .. "/16步 · 次数按独立成功事件计数") or "文本无效，请在高级文本中修正")
    for i,widgets in ipairs(self.sequenceRows) do
        local row=rows and rows[i]
        self:Paint(widgets.frame,row and "Show" or "Hide")
        if row then
            local view=row.unverified and S.Spell(row.name,row.name) or S.Spell(row.spellID,row.name)
            self:Paint(widgets.icon,"SetTexture",view.icon)
            self:Paint(widgets.name,"SetText",i .. ". " .. view.name .. "\nID " .. row.spellID .. " · 匹配 " .. table.concat(row.matchIDs,"/"))
            self:Paint(widgets.count,"SetText",tostring(row.repeatCount or 1))
            self:SetControlEnabled(widgets.up,i>1); self:SetControlEnabled(widgets.down,i<#rows)
        end
    end
    self:Paint(self.sequenceChild,"SetHeight",math.max(235,rows and math.min(#rows,16)*48 or 235))
end
function U:CreateSequenceEditor(parent)
    self.sequenceAdvanced=false
    self.dropZone=self:CreateActionButton(parent,"拖入技能（追加）",4,-80,195,function() self:ReceiveSequenceSpell() end)
    self:Paint(self.dropZone,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveSequenceSpell() end) end)
    self.spellIDInput=self:SequenceInput(parent,216,-80,90)
    self:Paint(self.spellIDInput,"SetText","")
    self:CreateActionButton(parent,"ID新增",317,-80,94,function()
        local ok,raw=self:Invoke(self.spellIDInput,"GetText")
        local text=ok and S.Public(raw,"string")
        local id=text and text:match("^%s*(%d+)%s*$") and tonumber(text)
        if self:AddSequenceSpell(id) then self:Paint(self.spellIDInput,"SetText",""); self:Paint(self.spellIDInput,"ClearFocus") end
    end)
    self:CreateActionButton(parent,"射击5019",421,-80,132,function() self:AddSequenceSpell(5019) end)
    self.sequenceCount=self:Text(parent,4,-115,560,"GameFontHighlightSmall")
    local scroll=self:Frame("ScrollFrame",parent,"UIPanelScrollFrameTemplate")
    self.sequenceScroll=scroll
    self:Paint(scroll,"SetPoint","TOPLEFT",parent,"TOPLEFT",4,-138); self:Paint(scroll,"SetSize",550,226)
    local child=self:Frame("Frame",scroll); self.sequenceChild=child
    self:Paint(child,"SetSize",540,235); self:Paint(scroll,"SetScrollChild",child)
    self.sequenceRows={}
    for i=1,16 do
        local index=i
        local row=self:Frame("Frame",child,"BackdropTemplate")
        self:Paint(row,"SetPoint","TOPLEFT",child,"TOPLEFT",0,-(i-1)*48); self:Paint(row,"SetSize",540,44)
        self:Paint(row,"EnableMouse",true)
        self:Paint(row,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveSequenceSpell(index) end) end)
        local made,icon=self:Invoke(row,"CreateTexture",nil,"ARTWORK")
        if made then self:Paint(icon,"SetSize",32,32); self:Paint(icon,"SetPoint","TOPLEFT",row,"TOPLEFT",2,-5) end
        local widgets={frame=row,icon=icon,name=self:Text(row,41,-3,230,"GameFontHighlightSmall"),count=self:SequenceInput(row,300,-8,37)}
        self:Paint(self:Text(row,275,-14,25,"GameFontHighlightSmall"),"SetText","次")
        self:Paint(widgets.count,"SetScript","OnEnterPressed",function(box)
            self:Guard(function() local ok,raw=self:Invoke(box,"GetText"); if ok then self:EditSequenceRow(index,"count",raw) end end)
            self:Paint(box,"ClearFocus")
        end)
        self:Paint(widgets.count,"SetScript","OnEditFocusLost",function(box)
            self:Guard(function() local ok,raw=self:Invoke(box,"GetText"); if ok then self:EditSequenceRow(index,"count",raw) end end)
        end)
        widgets.up=self:CreateActionButton(row,"上",350,-8,42,function() self:EditSequenceRow(index,"move",-1) end)
        widgets.down=self:CreateActionButton(row,"下",398,-8,42,function() self:EditSequenceRow(index,"move",1) end)
        self:CreateActionButton(row,"删除",447,-8,70,function() self:EditSequenceRow(index,"delete") end)
        self.sequenceRows[i]=widgets
    end
    self:CreateActionButton(parent,"高级文本",371,-377,110,function()
        self.sequenceAdvanced=not self.sequenceAdvanced; self:RefreshSequenceEditor(true)
        self:SequenceMessage("每行 主ID:匹配ID/匹配ID*次数；例如205:205*3。保存才生效。")
    end)
end
