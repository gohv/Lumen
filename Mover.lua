local _, L = ...

------------------------------------------------------------------------
-- Edit mode: every Lumen element registers here and gets a handle.
--   drag            move (snaps to the grid when it is on)
--   mouse wheel     resize that element
--   arrow keys      nudge 1px (Shift = 10px) while hovering
--   right-click     reset that element
-- Positions are stored as the element's center, relative to the bottom
-- center of the screen, in UIParent units: db.pos[key] = { x, y, scale }.
------------------------------------------------------------------------
L.movers = {}
L.pending = L.pending or {}
local GRID, SNAP = 32, 8

local function getPos(key)
    L.db.pos = L.db.pos or {}
    return L.db.pos[key]
end

local function ensurePos(key)
    L.db.pos = L.db.pos or {}
    L.db.pos[key] = L.db.pos[key] or {}
    return L.db.pos[key]
end

local function blocked(e)
    return e.secure and InCombatLockdown()
end

------------------------------------------------------------------------
-- Apply / sync
------------------------------------------------------------------------
function L.ApplyElement(e)
    if blocked(e) then L.pending.layout = true return end
    local f, p = e.frame, getPos(e.key)
    f:SetScale((e.baseScale and e.baseScale() or 1) * ((p and p.scale) or 1))
    f:ClearAllPoints()
    if p and p.x and p.y then
        local s = f:GetScale()
        f:SetPoint("CENTER", UIParent, "BOTTOM", p.x / s, p.y / s)
    else
        e.default(f)
    end
    if e.onApply then e.onApply() end
end

function L.SyncMover(e)
    local f, m = e.frame, e.mover
    if not m or m.dragging then return end
    local s = f:GetScale() or 1
    m:SetSize(math.max(48, (f:GetWidth() or 0) * s), math.max(18, (f:GetHeight() or 0) * s))
    local cx, cy = f:GetCenter()
    m:ClearAllPoints()
    if cx and cy then
        m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * s, cy * s)
    else
        m:SetPoint("CENTER")
    end
end

function L.SyncMovers()
    for _, e in ipairs(L.movers) do L.SyncMover(e) end
end

function L.ApplyAllElements()
    for _, e in ipairs(L.movers) do L.ApplyElement(e) end
    L.SyncMovers()
end

local function snap(v)
    if not L.db.grid then return math.floor(v + .5) end
    return math.floor(v / SNAP + .5) * SNAP
end

-- Store the element where its handle currently is.
local function saveFromMover(e, noSnap)
    local m = e.mover
    local cx, cy = m:GetCenter()
    if not cx then return end
    local p = ensurePos(e.key)
    local x, y = cx - (UIParent:GetWidth() or 0) / 2, cy
    if noSnap then p.x, p.y = math.floor(x + .5), math.floor(y + .5)
    else p.x, p.y = snap(x), snap(y) end
    L.ApplyElement(e)
    m.coords:SetText(string.format("%d, %d", p.x, p.y))
end

local function nudge(e, dx, dy)
    if blocked(e) then return end
    local p = getPos(e.key)
    if not (p and p.x) then saveFromMover(e, true); p = getPos(e.key) end
    if not (p and p.x) then return end
    p.x, p.y = p.x + dx, p.y + dy
    L.ApplyElement(e)
    L.SyncMovers()
    e.mover.coords:SetText(string.format("%d, %d", p.x, p.y))
end

local function resize(e, delta)
    if blocked(e) then return end
    local p = ensurePos(e.key)
    p.scale = L.Clamp(math.floor(((p.scale or 1) + delta * .05) * 100 + .5) / 100, .5, 2)
    L.ApplyElement(e)
    L.SyncMovers()
    e.mover.coords:SetText(string.format("size %d%%", p.scale * 100))
end

local function reset(e)
    if blocked(e) then return end
    L.db.pos[e.key] = nil
    L.ApplyElement(e)
    L.SyncMovers()
    e.mover.coords:SetText("reset")
end

