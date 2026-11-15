local _, L = ...
local M = L.MEDIA

------------------------------------------------------------------------
-- Cooldown pulse: a long cooldown coming back blooms in the screen center
------------------------------------------------------------------------
local pulse

function L.CreatePulse()
    local f = CreateFrame("Frame", "LumenPulse", UIParent)
    f:SetSize(64, 64)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetAlpha(0)

    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture(M .. "glow")
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(150, 150)
    f.glow:SetPoint("CENTER")
    f.disk = f:CreateTexture(nil, "BORDER")
    f.disk:SetTexture(M .. "circle")
    f.disk:SetVertexColor(.05, .06, .09, .9)
    f.disk:SetAllPoints()
    f.icon = L.RoundIcon(f, 60, "ARTWORK", 0)
    f.shine = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.shine:SetTexture(M .. "shine")
    f.shine:SetBlendMode("ADD")
    f.shine:SetAlpha(.4)
    f.shine:SetSize(60, 60)
    f.shine:SetPoint("CENTER")
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(M .. "ring_bold")
    f.ring:SetAllPoints()

    local g = f:CreateAnimationGroup()
    local function step(kind, order, dur, a, b, smooth)
        local an = g:CreateAnimation(kind)
        an:SetOrder(order)
        an:SetDuration(dur)
        an:SetSmoothing(smooth or "OUT")
        if kind == "Alpha" then
            an:SetFromAlpha(a); an:SetToAlpha(b)
        else
            if an.SetScaleFrom then an:SetScaleFrom(a, a); an:SetScaleTo(b, b)
            else an:SetFromScale(a, a); an:SetToScale(b, b) end
            an:SetOrigin("CENTER", 0, 0)
        end
    end
    step("Alpha", 1, .18, 0, 1)
    step("Scale", 1, .28, .45, 1)
    step("Alpha", 2, .45, 1, 1)
    step("Alpha", 3, .5, 1, 0, "IN")
    step("Scale", 3, .5, 1, 1.35, "IN")
    f.anim = g
    pulse = f
    L.RegisterMover({
        key = "pulse", label = "Cooldown pulse", frame = f,
        default = function(fr) fr:SetPoint("CENTER", UIParent, "CENTER", 0, 150) end,
    })
end

-- Show a placeholder while editing so the pulse can be placed.
function L.SetPulsePreview(on)
    if not pulse then return end
    pulse.anim:Stop()
    if on then
        local a = L.theme.accent
        pulse.icon:SetTexture(134400) -- question mark
        pulse.glow:SetVertexColor(a[1], a[2], a[3], .9)
        pulse.ring:SetVertexColor(a[1], a[2], a[3])
        pulse:SetAlpha(1)
    else
        pulse:SetAlpha(0)
    end
end

function L.Pulse(b)
    if not pulse or L.unlocked then return end
    local a = L.theme.accent
    pulse.icon:SetTexture(b.icon:GetTexture())
    pulse.glow:SetVertexColor(a[1], a[2], a[3], .9)
    pulse.ring:SetVertexColor(a[1], a[2], a[3])
    pulse.anim:Stop()
    pulse.anim:Play()
end

------------------------------------------------------------------------
-- XP bar: always tells you how far to the next level.
--
--   [=========|=========|====>····|·········|·········]   <- 10% segments
--   LV 23          14,710 to level  ·  45.2%          LV 24
--            ≈ 14 kills  ·  ≈ 38 min  ·  2,450 rested
------------------------------------------------------------------------
local xp
local H = 10

local function pill(parent, layer, sub)
    local l = parent:CreateTexture(nil, layer, nil, sub)
    l:SetTexture(M .. "circle"); l:SetTexCoord(0, .5, 0, 1)
    local r = parent:CreateTexture(nil, layer, nil, sub)
    r:SetTexture(M .. "circle"); r:SetTexCoord(.5, 1, 0, 1)
    local m = parent:CreateTexture(nil, layer, nil, sub)
    m:SetTexture(L.WHITE)
    l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(H / 2)
    r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(H / 2)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    return { l, m, r }
end

local function tint(parts, r, g, b, a)
    for _, t in ipairs(parts) do t:SetVertexColor(r, g, b, a or 1) end
end

