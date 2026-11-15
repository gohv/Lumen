local _, L = ...
local M = L.MEDIA
local call, plain, secret = L.call, L.plain, L.secret

------------------------------------------------------------------------
-- Cast arc: a ring hugging an orb that fills while the unit casts and
-- drains while it channels. Success blooms in the theme accent, an
-- interrupt flashes red. Target arcs: red = interruptible, grey = not.
-- Uses duration objects when available, so it also works when cast
-- timings are secret.
------------------------------------------------------------------------
L.castArcs = {}

local function durationFor(unit, channel)
    local fn = channel and UnitChannelDuration or UnitCastingDuration
    if fn then return call(fn, unit) end
end

local function info(unit, channel)
    if channel then
        local name, _, tex, s, e, _, notInt = UnitChannelInfo(unit)
        return name, tex, s, e, notInt
    end
    local name, _, tex, s, e, _, _, notInt = UnitCastingInfo(unit)
    return name, tex, s, e, notInt
end

local GREY, RED
local function swipeFromColor(cd, c) cd:SetSwipeColor(c:GetRGBA()) end

local function enabled(arc) return L.db[arc.key] and true or false end

local function start(arc, channel)
    if not enabled(arc) then return end
    local unit = arc.unit
    local name, tex, s, e, notInt = info(unit, channel)
    if not name and not secret(name) then return end
    arc.casting, arc.channel = true, channel
    local cd = arc.cd
    cd:SetReverse(not channel) -- casts grow, channels drain

    local d = durationFor(unit, channel)
    local ok = d and cd.SetCooldownFromDurationObject and pcall(cd.SetCooldownFromDurationObject, cd, d)
    local how = ok and "duration object" or nil
    s, e = plain(s), plain(e)
    if not ok and s and e and e > s then
        cd:SetCooldown(s / 1000, (e - s) / 1000)
        ok, how = true, "start/end times"
    end
    arc.s, arc.e = s and s / 1000, e and e / 1000
    -- timings hidden from addons: show a spinning comet until the cast ends
    if ok then
        arc.spinAnim:Stop(); arc.spin:SetAlpha(0)
    else
        cd:Clear()
        arc.spinAnim:Play(); arc.spin:SetAlpha(1)
        how = "spinner (timings hidden)"
    end
    L.castDebug = unit .. (channel and " channel" or " cast") .. " shown with " .. how

    -- color
    if unit == "player" then
        local c = channel and L.theme.proc or L.theme.accent
        cd:SetSwipeColor(c[1], c[2], c[3], 1)
        arc.glowColor = c
    else
        if not GREY and CreateColor then GREY, RED = CreateColor(.6, .62, .68, 1), CreateColor(1, .3, .22, 1) end
        local p = plain(notInt)
        if p ~= nil or not secret(notInt) then
            if p then cd:SetSwipeColor(.6, .62, .68, 1) else cd:SetSwipeColor(1, .3, .22, 1) end
        elseif C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and GREY then
            local c = call(C_CurveUtil.EvaluateColorFromBoolean, notInt, GREY, RED)
            if not (c and pcall(swipeFromColor, cd, c)) then cd:SetSwipeColor(1, .3, .22, 1) end
        end
        arc.glowColor = { 1, .3, .22 }
    end

    pcall(arc.text.SetText, arc.text, name)
    arc.spark:SetVertexColor(1, 1, 1)
    local gc = arc.glowColor or L.theme.accent
    arc.spin:SetVertexColor(gc[1], gc[2], gc[3])
    arc.frame:Show()
    L.FadeTo(arc.frame, 1, .12)
end

-- Is the unit still casting/channeling? (works with secret results too)
local function stillCasting(unit)
    local c, ch = UnitCastingInfo(unit), UnitChannelInfo(unit)
    return (secret(c) or c or secret(ch) or ch) and true or false
end

local function finish(arc, success)
    if not arc.casting then return end
    arc.casting = false
    arc.spinAnim:Stop(); arc.spin:SetAlpha(0)
    arc.s, arc.e = nil, nil
    local c = success and (arc.glowColor or L.theme.accent) or { 1, .15, .12 }
    arc.flash:SetVertexColor(c[1], c[2], c[3])
    arc.flashAnim:Stop(); arc.flashAnim:Play()
    if not success then
        arc.text:SetText(arc.unit == "player" and "Interrupted" or "Interrupted!")
        arc.text:SetTextColor(1, .35, .3)
    end
    C_Timer.After(success and .05 or .35, function()
        if not arc.casting then L.FadeTo(arc.frame, 0, .3) end
    end)
    C_Timer.After(.7, function()
        if not arc.casting then
            arc.cd:Clear()
            arc.text:SetTextColor(1, 1, 1)
        end
    end)
end

