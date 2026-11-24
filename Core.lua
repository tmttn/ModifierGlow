-- Modifier Glow: while a modifier is held, lights up the action buttons that modifier gives you: buttons bound to a key
-- with exactly that modifier (SHIFT-1, CTRL-Q, CTRL-SHIFT-E), and macros whose conditions ask for it ([mod], [mod:shift]).
local addonName, ns = ...
local Glow = ns.Glow

ns.MODIFIERS = { "shift", "ctrl", "alt", "combo" }
ns.MODIFIER_NAMES = { shift = "Shift", ctrl = "Ctrl", alt = "Alt", combo = "Two or more" }

ns.WHENS = {
    { "always", "Always", "whenever you hold the modifier." },
    { "inCombat", "In combat", "only in a fight." },
    { "outOfCombat", "Out of combat", "only out of a fight." },
    { "enemyTargeted", "Enemy targeted", "with a living enemy targeted, and all through a fight." },
    { "allyTargeted", "Ally targeted", "with a living ally targeted (you count too)." },
    { "anyTargeted", "Any targeted", "with anyone living targeted, and all through a fight." },
}

local function style(color)
    return { enabled = true, color = color, glowPercent = 100, animation = "circling", when = "always" }
end

ns.DEFAULTS = {
    enabled = true,
    useBindings = true,
    useMacros = true,
    dimOthers = true,
    dimPercent = 60,
    styles = {
        shift = style({ 0.2, 0.55, 1 }),
        ctrl = style({ 1, 0.85, 0.2 }),
        alt = style({ 0.3, 1, 0.3 }),
        combo = style({ 0.8, 0.4, 1 }),
    },
}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- The buttons and their bindings

