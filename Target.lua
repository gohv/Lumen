local _, L = ...
local M = L.MEDIA
local call, plain = L.call, L.plain

------------------------------------------------------------------------
-- Target orb: the avatar's mirror. Live 3D model of your target in a glass
-- orb with liquid health, reaction-colored glow, gold ring for elites,
-- red pulse when it is attacking you, flinch + shake when it gets hit,
-- death animation. Secure: left-click targets, right-click opens the menu.
------------------------------------------------------------------------
local T = {}
L.Target = T

local S = 70
local D = math.floor(S * 1.45 + .5)
T.D = D

local AN = { STAND = 0, DEAD = 6, WOUND = 9, CRIT = 10, READY_UNARMED = 25, READY1H = 26, READYSPELL = 51 }
local LIQUID = { { 0, .95, .16, .22 }, { .35, 1, .62, .18 }, { .7, .35, .92, .45 }, { 1, .25, .85, .55 } }

local function texture(parent, layer, sub, file, size, blend)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(M .. file)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    if blend then t:SetBlendMode(blend) end
    return t
end

local function numFont(fs, size)
    if not fs:SetFont(L.NUMFONT, size, "") then fs:SetFont(L.FONT, size * .9, "") end
    fs:SetShadowColor(0, 0, 0, .95)
    fs:SetShadowOffset(1, -1)
end

local function hasAnim(m, id)
    if not call(m.HasAnimation, m, AN.STAND) then return true end -- not loaded yet
    return call(m.HasAnimation, m, id) and true or false
end

local function exists() return plain(UnitExists("target")) and true or false end

-- glow/ring color: class color for players, reaction for NPCs, grey if tapped
local function reactionColor()
    if plain(UnitIsTapDenied("target")) then return .55, .55, .6 end
    if plain(UnitIsPlayer("target")) then
        local _, class = UnitClass("target")
        class = plain(class)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    local r = plain(UnitReaction("target", "player"))
    if r then
        if r <= 3 then return 1, .28, .22 elseif r == 4 then return 1, .82, .25 end
        return .3, .9, .45
    end
    return .8, .84, 1
end

