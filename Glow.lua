-- Modifier Glow: the glows themselves. They are built the way Glowing Bars builds its glows (its glow_service and
-- glow-*_utils), so the 12 styles look and move the same: the spell alert ("ants"), the clean line, the classic alert
-- and the classic alert in the game's own gold, each circling, breathing or standing still.
local _, ns = ...

local Glow = {}
ns.Glow = Glow

-- Glowing Bars' look constants.
local GLOW_SCALE = 1.45
local GLOW_FALLBACK = "Interface\\Cooldown\\star4"
local LOOP_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local STILL_FADE_SECONDS = 0.25
local PULSE_ALPHA = 0.45
local PULSE_SECONDS = 0.5
local RETRY_SECONDS = 0.1

-- The clean line: 30 pictures in 6 rows of 5, one turn a second.
local LINE_ATLAS = "rotationhelper_ants_flipbook"

-- The soft square frame of the clean breathing/still styles.
local BORDER_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"
local BORDER_SCALE = 24 / 21
local BORDER_OFFSET_X, BORDER_OFFSET_Y = -1, 1
local BORDER_TRIM = 1 / 32

-- The classic alert.
local CLASSIC_TEXTURE = "Interface\\SpellActivationOverlay\\IconAlert"
local CLASSIC_COORDS = { 0.0078125, 0.5078125, 0.27734375, 0.52734375 }
local ANTS_TEXTURE = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local ANTS_SHEET, ANTS_CELL, ANTS_FRAMES, ANTS_FRAME_SECONDS = 256, 48, 22, 0.017
local CLASSIC_SCALE = 1.4
local CLASSIC_ANTS_SCALE = 0.85

-- The 12 styles, in Glowing Bars' order and words.
Glow.ANIMATIONS = {
    { "circling", "Circling (ants)" },
    { "clean", "Circling (clean)" },
    { "circlingClassic", "Circling (classic)" },
    { "circlingOriginal", "Circling (original)" },
    { "breathing", "Breathing (ants)" },
    { "breathingClean", "Breathing (clean)" },
    { "breathingClassic", "Breathing (classic)" },
    { "breathingOriginal", "Breathing (original)" },
    { "none", "None (ants)" },
    { "noneClean", "None (clean)" },
    { "noneClassic", "None (classic)" },
    { "noneOriginal", "None (original)" },
}

local function isOriginal(a)
    return a == "circlingOriginal" or a == "breathingOriginal" or a == "noneOriginal"
end
local function isCircling(a)
    return a == "circling" or a == "clean" or a == "circlingClassic" or a == "circlingOriginal"
end
local function isStill(a)
    return a == "none" or a == "noneClean" or a == "noneClassic" or a == "noneOriginal"
end
local function isClassic(a)
    return a == "circlingClassic" or a == "breathingClassic" or a == "noneClassic" or isOriginal(a)
end

-- Breathing glows all breathe in step: each new one restarts them together.
local pulses = {}
local function syncPulses()
    for pulse in pairs(pulses) do
        pulse:Stop()
        pulse:Play()
    end
end

local function createPictureFade(owner, picture, fromAlpha, toAlpha, seconds)
    if picture == nil then return nil end
    local group = owner:CreateAnimationGroup()
    local fade = group and group:CreateAnimation("Alpha")
    if group == nil or fade == nil then return nil end
    fade:SetTarget(picture)
    fade:SetFromAlpha(fromAlpha)
    fade:SetToAlpha(toAlpha)
    fade:SetDuration(seconds)
    return group
end

local function createStillFades(owner, picture)
    local fades = {
        fadeIn = createPictureFade(owner, picture, 0, 1, STILL_FADE_SECONDS),
        fadeOut = createPictureFade(owner, picture, 1, 0, STILL_FADE_SECONDS),
        breathe = createPictureFade(owner, picture, 1, PULSE_ALPHA, PULSE_SECONDS),
    }
    if fades.breathe then fades.breathe:SetLooping("BOUNCE") end
    if fades.fadeOut then
        fades.fadeOut:SetScript("OnFinished", function() owner:Hide() end)
    end
    return fades
end

-- A still glow shows at once (no fade in, unlike Glowing Bars): it follows a held key.
local function startStill(entry)
    if isStill(entry.animation) then
        return
    elseif entry.breathe then
        pulses[entry.breathe] = true
        syncPulses()
    end
end

local function stopFades(entry)
    if entry.fadeIn then entry.fadeIn:Stop() end
    if entry.fadeOut then entry.fadeOut:Stop() end
    if entry.breathe then entry.breathe:Stop() end
    if entry.breathe then pulses[entry.breathe] = nil end
end

local function newFrame(parent, button, level)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(level)
    frame:SetPoint("CENTER", button, "CENTER", 0, 0)
    return frame
end

local function createLayer(frame, file)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(file)
    texture:SetBlendMode("ADD")
    texture:SetDesaturated(true)
    return texture
