local _, L = ...
local M = L.MEDIA
local api, call, plain, secret = L.api, L.call, L.plain, L.secret

local Button = {}
L.Button = Button
L.buttons = {}   -- every Lumen button
L.cdActive = {}  -- buttons with a running (non-GCD) cooldown, colorized every frame
L.procs = {}     -- spellID -> true while the spell alert is lit

local HasAction          = api("HasAction")
local GetActionTexture   = api("GetActionTexture")
local GetActionCount     = api("GetActionCount")
local IsUsableAction     = api("IsUsableAction")
local IsActionInRange    = api("IsActionInRange")
local IsCurrentAction    = api("IsCurrentAction")
local IsAutoRepeatAction = api("IsAutoRepeatAction")
local IsEquippedAction   = api("IsEquippedAction")
local IsConsumableAction = api("IsConsumableAction")
local IsStackableAction  = api("IsStackableAction")
local GetActionInfo      = api("GetActionInfo")
local GetActionCharges   = api("GetActionCharges")
local GetActionCooldown  = api("GetActionCooldown")
local PickupAction       = api("PickupAction")
local PlaceAction        = api("PlaceAction")
local GetActionCooldownDuration = C_ActionBar and C_ActionBar.GetActionCooldownDuration
local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed

local WHITE, RED, GREY
local function colors()
    if WHITE or not CreateColor then return end
    WHITE, RED, GREY = CreateColor(1, 1, 1, 1), CreateColor(.95, .28, .30, 1), CreateColor(.38, .38, .42, 1)
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
local function tex(parent, layer, sub, file, size, blend)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(M .. file)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    if blend then t:SetBlendMode(blend) end
    return t
end

local function newCooldown(parent, size, level, swipe)
    local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cd:ClearAllPoints()
    cd:SetPoint("CENTER")
    cd:SetSize(size, size)
    cd:SetFrameLevel(level)
    cd:SetSwipeTexture(M .. swipe)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    if cd.SetUseCircularEdge then cd:SetUseCircularEdge(true) end
    return cd
end