local function aggro()
    return plain(UnitIsUnit("targettarget", "player")) and plain(UnitCanAttack("player", "target")) and true or false
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function L.CreateTargetOrb()
    local orb = CreateFrame("Button", "LumenTarget", UIParent, "SecureUnitButtonTemplate")
    orb:SetSize(D, D)
    orb:SetFrameStrata("LOW")
    orb:RegisterForClicks("AnyUp")
    orb:SetAttribute("unit", "target")
    orb:SetAttribute("*type1", "target")
    orb:SetAttribute("*type2", "togglemenu")
    orb:EnableMouseWheel(true)
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[orb] = true
    T.orb = orb

    orb.halo = texture(orb, "BACKGROUND", -7, "glow", D * 1.75, "ADD")
    orb.shadow = texture(orb, "BACKGROUND", -6, "shadow", D * 1.15)
    orb.shadow:SetPoint("CENTER", 0, -D * .05)

    local c = CreateFrame("Frame", nil, orb)
    c:SetAllPoints(orb)
    local lvl = orb:GetFrameLevel()
    c:SetFrameLevel(lvl + 1)

    orb.disk = texture(c, "BACKGROUND", 0, "circle", S + 2)
    orb.disk:SetVertexColor(.03, .04, .07, 1)

    local liq = CreateFrame("StatusBar", nil, c)
    liq:SetSize(S, S)
    liq:SetPoint("CENTER")
    liq:SetFrameLevel(lvl + 2)
    liq:SetOrientation("VERTICAL")
    liq:SetStatusBarTexture(M .. "liquid")
    liq:SetMinMaxValues(0, 1)
    liq:SetValue(1)
    local mask = liq:CreateMaskTexture()
    mask:SetTexture(M .. "circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(S, S)
    mask:SetPoint("CENTER")
    liq:GetStatusBarTexture():AddMaskTexture(mask)
    orb.liquid = liq
    orb.wave = liq:CreateTexture(nil, "OVERLAY")
    orb.wave:SetTexture(M .. "wave")
    orb.wave:SetBlendMode("ADD")
    orb.wave:SetSize(S * 2, 10)
    orb.wave:SetPoint("LEFT", liq:GetStatusBarTexture(), "TOPLEFT", 0, 0)
    orb.wave:AddMaskTexture(mask)
    local wg = orb.wave:CreateAnimationGroup()
    wg:SetLooping("REPEAT")
    local wm = wg:CreateAnimation("Translation")
    wm:SetOffset(-S, 0)
    wm:SetDuration(3.6)
    wg:Play()

    local model = CreateFrame("PlayerModel", nil, c)
    model:SetSize(S, S)
    model:SetPoint("CENTER")
    model:SetFrameLevel(lvl + 3)
    orb.model = model

    local fx = CreateFrame("Frame", nil, c)
    fx:SetAllPoints(c)
    fx:SetFrameLevel(lvl + 4)
    orb.hurt = texture(fx, "OVERLAY", 0, "glow", S * 1.15, "ADD")
    orb.hurt:SetVertexColor(1, .1, .1)
    orb.hurt:SetAlpha(0)
    orb.hurtAnim = L.Anim(orb.hurt, { dur = .4, alphaFrom = .9, alphaTo = 0 })

    local top = CreateFrame("Frame", nil, c)
    top:SetAllPoints(c)
    top:SetFrameLevel(lvl + 5)
    orb.band = texture(top, "ARTWORK", 0, "band", D)
    orb.band:SetVertexColor(.11, .12, .17)
    orb.inner = texture(top, "ARTWORK", 1, "ring_thin", S + 3)
    orb.inner:SetAlpha(.9)
    orb.outer = texture(top, "ARTWORK", 2, "ring", D)
    orb.gloss = texture(top, "ARTWORK", 3, "shine", D * .9, "ADD")
    orb.gloss:SetAlpha(.25)

    -- elite / rare: a metal ring with a slow comet circling it
    orb.elite = texture(top, "OVERLAY", 0, "ring_bold", D + 6)
    orb.eliteComet = texture(top, "OVERLAY", 1, "comet", D * 1.22, "ADD")
    local eg = orb.eliteComet:CreateAnimationGroup()
    eg:SetLooping("REPEAT")
    local er = eg:CreateAnimation("Rotation")
    er:SetDegrees(-360)
    er:SetDuration(6)
    er:SetOrigin("CENTER", 0, 0)
    orb.eliteSpin = eg

    -- name + level above (room left for the aura bubbles in between)
    orb.nameText = top:CreateFontString(nil, "OVERLAY")
    numFont(orb.nameText, 16)
    orb.nameText:SetPoint("BOTTOM", orb, "TOP", 0, 34)
    orb.levelText = top:CreateFontString(nil, "OVERLAY")
    numFont(orb.levelText, 14)
    orb.levelText:SetPoint("RIGHT", orb.nameText, "LEFT", -5, 0)

    -- power bar + numbers + target-of-target under the orb
    local pw = D * .78
    local pbg = orb:CreateTexture(nil, "BACKGROUND", nil, -5)
    pbg:SetTexture(L.WHITE)
    pbg:SetVertexColor(.03, .04, .07, .85)
    pbg:SetSize(pw + 2, 7)
    pbg:SetPoint("TOP", orb, "BOTTOM", 0, -5)
    local pb = CreateFrame("StatusBar", nil, c)
    pb:SetSize(pw, 5)
    pb:SetPoint("CENTER", pbg, "CENTER")
    pb:SetFrameLevel(lvl + 1)
    pb:SetStatusBarTexture(L.WHITE)
    pb:SetMinMaxValues(0, 1)
    orb.power, orb.powerBg = pb, pbg

    local function line(big, small)
        local ln = {}
        ln.anchor = top:CreateFontString(nil, "OVERLAY"); numFont(ln.anchor, small); ln.anchor:SetText("/")
        ln.cur = top:CreateFontString(nil, "OVERLAY"); numFont(ln.cur, big)
        ln.cur:SetPoint("BOTTOMRIGHT", ln.anchor, "BOTTOMLEFT", -3, -1)
        ln.max = top:CreateFontString(nil, "OVERLAY"); numFont(ln.max, small)
        ln.max:SetPoint("BOTTOMLEFT", ln.anchor, "BOTTOMRIGHT", 3, 0)
        return ln
    end
    orb.hpLine = line(16, 11)
    orb.hpLine.anchor:SetPoint("TOP", pbg, "BOTTOM", 0, -3)
    orb.ppLine = line(13, 10)
    orb.ppLine.anchor:SetPoint("TOP", orb.hpLine.anchor, "BOTTOM", 0, -1)
    orb.tot = top:CreateFontString(nil, "OVERLAY")
    numFont(orb.tot, 12)
    orb.tot:SetPoint("TOP", orb.ppLine.anchor, "BOTTOM", 0, -2)

    local bg = orb.halo:CreateAnimationGroup()
    bg:SetLooping("BOUNCE")
    orb.breath = bg:CreateAnimation("Alpha")
    orb.breath:SetSmoothing("IN_OUT")
    orb.breathAnim = bg

    local sh = c:CreateAnimationGroup()
    for i, dx in ipairs({ -4, 8, -6, 3, -1 }) do
        local t = sh:CreateAnimation("Translation")
        t:SetOffset(dx, (i % 2 == 0) and -1 or 1)
        t:SetDuration(.045)
        t:SetOrder(i)
    end
    orb.shake = sh

    orb:SetScript("OnMouseWheel", function(_, delta)
        if L.unlocked then return end
        L.db.targetZoom = L.Clamp((L.db.targetZoom or .65) + delta * .05, 0, 1)
        T.ApplyZoom()
    end)
    pcall(model.SetScript, model, "OnModelLoaded", function()
        T.ApplyZoom()
        T.anim = nil
        T.UpdateAnim()
    end)

    T.healthCurve = L.BuildCurve(LIQUID)
    L.RegisterMover({
        key = "target", label = "Target", frame = orb, secure = true,
        default = function(f)
            local main = L.bars[1] and L.bars[1].header
            if main then f:SetPoint("LEFT", main, "RIGHT", 16, 14)
            else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 380, 40) end
        end,
    })
    if L.db.target then RegisterUnitWatch(orb) else orb:Hide() end
    T.StartEvents()
    T.Update()