------------------------------------------------------------------------
-- Handle widget
------------------------------------------------------------------------
local function edge(m, p1, p2, horiz)
    local t = m:CreateTexture(nil, "BORDER")
    t:SetPoint(p1); t:SetPoint(p2)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
    m.edges[#m.edges + 1] = t
end

local function paint(m, hot)
    local a = L.theme.accent
    m.bg:SetColorTexture(a[1], a[2], a[3], hot and .28 or .14)
    for _, t in ipairs(m.edges) do t:SetColorTexture(a[1], a[2], a[3], hot and 1 or .6) end
end

local function createMover(e)
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:RegisterForDrag("LeftButton")
    m:Hide()

    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.edges = {}
    edge(m, "TOPLEFT", "TOPRIGHT", true)
    edge(m, "BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge(m, "TOPLEFT", "BOTTOMLEFT", false)
    edge(m, "TOPRIGHT", "BOTTOMRIGHT", false)

    m.label = m:CreateFontString(nil, "OVERLAY")
    m.label:SetFont(L.FONT, 12, "OUTLINE")
    m.label:SetPoint("CENTER", 0, 5)
    m.label:SetText(e.label)
    m.coords = m:CreateFontString(nil, "OVERLAY")
    m.coords:SetFont(L.FONT, 10, "OUTLINE")
    m.coords:SetPoint("TOP", m.label, "BOTTOM", 0, -2)
    m.coords:SetTextColor(.75, .8, .9)

    m:SetScript("OnEnter", function(self)
        paint(self, true)
        self:EnableKeyboard(true)
        local p = getPos(e.key)
        self.coords:SetText(p and p.x and string.format("%d, %d", p.x, p.y) or "default position")
    end)
    m:SetScript("OnLeave", function(self)
        paint(self, false)
        self:EnableKeyboard(false)
        self.coords:SetText("")
    end)
    m:SetScript("OnKeyDown", function(self, key)
        local step = IsShiftKeyDown() and 10 or 1
        local dx, dy
        if key == "UP" then dy = step elseif key == "DOWN" then dy = -step
        elseif key == "LEFT" then dx = -step elseif key == "RIGHT" then dx = step end
        if dx or dy then
            pcall(self.SetPropagateKeyboardInput, self, false)
            nudge(e, dx or 0, dy or 0)
        else
            pcall(self.SetPropagateKeyboardInput, self, true)
        end
    end)
    m:SetScript("OnMouseWheel", function(_, delta) resize(e, delta) end)
    m:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then reset(e) end
    end)
    m:SetScript("OnDragStart", function(self)
        if blocked(e) then return end
        self.dragging = true
        self:StartMoving()
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = false
        saveFromMover(e)
        L.SyncMovers()
    end)
    m:SetScript("OnUpdate", function(self)
        if self.dragging then
            saveFromMover(e) -- element follows the handle live
            for _, other in ipairs(L.movers) do
                if other ~= e then L.SyncMover(other) end
            end
        end
    end)
    e.mover = m
end

-- e = { key, label, frame, default(frame), secure?, baseScale()?, onApply()? }
function L.RegisterMover(e)
    L.movers[#L.movers + 1] = e
    L.movers[e.key] = e
    createMover(e)
    L.ApplyElement(e)
end

------------------------------------------------------------------------
-- Grid
------------------------------------------------------------------------
local grid
local function showGrid(on)
    if on and not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
    end
    if not grid then return end
    if not on then grid:Hide() return end
    for _, t in ipairs(grid.lines) do t:Hide() end
    local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local a, n = L.theme.accent, 0
    local function line(vertical, off, center)
        n = n + 1
        local t = grid.lines[n]
        if not t then
            t = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[n] = t
        end
        t:ClearAllPoints()
        if vertical then
            t:SetPoint("TOP", grid, "TOP", off, 0); t:SetPoint("BOTTOM", grid, "BOTTOM", off, 0); t:SetWidth(1)
        else
            t:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, off); t:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, off); t:SetHeight(1)
        end
        if center then t:SetColorTexture(a[1], a[2], a[3], .45) else t:SetColorTexture(1, 1, 1, .07) end
        t:Show()
    end
    for i = 0, math.floor(w / 2 / GRID) do
        line(true, i * GRID, i == 0)
        if i > 0 then line(true, -i * GRID) end
    end
    for i = 0, math.floor(h / GRID) do line(false, i * GRID) end
    line(false, h / 2, true)
    grid:Show()
end

------------------------------------------------------------------------
-- Control panel
------------------------------------------------------------------------
local panel