-- Blizzard's bars: the button prefix and the binding command of its buttons.
local BLIZZARD_BARS = {
    { "ActionButton", "ACTIONBUTTON", 12 },
    { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON", 12 },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", 12 },
    { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON", 12 },
    { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON", 12 },
    { "MultiBar5Button", "MULTIACTIONBAR5BUTTON", 12 },
    { "MultiBar6Button", "MULTIACTIONBAR6BUTTON", 12 },
    { "MultiBar7Button", "MULTIACTIONBAR7BUTTON", 12 },
    { "StanceButton", "SHAPESHIFTBUTTON", 10, "stance" },
    { "ShapeshiftButton", "SHAPESHIFTBUTTON", 10, "stance" },
    { "PetActionButton", "BONUSACTIONBUTTON", 10, "pet" },
}

-- Bar addons whose buttons are bound by clicking them.
local ADDON_BUTTONS = {
    { "BT4Button", 180 },
    { "DominosActionButton", 168 },
}

local buttons = {} -- list of { button, commands, kind }
local function collectButtons()
    wipe(buttons)
    local seen = {}
    local function add(button, command, kind)
        if not button or seen[button] or type(button) ~= "table" or not button.GetObjectType then return end
        seen[button] = true
        local name = button:GetName()
        local commands = {}
        if command then commands[#commands + 1] = command end
        if type(button.commandName) == "string" and button.commandName ~= command then
            commands[#commands + 1] = button.commandName
        end
        if name then
            commands[#commands + 1] = "CLICK " .. name .. ":LeftButton"
            commands[#commands + 1] = "CLICK " .. name .. ":Keybind"
            commands[#commands + 1] = "CLICK " .. name .. ":HOTKEY"
        end
        buttons[#buttons + 1] = { button = button, commands = commands, kind = kind or "action", index = nil }
    end
    for _, bar in ipairs(BLIZZARD_BARS) do
        for i = 1, bar[3] do
            local button = _G[bar[1] .. i]
            if button then
                add(button, bar[2] .. i, bar[4])
                buttons[#buttons].index = i
            end
        end
    end
    for _, run in ipairs(ADDON_BUTTONS) do
        for i = 1, run[2] do
            add(_G[run[1] .. i], nil, "action")
        end
    end
end

local MODIFIER_TOKENS = {
    SHIFT = "shift", LSHIFT = "shift", RSHIFT = "shift",
    CTRL = "ctrl", LCTRL = "ctrl", RCTRL = "ctrl",
    ALT = "alt", LALT = "alt", RALT = "alt",
    META = "meta",
}

-- The modifiers of a key binding, as a sorted word ("ctrl+shift"); "" without any.
local keyCache = {}
local function keyModifiers(key)
    local cached = keyCache[key]
    if cached then return cached end
    local found = {}
    for token in key:gmatch("([^-]+)-") do
        local modifier = MODIFIER_TOKENS[token]
        if modifier then found[modifier] = true end
    end
    local parts = {}
    for _, modifier in ipairs({ "alt", "ctrl", "meta", "shift" }) do
        if found[modifier] then parts[#parts + 1] = modifier end
    end
    cached = table.concat(parts, "+")
    keyCache[key] = cached
    return cached
end

-- bindingSets[entry] = { ["shift"] = true, ["ctrl+shift"] = true, ... }: the modifier sets the button is bound with.
local bindingSets = {}
local function getBindingSet(entry)
    local set = bindingSets[entry]
    if set then return set end
    set = {}
    for _, command in ipairs(entry.commands) do
        local keys = { GetBindingKey(command) }
        for _, key in ipairs(keys) do
            local modifiers = keyModifiers(key)
            if modifiers ~= "" then set[modifiers] = true end
        end
    end
    bindingSets[entry] = set
    return set
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Macros

local MACRO_MODIFIERS = {
    shift = "shift", lshift = "shift", rshift = "shift",
    ctrl = "ctrl", lctrl = "ctrl", rctrl = "ctrl",
    alt = "alt", lalt = "alt", ralt = "alt",
}

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A macro, read once: per command line, its clauses, each a list of condition groups (each a list of modifier tests)
-- and the action it picks. A test is { negated, set } where set is nil for a bare [mod] (any modifier).
local macroCache = {}
local function parseMacro(body)
    local cached = macroCache[body]
    if cached then return cached end
    local lines = {}
    for line in body:gmatch("[^\r\n]+") do
        local command, rest = trim(line):match("^(/%S+)%s*(.*)$")
        if command and rest:find("[", 1, true) then
            local clauses = {}
            for clauseText in (rest .. ";"):gmatch("([^;]*);") do
                local groups = {}
                local text = trim(clauseText)
                while true do
                    local inside, after = text:match("^%[(.-)%]%s*(.*)$")
                    if not inside then break end
                    local tests = {}
                    for condition in inside:gmatch("[^,]+") do
                        local word, values = trim(condition):lower():match("^(%a+)%s*:?%s*(.*)$")
                        local negated = word == "nomod" or word == "nomodifier"
                        if negated or word == "mod" or word == "modifier" then
                            local set
                            if values ~= "" then
                                set = {}
                                for value in values:gmatch("[^/]+") do
                                    local modifier = MACRO_MODIFIERS[(value:gsub("%s", ""))]
                                    if modifier then set[modifier] = true end
                                end
                            end
                            tests[#tests + 1] = { negated, set }
                        end
                    end
                    groups[#groups + 1] = tests
                    text = after
                end
                clauses[#clauses + 1] = { groups = groups, action = command .. " " .. text }
            end
            lines[#lines + 1] = clauses
        end
    end
    macroCache[body] = lines
    return lines
end

-- Is this modifier test true with these modifiers held?
local function testModifiers(test, held)
    local negated, set = test[1], test[2]
    local any = false
    for modifier, isHeld in pairs(held) do
        if isHeld and (set == nil or set[modifier]) then any = true end
    end
    if negated then return not any end
    return any
end

-- The action a line picks with these modifiers held, reading only its modifier conditions (the others count as true).
local function pickAction(clauses, held)
    for _, clause in ipairs(clauses) do
        if #clause.groups == 0 then return clause.action end
        for _, tests in ipairs(clause.groups) do
            local ok = true
            for _, test in ipairs(tests) do
                if not testModifiers(test, held) then ok = false; break end
            end
            if ok then return clause.action end
        end
    end
    return nil
end

local NOTHING_HELD = { shift = false, ctrl = false, alt = false }

local function getSlot(button)
    local slot = button.action
    if type(slot) ~= "number" and button._state_action then slot = button._state_action end
    if type(slot) ~= "number" and button.GetAttribute then
        slot = tonumber(button:GetAttribute("action"))
    end
    if type(slot) ~= "number" and button.CalculateAction then
        local ok, value = pcall(button.CalculateAction, button)
        if ok then slot = value end
    end
    if type(slot) ~= "number" and ActionButton_CalculateAction then
        local ok, value = pcall(ActionButton_CalculateAction, button)
        if ok then slot = value end
    end
    return type(slot) == "number" and slot or nil
end

-- Does the macro do something else with these modifiers held than without any?
local function macroMatches(slot, held)
    local actionType, id = GetActionInfo(slot)
    if actionType ~= "macro" or not id then return false end
    local body = GetMacroBody(id)
    if not body then return false end
    for _, clauses in ipairs(parseMacro(body)) do
        if pickAction(clauses, held) ~= pickAction(clauses, NOTHING_HELD) then return true end
    end
    return false
end

-- Can the button be pressed while these modifiers (the word, "alt+shift") are held? With no key it is clicked; a key
-- without modifiers works with them held, unless that combination is bound to something else.
local function isPressable(entry, wanted)
    local prefix = wanted:upper():gsub("%+", "-") .. "-"
    local hasKey = false
    for _, command in ipairs(entry.commands) do
        for _, key in ipairs({ GetBindingKey(command) }) do
            hasKey = true
            local modifiers = keyModifiers(key)
            if modifiers == wanted then return true end
            if modifiers == "" then
                local other = GetBindingAction(prefix .. key)
                if other == nil or other == "" then return true end
            end
        end
    end
    return not hasKey
end

-- ---------------------------------------------------------------------------------------------------------------------
-- When

local function isInCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

local function hasLivingTarget()
    return UnitExists("target") and not UnitIsDeadOrGhost("target")
end

local WHEN_TESTS = {
    always = function() return true end,
    inCombat = isInCombat,
    outOfCombat = function() return not isInCombat() end,
    enemyTargeted = function()
        return isInCombat() or (hasLivingTarget() and UnitCanAttack("player", "target"))
    end,
    allyTargeted = function()
        return hasLivingTarget() and UnitIsFriend("player", "target")
    end,
    anyTargeted = function() return isInCombat() or hasLivingTarget() end,
}

-- ---------------------------------------------------------------------------------------------------------------------
-- Refresh

local shown = {} -- button -> glow entry

local function hideButton(button)
    local entry = shown[button]
    if entry then
        Glow.Hide(entry)
        shown[button] = nil
    end
end

-- The dimming of the buttons that do not glow: a dark layer over each, so their own opacity (which bar addons and
-- Glowing Bars' bar fading set) is left alone.
local dims = {}   -- button -> dim frame
local dimmed = {} -- button -> true
local function dimButton(button, percent)
    local dim = dims[button]
    if not dim then
        dim = CreateFrame("Frame", nil, button)
        dim:SetFrameLevel(button:GetFrameLevel() + 5)
        dim:SetAllPoints(button.icon or button)
        dim.texture = dim:CreateTexture(nil, "OVERLAY")
        dim.texture:SetAllPoints(dim)
        dim.texture:SetColorTexture(0, 0, 0, 1)
        dims[button] = dim
    end
    dim:SetAlpha(percent / 100)
    dim:Show()
    dimmed[button] = true
end

local function undimAll()
    for button in pairs(dimmed) do
        dims[button]:Hide()
        dimmed[button] = nil
    end
end

local function hideAll()
    for button in pairs(shown) do hideButton(button) end
    undimAll()
end

local function hasContent(entry, slot)
    if entry.kind == "pet" then
        return entry.index ~= nil and GetPetActionInfo(entry.index) ~= nil
    end
    if entry.kind == "stance" then return true end
    return slot ~= nil and HasAction(slot)
end

local heldNow = 0
function ns.Refresh()
    local db = ns.db
    if not db then return end
    local held = { shift = IsShiftKeyDown(), ctrl = IsControlKeyDown(), alt = IsAltKeyDown() }
    local parts = {}
    for _, modifier in ipairs({ "alt", "ctrl", "shift" }) do
        if held[modifier] then parts[#parts + 1] = modifier end
    end
    heldNow = #parts
    local style = heldNow == 1 and db.styles[parts[1]] or db.styles.combo
    local test = style and WHEN_TESTS[style.when] or WHEN_TESTS.always
    if heldNow == 0 or not db.enabled or not style or not style.enabled or not test() then
        return hideAll()
    end
    local wanted = table.concat(parts, "+")
    for _, entry in ipairs(buttons) do
        local button = entry.button
        local match = false
        if button:IsVisible() then
            local slot = entry.kind == "action" and getSlot(button) or nil
            if hasContent(entry, slot) then
                if db.useBindings and getBindingSet(entry)[wanted] then
                    match = true
                elseif db.useMacros and slot and macroMatches(slot, held) and isPressable(entry, wanted) then
                    match = true
                end
            end
        end
        if match then
            local glow = Glow.Get(button, style.animation, style.color, style.glowPercent)
            if shown[button] and shown[button] ~= glow then hideButton(button) end
            Glow.Show(glow)
            shown[button] = glow
        else
            hideButton(button)
        end
    end
    if db.dimOthers and next(shown) ~= nil then
        for _, entry in ipairs(buttons) do
            local button = entry.button
            if shown[button] == nil and button:IsVisible() then
                dimButton(button, db.dimPercent)
            elseif dimmed[button] then
                dims[button]:Hide()
                dimmed[button] = nil
            end
        end
    else
        undimAll()
    end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Events

local frame = CreateFrame("Frame")
local function onEvent(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        ModifierGlowDB = ModifierGlowDB or {}
        copyDefaults(ModifierGlowDB, ns.DEFAULTS)
        ns.db = ModifierGlowDB
        if ns.OnLoaded then ns.OnLoaded() end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- Again on entering the world: a bar addon may make its buttons after login.
        collectButtons()
        wipe(bindingSets)
    elseif event == "UPDATE_BINDINGS" then
        wipe(bindingSets)
    elseif event == "UPDATE_MACROS" then
        wipe(macroCache)
    end
    ns.Refresh()
end
frame:SetScript("OnEvent", onEvent)
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "MODIFIER_STATE_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORMS",
    "PET_BAR_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
}) do
    pcall(frame.RegisterEvent, frame, event)
end

-- While a modifier is held, look again a few times a second: a target that dies, a bar that pages, and a key let go
-- while the game was not in front (alt-tab) all show up here.
local elapsedSince = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    if heldNow == 0 and next(shown) == nil then return end
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.25 then return end
    elapsedSince = 0
    ns.Refresh()
end)