function L.CreateCastArc(orb, unit, key)
    local D = orb:GetWidth()
    local R = math.floor(D * 1.12 + .5)
    local f = CreateFrame("Frame", nil, orb)
    f:SetSize(R, R)
    f:SetPoint("CENTER")
    f:SetFrameLevel(orb:GetFrameLevel() + 9)
    f:SetAlpha(0)

    local track = f:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(M .. "ring")
    track:SetAllPoints()
    track:SetVertexColor(.05, .06, .1, .75)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:ClearAllPoints()
    cd:SetAllPoints(f)
    cd:SetSwipeTexture(M .. "ring")
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    if cd.SetUseCircularEdge then cd:SetUseCircularEdge(true) end

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints(f)
    top:SetFrameLevel(cd:GetFrameLevel() + 2)

    -- glowing head travelling with the arc (only when timings are readable)
    local spark = top:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(M .. "bloom")
    spark:SetBlendMode("ADD")
    spark:SetSize(16, 16)
    spark:Hide()

    -- indeterminate spinner for when cast timings are hidden
    local spin = top:CreateTexture(nil, "OVERLAY")
    spin:SetTexture(M .. "comet")
    spin:SetBlendMode("ADD")
    spin:SetSize(R * 1.05, R * 1.05)
    spin:SetPoint("CENTER")
    spin:SetAlpha(0)
    local sg = spin:CreateAnimationGroup()
    sg:SetLooping("REPEAT")
    local sr = sg:CreateAnimation("Rotation")
    sr:SetDegrees(-360)
    sr:SetDuration(1.1)
    sr:SetOrigin("CENTER", 0, 0)

    local flash = top:CreateTexture(nil, "OVERLAY", nil, 1)
    flash:SetTexture(M .. "glow")
    flash:SetBlendMode("ADD")
    flash:SetSize(R * 1.25, R * 1.25)
    flash:SetPoint("CENTER")
    flash:SetAlpha(0)

    -- spell name inside the lower part of the window
    local text = top:CreateFontString(nil, "OVERLAY")
    if not text:SetFont(L.NUMFONT, 13, "") then text:SetFont(L.FONT, 12, "") end
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetPoint("CENTER", f, "CENTER", 0, -D * .16)
    text:SetWidth(D * .62)
    text:SetWordWrap(false)

    local arc = {
        unit = unit, key = key, frame = f, cd = cd, spark = spark, text = text, flash = flash,
        spin = spin, spinAnim = sg,
        flashAnim = L.Anim(flash, { dur = .45, scaleFrom = .85, scaleTo = 1.1, alphaFrom = .9, alphaTo = 0 }),
    }
    L.castArcs[#L.castArcs + 1] = arc

    local radius = R / 2 - R * .03
    f:SetScript("OnUpdate", function()
        if not (arc.casting and arc.s and arc.e) then spark:Hide() return end
        local p = L.Clamp((GetTime() - arc.s) / (arc.e - arc.s), 0, 1)
        if arc.channel then p = 1 - p end
        local a = math.pi / 2 - p * 2 * math.pi -- clockwise from 12 o'clock
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", f, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
        spark:Show()
    end)

    local ev = CreateFrame("Frame")
    local H = {
        UNIT_SPELLCAST_START = function() start(arc, false) end,
        UNIT_SPELLCAST_CHANNEL_START = function() start(arc, true) end,
        UNIT_SPELLCAST_EMPOWER_START = function() start(arc, true) end,
        UNIT_SPELLCAST_DELAYED = function() if arc.casting then start(arc, false) end end,
        UNIT_SPELLCAST_CHANNEL_UPDATE = function() if arc.casting then start(arc, true) end end,
        UNIT_SPELLCAST_STOP = function() finish(arc, true) end,
        UNIT_SPELLCAST_CHANNEL_STOP = function() finish(arc, true) end,
        UNIT_SPELLCAST_EMPOWER_STOP = function() finish(arc, true) end,
        UNIT_SPELLCAST_INTERRUPTED = function()
            C_Timer.After(0, function() if not stillCasting(unit) then finish(arc, false) end end)
        end,
        UNIT_SPELLCAST_FAILED = function()
            C_Timer.After(0, function() if not stillCasting(unit) then finish(arc, false) end end)
        end,
    }
    for e in pairs(H) do pcall(ev.RegisterUnitEvent, ev, e, unit) end
    if unit == "target" then
        H.PLAYER_TARGET_CHANGED = function()
            arc.casting = false
            arc.cd:Clear()
            f:SetAlpha(0)
            local c, ch = UnitCastingInfo("target"), UnitChannelInfo("target")
            if secret(c) or c then start(arc, false)
            elseif secret(ch) or ch then start(arc, true) end
        end
        ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    ev:SetScript("OnEvent", function(_, e) H[e]() end)
    return arc
end

-- Called when the cast-arc options change.
function L.UpdateCastArcs()
    for _, arc in ipairs(L.castArcs) do
        if not enabled(arc) then
            arc.casting = false
            arc.cd:Clear()
            arc.frame:SetAlpha(0)
        end
    end
    if L.UpdateCastBars then L.UpdateCastBars() end
end