end

------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------
function T.ApplyZoom()
    if T.orb then call(T.orb.model.SetPortraitZoom, T.orb.model, T.dead and 0 or (L.db.targetZoom or .65)) end
end

local function setLine(ln, cur, max, r, g, b, shown)
    for _, fs in ipairs({ ln.anchor, ln.cur, ln.max }) do fs:SetShown(shown) end
    if not shown then return end
    local function fmt(v)
        local p = plain(v)
        if p then return BreakUpLargeNumbers and BreakUpLargeNumbers(p) or tostring(p) end
        return v
    end
    pcall(ln.cur.SetText, ln.cur, fmt(cur))
    pcall(ln.max.SetText, ln.max, fmt(max))
    ln.cur:SetTextColor(r, g, b)
    ln.max:SetTextColor(r * .68, g * .68, b * .72)
    ln.anchor:SetTextColor(r * .55, g * .55, b * .6)
end

local function tint(t, c) t:SetVertexColor(c:GetRGB()) end

function T.UpdateHealth()
    local o = T.orb
    if not o or not exists() then return end
    local hp, max = UnitHealth("target"), UnitHealthMax("target")
    pcall(o.liquid.SetMinMaxValues, o.liquid, 0, max)
    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if not (interp and pcall(o.liquid.SetValue, o.liquid, hp, interp)) then pcall(o.liquid.SetValue, o.liquid, hp) end

    local fill = o.liquid:GetStatusBarTexture()
    local dead = plain(UnitIsDeadOrGhost("target"))
    local done = false
    if dead then
        fill:SetVertexColor(.35, .35, .38); o.wave:SetVertexColor(.35, .35, .38); done = true
    elseif T.healthCurve and UnitHealthPercent then
        local c = call(UnitHealthPercent, "target", true, T.healthCurve)
        if c and pcall(tint, fill, c) then pcall(tint, o.wave, c); done = true end
    end
    if not done then
        local h, m = plain(hp), plain(max)
        local r, g, b = L.StopsColor(LIQUID, (h and m and m > 0) and h / m or 1)
        fill:SetVertexColor(r, g, b); o.wave:SetVertexColor(r, g, b)
    end
    setLine(o.hpLine, hp, max, .93, .96, 1, true)

    -- hit detection when numbers are readable (UNIT_COMBAT covers the rest)
    local h, m = plain(hp), plain(max)
    local f = (h and m and m > 0) and h / m or nil
    if f and T.lastHealth and f < T.lastHealth - .003 then T.Hit((T.lastHealth - f) > .12) end
    T.lastHealth = f
    if (dead and true or false) ~= (T.dead or false) then
        T.dead = dead and true or false
        T.ApplyZoom()
        T.UpdateAnim()
        T.UpdateMood()
    end