local function flatButton(parent, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, .08)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont(L.FONT, 11, "")
    b.text:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        local a = L.theme.accent
        self.bg:SetColorTexture(a[1], a[2], a[3], .35)
    end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, .08) end)
    b:SetScript("OnClick", onClick)
    return b
end

local THEME_ORDER = { "aurora", "ember", "frost", "neon", "verdant" }

local function refreshPanel()
    if not panel then return end
    local a = L.theme.accent
    panel.line:SetColorTexture(a[1], a[2], a[3], .9)
    panel.title:SetTextColor(a[1], a[2], a[3])
    panel.grid.text:SetText("Grid: " .. (L.db.grid and "on" or "off"))
    panel.layout.text:SetText(L.db.layout == "arc" and "Shape: arc" or "Shape: line")
    panel.theme.text:SetText("Theme: " .. L.theme.name)
    for _, e in ipairs(L.movers) do paint(e.mover, false) end
end

local function createPanel()
    panel = CreateFrame("Frame", "LumenEditPanel", UIParent)
    panel:SetSize(470, 78)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -110)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.04, .05, .08, .92)
    panel.line = panel:CreateTexture(nil, "BORDER")
    panel.line:SetPoint("TOPLEFT"); panel.line:SetPoint("TOPRIGHT"); panel.line:SetHeight(2)

    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetFont(L.FONT, 13, "OUTLINE")
    panel.title:SetPoint("TOPLEFT", 10, -8)
    panel.title:SetText("Lumen · edit mode")
    local hint = panel:CreateFontString(nil, "OVERLAY")
    hint:SetFont(L.FONT, 10, "")
    hint:SetPoint("TOPRIGHT", -10, -10)
    hint:SetTextColor(.7, .74, .82)
    hint:SetText("drag · wheel = size · arrows = nudge · right-click = reset")

    local x = 10
    local function add(w, fn)
        local b = flatButton(panel, w, fn)
        b:SetPoint("BOTTOMLEFT", x, 10)
        x = x + w + 6
        return b
    end
    panel.grid = add(76, function()
        L.db.grid = not L.db.grid
        showGrid(L.db.grid)
        refreshPanel()
    end)
    panel.layout = add(86, function()
        if InCombatLockdown() then return end
        L.db.layout = (L.db.layout == "arc") and "line" or "arc"
        L.RelayoutAll()
        refreshPanel()
    end)
    panel.theme = add(112, function()
        local cur = 1
        for i, n in ipairs(THEME_ORDER) do if n == L.db.theme then cur = i end end
        L.ApplyTheme(THEME_ORDER[cur % #THEME_ORDER + 1])
        if L.db.grid then showGrid(true) end
        refreshPanel()
    end)
    panel.reset = add(76, function()
        if InCombatLockdown() then return end
        L.db.pos = {}
        L.ApplyAllElements()
    end)
    panel.done = add(76, function() L.SetUnlocked(false) end)
    panel.done.text:SetText("Done")
    panel.reset.text:SetText("Reset all")
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function L.SetUnlocked(on)
    if on and InCombatLockdown() then L.Print("can't edit the layout in combat.") return end
    on = on and true or false
    if on == (L.unlocked and true or false) then return end
    L.unlocked = on
    if on and not panel then createPanel() end
    if panel then panel:SetShown(on) end
    showGrid(on and L.db.grid)
    for _, e in ipairs(L.movers) do
        if on then L.SyncMover(e) end
        e.mover:SetShown(on)
        if not on then e.mover:EnableKeyboard(false) end
    end
    if on then refreshPanel() end
    if L.SetPulsePreview then L.SetPulsePreview(on) end
    if L.Target and L.Target.SetPreview then L.Target.SetPreview(on) end
    if L.UpdateXP then L.UpdateXP(true) end
    for _, b in ipairs(L.buttons) do L.Button.ApplyAlpha(b) end
    L.UpdateAllBarAlpha()
    if on then L.SyncMovers() end
end

-- Blizzard Edit Mode opens/closes Lumen's edit mode too.
function L.HookEditMode()
    local em = EditModeManagerFrame
    if not (em and hooksecurefunc) then return end
    if em.EnterEditMode then
        hooksecurefunc(em, "EnterEditMode", function()
            if not InCombatLockdown() then L.SetUnlocked(true) end
        end)
    end
    if em.ExitEditMode then
        hooksecurefunc(em, "ExitEditMode", function() L.SetUnlocked(false) end)
    end
end
