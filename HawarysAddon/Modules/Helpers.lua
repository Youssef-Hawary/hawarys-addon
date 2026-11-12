-- Hawary's Addon: Trainer Planner (What's Training style) and Macro Helper (macro generator).
--   Trainer: remembers what your class trainer offers (read while YOU have the trainer open):
--            what you can learn now, what unlocks at the next levels and the gold you need.
--            It never buys anything.
--   Macros:  builds normal Blizzard macros from safe templates (mouseover, focus, self-cast,
--            /castsequence, ...). One key press = one action, exactly Blizzard's own macro rules.
--            Nothing is automated; creating the macro is your click, out of combat.
local _, ns = ...
local L, U, T, W = ns.L, ns.Util, ns.Theme, ns.W

---------------------------------------------------------------------------
-- Trainer Planner
---------------------------------------------------------------------------
local Trainer = ns:NewModule("training", {
    title = L.MOD_TRAINING,
    desc = L.MOD_TRAINING_DESC,
    order = 11,
    defaults = {},
    charDefaults = { services = {}, updated = 0 },
})

function Trainer:Scan()
    if not GetNumTrainerServices then return end
    if C_Trainer.GetTrainerType and Enum.TrainerType and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet then return end
    local list = {}
    for i = 1, GetNumTrainerServices() do
        local name, status, _, reqLevel, rank = GetTrainerServiceInfo(i)
        local cost, isProfession = GetTrainerServiceCost(i)
        if name and not isProfession then
            list[#list + 1] = { name = name, rank = rank or "", status = status, level = reqLevel or 0, cost = cost or 0 }
        end
    end
    if #list > 0 then
        self:CharDB().services = list
        self:CharDB().updated = time()
        ns:Fire("TRAINER_UPDATED")
    end
end

-- Returns now (list), byLevel ({level = {services}}), costNow, levels (sorted)
function Trainer:Plan()
    local level = UnitLevel("player")
    local now, byLevel, costNow, levels = {}, {}, 0, {}
    for _, s in ipairs(self:Get("services")) do
        if s.status == "available" then
            now[#now + 1] = s
            costNow = costNow + s.cost
        elseif s.status == "unavailable" and s.level > level then
            if not byLevel[s.level] then byLevel[s.level] = {}; levels[#levels + 1] = s.level end
            table.insert(byLevel[s.level], s)
        end
    end
    table.sort(levels)
    return now, byLevel, costNow, levels
end

function Trainer:BuildPage(content, width, y)
    local top = y
    local holder = CreateFrame("Frame", nil, content)
    holder:SetPoint("TOPLEFT", 0, y)
    holder:SetWidth(width)
    holder.lines = {}
    local function Line(i, text, font, color, x, yy)
        local fs = holder.lines[i]
        if not fs then fs = W.Label(holder, "", font, color); holder.lines[i] = fs end
        fs:SetFontObject(T.font(font))
        T.TextColor(fs, color)
        fs:SetText(text)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", x, yy)
        fs:SetWidth(width - x)
        fs:SetWordWrap(true)
        fs:Show()
        return fs
    end
    function holder:Refresh()
        for _, l in ipairs(self.lines) do l:Hide() end
        local now, byLevel, costNow, levels = Trainer:Plan()
        local hy, n = 0, 0
        local function add(text, font, color, x)
            n = n + 1
            local fs = Line(n, text, font, color, x or 0, hy)
            hy = hy - fs:GetStringHeight() - (font == "h2" and 10 or 5)
        end
        if #Trainer:Get("services") == 0 then
            add(L.TRAINING_EMPTY, "small", "text3")
        else
            add(L.TRAINING_NOW:format(#now, U.money(costNow)), "h2", "accent")
            for _, s in ipairs(now) do add(("%s %s  ·  %s"):format(s.name, s.rank ~= "" and ("(" .. s.rank .. ")") or "", U.money(s.cost)), "body", "text", 10) end
            hy = hy - 8
            local running = GetMoney() - costNow
            for i = 1, math.min(#levels, 6) do
                local lvl = levels[i]
                local total = 0
                for _, s in ipairs(byLevel[lvl]) do total = total + s.cost end
                running = running - total
                local enough = running >= 0 and "|cff4ade80" or "|cfff87171"
                add(L.TRAINING_LEVEL:format(lvl, U.money(total), enough .. L.TRAINING_AFFORD .. "|r"), "h2", "text")
                for _, s in ipairs(byLevel[lvl]) do add(("%s %s"):format(s.name, s.rank ~= "" and ("(" .. s.rank .. ")") or ""), "small", "text2", 10) end
                hy = hy - 6
            end
            add(L.TRAINING_UPDATED:format(date("%b %d %H:%M", Trainer:Get("updated"))), "small", "text3")
        end
        self:SetHeight(-hy)
        content:SetHeight(-top - hy + 20)
        return hy
    end
    ns:On("TRAINER_UPDATED", function() if content:IsVisible() then holder:Refresh() end end)
    content:HookScript("OnShow", function() holder:Refresh() end)
    return top + holder:Refresh()
end

function Trainer:OnEnable()
    self:RegisterEvent("TRAINER_SHOW", function() C_Timer.After(0.5, function() ns.Safe(Trainer.Scan, Trainer) end) end)
    self:RegisterEvent("TRAINER_UPDATE", function() C_Timer.After(0.3, function() ns.Safe(Trainer.Scan, Trainer) end) end)
end

ns:RegisterStat("train", L.TRAINING_STAT, function()
    if not Trainer.enabled then return "–" end
    local now = Trainer:Plan()
    return #now
end, 50)

---------------------------------------------------------------------------
-- Macro Helper / generator
---------------------------------------------------------------------------
local Macros = ns:NewModule("macros", {
    title = L.MOD_MACROS,
    desc = L.MOD_MACROS_DESC,
    order = 12,
    defaults = {},
})

-- Templates: {spell} and {spell2} are filled in. Only Blizzard's own macro features.
Macros.templates = {
    { id = "mouseover_help", text = "#showtooltip {spell}\n/cast [@mouseover,help,nodead][help,nodead][@player] {spell}" },
    { id = "mouseover_harm", text = "#showtooltip {spell}\n/cast [@mouseover,harm,nodead][harm,nodead] {spell}" },
    { id = "focus", text = "#showtooltip {spell}\n/cast [@focus,exists,nodead][] {spell}" },
    { id = "self", text = "#showtooltip {spell}\n/cast [@player] {spell}" },
    { id = "stopcast", text = "#showtooltip {spell}\n/stopcasting\n/cast {spell}" },
    { id = "attack", text = "#showtooltip {spell}\n/startattack\n/cast {spell}" },
    { id = "modifier", text = "#showtooltip\n/cast [mod:shift] {spell2}; {spell}" },
    { id = "sequence", text = "#showtooltip\n/castsequence reset=target {spell}, {spell2}" },
    { id = "pet", text = "#showtooltip {spell}\n/petattack\n/cast {spell}" },
    { id = "trinket", text = "#showtooltip {spell}\n/use 13\n/cast {spell}" },
}

function Macros.Build(templateText, spell, spell2)
    local body = templateText:gsub("{spell2}", (spell2 and spell2 ~= "") and spell2 or spell):gsub("{spell}", spell)
    return body, #body
end

function Macros:Spells()
    local out = {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if line then
            for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local name = C_SpellBook.GetSpellBookItemName(j, bank)
                if name and not C_SpellBook.IsSpellBookItemPassive(j, bank) then out[#out + 1] = name end
            end
        end
    end
    table.sort(out)
    return out
end

function Macros:Create(name, body)
    if ns.InCombat() then ns:Print(L.NOT_IN_COMBAT); return end
    name = U.trim(name or "")
    if name == "" or #name > 16 then ns:Print(L.MACROS_BAD_NAME); return end
    if #body > 255 then ns:Print(L.MACROS_TOO_LONG); return end
    local _, numChar = GetNumMacros()
    local max = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS or 30
    if numChar >= max then ns:Print(L.MACROS_FULL); return end
    CreateMacro(name, "INV_Misc_QuestionMark", body, true)
    ns:Toast(L.MOD_MACROS, L.MACROS_CREATED:format(name), "Interface\\Icons\\INV_Misc_Note_01")
end

function Macros:BuildPage(content, width, y)
    local state = { template = Macros.templates[1].id, spell = "", spell2 = "" }
    local function tmpl()
        for _, t in ipairs(Macros.templates) do if t.id == state.template then return t end end
        return Macros.templates[1]
    end
    local card = W.Card(content)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetSize(width, 330)
    local yy = -16
    local function label(text)
        local fs = W.Label(card, text, "small", "text2")
        fs:SetPoint("TOPLEFT", 16, yy)
        yy = yy - 18
        return fs
    end
    label(L.MACROS_TEMPLATE)
    local tdd = W.Dropdown(card, 300, function()
        local out = {}
        for _, t in ipairs(Macros.templates) do out[#out + 1] = { value = t.id, text = L["MACRO_T_" .. t.id:upper()] } end
        return out
    end, function() return state.template end, function(v) state.template = v; card.Update() end)
    tdd:SetPoint("TOPLEFT", 16, yy)
    yy = yy - 36
    label(L.MACROS_SPELL)
    local spell = W.EditBox(card, 220, 26)
    spell:SetPoint("TOPLEFT", 16, yy)
    local pick = W.Dropdown(card, 200, function()
        local out = {}
        for _, s in ipairs(Macros:Spells()) do out[#out + 1] = { value = s, text = s } end
        return out
    end, function() return state.spell end, function(v) state.spell = v; spell:SetText(v); card.Update() end)
    pick:SetPoint("LEFT", spell, "RIGHT", 10, 0)
    yy = yy - 34
    label(L.MACROS_SPELL2)
    local spell2 = W.EditBox(card, 220, 26)
    spell2:SetPoint("TOPLEFT", 16, yy)
    local name = W.EditBox(card, 160, 26)
    name:SetPoint("LEFT", spell2, "RIGHT", 10, 0)
    local nameLabel = W.Label(card, L.MACROS_NAME, "small", "text2")
    nameLabel:SetPoint("BOTTOMLEFT", name, "TOPLEFT", 2, 3)
    yy = yy - 40
    label(L.MACROS_PREVIEW)
    local preview = W.EditBox(card, width - 32, 90, true)
    preview:SetPoint("TOPLEFT", 16, yy)
    local countFs = W.Label(card, "", "small", "text3", "RIGHT")
    countFs:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", 0, -4)
    local create = W.Button(card, L.MACROS_CREATE, "primary", 160)
    create:SetPoint("BOTTOMLEFT", 16, 14)
    local note = W.Label(card, L.MACROS_NOTE, "small", "text3")
    note:SetPoint("LEFT", create, "RIGHT", 12, 0)
    note:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    note:SetWordWrap(true)

    function card.Update()
        state.spell = U.trim(spell:GetText())
        state.spell2 = U.trim(spell2:GetText())
        local body, n = Macros.Build(tmpl().text, state.spell ~= "" and state.spell or "Spell", state.spell2)
        preview:SetText(body)
        countFs:SetText(("%d / 255"):format(n))
        T.TextColor(countFs, n > 255 and "bad" or "text3")
        if tdd.Refresh then tdd:Refresh() end
    end
    spell.edit:SetScript("OnTextChanged", function() card.Update() end)
    spell2.edit:SetScript("OnTextChanged", function() card.Update() end)
    create:SetScript("OnClick", function() Macros:Create(name:GetText(), preview:GetText()) end)
    card.Update()
    return y - 330 - 16
end
