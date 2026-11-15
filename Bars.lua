local _, L = ...

L.bars = {}
L.pending = L.pending or {}

-- Three nested curved bars. Bar 1 pages like the default main bar; bars 2/3
-- reuse the Bottom Left (61-72) and Bottom Right (49-60) slots and keybinds.
L.BAR_DEFS = {
    { size = 46, gap = 8, arc = 20, binding = "ACTIONBUTTON",          paged = true, fade = false, y = 46 },
    { size = 38, gap = 7, arc = 16, binding = "MULTIACTIONBAR1BUTTON", first = 61,   fade = true,  y = 112 },
    { size = 32, gap = 6, arc = 12, binding = "MULTIACTIONBAR2BUTTON", first = 49,   fade = true,  y = 164 },
}

local BAR_LABELS = { "Main bar", "Bar 2  (Bottom Left keybinds)", "Bar 3  (Bottom Right keybinds)" }

local function pageCondition()
    local c = {}
    local function add(cond, page)
        if type(page) == "number" and page > 0 then c[#c + 1] = cond .. page end
    end
    if GetOverrideBarIndex then add("[overridebar]", GetOverrideBarIndex()) end
    if GetVehicleBarIndex then
        add("[vehicleui]", GetVehicleBarIndex())
        add("[possessbar]", GetVehicleBarIndex())
    end
    if GetTempShapeshiftBarIndex then add("[shapeshift]", GetTempShapeshiftBarIndex()) end
    for i = 2, 6 do c[#c + 1] = "[bar:" .. i .. "]" .. i end           -- manual paging wins
    for i = 5, 1, -1 do c[#c + 1] = "[bonusbar:" .. i .. "]" .. (6 + i) end -- stances / forms / stealth
    c[#c + 1] = "1"
    return table.concat(c, ";")
end

------------------------------------------------------------------------
-- Layout / position
------------------------------------------------------------------------
function L.LayoutBar(bar)
    if InCombatLockdown() then L.pending.layout = true return end
    local d = bar.def
    local step = d.size + d.gap
    local arc = (L.db.layout == "arc") and d.arc or 0
    local n = #bar.buttons
    local half = (n - 1) / 2 * step
    bar.header:SetSize(n * step - d.gap, d.size + arc)
    for i, b in ipairs(bar.buttons) do
        local x = (i - 1) * step - half
        local t = half > 0 and x / half or 0
        b:ClearAllPoints()
        b:SetPoint("BOTTOM", bar.header, "BOTTOM", x, arc * t * t) -- a gentle smile
    end
    if bar.id == 1 and L.LayoutXP then L.LayoutXP() end
end

-- Re-layout bars, then re-apply every element's position and size.
function L.RelayoutAll()
    if InCombatLockdown() then L.pending.layout = true return end
    for _, bar in ipairs(L.bars) do L.LayoutBar(bar) end
    L.ApplyAllElements()
end

------------------------------------------------------------------------
-- Fading
------------------------------------------------------------------------
local function setBarAlpha(bar, a)
    bar.alpha = a
    for _, b in ipairs(bar.buttons) do L.Button.ApplyAlpha(b) end
end

function L.UpdateBarAlpha(bar, instant)
    local target = 1
    if bar.def.fade and L.db.fade and not (L.inCombat or bar.hover > 0 or L.showGrid or L.unlocked) then
        target = L.db.fadeAlpha
    end
    L.Tween(bar, bar.alpha, target, instant and 0 or .4, setBarAlpha)
end

function L.UpdateAllBarAlpha(instant)
    for _, bar in ipairs(L.bars) do L.UpdateBarAlpha(bar, instant) end
end

------------------------------------------------------------------------
-- Dock magnifier (macOS style): icons near the cursor grow and lift, and
-- their neighbours slide apart so nothing overlaps. Only the unprotected
-- visual layer moves, so it works in combat too.
------------------------------------------------------------------------
local function dockFrame(bar)
    local d = bar.def
    local step = d.size + d.gap
    local n = #bar.buttons
    local cur = {}           -- current scale / dx / dy per button (smoothed)
    for i = 1, n do cur[i] = { s = 1, dx = 0, dy = 0 } end
    local f = CreateFrame("Frame", nil, bar.header)
    f:Hide()
    local tgt, w, base = {}, {}, {}

    f:SetScript("OnUpdate", function(self, elapsed)
        local M = L.db.magnifyScale or 1.6
        local radius = step * 2.4
        local hovering = L.db.magnify and not L.unlocked and L.activeDock == bar and bar.header:IsVisible()
            and bar.header:IsMouseOver(d.size * .8, -d.size * .4, -step * .6, step * .6)
        local cx
        if hovering then
            local x = GetCursorPosition()
            cx = x / bar.header:GetEffectiveScale()
        end

        -- target scales
        for i, b in ipairs(bar.buttons) do
            local bx = b:GetCenter()
            base[i] = bx or 0
            local s = 1
            if cx and bx then
                local dist = math.abs(cx - bx)
                if dist < radius then s = 1 + (M - 1) * (math.cos(dist / radius * math.pi) + 1) / 2 end
            end
            tgt[i] = s
            w[i] = d.size * s + d.gap
        end

        -- lay the magnified icons out so the point under the cursor stays put
        local shift = {}
        if cx and base[1] then
            local u = L.Clamp((cx - base[1]) / step + .5, 0, n)       -- cursor in "icon units"
            local k = math.min(n, math.floor(u) + 1)
            local frac = u - (k - 1)
            local left = 0
            for j = 1, k - 1 do left = left + w[j] end
            local pNew = left + frac * w[k]
            local origin = (base[1] - step / 2) + (u * step - pNew)    -- new left edge of icon 1
            local x = origin
            for i = 1, n do
                shift[i] = (x + w[i] / 2) - base[i]
                x = x + w[i]
            end
        end

        -- ease toward targets
        local k = math.min(1, elapsed * 14)
        local moving = false
        for i, b in ipairs(bar.buttons) do
            local c = cur[i]
            local ts, tdx = tgt[i], shift[i] or 0
            local tdy = (ts - 1) * d.size * .5           -- grow upward like the dock
            c.s = c.s + (ts - c.s) * k
            c.dx = c.dx + (tdx - c.dx) * k
            c.dy = c.dy + (tdy - c.dy) * k
            if math.abs(ts - c.s) > .002 or math.abs(tdx - c.dx) > .2 then moving = true end
            local v = b.visual
            v:SetScale(c.s)
            v:ClearAllPoints()
            v:SetPoint("CENTER", b, "CENTER", c.dx / c.s, c.dy / c.s)
        end
        if not hovering and not moving then
            for i, b in ipairs(bar.buttons) do
                cur[i].s, cur[i].dx, cur[i].dy = 1, 0, 0
                b.visual:SetScale(1)
                b.visual:ClearAllPoints()
                b.visual:SetPoint("CENTER", b, "CENTER", 0, 0)
            end
            self:Hide()
        end
    end)
    bar.dock = f
end

function L.BarHover(bar, entering)
    if entering then L.activeDock = bar end
    if entering and bar.dock and L.db.magnify then bar.dock:Show() end
    if entering then
        bar.hover = bar.hover + 1
        L.UpdateBarAlpha(bar)
    else
        bar.hover = math.max(0, bar.hover - 1)
        C_Timer.After(.3, function() L.UpdateBarAlpha(bar) end)
    end
end

------------------------------------------------------------------------
-- Keybinds: the default ACTIONBUTTON / MULTIACTIONBAR binds click our buttons
------------------------------------------------------------------------
L.bindOwner = CreateFrame("Frame")

function L.UpdateBindings()
    if InCombatLockdown() then L.pending.bindings = true return end
    ClearOverrideBindings(L.bindOwner)
    for _, bar in ipairs(L.bars) do
        for _, b in ipairs(bar.buttons) do
            for _, key in ipairs({ GetBindingKey(b.bindingCmd) }) do
                if key and key ~= "" then
                    SetOverrideBindingClick(L.bindOwner, false, key, b:GetName(), "LeftButton")
                end
            end
            L.Button.UpdateHotkey(b)
        end
    end
end

------------------------------------------------------------------------
-- Creation (out of combat only)
------------------------------------------------------------------------
function L.CreateBar(id, def)
    local header = CreateFrame("Frame", "LumenBar" .. id, UIParent, "SecureHandlerStateTemplate")
    header:SetMovable(true)
    header:SetClampedToScreen(true)
    local bar = { id = id, def = def, header = header, buttons = {}, alpha = 1, hover = 0 }
    L.bars[id] = bar

    for i = 1, 12 do
        local b = L.Button.Create(bar, i)
        bar.buttons[i] = b
        header:SetFrameRef("b" .. i, b)
    end
    for i, b in ipairs(bar.buttons) do
        b:SetAttribute("action", def.paged and i or (def.first + i - 1))
    end

    if def.paged then
        header:SetAttribute("_onstate-page", [[
            local page = tonumber(newstate) or 1
            for i = 1, 12 do
                local b = self:GetFrameRef("b" .. i)
                if b then b:SetAttribute("action", (page - 1) * 12 + i) end
            end
        ]])
        RegisterStateDriver(header, "page", pageCondition())
        RegisterStateDriver(header, "visibility", "[petbattle] hide; show")
    else
        RegisterStateDriver(header, "visibility", "[petbattle][vehicleui][overridebar][possessbar] hide; show")
    end

    L.LayoutBar(bar)
    dockFrame(bar)
    L.RegisterMover({
        key = "bar" .. id,
        label = BAR_LABELS[id],
        frame = header,
        secure = true,
        baseScale = function() return L.db.scale end,
        default = function(f) f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, def.y) end,
        onApply = id == 1 and function() if L.LayoutXP then L.LayoutXP() end end or nil,
    })
    return bar
end
