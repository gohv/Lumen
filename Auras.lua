local _, L = ...
local M = L.MEDIA
local call, plain, secret = L.call, L.plain, L.secret

------------------------------------------------------------------------
-- Aura bubbles: round icons floating in an arc around an orb, gently
-- bobbing. Each has a timer ring and stack count, pops in when it appears
-- and shows the tooltip on hover.
--   avatar: your buffs over the top, debuffs down the outer side
--   target: your debuffs on it (or its buffs if friendly) over the top,
--           the rest down the outer side
------------------------------------------------------------------------
L.auraRings = {}

local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount

local function bubble(ring, size)
    local b = CreateFrame("Frame", nil, ring.frame)
    b:SetSize(size, size)
    b:EnableMouse(true)
    b:Hide()

    b.shadow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    b.shadow:SetTexture(M .. "shadow")
    b.shadow:SetSize(size * 1.35, size * 1.35)
    b.shadow:SetPoint("CENTER", 0, -1)
    b.disk = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.disk:SetTexture(M .. "circle")
    b.disk:SetVertexColor(.04, .05, .08, .95)
    b.disk:SetAllPoints()
    b.icon = L.RoundIcon(b, size - 4, "ARTWORK", 0)
    b.shine = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.shine:SetTexture(M .. "shine")
    b.shine:SetBlendMode("ADD")
    b.shine:SetAlpha(.3)
    b.shine:SetSize(size - 4, size - 4)
    b.shine:SetPoint("CENTER")

    b.border = b:CreateTexture(nil, "OVERLAY", nil, 0)
    b.border:SetTexture(M .. "ring")
    b.border:SetAllPoints()

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:ClearAllPoints()
    cd:SetAllPoints(b)
    cd:SetSwipeTexture(M .. "ring_bold")
    cd:SetSwipeColor(1, 1, 1, .9)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    b.cd = cd

    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(b)
    top:SetFrameLevel(cd:GetFrameLevel() + 2)
    b.count = top:CreateFontString(nil, "OVERLAY")
    if not b.count:SetFont(L.NUMFONT, size * .5, "OUTLINE") then b.count:SetFont(L.FONT, size * .45, "OUTLINE") end
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)

    b.popAnim = L.Anim(b, { dur = .28, scaleFrom = .25, scaleTo = 1 })

    b:SetScript("OnEnter", function(self)
        if not self.auraIndex then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 4, -4)
        local ok = self.auraID and GameTooltip.SetUnitAuraByAuraInstanceID
            and pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, ring.unit, self.auraID)
        if not ok then pcall(GameTooltip.SetUnitAura, GameTooltip, ring.unit, self.auraIndex, self.filter) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function fill(ring, b, aura, index, filter, debuff)
    local was = b:IsShown()
    b.auraIndex, b.filter, b.auraID = index, filter, aura.auraInstanceID
    pcall(b.icon.SetTexture, b.icon, aura.icon)

    -- timer ring
    local d = GetAuraDuration and b.auraID and call(GetAuraDuration, ring.unit, b.auraID)
    if not (d and b.cd.SetCooldownFromDurationObject and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d, true)) then
        local dur, exp = plain(aura.duration), plain(aura.expirationTime)
        if dur and exp and dur > 0 then b.cd:SetCooldown(exp - dur, dur) else b.cd:Clear() end
    end

    -- stacks
    local n = plain(aura.applications)
    if n then
        b.count:SetText(n > 1 and n or "")
    elseif GetDisplayCount and b.auraID then
        pcall(b.count.SetText, b.count, call(GetDisplayCount, ring.unit, b.auraID, 2, 999))
    else
        b.count:SetText("")
    end

    -- ring colors: debuffs by dispel type, buffs in the theme
    local r, g, bl
    if debuff then
        local dt = plain(aura.dispelName)
        local c = dt and DebuffTypeColor and DebuffTypeColor[dt]
        if c then r, g, bl = c.r, c.g, c.b else r, g, bl = .9, .22, .22 end
    else
        local a = L.theme.accent
        r, g, bl = a[1], a[2], a[3]
    end
    b.border:SetVertexColor(r * .8, g * .8, bl * .8, .9)
    b.cd:SetSwipeColor(r, g, bl, .95)

    if not was then
        b:Show()
        b.popAnim:Stop(); b.popAnim:Play()
    end