end

function T.UpdatePower()
    local o = T.orb
    if not o or not exists() then return end
    local max = UnitPowerMax("target")
    local zero = plain(max) == 0
    o.power:SetShown(not zero); o.powerBg:SetShown(not zero)
    if zero then setLine(o.ppLine, 0, 0, 1, 1, 1, false) return end
    pcall(o.power.SetMinMaxValues, o.power, 0, max)
    pcall(o.power.SetValue, o.power, UnitPower("target"))
    local pt, token = UnitPowerType("target")
    token = plain(token)
    local pc = (token and PowerBarColor and PowerBarColor[token]) or (PowerBarColor and PowerBarColor[plain(pt) or 0])
    local r, g, b = .25, .5, 1
    if pc then r, g, b = pc.r, pc.g, pc.b end
    o.power:GetStatusBarTexture():SetVertexColor(r, g, b)
    r, g, b = r + (1 - r) * .3, g + (1 - g) * .3, b + (1 - b) * .3
    setLine(o.ppLine, UnitPower("target"), max, r, g, b, true)
end

function T.UpdateName()
    local o = T.orb
    if not o or not exists() then return end
    pcall(o.nameText.SetText, o.nameText, (UnitName("target")))
    local r, g, b = reactionColor()
    o.nameText:SetTextColor(r + (1 - r) * .35, g + (1 - g) * .35, b + (1 - b) * .35)

    local lvl = plain(UnitLevel("target"))
    local class = plain(UnitClassification("target"))
    local txt = lvl and (lvl < 0 and "??" or tostring(lvl)) or ""
    if class == "elite" or class == "rareelite" then txt = txt .. "+" elseif class == "worldboss" then txt = "Boss" end
    o.levelText:SetText(txt)
    local dc = lvl and lvl > 0 and ((GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl))
        or (GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)))
    if lvl and lvl < 0 then o.levelText:SetTextColor(1, .2, .2)
    elseif dc then o.levelText:SetTextColor(dc.r, dc.g, dc.b)
    else o.levelText:SetTextColor(.8, .8, .85) end

    local elite = class == "elite" or class == "worldboss" or class == "rareelite"
    local rare = class == "rare" or class == "rareelite"
    o.elite:SetShown(elite or rare)
    o.eliteComet:SetShown(elite or rare)
    if elite or rare then
        if rare and not elite then o.elite:SetVertexColor(.82, .86, .95); o.eliteComet:SetVertexColor(.82, .86, .95)
        else o.elite:SetVertexColor(1, .78, .3); o.eliteComet:SetVertexColor(1, .8, .35) end
        o.eliteSpin:Play()
    else
        o.eliteSpin:Stop()
    end
end

