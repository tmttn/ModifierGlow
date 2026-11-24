-- Modifier Glow: the options, in the game's Settings window (Options > AddOns > Modifier Glow) and with /modglow.
-- Each modifier has its own look, as each reminder type has in Glowing Bars: on/off, color, glow %, animation and when.
local _, ns = ...
local Glow = ns.Glow

local canvas = CreateFrame("Frame")
canvas.name = "Modifier Glow"
canvas:Hide()

local syncers = {}
local function Sync()
    if not ns.db then return end
    for _, sync in ipairs(syncers) do sync() end
end

local function Changed()
    ns.Refresh()
end

local function ShowTooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
    GameTooltip:Show()
end

local function AddTooltip(widget, title, text)
    widget:HookScript("OnEnter", function(self) ShowTooltip(self, title, type(text) == "function" and text() or text) end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeCheckbox(parent, label, get, set, tip)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    if label then
        local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", box, "RIGHT", 2, 1)
        text:SetText(label)
    end
    box:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Changed()
    end)
    syncers[#syncers + 1] = function() box:SetChecked(get()) end
    if tip then AddTooltip(box, label or tip, label and tip or nil) end
    return box
end

-- A button that steps through `choices` ({ value, words } pairs): left click forward, right click back.
local function MakeCycle(parent, width, choices, get, set, title, tip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function indexOf(value)
        for i, choice in ipairs(choices) do
            if choice[1] == value then return i end
        end
        return 1
    end
    local function update()
        button:SetText(choices[indexOf(get())][2])
    end
    button:SetScript("OnClick", function(_, mouse)
        local i = indexOf(get())
        i = mouse == "RightButton" and (i - 2) % #choices + 1 or i % #choices + 1
        set(choices[i][1])
        update()
        Changed()
    end)
    syncers[#syncers + 1] = update
    AddTooltip(button, title, tip)
    return button
end

local function MakeSwatch(parent, get, set)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(22, 22)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.8, 0.8, 0.8, 1)
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local function update()
        local c = get()
        fill:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local function apply(r, g, b)
        set({ r, g, b })
        update()
        Changed()
    end
    swatch:SetScript("OnClick", function()
        local c = get()
        local pr, pg, pb = c[1], c[2], c[3]
        local function onChange() apply(ColorPickerFrame:GetColorRGB()) end
        local function onCancel() apply(pr, pg, pb) end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = pr, g = pg, b = pb,
                hasOpacity = false,
                swatchFunc = onChange,
                cancelFunc = onCancel,
            })
        else
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = onChange
            ColorPickerFrame.cancelFunc = onCancel
            ColorPickerFrame:SetColorRGB(pr, pg, pb)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    syncers[#syncers + 1] = update
    AddTooltip(swatch, "Color", "The color of the glow. The (original) styles keep the game's own gold, whatever color you pick.")
    return swatch
end

local function MakePercent(parent, get, set, title, tip)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(36, 20)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetJustifyH("CENTER")
    local function update() box:SetText(tostring(get())) end
    local function commit()
        local value = tonumber(box:GetText())
        if value then
            set(math.max(1, math.min(100, math.floor(value + 0.5))))
            Changed()
        end
        update()
    end
    box:SetScript("OnEnterPressed", function(self) commit(); self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) update(); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", commit)
    syncers[#syncers + 1] = update
    AddTooltip(box, title or "Glow %", tip or "How strong the glow is, 1 to 100. Type a number.")
    return box
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Layout

local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Modifier Glow")

local intro = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
intro:SetWidth(600)
intro:SetJustifyH("LEFT")
intro:SetText("While you hold Shift, Ctrl or Alt, the action buttons you can use with that modifier light up: buttons bound "
    .. "to a key with exactly those modifiers (SHIFT-1, CTRL-Q, CTRL-SHIFT-E), and macros with [mod] conditions. "
    .. "Holding two or more modifiers together uses the \"Two or more\" look.")

local enabledBox = MakeCheckbox(canvas, "Enabled",
    function() return ns.db.enabled end, function(v) ns.db.enabled = v end)
enabledBox:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -2, -12)

local bindingsBox = MakeCheckbox(canvas, "Key bindings",
    function() return ns.db.useBindings end, function(v) ns.db.useBindings = v end,
    "Light up buttons bound to a key with the modifiers you hold, such as SHIFT-1.")
bindingsBox:SetPoint("LEFT", enabledBox, "RIGHT", 100, 0)

local macrosBox = MakeCheckbox(canvas, "Macros",
    function() return ns.db.useMacros end, function(v) ns.db.useMacros = v end,
    "Light up macros with a [mod], [mod:shift], [mod:ctrl/alt] ... condition the modifiers you hold make true.")
macrosBox:SetPoint("LEFT", bindingsBox, "RIGHT", 110, 0)

local dimBox = MakeCheckbox(canvas, "Dim the other buttons",
    function() return ns.db.dimOthers end, function(v) ns.db.dimOthers = v end,
    "While buttons glow, darken the action buttons that do not.")
dimBox:SetPoint("TOPLEFT", enabledBox, "BOTTOMLEFT", 0, -6)

local dimPercent = MakePercent(canvas, function() return ns.db.dimPercent end,
    function(v) ns.db.dimPercent = v end, "Dim %",
    "How dark the other buttons get, 1 to 100. Type a number.")
dimPercent:SetPoint("LEFT", dimBox, "RIGHT", 160, 0)

local dimLabel = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
dimLabel:SetPoint("LEFT", dimPercent, "RIGHT", 6, 0)
dimLabel:SetText("% darker")

local COLUMNS = { modifier = 0, on = 100, color = 140, percent = 182, animation = 232, when = 412 }

local header = CreateFrame("Frame", nil, canvas)
header:SetSize(600, 20)
header:SetPoint("TOPLEFT", dimBox, "BOTTOMLEFT", 2, -16)
for key, words in pairs({ modifier = "Modifier", on = "On", color = "Color", percent = "Glow %",
    animation = "Animation", when = "When" }) do
    local text = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", header, "LEFT", COLUMNS[key], 0)
    text:SetText(words)
end

local animationHelp = "How the glow moves:\n"
    .. "Circling: a light runs around the button.\nBreathing: the glow swells and fades.\nNone: the glow stands still.\n\n"
    .. "(ants): the marching line of the game's spell alert.\n(clean): a smooth line.\n"
    .. "(classic): the older spell alert of the game.\n(original): the game's own colors, whatever color you pick.\n\n"
    .. "Left click: next. Right click: back."

local whenHelp = function()
    local lines = { "When the glow may show:" }
    for _, when in ipairs(ns.WHENS) do
        lines[#lines + 1] = when[2] .. ": " .. when[3]
    end
    lines[#lines + 1] = "\nLeft click: next. Right click: back."
    return table.concat(lines, "\n")
end

local whenChoices = {}
for _, when in ipairs(ns.WHENS) do whenChoices[#whenChoices + 1] = { when[1], when[2] } end

local anchor = header
for _, modifier in ipairs(ns.MODIFIERS) do
    local function styleOf() return ns.db.styles[modifier] end
    local row = CreateFrame("Frame", nil, canvas)
    row:SetSize(600, 28)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    anchor = row

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", COLUMNS.modifier, 0)
    label:SetText(ns.MODIFIER_NAMES[modifier])

    local on = MakeCheckbox(row, nil, function() return styleOf().enabled end,
        function(v) styleOf().enabled = v end, "Glow while you hold " .. ns.MODIFIER_NAMES[modifier] .. ".")
    on:SetPoint("LEFT", row, "LEFT", COLUMNS.on - 4, 0)

    local swatch = MakeSwatch(row, function() return styleOf().color end, function(c) styleOf().color = c end)
    swatch:SetPoint("LEFT", row, "LEFT", COLUMNS.color, 0)

    local percent = MakePercent(row, function() return styleOf().glowPercent end,
        function(v) styleOf().glowPercent = v end)
    percent:SetPoint("LEFT", row, "LEFT", COLUMNS.percent + 4, 0)

    local animation = MakeCycle(row, 170, Glow.ANIMATIONS, function() return styleOf().animation end,
        function(v) styleOf().animation = v end, "Animation", animationHelp)
    animation:SetPoint("LEFT", row, "LEFT", COLUMNS.animation, 0)

    local when = MakeCycle(row, 130, whenChoices, function() return styleOf().when end,
        function(v) styleOf().when = v end, "When", whenHelp)
    when:SetPoint("LEFT", row, "LEFT", COLUMNS.when, 0)
end

local reset = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
reset:SetSize(140, 22)
reset:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
reset:SetText("Reset to defaults")
reset:SetScript("OnClick", function()
    for key in pairs(ns.db) do ns.db[key] = nil end
    for key, value in pairs(CopyTable(ns.DEFAULTS)) do ns.db[key] = value end
    Sync()
    Changed()
end)

local tip = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
tip:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
tip:SetWidth(600)
tip:SetJustifyH("LEFT")
tip:SetText("Changes apply at once: hold a modifier to see them. /modglow opens this page; /modglow toggle turns the addon on or off.")

canvas:SetScript("OnShow", Sync)
canvas.OnRefresh = Sync

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(canvas, canvas.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(canvas)
end

local function OpenOptions()
    if Settings and Settings.OpenToCategory and category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(canvas)
        InterfaceOptionsFrame_OpenToCategory(canvas)
    end
end

ns.OnLoaded = Sync

SLASH_MODIFIERGLOW1 = "/modglow"
SlashCmdList.MODIFIERGLOW = function(message)
    message = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message == "toggle" then
        ns.db.enabled = not ns.db.enabled
        print("|cff66bbffModifier Glow|r " .. (ns.db.enabled and "on." or "off."))
        Sync()
        Changed()
    else
        OpenOptions()
    end
end