local function font(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not fs:SetFont(L.NUMFONT, size, "") then fs:SetFont(L.FONT, size * .9, "") end
    fs:SetShadowColor(0, 0, 0, .95)
    fs:SetShadowOffset(1, -1)
    return fs
end

local function num(v) return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v) end

local function hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

local function duration(sec)
    if sec < 60 then return "<1 min" end
    local m = math.floor(sec / 60 + .5)
    if m < 60 then return m .. " min" end
    return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

local function maxLevel()
    if GetMaxLevelForPlayerExpansion then
        local v = L.call(GetMaxLevelForPlayerExpansion)
        if v then return v end
    end
    return MAX_PLAYER_LEVEL or 60
end

local function xpHidden()
    if not L.db.xp then return true end
    if L.unlocked then return false end -- always visible while editing
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    return UnitLevel("player") >= maxLevel()
end

function L.CreateXPBar()
    local f = CreateFrame("Frame", "LumenXP", UIParent)
    f:SetHeight(H)
    f:EnableMouse(true)
    xp = f

    f.bg = pill(f, "BACKGROUND", 0)
    tint(f.bg, .02, .03, .05, .85)

    f.rested = f:CreateTexture(nil, "BORDER")
    f.rested:SetTexture(L.WHITE)
    f.rested:SetHeight(H - 4)

    f.cap = f:CreateTexture(nil, "ARTWORK")
    f.cap:SetTexture(M .. "circle"); f.cap:SetTexCoord(0, .5, 0, 1)
    f.cap:SetSize(H / 2, H)
    f.cap:SetPoint("LEFT")
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetTexture(L.WHITE)
    f.fill:SetHeight(H)
    f.fill:SetPoint("LEFT", f.cap, "RIGHT")
    f.rested:SetPoint("LEFT", f.fill, "RIGHT")

    -- 10% segment dividers so progress can be read at a glance
    f.ticks = {}
    for i = 1, 9 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetColorTexture(0, 0, 0, .6)
        t:SetSize(1, H)
        f.ticks[i] = t
    end

    -- Shimmer: placed by hand every frame and cropped to the filled part, so
    -- it scales with the fill and can never leave the bar.
    local SW = 60                    -- shimmer width
    f.shimmer = f:CreateTexture(nil, "OVERLAY")
    f.shimmer:SetTexture(M .. "shimmer")
    f.shimmer:SetBlendMode("ADD")
    f.shimmer:SetHeight(H - 2)
    f.shimmer:SetAlpha(.35)
    f.shimmer:Hide()
    f.shimT = 0
    local drv = CreateFrame("Frame", nil, f)
    drv:SetScript("OnUpdate", function(_, elapsed)
        local fillW, sh = f.fillW or 0, f.shimmer
        if fillW < 12 then sh:Hide() return end
        f.shimT = f.shimT + elapsed
        local travel = fillW + SW
        local sweep = travel / 150          -- constant speed (px/s)
        local t = f.shimT % (sweep + 1.6)   -- sweep, then rest
        if t > sweep then sh:Hide() return end
        local x = t / sweep * travel - SW   -- shimmer's left edge, relative to fill start
        local l, r = math.max(0, x), math.min(fillW, x + SW)
        if r - l < 1 then sh:Hide() return end
        sh:ClearAllPoints()
        sh:SetPoint("LEFT", f, "LEFT", H / 2 + l, 0)
        sh:SetWidth(r - l)
        sh:SetTexCoord((l - x) / SW, (r - x) / SW, 0, 1)
        sh:Show()
    end)

    -- Glow at the fill edge: sized from the bar height so it stays inside the
    -- bar (an oval exactly as tall as the bar), and kept off the rounded ends.
    f.head = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.head:SetTexture(M .. "bloom")
    f.head:SetBlendMode("ADD")
    f.head:SetSize(H * 1.8, H)

    f.flash = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.flash:SetTexture(M .. "glow")
    f.flash:SetBlendMode("ADD")
    f.flash:SetPoint("CENTER")
    f.flash:SetAlpha(0)
    f.flashAnim = L.Anim(f.flash, { dur = 1.1, scaleFrom = .6, scaleTo = 1.2, alphaFrom = 1, alphaTo = 0 })

    -- labels
    f.lvl = font(f, 13)
    f.lvl:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -3)
    f.nextLvl = font(f, 13)
    f.nextLvl:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -2, -3)
    f.main = font(f, 15)
    f.main:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.sub = font(f, 12)
    f.sub:SetPoint("TOP", f.main, "BOTTOM", 0, -1)

    -- floating +xp numbers
    f.floaters = {}
    for i = 1, 4 do
        local fl = CreateFrame("Frame", nil, f)
        fl:SetSize(120, 18)
        fl:SetAlpha(0)
        fl.text = font(fl, 15)
        fl.text:SetPoint("CENTER")
        local g = fl:CreateAnimationGroup()
        local mv = g:CreateAnimation("Translation")
        mv:SetOffset(0, 24); mv:SetDuration(1.4); mv:SetSmoothing("OUT")
        local a1 = g:CreateAnimation("Alpha")
        a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(.15)
        local a2 = g:CreateAnimation("Alpha")
        a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(.5); a2:SetStartDelay(.9)
        fl.anim = g
        f.floaters[i] = fl
    end
    f.nextFloater = 1

    -- pace tracking for the estimates
    f.sessionStart, f.sessionXP = GetTime(), 0
    f.kills = {}

    f.shown, f.target = 0, 0
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 8)
        local cur, max = UnitXP("player"), UnitXPMax("player")
        local rest = GetXPExhaustion and GetXPExhaustion() or 0
        GameTooltip:AddLine("Level " .. UnitLevel("player") .. "  to  " .. (UnitLevel("player") + 1), 1, 1, 1)
        GameTooltip:AddDoubleLine("Experience", num(cur) .. " / " .. num(max), .8, .8, .9, 1, 1, 1)
        GameTooltip:AddDoubleLine("To level", num(max - cur), .8, .8, .9, 1, 1, 1)
        if rest > 0 then
            GameTooltip:AddDoubleLine("Rested (double kill XP)", num(rest), .8, .8, .9, .5, .75, 1)
        end
        local avg = L.AvgKillXP()
        if avg then GameTooltip:AddDoubleLine("Avg XP per kill", num(math.floor(avg + .5)), .8, .8, .9, 1, 1, 1) end
        local rate = L.XPPerHour()
        if rate then GameTooltip:AddDoubleLine("XP per hour", num(math.floor(rate)), .8, .8, .9, 1, 1, 1) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.lastXP, f.lastLevel, f.lastMax = UnitXP("player"), UnitLevel("player"), UnitXPMax("player")
    L.ApplyXPTheme()
    L.RegisterMover({
        key = "xp", label = "XP bar", frame = f,
        default = function(fr)
            local main = L.bars[1] and L.bars[1].header
            if main then fr:SetPoint("TOP", main, "BOTTOM", 0, -6)
            else fr:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40) end
        end,
    })
    L.LayoutXP()
    L.UpdateXP(true)