end

-- A frame whose picture (`inner`) breathes or fades in and out.
local function setUpBorder(entry, inner)
    local fades = createStillFades(entry.frame, inner)
    entry.fadeIn, entry.fadeOut, entry.breathe = fades.fadeIn, fades.fadeOut, fades.breathe
    entry.frame:SetScript("OnShow", function() startStill(entry) end)
    entry.frame:SetScript("OnHide", function() stopFades(entry) end)
    return entry
end

-- The clean line, running around the button.
local function createLineGlow(button, level, animation)
    local frame = newFrame(button, button, level)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(frame)
    texture:SetAtlas(LINE_ATLAS, false, nil, true)
    texture:SetDesaturated(true)
    local group = frame:CreateAnimationGroup()
    local flipbook = group and group:CreateAnimation("FlipBook")
    if group and flipbook then
        flipbook:SetTarget(texture)
        flipbook:SetFlipBookRows(6)
        flipbook:SetFlipBookColumns(5)
        flipbook:SetFlipBookFrames(30)
        flipbook:SetFlipBookFrameWidth(0)
        flipbook:SetFlipBookFrameHeight(0)
        flipbook:SetDuration(1)
        group:SetLooping("REPEAT")
        frame:SetScript("OnShow", function() group:Play() end)
        frame:SetScript("OnHide", function() group:Stop() end)
    end
    frame:Hide()
    return { frame = frame, parts = { texture }, animation = animation, scale = GLOW_SCALE }
end

-- The soft square of the clean breathing and still styles.
local function createSoftFrame(button, level, animation)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(level)
    frame:SetPoint("CENTER", button.icon or button, "CENTER", BORDER_OFFSET_X, BORDER_OFFSET_Y)
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetAllPoints(frame)
    local texture = inner:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(inner)
    texture:SetTexture(BORDER_TEXTURE)
    texture:SetTexCoord(BORDER_TRIM, 1 - BORDER_TRIM, BORDER_TRIM, 1 - BORDER_TRIM)
    texture:SetBlendMode("ADD")
    texture:SetDesaturated(true)
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
    frame:Hide()
    return setUpBorder({ frame = frame, parts = { texture }, animation = animation, scale = BORDER_SCALE }, inner)
end

local function startAntsMarch(frame, ants)
    local columns = math.floor(ANTS_SHEET / ANTS_CELL)
    local cell = ANTS_CELL / ANTS_SHEET
    local step, carried = 0, 0
    local function draw()
        local left = step % columns * cell
        local top = math.floor(step / columns) * cell
        ants:SetTexCoord(left, left + cell, top, top + cell)
    end
    draw()
    frame:SetScript("OnUpdate", function(_, elapsed)
        carried = carried + elapsed
        if carried < ANTS_FRAME_SECONDS then return end
        local advance = math.floor(carried / ANTS_FRAME_SECONDS)
        carried = carried - advance * ANTS_FRAME_SECONDS
        step = (step + advance) % ANTS_FRAMES
        draw()
    end)
end

-- The older spell alert: a soft square, with marching ants when it circles.
local function createClassic(button, level, animation)
    local marching = isCircling(animation)
    local frame = newFrame(button, button, level)
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetAllPoints(frame)
    local border = createLayer(inner, CLASSIC_TEXTURE)
    border:SetTexCoord(unpack(CLASSIC_COORDS))
    border:SetAllPoints(inner)
    local entry = { frame = frame, parts = { border }, animation = animation, scale = CLASSIC_SCALE,
        haloScale = CLASSIC_ANTS_SCALE }
    if marching then
        local ants = createLayer(inner, ANTS_TEXTURE)
        ants:SetPoint("CENTER", inner, "CENTER", 0, 0)
        entry.parts[2] = ants
        entry.halo = ants
        startAntsMarch(frame, ants)
        frame:Hide()
        return entry
    end
    frame:Hide()
    return setUpBorder(entry, inner)
end

-- Stops the alert's loop on the picture it has reached; it may have reached none yet, then it looks again later.
local function applyLoopPicture(alert, picture, sheetWidth, after, delay)
    C_Timer.After(delay, function()
        if not alert:IsShown() then return end
        local ulX, ulY, llX, llY, urX, urY, lrX, lrY = picture:GetTexCoord()
        if urX - ulX > sheetWidth * 0.9 then
            return applyLoopPicture(alert, picture, sheetWidth, after, RETRY_SECONDS)
        end
        alert.ProcLoop:Stop()
        picture:SetTexCoord(ulX, ulY, llX, llY, urX, urY, lrX, lrY)
        picture:SetAlpha(1)
        after()
    end)
end

local function showLoopPicture(alert, after)
    local picture = alert.ProcLoopFlipbook
    if picture == nil then return end
    picture:SetAtlas(LOOP_ATLAS, false, nil, true)
    picture:SetAlpha(0)
    local sheetLeft, _, _, _, sheetRight = picture:GetTexCoord()
    picture:Show()
    alert.ProcLoop:Play()
    applyLoopPicture(alert, picture, sheetRight - sheetLeft, after, 0)