function T.UpdateToT()
    local o = T.orb
    if not o or not exists() then return end
    if not plain(UnitExists("targettarget")) then o.tot:SetText("") return end
    if plain(UnitIsUnit("targettarget", "player")) then
        o.tot:SetText("targeting YOU")
        o.tot:SetTextColor(1, .35, .3)
    else
        pcall(o.tot.SetFormattedText, o.tot, "targeting %s", (UnitName("targettarget")))
        o.tot:SetTextColor(.62, .67, .78)
    end
end

function T.UpdateMood()
    local o = T.orb
    if not o then return end
    local r, g, b, lo, hi, t
    if T.dead then
        r, g, b, lo, hi, t = .45, .45, .5, .1, .1, 1
    elseif aggro() then
        r, g, b, lo, hi, t = 1, .15, .12, .3, .95, .55   -- it's on you
    else
        r, g, b = reactionColor()
        lo, hi, t = .15, .35, 2.4
    end
    o.halo:SetVertexColor(r, g, b)
    o.inner:SetVertexColor(r, g, b)
    o.outer:SetVertexColor(r * .8 + .1, g * .8 + .1, b * .8 + .1, .6)
    o.breath:SetFromAlpha(lo); o.breath:SetToAlpha(hi); o.breath:SetDuration(t)
    o.breathAnim:Stop(); o.breathAnim:Play()
end

function T.UpdateAnim()
    local o = T.orb
    if not o or (T.oneshotUntil and GetTime() < T.oneshotUntil) then return end
    local want = AN.STAND
    if T.dead then want = AN.DEAD
    elseif T.casting and hasAnim(o.model, AN.READYSPELL) then want = AN.READYSPELL
    elseif aggro() or plain(UnitAffectingCombat("target")) then
        want = hasAnim(o.model, AN.READY1H) and AN.READY1H or (hasAnim(o.model, AN.READY_UNARMED) and AN.READY_UNARMED or AN.STAND)
    end
    if want ~= T.anim then
        T.anim = want
        call(o.model.SetAnimation, o.model, want)
    end
end

function T.Hit(big)
    local o, t = T.orb, GetTime()
    if not o or T.dead or (T.lastHit and t - T.lastHit < .6) then return end
    T.lastHit = t
    o.hurtAnim:Stop(); o.hurtAnim:Play()
    o.shake:Stop(); o.shake:Play()
    local id = big and AN.CRIT or AN.WOUND
    if hasAnim(o.model, id) then
        T.oneshotUntil = t + (big and .9 or .6)
        T.anim = id
        call(o.model.SetAnimation, o.model, id)
    end
end

function T.Update()
    local o = T.orb
    if not o or not exists() then return end
    call(o.model.SetUnit, o.model, "target")
    T.dead = plain(UnitIsDeadOrGhost("target")) and true or false
    T.lastHealth, T.anim, T.oneshotUntil = nil, nil, nil
    T.ApplyZoom()
    T.UpdateName(); T.UpdateHealth(); T.UpdatePower(); T.UpdateToT(); T.UpdateMood(); T.UpdateAnim()
end

------------------------------------------------------------------------
-- Enable / preview
------------------------------------------------------------------------
function T.SetEnabled(on)
    if InCombatLockdown() or not T.orb then return false end
    L.db.target = on
    if on then
        RegisterUnitWatch(T.orb)
        T.Update()
    else
        UnregisterUnitWatch(T.orb)
        T.orb:Hide()
    end
    if L.UpdateTargetFrame then L.UpdateTargetFrame() end
end

-- Edit mode: show it even without a target so it can be placed.
function T.SetPreview(on)
    if not T.orb or InCombatLockdown() or not L.db.target then return end
    if on then
        UnregisterUnitWatch(T.orb)
        T.orb:Show()
        if not exists() then
            call(T.orb.model.SetUnit, T.orb.model, "player")
            T.orb.nameText:SetText("Target")
            T.orb.levelText:SetText("")
        end
    else
        RegisterUnitWatch(T.orb)
        T.Update()
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local H = {}
local function on(unit) return unit == "target" end

