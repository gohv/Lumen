local ADDON, L = ...
Lumen = L -- handy for /dump Lumen.db

L.MEDIA = "Interface\\AddOns\\Lumen\\Media\\"
L.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
L.NUMFONT = L.MEDIA .. "Fonts\\Rajdhani-SemiBold.ttf" -- SIL OFL, see Media/Fonts
L.WHITE = "Interface\\Buttons\\WHITE8X8"

------------------------------------------------------------------------
-- Secret-value helpers (Forever runs the Midnight engine: in combat many
-- numbers come back as "secret" and cannot be compared or branched on).
------------------------------------------------------------------------
local issecretvalue = issecretvalue

function L.secret(v)
    if issecretvalue and issecretvalue(v) then return true end
    return false
end

-- Returns v when it is safe to inspect, nil when it is secret.
function L.plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Prefer the C_ActionBar namespace, fall back to the legacy global.
function L.api(name)
    local ns = C_ActionBar
    return (ns and ns[name]) or _G[name]
end

-- pcall wrapper that returns up to four results, or nothing on failure.
function L.call(f, ...)
    if not f then return end
    local ok, a, b, c, d = pcall(f, ...)
    if ok then return a, b, c, d end
end

function L.Print(...)
    print("|cffb48cffLumen|r:", ...)
end

function L.Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

------------------------------------------------------------------------
-- Color stops / curves
------------------------------------------------------------------------
-- stops = { {x, r, g, b}, ... } with ascending x in 0..1
function L.StopsColor(stops, x)
    local first = stops[1]
    if x <= first[1] then return first[2], first[3], first[4] end
    for i = 2, #stops do
        local s = stops[i]
        if x <= s[1] then
            local p = stops[i - 1]
            local t = (x - p[1]) / (s[1] - p[1])
            return p[2] + (s[2] - p[2]) * t, p[3] + (s[3] - p[3]) * t, p[4] + (s[4] - p[4]) * t
        end
    end
    local last = stops[#stops]
    return last[2], last[3], last[4]
end

-- Native color curve: lets the client color a cooldown by its remaining
-- percent even when the cooldown itself is secret.
function L.BuildCurve(stops)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return nil end
    if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
        pcall(curve.SetType, curve, Enum.LuaCurveType.Linear)
    end
    for _, s in ipairs(stops) do
        if not pcall(curve.AddPoint, curve, s[1], CreateColor(s[2], s[3], s[4], 1)) then return nil end
    end
    return curve
end

------------------------------------------------------------------------
-- Tiny tween engine (ease-out quad)
------------------------------------------------------------------------
local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
    for key, tw in pairs(tweens) do
        tw.t = tw.t + elapsed
        local p = tw.t >= tw.dur and 1 or tw.t / tw.dur
        p = 1 - (1 - p) * (1 - p)
        tw.set(key, tw.from + (tw.to - tw.from) * p)
        if tw.t >= tw.dur then tweens[key] = nil end
    end
    if not next(tweens) then self:Hide() end
end)

function L.Tween(key, from, to, dur, set)
    if not dur or dur <= 0 or math.abs(to - from) < 0.005 then
        tweens[key] = nil
        set(key, to)
        return
    end
    tweens[key] = { from = from, to = to, t = 0, dur = dur, set = set }
    driver:Show()
end

local function setAlpha(region, a) region:SetAlpha(a) end
function L.FadeTo(region, to, dur)
    L.Tween(region, region:GetAlpha() or 0, to, dur or 0.2, setAlpha)
end

------------------------------------------------------------------------
-- Animation helper: one group with optional scale + alpha
------------------------------------------------------------------------
function L.Anim(region, spec)
    local g = region:CreateAnimationGroup()
    local d = spec.dur or 0.4
    local smooth = spec.smooth or "OUT"
    if spec.scaleFrom then
        local s = g:CreateAnimation("Scale")
        if s.SetScaleFrom then
            s:SetScaleFrom(spec.scaleFrom, spec.scaleFrom)
            s:SetScaleTo(spec.scaleTo, spec.scaleTo)
        else
            s:SetFromScale(spec.scaleFrom, spec.scaleFrom)
            s:SetToScale(spec.scaleTo, spec.scaleTo)
        end
        s:SetDuration(d)
        s:SetSmoothing(smooth)
        s:SetOrigin("CENTER", 0, 0)
        if spec.order then s:SetOrder(spec.order) end
    end
    if spec.alphaFrom then
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(spec.alphaFrom)
        a:SetToAlpha(spec.alphaTo)
        a:SetDuration(d)
        a:SetSmoothing(smooth)
        if spec.order then a:SetOrder(spec.order) end
    end
    return g
end

-- Masked circular icon
function L.RoundIcon(parent, size, layer, sub)
    local icon = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    icon:SetSize(size, size)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(L.MEDIA .. "circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    return icon
end