end

-- Average of recent "kill-sized" gains (quest turn-ins are left out).
function L.AvgKillXP()
    if not xp or #xp.kills == 0 then return nil end
    local sum = 0
    for _, v in ipairs(xp.kills) do sum = sum + v end
    return sum / #xp.kills
end

function L.XPPerHour()
    if not xp then return nil end
    local t = GetTime() - xp.sessionStart
    if t < 180 or xp.sessionXP <= 0 then return nil end
    return xp.sessionXP / t * 3600
end

function L.ApplyXPTheme()
    if not xp then return end
    local s = L.theme.stops
    local r1, g1, b1 = L.StopsColor(s, 1)
    local r2, g2, b2 = L.StopsColor(s, 0)
    xp.cap:SetVertexColor(r1, g1, b1)
    if not (CreateColor and pcall(xp.fill.SetGradient, xp.fill, "HORIZONTAL",
            CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))) then
        xp.fill:SetVertexColor(r2, g2, b2)
    end
    xp.head:SetVertexColor(r2, g2, b2, .6)
    local a = L.theme.accent
    xp.rested:SetVertexColor(a[1], a[2], a[3], .35)
    xp.flash:SetVertexColor(a[1], a[2], a[3])
    if xp.width then L.XPText() end
end

function L.LayoutXP()
    if not xp or not L.bars[1] then return end
    local main = L.bars[1].header
    local w = math.floor(main:GetWidth() * main:GetScale() * .75 + .5)
    xp.width = w
    xp:SetWidth(w)
    for i, t in ipairs(xp.ticks) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", xp, "LEFT", w * i / 10, 0)
    end
    xp.flash:SetSize(w * 1.1, 60)
    L.DrawXP()