H.PLAYER_TARGET_CHANGED = function() T.casting = nil; T.Update() end
H.PLAYER_ENTERING_WORLD = function() T.Update() end
H.UNIT_HEALTH = function(u) if on(u) then T.UpdateHealth() end end
H.UNIT_MAXHEALTH = H.UNIT_HEALTH
H.UNIT_POWER_FREQUENT = function(u) if on(u) then T.UpdatePower() end end
H.UNIT_MAXPOWER = H.UNIT_POWER_FREQUENT
H.UNIT_DISPLAYPOWER = H.UNIT_POWER_FREQUENT
H.UNIT_NAME_UPDATE = function(u) if on(u) then T.UpdateName() end end
H.UNIT_LEVEL = H.UNIT_NAME_UPDATE
H.UNIT_FACTION = function(u) if on(u) then T.UpdateName(); T.UpdateMood() end end
H.UNIT_CLASSIFICATION_CHANGED = H.UNIT_NAME_UPDATE
H.UNIT_MODEL_CHANGED = function(u) if on(u) then call(T.orb.model.SetUnit, T.orb.model, "target") end end
H.UNIT_TARGET = function(u) if on(u) then T.UpdateToT(); T.UpdateMood(); T.UpdateAnim() end end
H.UNIT_THREAT_SITUATION_UPDATE = function() T.UpdateMood(); T.UpdateAnim() end
H.UNIT_COMBAT = function(u, action)
    if not on(u) or T.lastHealth then return end -- readable health handles it
    local a = plain(action)
    if a == nil or a == "WOUND" then T.Hit(false) end
end
local function castOn(u) if on(u) then T.casting = true; T.UpdateAnim() end end
local function castOff(u) if on(u) then T.casting = nil; T.UpdateAnim() end end
H.UNIT_SPELLCAST_START = castOn
H.UNIT_SPELLCAST_CHANNEL_START = castOn
H.UNIT_SPELLCAST_STOP = castOff
H.UNIT_SPELLCAST_FAILED = castOff
H.UNIT_SPELLCAST_INTERRUPTED = castOff
H.UNIT_SPELLCAST_CHANNEL_STOP = castOff
H.PLAYER_REGEN_ENABLED = function() T.UpdateMood(); T.UpdateAnim() end
H.PLAYER_REGEN_DISABLED = H.PLAYER_REGEN_ENABLED

local UNIT_EVENTS = {
    UNIT_HEALTH = 1, UNIT_MAXHEALTH = 1, UNIT_POWER_FREQUENT = 1, UNIT_MAXPOWER = 1, UNIT_DISPLAYPOWER = 1,
    UNIT_NAME_UPDATE = 1, UNIT_LEVEL = 1, UNIT_FACTION = 1, UNIT_CLASSIFICATION_CHANGED = 1,
    UNIT_MODEL_CHANGED = 1, UNIT_TARGET = 1, UNIT_COMBAT = 1, UNIT_SPELLCAST_START = 1,
    UNIT_SPELLCAST_CHANNEL_START = 1, UNIT_SPELLCAST_STOP = 1, UNIT_SPELLCAST_FAILED = 1,
    UNIT_SPELLCAST_INTERRUPTED = 1, UNIT_SPELLCAST_CHANNEL_STOP = 1,
}

function T.StartEvents()
    for e in pairs(H) do
        if UNIT_EVENTS[e] then pcall(ev.RegisterUnitEvent, ev, e, "target")
        else pcall(ev.RegisterEvent, ev, e) end
    end
    ev:SetScript("OnEvent", function(_, e, ...)
        if L.db.target then H[e](...) end
    end)
    local acc = 0
    ev:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < .25 then return end
        acc = 0
        if L.db.target and exists() then
            if T.oneshotUntil and GetTime() >= T.oneshotUntil then T.oneshotUntil = nil; T.anim = nil end
            T.UpdateAnim()
        end
    end)
end