end

local function startAlert(entry)
    local alert = entry.alert
    alert.ProcLoop:Stop()
    local marching = entry.animation == "circling"
    if alert.ProcStartFlipbook then alert.ProcStartFlipbook:SetShown(marching) end
    if marching then
        -- Straight into the loop, without the alert's start burst: the glow is there the moment the key is down.
        if alert.ProcStartFlipbook then alert.ProcStartFlipbook:Hide() end
        if alert.ProcLoopFlipbook then
            alert.ProcLoopFlipbook:SetAtlas(LOOP_ATLAS)
            alert.ProcLoopFlipbook:SetAlpha(1)
            alert.ProcLoopFlipbook:Show()
        end
        alert.ProcLoop:Play()
        return
    end
    showLoopPicture(alert, function() startStill(entry) end)
end

-- The game's spell alert ("ants"); the star of the client's own art where the template is missing.
local function createAlert(button, level, animation)
    local ok, alert = pcall(CreateFrame, "Frame", nil, button, "ActionButtonSpellAlertTemplate")
    if ok and alert and alert.ProcStartAnim and alert.ProcLoop then
        alert:SetFrameStrata("MEDIUM")
        alert:SetFrameLevel(level)
        alert:SetPoint("CENTER", button, "CENTER", 0, 0)
        local entry = { frame = alert, alert = alert, animation = animation, scale = GLOW_SCALE }
        local fades = createStillFades(alert, alert.ProcLoopFlipbook)
        entry.fadeIn, entry.fadeOut, entry.breathe = fades.fadeIn, fades.fadeOut, fades.breathe
        alert:SetScript("OnShow", function() startAlert(entry) end)
        alert:SetScript("OnHide", function()
            alert.ProcStartAnim:Stop()
            alert.ProcLoop:Stop()
            stopFades(entry)
        end)
        if alert.ProcAltGlow then alert.ProcAltGlow:Hide() end
        alert:Hide()
        return entry
    end
    local frame = newFrame(button, button, level)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(frame)
    texture:SetTexture(GLOW_FALLBACK)
    texture:SetBlendMode("ADD")
    frame:Hide()
    return { frame = frame, parts = { texture }, animation = animation, scale = GLOW_SCALE }
end

local function createOverlay(button, animation)
    local level = button:GetFrameLevel() + 6
    if animation == "clean" then
        return createLineGlow(button, level, animation)
    end
    if isClassic(animation) then
        return createClassic(button, level, animation)
    end
    if animation == "breathingClean" or animation == "noneClean" then
        return createSoftFrame(button, level, animation)
    end
    return createAlert(button, level, animation)
end

local function applySize(entry, button)
    local width, height = button:GetWidth(), button:GetHeight()
    if not width or width < 8 then width = 36 end
    if not height or height < 8 then height = 36 end
    local scale = entry.scale or GLOW_SCALE
    entry.frame:SetSize(width * scale, height * scale)
    if entry.halo then
        local haloScale = entry.haloScale or 1
        entry.halo:SetSize(width * scale * haloScale, height * scale * haloScale)
    end
end

local function applyColor(entry, color, glowPercent)
    local r, g, b = color[1], color[2], color[3]
    if entry.alert then
        for _, key in ipairs({ "ProcStartFlipbook", "ProcLoopFlipbook" }) do
            local texture = entry.alert[key]
            if texture then
                texture:SetDesaturated(true)
                texture:SetVertexColor(r, g, b)
            end
        end
    else
        local own = isOriginal(entry.animation)
        local gray = not own and isClassic(entry.animation)
        if own then r, g, b = 1, 1, 1 end
        for _, part in ipairs(entry.parts) do
            if own or gray then part:SetDesaturated(gray) end
            part:SetVertexColor(r, g, b, 0.95)
        end
    end
    entry.frame:SetAlpha((glowPercent or 100) / 100)
end

-- overlays[button][animation] = entry
local overlays = {}

--- The glow of `button` in this style, made the first time, sized and colored.
function Glow.Get(button, animation, color, glowPercent)
    local byAnimation = overlays[button]
    if not byAnimation then
        byAnimation = {}
        overlays[button] = byAnimation
    end
    local entry = byAnimation[animation]
    if not entry then
        entry = createOverlay(button, animation)
        byAnimation[animation] = entry
    end
    applySize(entry, button)
    applyColor(entry, color, glowPercent)
    return entry
end

function Glow.Show(entry)
    entry.isWanted = true
    if entry.fadeOut and entry.fadeOut:IsPlaying() then
        entry.fadeOut:Stop()
    elseif not entry.frame:IsShown() then
        entry.frame:Show()
    end
end

function Glow.Hide(entry)
    entry.isWanted = false
    entry.frame:Hide()
end
