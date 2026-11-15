local _, L = ...
local M = L.MEDIA
local call, plain = L.call, L.plain

------------------------------------------------------------------------
-- Living avatar: your 3D character in a glass orb that reacts to what
-- you're doing. Ready stance and darting glances in combat, flinches when
-- hit, roars when a fight ends, sits down in town, falls asleep when AFK,
-- mirrors your /emotes. Behind it, a liquid health fill.
------------------------------------------------------------------------
local A = {}
L.Avatar = A

local S = 78                 -- model window (diameter)
local D = math.floor(S * 1.45 + .5) -- whole orb (band hides the model's square corners)

-- Animation IDs (AnimationData)
local AN = {
    STAND = 0, DEAD = 6, WALK = 4, RUN = 5, STANDWOUND = 8, WOUND = 9, CRIT = 10, STUN = 14,
    ATT_UNARMED = 16, ATT1H = 17, ATT2H = 18, READY_UNARMED = 25, READY1H = 26, READY2H = 27,
    FALL = 40, SWIMIDLE = 41, SWIM = 42, LOOT = 50, READYSPELL = 51, CASTOMNI = 54, BATTLEROAR = 55,
    SPECIAL1H = 57, SPECIAL2H = 58, TALK = 60, EAT = 61, EXCLAIM = 64, QUESTION = 65, BOW = 66,
    WAVE = 67, CHEER = 68, DANCE = 69, LAUGH = 70, RUDE = 73, ROAR = 74, KNEEL = 75, KISS = 76,
    CRY = 77, CHICKEN = 78, BEG = 79, APPLAUD = 80, SHOUT = 81, FLEX = 82, SHY = 83, POINT = 84,
    SITDOWN = 96, SIT = 97, SITUP = 98, SLEEPDOWN = 99, SLEEP = 100, SLEEPUP = 101, SALUTE = 113,
    STEALTHWALK = 119, STEALTHSTAND = 120, CHANNEL = 124,
}

-- One-shot durations (seconds)
local DUR = {
    [AN.WOUND] = .6, [AN.CRIT] = .9, [AN.CASTOMNI] = 1, [AN.SPECIAL1H] = .9, [AN.SPECIAL2H] = 1,
    [AN.ATT_UNARMED] = .8, [AN.ATT1H] = .8, [AN.ATT2H] = 1, [AN.LOOT] = 1.4, [AN.BATTLEROAR] = 1.3,
    [AN.SITDOWN] = 1, [AN.SITUP] = 1, [AN.SLEEPDOWN] = 1.6, [AN.SLEEPUP] = 1.6,
}
local EMOTE_DUR = 2.4

-- Mood = halo color + breathing speed
local MOODS = {
    idle   = { c = { .80, .84, 1 },   lo = .10, hi = .22, t = 2.4 },
    rest   = { c = { .40, .62, 1 },   lo = .22, hi = .45, t = 2.8 },
    combat = { c = { 1, .36, .18 },   lo = .30, hi = .75, t = .9 },
    low    = { c = { 1, .12, .16 },   lo = .25, hi = .95, t = .42 },
    cast   = { accent = true,         lo = .35, hi = .70, t = .7 },
    sleep  = { c = { .62, .45, 1 },   lo = .20, hi = .45, t = 3.2 },
    dead   = { c = { .45, .45, .50 }, lo = .12, hi = .12, t = 1 },
    ghost  = { c = { .45, .95, 1 },   lo = .30, hi = .60, t = 2 },
    party  = { proc = true,           lo = .35, hi = .90, t = .5 },
}

-- State -> looping animation, camera zoom (nil = your zoom), mood
-- enter/exit = transition one-shots
local STATES = {
    dead      = { anim = AN.DEAD,         zoom = 0,   mood = "dead" },
    ghost     = { anim = AN.STAND,                    mood = "ghost" },
    stun      = { anim = AN.STUN,                     mood = "low" },
    cast      = { anim = AN.READYSPELL,               mood = "cast" },
    channel   = { anim = AN.CHANNEL,                  mood = "cast" },
    swim      = { anim = AN.SWIM,         zoom = .25, mood = "idle" },
    swimidle  = { anim = AN.SWIMIDLE,     zoom = .25, mood = "idle" },
    fall      = { anim = AN.FALL,         zoom = .25, mood = "idle" },
    run       = { anim = AN.RUN,          zoom = .3,  mood = "idle" },
    walk      = { anim = AN.WALK,         zoom = .3,  mood = "idle" },
    sneak     = { anim = AN.STEALTHWALK,  zoom = .3,  mood = "idle" },
    combat    = { anim = "ready",                     mood = "combat" },
    hurt      = { anim = AN.STANDWOUND,               mood = "low" },
    dance     = { anim = AN.DANCE,        zoom = 0,   mood = "party" },
    sit       = { anim = AN.SIT,   enter = AN.SITDOWN,   exit = AN.SITUP,   zoom = .1, mood = "rest" },
    sleep     = { anim = AN.SLEEP, enter = AN.SLEEPDOWN, exit = AN.SLEEPUP, zoom = 0,  mood = "sleep", zzz = true },
    kneel     = { anim = AN.KNEEL,        zoom = .2,  mood = "rest" },
    eat       = { anim = AN.EAT,                      mood = "rest" },
    stealth   = { anim = AN.STEALTHSTAND,             mood = "idle" },
    idle      = { anim = AN.STAND,                    mood = "idle" },
}

-- /emote tokens the avatar mirrors. Numbers are one-shots, strings are looping states.
local EMOTES = {
    WAVE = AN.WAVE, CHEER = AN.CHEER, LAUGH = AN.LAUGH, LOL = AN.LAUGH, ROFL = AN.LAUGH, BOW = AN.BOW,
    ROAR = AN.ROAR, CRY = AN.CRY, FLEX = AN.FLEX, SALUTE = AN.SALUTE, POINT = AN.POINT, RUDE = AN.RUDE,
    APPLAUD = AN.APPLAUD, CLAP = AN.APPLAUD, BRAVO = AN.APPLAUD, SHOUT = AN.SHOUT, KISS = AN.KISS,
    CHICKEN = AN.CHICKEN, BEG = AN.BEG, SHY = AN.SHY, TALK = AN.TALK, TALKEX = AN.EXCLAIM,
    TALKQ = AN.QUESTION, QUESTION = AN.QUESTION, HELLO = AN.WAVE, BYE = AN.WAVE, GREET = AN.WAVE,
    CHARGE = AN.BATTLEROAR, ATTACKMYTARGET = AN.POINT, NO = AN.TALK, YES = AN.TALK, THANK = AN.BOW,
    DANCE = "dance", SIT = "sit", SLEEP = "sleep", KNEEL = "kneel", EAT = "eat",
}

local CLICK_REACTIONS = { AN.WAVE, AN.LAUGH, AN.SHY, AN.EXCLAIM, AN.QUESTION, AN.FLEX, AN.POINT }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function now() return GetTime() end
local function fighting()
    return (plain(UnitAffectingCombat("player")) or InCombatLockdown()) and true or false
end

local function weaponKind()
    local id = GetInventoryItemID("player", 16)
    if not id then return "unarmed" end
    local loc
    if C_Item and C_Item.GetItemInfoInstant then loc = select(4, C_Item.GetItemInfoInstant(id))
    elseif GetItemInfoInstant then loc = select(4, GetItemInfoInstant(id)) end
    return loc == "INVTYPE_2HWEAPON" and "2h" or "1h"
end

local function readyAnim()
    local k = weaponKind()
    return k == "2h" and AN.READY2H or k == "unarmed" and AN.READY_UNARMED or AN.READY1H
end

local function attackAnim()
    local k = weaponKind()
    return k == "2h" and AN.ATT2H or k == "unarmed" and AN.ATT_UNARMED or AN.ATT1H
end

local function healthFrac()
    local hp, max = plain(UnitHealth("player")), plain(UnitHealthMax("player"))
    if hp and max and max > 0 then return hp / max end
end

local function isMoving()
    local speed = plain(GetUnitSpeed("player")) or 0
    return speed > 0, speed
end

local function hasAnim(id)
    local m = A.model
    local loaded = call(m.HasAnimation, m, AN.STAND)
    if not loaded then return true end -- model not ready; let the client fall back
    return call(m.HasAnimation, m, id) and true or false
end

------------------------------------------------------------------------
-- Animation control
------------------------------------------------------------------------
local function stateAnim(name)
    local st = STATES[name] or STATES.idle
    if st.anim == "ready" then return readyAnim() end
    return st.anim
end

local function setAnim(id)
    if not hasAnim(id) then id = AN.STAND end
    call(A.model.SetAnimation, A.model, id)
end

-- Play a one-shot, then return to the current state's loop.
function A.Play(id, dur, force)
    if not A.model then return end
    if not force and (A.state == "dead") then return end
    if not hasAnim(id) then return end
    A.oneshotUntil = now() + (dur or DUR[id] or EMOTE_DUR)
    call(A.model.SetAnimation, A.model, id)
end

local function zoomFor(name)
    local st = STATES[name] or STATES.idle
    return st.zoom or L.db.avatarZoom
end

local function setZoom(_, z)
    A.zoom = z
    call(A.model.SetPortraitZoom, A.model, z)
end

local function applyZoom(instant)
    L.Tween(A, A.zoom or 0, zoomFor(A.state), instant and 0 or .45, setZoom)
end

A.ApplyZoom = function(instant) applyZoom(instant) end

local function setFacing(_, f)
    A.facing = f
    call(A.model.SetFacing, A.model, f)
end

function A.Glance(to, dur)
    L.Tween(A.glanceKey, A.facing or 0, to, dur or .25, setFacing)
end

------------------------------------------------------------------------
-- Mood glow + zzz
------------------------------------------------------------------------
function A.SetMood(name)
    local m = MOODS[name] or MOODS.idle
    local c = m.c
    if m.accent then c = L.theme.accent elseif m.proc then c = L.theme.proc end
    local o = A.orb
    o.halo:SetVertexColor(c[1], c[2], c[3])
    o.inner:SetVertexColor(c[1], c[2], c[3])
    o.breath:SetFromAlpha(m.lo)
    o.breath:SetToAlpha(m.hi)
    o.breath:SetDuration(m.t)
    o.breathAnim:Stop()
    o.breathAnim:Play()
    A.mood = name
end

local function setZzz(on)
    for _, z in ipairs(A.orb.zzz) do
        if on then z.anim:Play() else z.anim:Stop() end
    end
end

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------
function A.Compute()
    if A.forced then return A.forced end
    if UnitIsDeadOrGhost("player") then
        return UnitIsGhost("player") and "ghost" or "dead"
    end
    if A.stunned then return "stun" end
    if A.casting then return A.channeling and "channel" or "cast" end
    local moving, speed = isMoving()
    if IsSwimming and IsSwimming() then
        A.emoteLoop = nil
        return moving and "swim" or "swimidle"
    end
    if IsFalling and IsFalling() and not (IsFlying and IsFlying()) then return "fall" end
    if moving then
        A.emoteLoop = nil
        A.lastActive = now()
        if IsStealthed() then return "sneak" end
        return speed > 7.5 and "run" or "walk"
    end
    if fighting() then
        A.emoteLoop = nil
        local f = healthFrac()
        if f and f < .3 then return "hurt" end
        return "combat"
    end
    if A.emoteLoop then return A.emoteLoop end
    if UnitIsAFK("player") then return "sleep" end
    if A.eating then return "eat" end
    if IsStealthed() then return "stealth" end
    local idle = now() - (A.lastActive or now())
    if idle > 240 then return "sleep" end
    if idle > 75 and IsResting() then return "sit" end
    local f = healthFrac()
    if f and f < .3 then return "hurt" end
    return "idle"
end

function A.SetState(name)
    if name == A.state then return end
    local old, new = STATES[A.state], STATES[name] or STATES.idle
    A.state = name
    local trans = (old and old.exit) or new.enter
    if trans and hasAnim(trans) then
        A.Play(trans, DUR[trans], true)
    elseif not (A.oneshotUntil and A.oneshotUntil > now()) then
        A.oneshotUntil = nil
        setAnim(stateAnim(name))
    end
    applyZoom()
    A.SetMood(new.mood)
    setZzz(new.zzz)
    if name ~= "combat" then A.Glance(0, .4) end
    call(A.model.SetModelAlpha, A.model, name == "ghost" and .55 or (IsStealthed() and .6 or 1))
end

function A.Refresh()
    if A.model then A.SetState(A.Compute()) end
end

------------------------------------------------------------------------
-- Health liquid
------------------------------------------------------------------------
local LIQUID = { { 0, .95, .16, .22 }, { .35, 1, .62, .18 }, { .7, .35, .92, .45 }, { 1, .25, .85, .55 } }

local function tint(t, c) t:SetVertexColor(c:GetRGB()) end

function A.UpdateHealth()
    local o = A.orb
    if not o then return end
    local hp, max = UnitHealth("player"), UnitHealthMax("player")
    pcall(o.liquid.SetMinMaxValues, o.liquid, 0, max)
    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if not (interp and pcall(o.liquid.SetValue, o.liquid, hp, interp)) then
        pcall(o.liquid.SetValue, o.liquid, hp)
    end

    -- color: native curve works with secret health; Lua path otherwise
    local fill = o.liquid:GetStatusBarTexture()
    local done = false
    if A.healthCurve and UnitHealthPercent then
        local c = call(UnitHealthPercent, "player", true, A.healthCurve)
        if c and pcall(tint, fill, c) then
            pcall(tint, o.wave, c)
            done = true
        end
    end
    if not done then
        local f = healthFrac() or 1
        local r, g, b = L.StopsColor(LIQUID, f)
        fill:SetVertexColor(r, g, b)
        o.wave:SetVertexColor(r, g, b)
    end

    -- getting hit (only when the numbers are readable)
    local f = healthFrac()
    if f and A.lastHealth and f < A.lastHealth - .005 and not UnitIsDeadOrGhost("player") then
        A.Hit((A.lastHealth - f) > .1)
    end
    A.lastHealth = f
    if f then A.Refresh() end
    A.UpdateTexts()
end

------------------------------------------------------------------------
-- Power + hover text
------------------------------------------------------------------------
local function powerColor()
    local pt, token = UnitPowerType("player")
    token = plain(token)
    local c = token and PowerBarColor and PowerBarColor[token]
    if not c then c = PowerBarColor and PowerBarColor[plain(pt) or 0] end
    if c then return c.r, c.g, c.b end
    return .25, .5, 1
end

function A.UpdatePower()
    local o = A.orb
    if not o then return end
    local max = UnitPowerMax("player")
    local zero = plain(max) == 0
    o.power:SetShown(not zero)
    o.powerBg:SetShown(not zero)
    if zero then return end
    pcall(o.power.SetMinMaxValues, o.power, 0, max)
    local cur = UnitPower("player")
    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if not (interp and pcall(o.power.SetValue, o.power, cur, interp)) then
        pcall(o.power.SetValue, o.power, cur)
    end
    local r, g, b = powerColor()
    o.power:GetStatusBarTexture():SetVertexColor(r, g, b)
    o.powerSpark:SetVertexColor(r, g, b, .8)
    A.UpdateTexts()
end

local function numFont(fs, size)
    if not fs:SetFont(L.NUMFONT, size, "") then fs:SetFont(L.FONT, size * .9, "") end
    fs:SetShadowColor(0, 0, 0, .95)
    fs:SetShadowOffset(1, -1)
end

-- One "1,842 / 2,000" line, centered on the slash so no width math is needed
-- (widths of secret text can't be measured).
function A.NumberLine(parent, big, small)
    local line = {}
    line.anchor = parent:CreateFontString(nil, "OVERLAY")
    numFont(line.anchor, small)
    line.anchor:SetText("/")
    line.cur = parent:CreateFontString(nil, "OVERLAY")
    numFont(line.cur, big)
    line.cur:SetPoint("BOTTOMRIGHT", line.anchor, "BOTTOMLEFT", -3, -1)
    line.max = parent:CreateFontString(nil, "OVERLAY")
    numFont(line.max, small)
    line.max:SetPoint("BOTTOMLEFT", line.anchor, "BOTTOMRIGHT", 3, 0)
    return line
end

local function fmt(v)
    local p = plain(v)
    if p then return BreakUpLargeNumbers and BreakUpLargeNumbers(p) or tostring(p) end
    return v -- secret: FontString:SetText still displays it
end

local function setLine(line, cur, max, r, g, b, shown)
    for _, fs in ipairs({ line.anchor, line.cur, line.max }) do fs:SetShown(shown) end
    if not shown then return end
    pcall(line.cur.SetText, line.cur, fmt(cur))
    pcall(line.max.SetText, line.max, fmt(max))
    line.cur:SetTextColor(r, g, b)
    line.max:SetTextColor(r * .68, g * .68, b * .72)
    line.anchor:SetTextColor(r * .55, g * .55, b * .6)
end

function A.UpdateTexts()
    local o = A.orb
    if not o or not o.hpLine then return end
    setLine(o.hpLine, UnitHealth("player"), UnitHealthMax("player"), .93, .96, 1, true)
    local r, g, b = powerColor()
    -- lift dark power colors (mana blue) so the numbers stay readable
    r, g, b = r + (1 - r) * .3, g + (1 - g) * .3, b + (1 - b) * .3
    setLine(o.ppLine, UnitPower("player"), UnitPowerMax("player"), r, g, b, o.power:IsShown())
end

------------------------------------------------------------------------
-- Reactions
------------------------------------------------------------------------
function A.Hit(big)
    local t = now()
    if A.lastHit and t - A.lastHit < .7 then return end
    A.lastHit = t
    A.lastActive = t
    local o = A.orb
    o.hurtAnim:Stop(); o.hurtAnim:Play()
    o.shake:Stop(); o.shake:Play()
    if A.state ~= "cast" and A.state ~= "channel" then A.Play(big and AN.CRIT or AN.WOUND) end
    A.Glance(math.random() < .5 and -.5 or .5, .1) -- snap toward the "hit"
    C_Timer.After(.5, function() if fighting() then A.Glance(0, .3) end end)
end

function A.Shout(text)
    local o = A.orb
    o.shoutText:SetText(text)
    o.shoutAnim:Stop(); o.shoutAnim:Play()
end

local function onClick(_, button)
    if button ~= "LeftButton" or L.unlocked then return end
    local t = now()
    if not A.clickStart or t - A.clickStart > 3 then A.clickStart, A.clicks = t, 0 end
    A.clicks = A.clicks + 1
    A.lastActive = t
    if A.state == "sleep" then A.emoteLoop = nil; A.Refresh() return end
    if A.clicks >= 5 then
        A.clicks = 0
        A.Play(AN.RUDE)
        A.Shout("hey!")
    else
        A.Play(CLICK_REACTIONS[math.random(#CLICK_REACTIONS)])
    end
end

local function onWheel(_, delta)
    if L.unlocked then return end
    L.db.avatarZoom = L.Clamp((L.db.avatarZoom or .75) + delta * .05, 0, 1)
    applyZoom()
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
local function texture(parent, layer, sub, file, size, blend)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(M .. file)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    if blend then t:SetBlendMode(blend) end
    return t
end

function L.CreateAvatar()
    -- A secure unit button, so it can replace the player frame:
    -- left-click targets you, right-click opens your unit menu.
    local orb = CreateFrame("Button", "LumenAvatar", UIParent, "SecureUnitButtonTemplate")
    orb:SetSize(D, D)
    orb:SetFrameStrata("LOW")
    orb:RegisterForClicks("AnyUp")
    orb:SetAttribute("unit", "player")
    orb:SetAttribute("*type1", "target")
    orb:SetAttribute("*type2", "togglemenu")
    orb:EnableMouseWheel(true)
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[orb] = true
    A.orb = orb

    orb.halo = texture(orb, "BACKGROUND", -7, "glow", D * 1.75, "ADD")
    orb.shadow = texture(orb, "BACKGROUND", -6, "shadow", D * 1.15)
    orb.shadow:SetPoint("CENTER", 0, -D * .05)

    -- content shakes as one piece
    local c = CreateFrame("Frame", nil, orb)
    c:SetAllPoints(orb)
    local lvl = orb:GetFrameLevel()
    c:SetFrameLevel(lvl + 1)
    orb.content = c

    orb.disk = texture(c, "BACKGROUND", 0, "circle", S + 2)
    orb.disk:SetVertexColor(.03, .04, .07, 1)

    -- liquid health
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
    wm:SetDuration(3.2)
    wg:Play()

    -- the character
    local model = CreateFrame("PlayerModel", nil, c)
    model:SetSize(S, S)
    model:SetPoint("CENTER")
    model:SetFrameLevel(lvl + 3)
    A.model = model
    A.glanceKey = {}

    -- red hit flash inside the window
    local fx = CreateFrame("Frame", nil, c)
    fx:SetAllPoints(c)
    fx:SetFrameLevel(lvl + 4)
    orb.hurt = texture(fx, "OVERLAY", 0, "glow", S * 1.15, "ADD")
    orb.hurt:SetVertexColor(1, .1, .1)
    orb.hurt:SetAlpha(0)
    orb.hurtAnim = L.Anim(orb.hurt, { dur = .45, alphaFrom = .95, alphaTo = 0 })

    -- glass band, rings, badge
    local top = CreateFrame("Frame", nil, c)
    top:SetAllPoints(c)
    top:SetFrameLevel(lvl + 5)
    orb.top = top
    orb.band = texture(top, "ARTWORK", 0, "band", D)
    orb.inner = texture(top, "ARTWORK", 1, "ring_thin", S + 3)
    orb.inner:SetAlpha(.85)
    orb.outer = texture(top, "ARTWORK", 2, "ring", D)
    orb.gloss = texture(top, "ARTWORK", 3, "shine", D * .9, "ADD")
    orb.gloss:SetAlpha(.25)

    orb.pill = top:CreateTexture(nil, "OVERLAY", nil, 0)
    orb.pill:SetTexture(M .. "circle")
    orb.pill:SetVertexColor(.04, .05, .08, .95)
    orb.pill:SetSize(30, 16)
    orb.pill:SetPoint("CENTER", orb, "BOTTOM", 0, D * .1)
    orb.level = top:CreateFontString(nil, "OVERLAY")
    orb.level:SetDrawLayer("OVERLAY", 1)
    orb.level:SetFont(L.FONT, 10, "OUTLINE")
    orb.level:SetPoint("CENTER", orb.pill, "CENTER", 0, 0)

    -- power bar (mana / rage / energy) under the orb
    local pw = D * .78
    local pbg = orb:CreateTexture(nil, "BACKGROUND", nil, -5)
    pbg:SetTexture(L.WHITE)
    pbg:SetVertexColor(.03, .04, .07, .85)
    pbg:SetSize(pw + 2, 7)
    pbg:SetPoint("TOP", orb, "BOTTOM", 0, -5) -- gap below the orb
    local pb = CreateFrame("StatusBar", nil, c)
    pb:SetSize(pw, 5)
    pb:SetPoint("CENTER", pbg, "CENTER")
    pb:SetFrameLevel(lvl + 1)
    pb:SetStatusBarTexture(L.WHITE)
    pb:SetMinMaxValues(0, 1)
    pb:SetValue(1)
    orb.power, orb.powerBg = pb, pbg
    local pspark = pb:CreateTexture(nil, "OVERLAY")
    pspark:SetTexture(M .. "bloom")
    pspark:SetBlendMode("ADD")
    pspark:SetSize(14, 14)
    pspark:SetPoint("CENTER", pb:GetStatusBarTexture(), "RIGHT", 0, 0)
    orb.powerSpark = pspark

    -- exact values on hover
    -- health + power numbers, always shown: big current value, small "/ max"
    orb.hpLine = A.NumberLine(top, 16, 11)
    orb.hpLine.anchor:SetPoint("TOP", pbg, "BOTTOM", 0, -3)
    orb.ppLine = A.NumberLine(top, 13, 10)
    orb.ppLine.anchor:SetPoint("TOP", orb.hpLine.anchor, "BOTTOM", 0, -1)

    -- breathing halo
    local bg = orb.halo:CreateAnimationGroup()
    bg:SetLooping("BOUNCE")
    orb.breath = bg:CreateAnimation("Alpha")
    orb.breath:SetSmoothing("IN_OUT")
    orb.breathAnim = bg

    -- shake
    local sh = c:CreateAnimationGroup()
    for i, dx in ipairs({ 4, -8, 6, -3, 1 }) do
        local t = sh:CreateAnimation("Translation")
        t:SetOffset(dx, (i % 2 == 0) and 1 or -1)
        t:SetDuration(.045)
        t:SetOrder(i)
    end
    orb.shake = sh

    -- zzz
    orb.zzz = {}
    for i, ch in ipairs({ "z", "z", "Z" }) do
        local z = top:CreateFontString(nil, "OVERLAY")
        z:SetFont(L.FONT, 10 + i * 3, "OUTLINE")
        z:SetText(ch)
        z:SetTextColor(.75, .65, 1)
        z:SetPoint("CENTER", orb, "TOPRIGHT", -D * .18, -D * .18)
        z:SetAlpha(0)
        local g = z:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        local mv = g:CreateAnimation("Translation")
        mv:SetOffset(14, 26); mv:SetDuration(2.4); mv:SetStartDelay((i - 1) * .8)
        local a1 = g:CreateAnimation("Alpha")
        a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(.5); a1:SetStartDelay((i - 1) * .8)
        local a2 = g:CreateAnimation("Alpha")
        a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(.9); a2:SetStartDelay((i - 1) * .8 + 1.5)
        z.anim = g
        orb.zzz[i] = z
    end

    -- "!" / speech pop
    orb.shoutText = top:CreateFontString(nil, "OVERLAY")
    orb.shoutText:SetFont(L.FONT, 18, "OUTLINE")
    orb.shoutText:SetPoint("BOTTOM", orb, "TOP", 0, -6)
    orb.shoutText:SetAlpha(0)
    local sg = orb.shoutText:CreateAnimationGroup()
    local s1 = sg:CreateAnimation("Alpha"); s1:SetFromAlpha(0); s1:SetToAlpha(1); s1:SetDuration(.12)
    local s2 = sg:CreateAnimation("Translation"); s2:SetOffset(0, 10); s2:SetDuration(1.1); s2:SetSmoothing("OUT")
    local s3 = sg:CreateAnimation("Alpha"); s3:SetFromAlpha(1); s3:SetToAlpha(0); s3:SetDuration(.4); s3:SetStartDelay(.8)
    orb.shoutAnim = sg

    orb:HookScript("PostClick", onClick)
    orb:SetScript("OnMouseWheel", onWheel)


    pcall(model.SetScript, model, "OnModelLoaded", function()
        A.zoom = nil
        applyZoom(true)
        setAnim(stateAnim(A.state or "idle"))
    end)

    A.healthCurve = L.BuildCurve(LIQUID)
    A.lastActive = now()
    A.zoom = L.db.avatarZoom
    A.LoadModel()
    A.ApplyTheme()
    A.UpdateHealth()
    A.UpdatePower()
    orb.level:SetText(UnitLevel("player"))
    A.state = nil
    A.Refresh()

    L.RegisterMover({
        key = "avatar", label = "Avatar", frame = orb, secure = true,
        default = function(f)
            local main = L.bars[1] and L.bars[1].header
            if main then f:SetPoint("RIGHT", main, "LEFT", -16, 14)
            else f:SetPoint("BOTTOM", UIParent, "BOTTOM", -380, 40) end
        end,
    })
    orb:SetShown(L.db.avatar)
    A.StartEvents()
end

function A.LoadModel()
    call(A.model.SetUnit, A.model, "player")
    call(A.model.SetPortraitZoom, A.model, A.zoom or L.db.avatarZoom)
    call(A.model.SetFacing, A.model, A.facing or 0)
    if A.state then setAnim(stateAnim(A.state)) end
end

function A.ApplyTheme()
    local o = A.orb
    if not o then return end
    local b = L.theme.base
    o.band:SetVertexColor(.11, .12, .17)
    o.outer:SetVertexColor(b[1], b[2], b[3], .55)
    if A.mood then A.SetMood(A.mood) end
end

------------------------------------------------------------------------
-- Events + tick
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local H = {}

H.PLAYER_ENTERING_WORLD = function() A.LoadModel(); A.UpdateHealth(); A.UpdatePower(); A.orb.level:SetText(UnitLevel("player")); A.Refresh() end
H.UNIT_MODEL_CHANGED = function(unit) if unit == "player" then A.LoadModel() end end
H.UNIT_PORTRAIT_UPDATE = H.UNIT_MODEL_CHANGED
H.PLAYER_EQUIPMENT_CHANGED = function() if A.state == "combat" then setAnim(readyAnim()) end end
H.UNIT_HEALTH = function(unit) if unit == "player" then A.UpdateHealth() end end
H.UNIT_MAXHEALTH = H.UNIT_HEALTH
H.UNIT_POWER_FREQUENT = function(unit) if unit == "player" then A.UpdatePower() end end
H.UNIT_MAXPOWER = H.UNIT_POWER_FREQUENT
H.UNIT_DISPLAYPOWER = H.UNIT_POWER_FREQUENT
H.PLAYER_FLAGS_CHANGED = function() A.Refresh() end
H.PLAYER_UPDATE_RESTING = function() A.Refresh() end
H.PLAYER_DEAD = function() A.casting = nil; A.Refresh() end
H.PLAYER_ALIVE = function() A.lastHealth = nil; A.Refresh() end
H.PLAYER_UNGHOST = H.PLAYER_ALIVE

H.PLAYER_REGEN_DISABLED = function()
    A.lastActive = now()
    A.emoteLoop = nil
    A.Refresh()
    A.Shout("!")
    if A.state == "combat" then A.Play(AN.BATTLEROAR) end
end
H.PLAYER_REGEN_ENABLED = function()
    A.lastActive = now()
    C_Timer.After(.3, function()
        A.Refresh()
        if not UnitIsDeadOrGhost("player") and A.state == "idle" then
            local f = healthFrac()
            if f and f < .4 then
                A.Play(AN.CRY) -- barely made it
            else
                local wins = { AN.ROAR, AN.FLEX, AN.LAUGH, AN.CHEER } -- the grin
                A.Play(wins[math.random(#wins)])
            end
        end
    end)
end

H.UNIT_COMBAT = function(unit, action)
    if unit ~= "player" or not fighting() then return end
    if healthFrac() then return end -- readable health: UpdateHealth handles hits precisely
    local a = plain(action)
    if a == nil or a == "WOUND" then A.Hit(false) end
end

local function castStart(channel)
    return function(unit)
        if unit ~= "player" then return end
        A.casting, A.channeling, A.emoteLoop, A.lastActive = true, channel, nil, now()
        A.Refresh()
    end
end
local function castEnd(unit)
    if unit ~= "player" then return end
    A.casting, A.channeling = nil, nil
    A.Refresh()
end
H.UNIT_SPELLCAST_START = castStart(false)
H.UNIT_SPELLCAST_CHANNEL_START = castStart(true)
H.UNIT_SPELLCAST_EMPOWER_START = castStart(true)
H.UNIT_SPELLCAST_STOP = castEnd
H.UNIT_SPELLCAST_FAILED = castEnd
H.UNIT_SPELLCAST_INTERRUPTED = castEnd
H.UNIT_SPELLCAST_CHANNEL_STOP = castEnd
H.UNIT_SPELLCAST_EMPOWER_STOP = castEnd
H.UNIT_SPELLCAST_SUCCEEDED = function(unit)
    if unit ~= "player" then return end
    A.lastActive = now()
    if A.channeling then return end
    A.casting = nil
    A.Refresh()
    if fighting() then
        local pt = plain(UnitPowerType("player"))
        if pt == 1 or pt == 3 then -- rage / energy: a weapon special
            A.Play(weaponKind() == "2h" and AN.SPECIAL2H or AN.SPECIAL1H)
        else
            A.Play(AN.CASTOMNI)
        end
    elseif A.state == "idle" then
        A.Play(AN.CASTOMNI)
    end
end

H.PLAYER_LEVEL_UP = function(level)
    A.orb.level:SetText(level or UnitLevel("player"))
    A.Play(AN.CHEER, 3, true)
    A.Shout("LEVEL UP!")
end
H.LOOT_READY = function() if not fighting() then A.lastActive = now(); A.Play(AN.LOOT) end end

H.UNIT_AURA = function(unit)
    if unit ~= "player" or fighting() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local eating = false
    for i = 1, 40 do
        local aura = call(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not aura then break end
        local name = plain(aura.name)
        if name == "Food" or name == "Drink" or name == "Food & Drink" or name == "Refreshment" then
            eating = true
            break
        end
    end
    if eating ~= (A.eating or false) then
        A.eating = eating
        A.Refresh()
    end
end

H.LOSS_OF_CONTROL_ADDED = function()
    local n = C_LossOfControl and plain(call(C_LossOfControl.GetActiveLossOfControlDataCount))
    A.stunned = n and n > 0 or nil
    A.Refresh()
end
H.LOSS_OF_CONTROL_UPDATE = H.LOSS_OF_CONTROL_ADDED

local UNIT_EVENTS = {
    UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true, UNIT_COMBAT = true, UNIT_AURA = true,
    UNIT_MODEL_CHANGED = true, UNIT_PORTRAIT_UPDATE = true,
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_START = true, UNIT_SPELLCAST_EMPOWER_STOP = true,
}

-- Tick: movement polling, one-shot expiry, combat glances, idle fidgets
local acc, nextFidget, nextSwing = 0, 0, 0
local function tick(_, elapsed)
    acc = acc + elapsed
    if acc < .1 then return end
    acc = 0
    local t = now()
    if A.oneshotUntil and t >= A.oneshotUntil then
        A.oneshotUntil = nil
        setAnim(stateAnim(A.state))
    end
    A.Refresh()
    if A.oneshotUntil then return end

    if A.state == "combat" then
        if t >= nextFidget then -- Doom-guy eyes: dart left/right
            local r = math.random()
            A.Glance(r < .4 and -.42 or r < .8 and .42 or 0, .18)
            nextFidget = t + 1.2 + math.random() * 1.8
        end
        local autoAttack = (C_Spell and C_Spell.IsCurrentSpell and call(C_Spell.IsCurrentSpell, 6603))
            or (IsCurrentSpell and call(IsCurrentSpell, 6603))
        if plain(autoAttack) and t >= nextSwing then
            A.Play(attackAnim())
            nextSwing = t + 1.6 + math.random() * 1.2
        end
    elseif A.state == "idle" and t >= nextFidget then
        local r = math.random()
        if r < .45 then
            A.Glance((math.random() - .5) * .9, .5)
            C_Timer.After(1.5 + math.random() * 2, function()
                if A.state == "idle" then A.Glance(0, .6) end
            end)
        elseif r < .65 then
            A.Play(math.random() < .5 and AN.TALK or AN.QUESTION, 2)
        end
        nextFidget = t + 7 + math.random() * 9
    end
end

function A.StartEvents()
    for e in pairs(H) do
        if UNIT_EVENTS[e] then
            pcall(ev.RegisterUnitEvent, ev, e, "player")
        else
            pcall(ev.RegisterEvent, ev, e)
        end
    end
    ev:SetScript("OnEvent", function(_, e, ...)
        if A.orb and A.orb:IsShown() then H[e](...) end
    end)
    ev:SetScript("OnUpdate", function(self, el)
        if A.orb and A.orb:IsShown() then tick(self, el) end
    end)
    -- mirror /dance, /wave, /sleep ...
    if hooksecurefunc and DoEmote then
        hooksecurefunc("DoEmote", function(token)
            if not A.orb or not A.orb:IsShown() then return end
            token = type(token) == "string" and token:upper() or nil
            local e = token and EMOTES[token]
            if not e then return end
            A.lastActive = now()
            if type(e) == "string" then
                A.emoteLoop = e
                A.Refresh()
            else
                A.Play(e)
            end
        end)
    end
end

function A.SetEnabled(on)
    if InCombatLockdown() then L.Print("can't change that in combat.") return end
    L.db.avatar = on
    if L.UpdatePlayerFrame then L.UpdatePlayerFrame() end
    if A.orb then
        A.orb:SetShown(on)
        if on then A.LoadModel(); A.state = nil; A.Refresh() end
    end
end

------------------------------------------------------------------------
-- /lumen avatar demo: walk through every mood
------------------------------------------------------------------------
function A.Demo()
    if not A.orb or not A.orb:IsShown() then return end
    local steps = {
        { "idle", 2.5, function() A.Play(AN.WAVE) end },
        { "combat", 2, function() A.Shout("!"); A.Play(AN.BATTLEROAR) end },
        { "combat", 1.2, function() A.lastHit = nil; A.Hit(false) end },
        { "combat", 1.6, function() A.lastHit = nil; A.Hit(true) end },
        { "cast", 2.2 },
        { "hurt", 2.2 },
        { "idle", 2.8, function() A.Play(AN.FLEX) end },
        { "run", 2.2 },
        { "sit", 3 },
        { "sleep", 4 },
        { "dance", 3.5 },
        { "dead", 3 },
        { "ghost", 2.5 },
    }
    A.demoId = (A.demoId or 0) + 1
    local id, t = A.demoId, 0
    for _, st in ipairs(steps) do
        C_Timer.After(t, function()
            if A.demoId ~= id then return end
            A.forced = st[1]
            A.Refresh()
            if st[3] then st[3]() end
        end)
        t = t + st[2]
    end
    C_Timer.After(t, function()
        if A.demoId ~= id then return end
        A.forced = nil
        A.Refresh()
    end)
end