end

function L.DrawXP()
    if not xp or not xp.width then return end
    local inner = xp.width - H / 2
    local fillW = math.max(.1, inner * xp.shown)
    xp.fill:SetWidth(fillW)
    xp.fillW = fillW
    local hw = H * .9 -- half the glow's width
    local hx = L.Clamp(H / 2 + fillW, hw, xp.width - hw)
    xp.head:ClearAllPoints()
    xp.head:SetPoint("CENTER", xp, "LEFT", hx, 0)
    xp.head:SetShown(fillW > H * .5 and xp.shown < .995)
    local max = UnitXPMax("player")
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    local restW = (max > 0) and math.min(inner - fillW, inner * rest / max) or 0
    xp.rested:SetWidth(math.max(.1, restW))
    xp.rested:SetShown(restW > 1)
    if xp.shown == xp.target then xp:SetScript("OnUpdate", nil) end
end

-- The words under the bar.
function L.XPText()
    if not xp then return end
    local cur, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    local togo = math.max(0, max - cur)
    local pct = max > 0 and cur / max * 100 or 0
    local a = L.theme.accent
    local accent = hex(a[1], a[2], a[3])

    xp.lvl:SetText("|cff9aa3b5LV|r " .. lvl)
    xp.lvl:SetTextColor(1, 1, 1)
    xp.nextLvl:SetText("|cff6f7787LV " .. (lvl + 1) .. "|r")
    xp.main:SetText(string.format("|cffffffff%s|r |cffaab3c5to level|r  %s%.1f%%|r", num(togo), accent, pct))

    local parts = {}
    local avg = L.AvgKillXP()
    if avg and avg > 0 then parts[#parts + 1] = "≈ " .. math.ceil(togo / avg) .. " kills" end
    local rate = L.XPPerHour()
    if rate and rate > 0 then parts[#parts + 1] = "≈ " .. duration(togo / rate * 3600) end -- rate is per hour
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    if rest > 0 then parts[#parts + 1] = accent .. num(rest) .. " rested|r" end
    xp.sub:SetText("|cff8d96a8" .. table.concat(parts, "  ·  ") .. "|r")
end

local function wake()
    xp:SetScript("OnUpdate", function(self, elapsed)
        local d = self.target - self.shown
        if math.abs(d) < .0005 then self.shown = self.target
        else self.shown = self.shown + d * math.min(1, elapsed * 5) end
        L.DrawXP()
    end)
end

local function floatText(text)
    local fl = xp.floaters[xp.nextFloater]
    xp.nextFloater = xp.nextFloater % #xp.floaters + 1
    local a = L.theme.accent
    fl.text:SetText(text)
    fl.text:SetTextColor(a[1], a[2], a[3])
    fl:ClearAllPoints()
    fl:SetPoint("BOTTOM", xp, "LEFT", H / 2 + (xp.width - H / 2) * xp.target, 6)
    fl.anim:Stop()
    fl.anim:Play()
end

local function syncBlizzardXP(lumenShown)
    if L.UpdateBlizzardXP and L.blizzXPWanted ~= lumenShown then L.UpdateBlizzardXP(lumenShown) end
end

function L.UpdateXP(instant)
    if not xp then return end
    if xpHidden() then
        xp:Hide()
        syncBlizzardXP(false)
        return
    end
    xp:Show()
    syncBlizzardXP(true)
    local cur, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    local frac = max > 0 and cur / max or 0
    local gained = 0
    if lvl > (xp.lastLevel or lvl) then
        gained = (xp.lastMax or 0) - (xp.lastXP or 0) + cur
        xp.shown = 0
        xp.flashAnim:Stop(); xp.flashAnim:Play()
        floatText("Level " .. lvl .. "!")
    elseif cur > (xp.lastXP or cur) then
        gained = cur - xp.lastXP
        floatText("+" .. num(gained) .. " XP")
    end
    if gained > 0 then
        xp.sessionXP = xp.sessionXP + gained
        if gained <= max * .08 then -- kill-sized
            table.insert(xp.kills, gained)
            if #xp.kills > 10 then table.remove(xp.kills, 1) end
        end
    end
    xp.lastXP, xp.lastLevel, xp.lastMax = cur, lvl, max
    xp.target = frac
    if instant then xp.shown = frac end
    L.XPText()
    wake()
end