end

local function collect(ring, filter, slots, debuff)
    local used = 0
    if not GetAuraDataByIndex then return 0 end
    for i = 1, 40 do
        if used >= #slots then break end
        local aura = call(GetAuraDataByIndex, ring.unit, i, filter)
        if not aura then break end
        used = used + 1
        fill(ring, slots[used], aura, i, filter, debuff)
    end
    for j = used + 1, #slots do slots[j]:Hide() end
    return used
end

function L.UpdateAuraRing(ring)
    local show = L.db[ring.key] and plain(UnitExists(ring.unit))
    ring.frame:SetShown(show and true or false)
    if not show then return end
    if ring.unit == "player" then
        collect(ring, "HELPFUL", ring.top, false)
        collect(ring, "HARMFUL", ring.side, true)
    else
        local hostile = plain(UnitCanAttack("player", ring.unit))
        if hostile then
            collect(ring, "HARMFUL|PLAYER", ring.top, true)   -- your dots/debuffs on it
            collect(ring, "HELPFUL", ring.side, false)        -- its buffs
        else
            collect(ring, "HELPFUL", ring.top, false)
            collect(ring, "HARMFUL", ring.side, true)
        end
    end
end

-- cfg: { key = db flag, side = "left" | "right", size, top = n, sideCount = n }
function L.CreateAuraRing(orb, unit, cfg)
    local D = orb:GetWidth()
    local size = cfg.size or 24
    local f = CreateFrame("Frame", nil, orb)
    f:SetAllPoints(orb)
    f:SetFrameLevel(orb:GetFrameLevel() + 12)
    local ring = { unit = unit, key = cfg.key, frame = f, top = {}, side = {}, all = {} }

    local radius = D / 2 + size / 2 + 10
    local step = math.deg((size + 5) / radius)
    local left = cfg.side == "left"
    -- angles in degrees, 0 = right, 90 = up
    for i = 1, cfg.top or 7 do
        local b = bubble(ring, size)
        b.angle = left and (160 - (i - 1) * step) or (20 + (i - 1) * step)
        ring.top[i] = b
        ring.all[#ring.all + 1] = b
    end
    for i = 1, cfg.sideCount or 3 do
        local b = bubble(ring, size)
        b.angle = left and (200 + (i - 1) * step) or (340 - (i - 1) * step)
        ring.side[i] = b
        ring.all[#ring.all + 1] = b
    end

    -- gentle float: each bubble bobs on its own phase, the arc sways slightly
    local t = math.random() * 10
    f:SetScript("OnUpdate", function(_, el)
        t = t + el
        local sway = math.sin(t * .35) * 2.5
        for i, b in ipairs(ring.all) do
            if b:IsShown() then
                local a = math.rad(b.angle + sway)
                b:ClearAllPoints()
                b:SetPoint("CENTER", f, "CENTER", math.cos(a) * radius, math.sin(a) * radius + math.sin(t * 1.7 + i * .9) * 1.6)
            end
        end
    end)

    local ev = CreateFrame("Frame")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", unit)
    pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
    if unit == "target" then pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED") end
    ev:SetScript("OnEvent", function() L.UpdateAuraRing(ring) end)

    L.auraRings[#L.auraRings + 1] = ring
    L.UpdateAuraRing(ring)
    return ring
end

function L.UpdateAuraRings()
    for _, ring in ipairs(L.auraRings) do L.UpdateAuraRing(ring) end
end