function Button.Create(bar, index)
    colors()
    local size = bar.def.size
    local b = CreateFrame("Button", bar.header:GetName() .. "Button" .. index, bar.header, "SecureActionButtonTemplate")
    b:SetSize(size, size)
    b.bar, b.index, b.size = bar, index, size
    b.bindingCmd = bar.def.binding .. index

    -- Midnight-engine secure buttons filter key-down/up themselves from the
    -- ActionButtonUseKeyDown CVar, so they need both registered.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:RegisterForDrag("LeftButton", "RightButton")
    b:SetAttribute("type", "action")
    b:SetAttribute("checkselfcast", true)
    b:SetAttribute("checkfocuscast", true)
    b:SetAttribute("checkmouseovercast", true)

    -- Everything visual lives on an unprotected child, so we can fade and
    -- animate it freely in combat.
    -- Centered (not SetAllPoints) so the dock magnifier can scale it around
    -- its middle and slide it sideways.
    local v = CreateFrame("Frame", nil, b)
    v:SetSize(size, size)
    v:SetPoint("CENTER", b, "CENTER", 0, 0)
    v:SetFrameLevel(b:GetFrameLevel() + 1)
    b.visual = v
    local lvl = v:GetFrameLevel()
    local inner = size - 4

    b.halo = tex(v, "BACKGROUND", -7, "glow", size * 1.9, "ADD")
    b.halo:SetAlpha(0)
    b.shadow = tex(v, "BACKGROUND", -6, "shadow", size * 1.32)
    b.shadow:SetPoint("CENTER", 0, -size * 0.06)
    b.backdrop = tex(v, "BACKGROUND", -5, "circle", size)
    b.backdrop:SetVertexColor(.05, .06, .09, .92)

    b.icon = L.RoundIcon(v, inner, "ARTWORK", 0)
    b.shine = tex(v, "ARTWORK", 2, "shine", inner, "ADD")
    b.shine:SetAlpha(.35)
    b.flash = tex(v, "ARTWORK", 3, "circle", inner, "ADD")
    b.flash:SetAlpha(0)

    -- Dark veil + countdown numbers over the icon
    b.cd = newCooldown(v, inner, lvl + 1, "circle")
    b.cd:SetSwipeColor(0, 0, 0, .62)
    b.cd:SetHideCountdownNumbers(not L.db.numbers)
    local fs = b.cd.GetCountdownFontString and b.cd:GetCountdownFontString()
    if not fs then
        for _, r in ipairs({ b.cd:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then fs = r break end
        end
    end
    if fs then
        fs:SetFont(L.FONT, math.max(10, size * 0.36), "OUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 0, 1)
        b.cdText = fs
    end

    -- Rim + color-shifting progress ring
    local rimF = CreateFrame("Frame", nil, v)
    rimF:SetAllPoints(v)
    rimF:SetFrameLevel(lvl + 2)
    b.rim = tex(rimF, "ARTWORK", 0, "ring", size)
    b.ring = newCooldown(rimF, size, lvl + 3, "ring_bold")
    b.ring:SetSwipeColor(1, 1, 1, 1)
    b.ring:SetHideCountdownNumbers(true)
    b.ring:SetScript("OnCooldownDone", function() Button.CooldownDone(b) end)

    -- Effects + text on top
    local top = CreateFrame("Frame", nil, v)
    top:SetAllPoints(v)
    top:SetFrameLevel(lvl + 5)
    b.comet = tex(top, "OVERLAY", 0, "comet", size * 1.42, "ADD")
    b.comet:SetAlpha(0)
    b.ripple = tex(top, "OVERLAY", 1, "ring", size, "ADD")
    b.ripple:SetAlpha(0)
    b.bloom = tex(top, "OVERLAY", 2, "glow", size * 1.9, "ADD")
    b.bloom:SetAlpha(0)

    b.pill = top:CreateTexture(nil, "OVERLAY", nil, 3)
    b.pill:SetTexture(M .. "circle")
    b.pill:SetVertexColor(.04, .05, .08, .88)
    b.pill:SetPoint("CENTER", b, "BOTTOM", 0, size * 0.04)
    b.hotkey = top:CreateFontString(nil, "OVERLAY")
    b.hotkey:SetDrawLayer("OVERLAY", 4)
    b.hotkey:SetFont(L.FONT, math.max(8, size * 0.22), "OUTLINE")
    b.hotkey:SetPoint("CENTER", b.pill, "CENTER", 0, 0)
    b.hotkey:SetTextColor(.92, .94, 1)

    b.count = top:CreateFontString(nil, "OVERLAY")
    b.count:SetDrawLayer("OVERLAY", 4)
    b.count:SetFont(L.FONT, math.max(9, size * 0.27), "OUTLINE")
    b.count:SetPoint("CENTER", b, "CENTER", size * 0.30, size * 0.30)

    -- Animations
    b.rippleAnim = L.Anim(b.ripple, { dur = .35, scaleFrom = 1, scaleTo = 1.45, alphaFrom = .9, alphaTo = 0 })
    b.bloomAnim = L.Anim(b.bloom, { dur = .7, scaleFrom = .5, scaleTo = 1.25, alphaFrom = 1, alphaTo = 0 })
    b.flashAnim = L.Anim(b.flash, { dur = .45, alphaFrom = .7, alphaTo = 0 })
    b.pressAnim = L.Anim(v, { dur = .22, scaleFrom = .86, scaleTo = 1 })

    local spin = b.comet:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local rot = spin:CreateAnimation("Rotation")
    rot:SetDegrees(-360)
    rot:SetDuration(1.6)
    rot:SetOrigin("CENTER", 0, 0)
    b.cometAnim = spin

    local breathe = b.halo:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    local ba = breathe:CreateAnimation("Alpha")
    ba:SetFromAlpha(.3)
    ba:SetToAlpha(.9)
    ba:SetDuration(.8)
    ba:SetSmoothing("IN_OUT")
    b.haloPulse = breathe

    b:SetScript("OnEnter", Button.OnEnter)
    b:SetScript("OnLeave", Button.OnLeave)
    b:SetScript("PostClick", Button.PostClick)
    b:SetScript("OnDragStart", Button.OnDragStart)
    b:SetScript("OnReceiveDrag", Button.OnReceiveDrag)
    b:HookScript("OnAttributeChanged", Button.OnAttributeChanged)

    L.buttons[#L.buttons + 1] = b
    return b
end

------------------------------------------------------------------------
-- Scripts
------------------------------------------------------------------------
function Button.OnAttributeChanged(b, name, value)
    if name == "action" then Button.SetAction(b, tonumber(value)) end
end

function Button.SetAction(b, slot)
    if b.action == slot then return end
    b.action = slot
    -- New action: drop the old cooldown state without celebrating it.
    b.cdActive, b.demoUntil, b.durObj = false, nil, nil
    L.cdActive[b] = nil
    Button.Update(b)
end

function Button.OnEnter(b)
    b.hover = true
    L.BarHover(b.bar, true)
    L.FadeTo(b.halo, math.max(b.haloBase or 0, .4), .15)
    L.FadeTo(b.rim, 1, .15)
    if GameTooltip and b.has then
        local lift = L.db.magnify and b.size * ((L.db.magnifyScale or 1.6) - 1) or 0
        GameTooltip:SetOwner(b, "ANCHOR_TOP", 0, 6 + lift)
        if call(GameTooltip.SetAction, GameTooltip, b.action) ~= false then GameTooltip:Show() end
    end
end

function Button.OnLeave(b)
    b.hover = false
    L.BarHover(b.bar, false)
    L.FadeTo(b.halo, b.haloBase or 0, .3)
    L.FadeTo(b.rim, b.rimAlpha or .3, .3)
    if GameTooltip and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

function Button.PostClick(b, _, down)
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    if (down and keyDown) or (not down and not keyDown) then
        b.pressAnim:Stop(); b.pressAnim:Play()
        local a = L.theme.accent
        b.ripple:SetVertexColor(a[1], a[2], a[3])
        b.rippleAnim:Stop(); b.rippleAnim:Play()
    end
    Button.Update(b)
end

function Button.OnDragStart(b)
    if InCombatLockdown() then return end
    local locked = (GetCVarBool and GetCVarBool("lockActionBars")) or LOCK_ACTIONBAR == "1"
    if not locked or IsModifiedClick("PICKUPACTION") then
        call(PickupAction, b.action)
        Button.Update(b)
    end
end

function Button.OnReceiveDrag(b)
    if InCombatLockdown() then return end
    call(PlaceAction, b.action)
    Button.Update(b)
end

------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------
local function abbreviate(key)
    key = key:upper()
    key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a"):gsub("META%-", "m")
    key = key:gsub("MOUSEWHEELUP", "wU"):gsub("MOUSEWHEELDOWN", "wD"):gsub("MIDDLEMOUSE", "M3"):gsub("BUTTON", "M")
    key = key:gsub("NUMPADDECIMAL", "n."):gsub("NUMPADPLUS", "n+"):gsub("NUMPADMINUS", "n-")
    key = key:gsub("NUMPADMULTIPLY", "n*"):gsub("NUMPADDIVIDE", "n/"):gsub("NUMPAD", "n")
    key = key:gsub("BACKSPACE", "Bs"):gsub("SPACE", "Sp"):gsub("CAPSLOCK", "Cp"):gsub("INSERT", "Ins")
    key = key:gsub("DELETE", "Del"):gsub("HOME", "Hm"):gsub("PAGEUP", "PU"):gsub("PAGEDOWN", "PD")
    return key
end

function Button.UpdateHotkey(b)
    local key = GetBindingKey(b.bindingCmd)
    local txt = key and abbreviate(key) or ""
    b.hotkey:SetText(txt)
    if txt == "" or not L.db.hotkeys then
        b.hotkey:Hide(); b.pill:Hide()
    else
        b.hotkey:Show(); b.pill:Show()
        local w = (b.hotkey:GetStringWidth() or 0) + b.size * 0.22
        b.pill:SetSize(math.max(w, b.size * 0.42), b.size * 0.30)
    end
end

function Button.UpdateCount(b)
    local slot, text = b.action, ""
    if b.has then
        if plain(call(IsConsumableAction, slot)) or plain(call(IsStackableAction, slot)) then
            local c = call(GetActionCount, slot)
            if secret(c) then b.count:SetText(c) return end
            c = c or 0
            text = c > 9999 and "*" or tostring(c)
        else
            local r1, r2 = call(GetActionCharges, slot)
            local cur, max
            if type(r1) == "table" then cur, max = plain(r1.currentCharges), plain(r1.maxCharges)
            else cur, max = plain(r1), plain(r2) end
            if cur and max and max > 1 then text = tostring(cur) end
        end
    end
    b.count:SetText(text)
end

function Button.UpdateState(b)
    local th, slot = L.theme, b.action
    local active = b.has and (plain(call(IsCurrentAction, slot)) or plain(call(IsAutoRepeatAction, slot)))
    local equipped = b.has and plain(call(IsEquippedAction, slot))
    local c
    if active then
        c, b.rimAlpha, b.haloBase = th.active, .95, .5
    elseif equipped then
        c, b.rimAlpha, b.haloBase = { .35, .95, .55 }, .8, 0
    else
        c, b.rimAlpha, b.haloBase = th.base, .3, 0
    end
    b.rim:SetVertexColor(c[1], c[2], c[3])
    if not b.proc then
        local h = active and th.active or th.accent
        b.halo:SetVertexColor(h[1], h[2], h[3])
    end
    if not b.hover then
        L.FadeTo(b.rim, b.rimAlpha, .2)
        if not b.proc then L.FadeTo(b.halo, b.haloBase, .25) end
    end
end

local function tintFromColor(t, c) t:SetVertexColor(c:GetRGB()) end

function Button.UpdateUsable(b)
    if not b.has then return end
    local slot, icon = b.action, b.icon
    local usable, noMana = call(IsUsableAction, slot)
    local inRange = call(IsActionInRange, slot)
    local dim = b.cdActive and .6 or 1

    if secret(inRange) or secret(usable) then
        -- Can't branch on secrets: let the client pick the color.
        local f = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
        if f and WHITE then
            local c = secret(inRange) and call(f, inRange, WHITE, RED) or call(f, usable, WHITE, GREY)
            if c and pcall(tintFromColor, icon, c) then
                icon:SetDesaturated(b.cdActive)
                return
            end
        end
        icon:SetVertexColor(dim, dim, dim)
        icon:SetDesaturated(b.cdActive)
        return
    end

    local r, g, bl, desat = 1, 1, 1, b.cdActive
    if inRange == false or inRange == 0 then
        r, g, bl = .95, .28, .30
    elseif usable then
        r, g, bl = 1, 1, 1
    elseif plain(noMana) then
        r, g, bl = .42, .55, 1
    else
        r, g, bl, desat = .38, .38, .42, true
    end
    icon:SetVertexColor(r * dim, g * dim, bl * dim)
    icon:SetDesaturated(desat)
end

local function setCD(cd, durObj, start, dur, modRate)
    if durObj and cd.SetCooldownFromDurationObject then
        if pcall(cd.SetCooldownFromDurationObject, cd, durObj) then return end
    end
    if start and dur then pcall(cd.SetCooldown, cd, start, dur, modRate) end
end

function Button.UpdateCooldown(b)
    if b.demoUntil then return end
    if not b.has then
        if b.cdActive then Button.Finish(b, false) end
        b.cd:Clear(); b.ring:Clear()
        return
    end
    local slot = b.action
    local active, gcd, start, dur, modRate
    local r1, r2, r3, r4 = call(GetActionCooldown, slot)
    if type(r1) == "table" then
        -- isActive / isOnGCD / isEnabled are never secret
        active, gcd = r1.isActive, r1.isOnGCD
        start, dur, modRate = plain(r1.startTime), plain(r1.duration), plain(r1.modRate)
        if active == nil and dur then active = dur > 0 and r1.isEnabled ~= false end
    else
        start, dur, modRate = plain(r1), plain(r2), plain(r4)
        local en = plain(r3)
        if dur then active = dur > 0 and en ~= 0 and en ~= false end
    end
    if gcd == nil and active and dur then gcd = dur <= 1.6 end
    local durObj = GetActionCooldownDuration and call(GetActionCooldownDuration, slot)

    if active and not gcd then
        if not b.cdActive then
            b.cdActive, b.cdBegan = true, GetTime()
        end
        b.cdStart, b.cdDur, b.durObj = start, dur, durObj
        b.cd:SetSwipeColor(0, 0, 0, .62)
        b.cd:SetHideCountdownNumbers(not L.db.numbers)
        setCD(b.cd, durObj, start, dur, modRate)
        setCD(b.ring, durObj, start, dur, modRate)
        L.cdActive[b] = true
        Button.Colorize(b)
        Button.UpdateUsable(b)
    elseif active then -- global cooldown: a soft, quiet sweep
        if b.cdActive then Button.Finish(b, true) end
        b.cd:SetSwipeColor(0, 0, 0, .38)
        b.cd:SetHideCountdownNumbers(true)
        setCD(b.cd, durObj, start, dur, modRate)
        b.ring:Clear()
    elseif active == nil and durObj then -- unknown state: just let the client draw it
        setCD(b.cd, durObj)
    else
        if b.cdActive then Button.Finish(b, true) end
        b.cd:Clear(); b.ring:Clear()
    end
end

local function applyRGB(b, r, g, bl)
    b.ring:SetSwipeColor(r, g, bl, 1)
    if b.cdText then b.cdText:SetTextColor(r, g, bl) end
end
local function applyColorObj(b, c) applyRGB(b, c:GetRGB()) end

-- Ring color follows remaining time. The native curve path works on secret
-- cooldowns; the Lua path is the fallback when numbers are readable.
function Button.Colorize(b)
    local curve, d = L.curve, b.durObj
    if curve and d then
        local ok, c = pcall(d.EvaluateRemainingPercent, d, curve)
        if ok and c and pcall(applyColorObj, b, c) then return end
    end
    local stops = L.theme.stops
    if b.cdStart and b.cdDur and b.cdDur > 0 then
        applyRGB(b, L.StopsColor(stops, L.Clamp((b.cdStart + b.cdDur - GetTime()) / b.cdDur, 0, 1)))
    else
        applyRGB(b, L.StopsColor(stops, .5))
    end
end

function Button.CooldownDone(b)
    if b.demoUntil then
        b.demoUntil = nil
        Button.Finish(b, true)
        Button.UpdateCooldown(b)
        return
    end
    C_Timer.After(0.05, function() Button.UpdateCooldown(b) end)
end

function Button.Finish(b, celebrate)
    b.cdActive, b.durObj, b.cdStart, b.cdDur = false, nil, nil, nil
    L.cdActive[b] = nil
    b.ring:Clear()
    Button.UpdateUsable(b)
    if celebrate and b.has then
        local a = L.theme.accent
        b.bloom:SetVertexColor(a[1], a[2], a[3])
        b.bloomAnim:Stop(); b.bloomAnim:Play()
        b.flashAnim:Stop(); b.flashAnim:Play()
        local elapsed = GetTime() - (b.cdBegan or GetTime())
        if L.db.pulse and elapsed >= (L.db.pulseMin or 6) and L.Pulse then L.Pulse(b) end
    end
end

function Button.SetProc(b, on)
    if on == b.proc then return end
    b.proc = on
    if on then
        local p = L.theme.proc
        b.comet:SetVertexColor(p[1], p[2], p[3])
        b.halo:SetVertexColor(p[1], p[2], p[3])
        b.comet:SetAlpha(1)
        b.cometAnim:Play()
        b.haloPulse:Play()
    else
        b.cometAnim:Stop()
        b.haloPulse:Stop()
        b.comet:SetAlpha(0)
        Button.UpdateState(b)
    end
end

function Button.UpdateProc(b)
    local on = false
    if b.has then
        local kind, id = call(GetActionInfo, b.action)
        kind, id = plain(kind), plain(id)
        if kind == "spell" and id then
            on = L.procs[id] or (plain(call(IsSpellOverlayed, id)) and true) or false
        end
    end
    if b.demoProc then on = true end
    Button.SetProc(b, on)
end

function Button.ApplyAlpha(b)
    local a = b.bar.alpha or 1
    if not b.has then
        if L.showGrid or L.unlocked then a = a * .8
        elseif L.db.sockets then a = a * .3
        else a = 0 end
    end
    b.visual:SetAlpha(a)
end

function Button.Update(b)
    local slot = b.action
    if not slot then return end
    b.has = plain(call(HasAction, slot)) and true or false
    if b.has then
        b.icon:SetTexture(call(GetActionTexture, slot))
        b.icon:Show()
    else
        b.icon:Hide()
    end
    Button.UpdateCount(b)
    Button.UpdateState(b)
    Button.UpdateCooldown(b)
    Button.UpdateUsable(b)
    Button.UpdateProc(b)
    Button.ApplyAlpha(b)
end
