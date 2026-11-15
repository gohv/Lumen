local _, L = ...
local M = L.MEDIA

------------------------------------------------------------------------
-- Options window (/lumen). Pages on the left, controls on the right.
-- Everything applies live; things that touch secure frames are refused in
-- combat (the control snaps back and a note is shown).
------------------------------------------------------------------------
local O = {}
L.Options = O

local WIN_W, WIN_H, NAV_W, PAD = 660, 500, 156, 18
local CONTENT_W = WIN_W - NAV_W - PAD * 2
local win
local repaint = {}   -- callbacks run when the theme changes
local refreshers = {} -- callbacks run when the window opens

local function accent() return L.theme.accent end

local function font(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not fs:SetFont(L.NUMFONT, size, "") then fs:SetFont(L.FONT, size * .9, "") end
    fs:SetShadowColor(0, 0, 0, .8)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function rect(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a)
    return t
end

-- pill made from two half circles + a middle
local function pill(parent, layer, sub)
    local p = {}
    p.l = parent:CreateTexture(nil, layer, nil, sub)
    p.l:SetTexture(M .. "circle"); p.l:SetTexCoord(0, .5, 0, 1)
    p.r = parent:CreateTexture(nil, layer, nil, sub)
    p.r:SetTexture(M .. "circle"); p.r:SetTexCoord(.5, 1, 0, 1)
    p.m = parent:CreateTexture(nil, layer, nil, sub)
    p.m:SetTexture(L.WHITE)
    function p:Place(frame, h)
        self.l:SetPoint("TOPLEFT", frame); self.l:SetPoint("BOTTOMLEFT", frame); self.l:SetWidth(h / 2)
        self.r:SetPoint("TOPRIGHT", frame); self.r:SetPoint("BOTTOMRIGHT", frame); self.r:SetWidth(h / 2)
        self.m:SetPoint("TOPLEFT", self.l, "TOPRIGHT"); self.m:SetPoint("BOTTOMRIGHT", self.r, "BOTTOMLEFT")
    end
    function p:Color(r, g, b, a)
        for _, t in ipairs({ self.l, self.m, self.r }) do t:SetVertexColor(r, g, b, a or 1) end
    end
    return p
end

local function note(msg)
    if not win then return end
    win.note:SetText(msg)
    win.noteAnim:Stop(); win.noteAnim:Play()
end

local function combatBlocked()
    if InCombatLockdown() then
        note("That one can only change out of combat.")
        return true
    end
end

------------------------------------------------------------------------
-- Widgets. Each takes (page, ...) and stacks under the previous one.
------------------------------------------------------------------------
local function place(page, w, h)
    w:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y)
    page.y = page.y + h
end

local function Header(page, text, sub)
    local h = CreateFrame("Frame", nil, page)
    h:SetSize(CONTENT_W, sub and 46 or 30)
    local t = font(h, 20)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(text)
    if sub then
        local s = font(h, 13, .62, .67, .78)
        s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        s:SetWidth(CONTENT_W)
        s:SetText(sub)
    end
    place(page, h, sub and 50 or 34)
end

-- On/off switch row. apply(value) may return false to refuse the change.
local function Toggle(page, label, desc, key, apply)
    local row = CreateFrame("Button", nil, page)
    local h = desc and 40 or 28
    row:SetSize(CONTENT_W, h)
    local t = font(row, 15)
    t:SetPoint("TOPLEFT", 0, desc and -2 or -6)
    t:SetText(label)
    if desc then
        local d = font(row, 12, .58, .63, .74)
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -1)
        d:SetWidth(CONTENT_W - 60)
        d:SetText(desc)
    end
    local sw = CreateFrame("Frame", nil, row)
    sw:SetSize(38, 20)
    sw:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local track = pill(sw, "ARTWORK", 0)
    track:Place(sw, 20)
    local knob = sw:CreateTexture(nil, "ARTWORK", nil, 2)
    knob:SetTexture(M .. "circle")
    knob:SetSize(16, 16)
    row.knobX = 2

    local function setKnob(_, x)
        row.knobX = x
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", sw, "LEFT", x, 0)
    end
    function row:Refresh(animate)
        local on = L.db[key] and true or false
        local a = accent()
        if on then track:Color(a[1], a[2], a[3], .95) else track:Color(.22, .24, .3, 1) end
        knob:SetVertexColor(on and 1 or .78, on and 1 or .8, on and 1 or .86)
        L.Tween(row, row.knobX, on and 20 or 2, animate and .15 or 0, setKnob)
    end
    row:SetScript("OnClick", function()
        local old = L.db[key]
        L.db[key] = not old
        if apply and apply(L.db[key]) == false then L.db[key] = old end
        row:Refresh(true)
        if O.onChange then O.onChange() end
    end)
    row:SetScript("OnEnter", function() t:SetTextColor(accent()[1], accent()[2], accent()[3]) end)
    row:SetScript("OnLeave", function() t:SetTextColor(1, 1, 1) end)
    repaint[#repaint + 1] = function() row:Refresh() end
    refreshers[#refreshers + 1] = function() row:Refresh() end
    place(page, row, h + 8)
    return row
end

local function Slider(page, label, key, min, max, step, fmt, apply)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(CONTENT_W, 44)
    local t = font(row, 15)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(label)
    local val = font(row, 15)
    val:SetPoint("TOPRIGHT", 0, 0)
    val:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(CONTENT_W - 8, 18)
    s:SetPoint("TOPLEFT", 4, -22)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(M .. "circle")
    thumb:SetSize(16, 16)
    s:SetThumbTexture(thumb)
    local track = rect(s, "BACKGROUND", .2, .22, .28, 1)
    track:SetHeight(4)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    local fillT = s:CreateTexture(nil, "BORDER")
    fillT:SetTexture(L.WHITE)
    fillT:SetHeight(4)
    fillT:SetPoint("LEFT", track, "LEFT")
    fillT:SetPoint("RIGHT", thumb, "CENTER")

    local busy = false
    local function show(v)
        val:SetText(fmt and fmt(v) or tostring(v))
    end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + .5) * step
        show(v)
        if busy then return end
        local old = L.db[key]
        if old == v then return end
        L.db[key] = v
        if apply and apply(v) == false then
            L.db[key] = old
            busy = true; s:SetValue(old); busy = false
            show(old)
        end
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(_, d) s:SetValue(L.Clamp((L.db[key] or min) + d * step, min, max)) end)
    function row:Refresh()
        local a = accent()
        fillT:SetVertexColor(a[1], a[2], a[3], 1)
        thumb:SetVertexColor(1, 1, 1)
        busy = true; s:SetValue(L.db[key] or min); busy = false
        show(L.db[key] or min)
    end
    repaint[#repaint + 1] = function() row:Refresh() end
    refreshers[#refreshers + 1] = function() row:Refresh() end
    place(page, row, 54)
    return row
end

-- Segmented choice: { {value, text}, ... }
local function Choice(page, label, key, choices, apply)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(CONTENT_W, 50)
    local t = font(row, 15)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(label)
    local btns, x = {}, 0
    for _, c in ipairs(choices) do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(96, 24)
        b:SetPoint("TOPLEFT", x, -22)
        x = x + 102
        b.bg = pill(b, "BACKGROUND", 0)
        b.bg:Place(b, 24)
        b.text = font(b, 14)
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        b.text:SetText(c[2])
        b.value = c[1]
        b:SetScript("OnClick", function()
            local old = L.db[key]
            L.db[key] = b.value
            if apply and apply(b.value) == false then L.db[key] = old end
            row:Refresh()
        end)
        btns[#btns + 1] = b
    end
    function row:Refresh()
        local a = accent()
        for _, b in ipairs(btns) do
            if L.db[key] == b.value then
                b.bg:Color(a[1], a[2], a[3], .95); b.text:SetTextColor(.05, .06, .09)
            else
                b.bg:Color(1, 1, 1, .08); b.text:SetTextColor(.85, .88, .95)
            end
        end
    end
    repaint[#repaint + 1] = function() row:Refresh() end
    refreshers[#refreshers + 1] = function() row:Refresh() end
    place(page, row, 58)
end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 28)
    b.bg = pill(b, "BACKGROUND", 0)
    b.bg:Place(b, 28)
    b.bg:Color(1, 1, 1, .08)
    b.text = font(b, 14)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function()
        local a = accent()
        b.bg:Color(a[1], a[2], a[3], .9); b.text:SetTextColor(.05, .06, .09)
    end)
    b:SetScript("OnLeave", function() b.bg:Color(1, 1, 1, .08); b.text:SetTextColor(1, 1, 1) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function ButtonRow(page, list)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(CONTENT_W, 32)
    local x = 0
    for _, item in ipairs(list) do
        local w = item[3] or 140
        local b = Button(row, item[1], w, item[2])
        b:SetPoint("TOPLEFT", x, 0)
        x = x + w + 8
    end
    place(page, row, 40)
end

local THEMES = { "aurora", "ember", "frost", "neon", "verdant" }
local function ThemePicker(page)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(CONTENT_W, 92)
    local sw = {}
    local w = math.floor((CONTENT_W - 4 * 8) / 5)
    for i, name in ipairs(THEMES) do
        local th = L.themes[name]
        local b = CreateFrame("Button", nil, row)
        b:SetSize(w, 84)
        b:SetPoint("TOPLEFT", (i - 1) * (w + 8), 0)
        b.bg = rect(b, "BACKGROUND", 1, 1, 1, .05)
        b.bg:SetAllPoints()
        -- preview: the cooldown gradient on a little ring + a bar
        local ring = b:CreateTexture(nil, "ARTWORK")
        ring:SetTexture(M .. "ring_bold")
        ring:SetSize(36, 36)
        ring:SetPoint("TOP", 0, -8)
        local r1, g1, b1 = L.StopsColor(th.stops, 1)
        local r2, g2, b2 = L.StopsColor(th.stops, 0)
        ring:SetVertexColor(L.StopsColor(th.stops, .5))
        local bar = b:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(L.WHITE)
        bar:SetSize(w - 20, 5)
        bar:SetPoint("TOP", ring, "BOTTOM", 0, -6)
        if not (CreateColor and pcall(bar.SetGradient, bar, "HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))) then
            bar:SetVertexColor(r2, g2, b2)
        end
        local label = font(b, 13)
        label:SetPoint("BOTTOM", 0, 7)
        label:SetJustifyH("CENTER")
        label:SetText(th.name)
        b.edge = b:CreateTexture(nil, "BORDER")
        b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetPoint("BOTTOMRIGHT"); b.edge:SetHeight(2)
        b.name = name
        b:SetScript("OnClick", function()
            L.ApplyTheme(name)
            O.Repaint()
        end)
        sw[i] = b
    end
    function row:Refresh()
        for _, b in ipairs(sw) do
            local sel = L.db.theme == b.name
            local a = L.themes[b.name].accent
            b.edge:SetColorTexture(a[1], a[2], a[3], sel and 1 or 0)
            b.bg:SetColorTexture(1, 1, 1, sel and .12 or .04)
        end
    end
    repaint[#repaint + 1] = function() row:Refresh() end
    refreshers[#refreshers + 1] = function() row:Refresh() end
    place(page, row, 100)
end

------------------------------------------------------------------------
-- Appliers
------------------------------------------------------------------------
local function relayout()
    if combatBlocked() then return false end
    L.RelayoutAll()
end
local function forButtons(fn) return function() for _, b in ipairs(L.buttons) do fn(b) end end end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local PAGES = {
    { "Look", function(p)
        Header(p, "Look", "Pick a theme. It colors cooldown rings, glows, the XP bar and this window.")
        ThemePicker(p)
        Slider(p, "Bar size", "scale", .6, 1.6, .05, function(v) return math.floor(v * 100 + .5) .. "%" end, relayout)
        Choice(p, "Bar shape", "layout", { { "arc", "Arc" }, { "line", "Straight" } }, relayout)
    end },
    { "Action bars", function(p)
        Header(p, "Action bars")
        Toggle(p, "Dock magnify", "Icons grow under the cursor, like the macOS dock.", "magnify")
        Slider(p, "Magnify strength", "magnifyScale", 1.1, 2.2, .05, function(v) return string.format("%.2fx", v) end)
        Toggle(p, "Keybind labels", nil, "hotkeys", forButtons(L.Button.UpdateHotkey))
        Toggle(p, "Cooldown numbers", nil, "numbers", function(v)
            if v then pcall(SetCVar, "countdownForCooldowns", "1") end
            L.dirty.cd = true
        end)
        Toggle(p, "Show empty slots", "Faint glass sockets where no ability is placed.", "sockets", forButtons(L.Button.ApplyAlpha))
        Toggle(p, "Fade upper bars out of combat", nil, "fade", function() L.UpdateAllBarAlpha() end)
        Slider(p, "Faded opacity", "fadeAlpha", .1, 1, .05, function(v) return math.floor(v * 100 + .5) .. "%" end,
            function() L.UpdateAllBarAlpha() end)
    end },
    { "Cooldowns", function(p)
        Header(p, "Cooldowns", "The ring around each button changes color as the cooldown runs out.")
        Toggle(p, "Ready pulse", "A long cooldown coming back pops up in the middle of the screen.", "pulse")
        Slider(p, "Only for cooldowns longer than", "pulseMin", 2, 60, 1, function(v) return v .. " sec" end)
        ButtonRow(p, { { "Preview animations", function() L.Demo() end, 180 } })
    end },
    { "Avatar", function(p)
        Header(p, "Avatar", "Your character, alive in a glass orb. Mouse wheel on it zooms; left-click targets you.")
        Toggle(p, "Living avatar", nil, "avatar", function(v)
            if combatBlocked() then return false end
            L.Avatar.SetEnabled(v); L.UpdateCastBars(); L.UpdateAuraRings()
        end)
        Slider(p, "Zoom", "avatarZoom", 0, 1, .05, function(v)
            return v <= .05 and "full body" or v >= .95 and "face" or math.floor(v * 100 + .5) .. "%"
        end, function() if L.Avatar.ApplyZoom then L.Avatar.ApplyZoom() end end)
        Toggle(p, "Hide Blizzard player frame", "The avatar shows health, mana and the menu instead.", "hidePlayerFrame",
            function() if combatBlocked() then return false end L.UpdatePlayerFrame() end)
        ButtonRow(p, { { "Play avatar demo", function() L.Avatar.Demo() end, 170 } })
    end },
    { "Target", function(p)
        Header(p, "Target", "A mirror orb for whatever you target: health, glow by reaction, elite ring.")
        Toggle(p, "Target orb", nil, "target", function(v)
            if combatBlocked() then return false end
            L.Target.SetEnabled(v); L.UpdateAuraRings()
        end)
        Slider(p, "Zoom", "targetZoom", 0, 1, .05, function(v)
            return v <= .05 and "full body" or v >= .95 and "face" or math.floor(v * 100 + .5) .. "%"
        end, function() L.Target.ApplyZoom() end)
        Toggle(p, "Hide Blizzard target frame", "Combo points move next to the target orb.", "hideTargetFrame",
            function() if combatBlocked() then return false end L.UpdateTargetFrame() end)
    end },
    { "Casts & auras", function(p)
        Header(p, "Casts & auras")
        Toggle(p, "Cast arc on your avatar", "Fills around the orb while you cast.", "castArc", function()
            if combatBlocked() then return false end L.UpdateCastArcs() end)
        Toggle(p, "Cast arc on your target", "Red = you can interrupt it, grey = you can't.", "targetCast", function()
            L.UpdateCastArcs() end)
        Toggle(p, "Hide Blizzard cast bar", nil, "hideCastBar", function()
            if combatBlocked() then return false end L.UpdateCastBars() end)
        Toggle(p, "Buff bubbles on your avatar", "Your buffs float over the orb, debuffs on the side.", "auras",
            function() L.UpdateAuraRings() end)
        Toggle(p, "Aura bubbles on your target", "Your debuffs on enemies; buffs on friends.", "targetAuras",
            function() L.UpdateAuraRings() end)
    end },
    { "XP bar", function(p)
        Header(p, "XP bar", "Shows XP to level, percent, kills and time to level, and rested XP.")
        Toggle(p, "Show XP bar", "Blizzard's XP bar is hidden while this one is on.", "xp", function() L.UpdateXP(true) end)
    end },
    { "Layout", function(p)
        Header(p, "Layout", "Move and resize everything: drag, mouse wheel to resize, arrows to nudge.")
        ButtonRow(p, {
            { "Edit layout", function() O.Hide(); L.SetUnlocked(true) end, 150 },
            { "Reset positions", function()
                if combatBlocked() then return end
                L.db.pos = {}; L.RelayoutAll(); note("Everything is back in its default place.")
            end, 160 },
        })
        Toggle(p, "Snap to grid while editing", nil, "grid")
        Toggle(p, "Hide Blizzard action bars", "Needs a UI reload to change.", "hideBlizzard", function()
            win.reload:Show()
        end)
    end },
}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function build()
    win = CreateFrame("Frame", "LumenOptions", UIParent)
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    tinsert(UISpecialFrames, "LumenOptions") -- Esc closes it

    local shadow = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(M .. "shadow")
    shadow:SetPoint("TOPLEFT", -40, 40); shadow:SetPoint("BOTTOMRIGHT", 40, -40)
    shadow:SetVertexColor(0, 0, 0, .9)
    local bg = rect(win, "BACKGROUND", .045, .05, .075, .97)
    bg:SetAllPoints()
    local nav = rect(win, "BACKGROUND", .03, .035, .055, 1)
    nav:SetPoint("TOPLEFT"); nav:SetPoint("BOTTOMLEFT"); nav:SetWidth(NAV_W)
    nav:SetDrawLayer("BACKGROUND", 1)
    local topLine = win:CreateTexture(nil, "BORDER")
    topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT"); topLine:SetHeight(2)

    -- title
    local icon = win:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(M .. "icon")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 16, -16)
    local title = font(win, 24)
    title:SetPoint("LEFT", icon, "RIGHT", 8, 1)
    title:SetText("Lumen")
    local ver = font(win, 12, .5, .55, .65)
    ver:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -4)
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Lumen", "Version")
        or (GetAddOnMetadata and GetAddOnMetadata("Lumen", "Version"))
    ver:SetText("version " .. (v or "?"))

    local close = CreateFrame("Button", nil, win)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.t = font(close, 20, .7, .74, .82)
    close.t:SetPoint("CENTER")
    close.t:SetText("x")
    close:SetScript("OnClick", function() O.Hide() end)
    close:SetScript("OnEnter", function() close.t:SetTextColor(1, .4, .35) end)
    close:SetScript("OnLeave", function() close.t:SetTextColor(.7, .74, .82) end)

    -- note line (combat refusals etc.)
    win.note = font(win, 13, 1, .75, .4)
    win.note:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", NAV_W + PAD, 14)
    win.note:SetAlpha(0)
    local ng = win.note:CreateAnimationGroup()
    local n1 = ng:CreateAnimation("Alpha"); n1:SetFromAlpha(0); n1:SetToAlpha(1); n1:SetDuration(.15)
    local n2 = ng:CreateAnimation("Alpha"); n2:SetFromAlpha(1); n2:SetToAlpha(0); n2:SetDuration(.6); n2:SetStartDelay(2.6)
    win.noteAnim = ng

    win.reload = Button(win, "Reload UI", 120, function() ReloadUI() end)
    win.reload:SetPoint("BOTTOMRIGHT", -PAD, 10)
    win.reload:Hide()

    -- pages + nav
    win.pages, win.navs = {}, {}
    for i, def in ipairs(PAGES) do
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + PAD, -PAD - 4)
        page:SetSize(CONTENT_W, WIN_H - PAD * 2 - 30)
        page.y = 0
        def[2](page)
        page:Hide()
        win.pages[i] = page

        local b = CreateFrame("Button", nil, win)
        b:SetSize(NAV_W, 34)
        b:SetPoint("TOPLEFT", 0, -84 - (i - 1) * 36)
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
        b.hl = rect(b, "BACKGROUND", 1, 1, 1, 0)
        b.hl:SetAllPoints()
        b.text = font(b, 16)
        b.text:SetPoint("LEFT", 18, 0)
        b.text:SetText(def[1])
        b:SetScript("OnClick", function() O.Select(i) end)
        b:SetScript("OnEnter", function() if win.sel ~= i then b.hl:SetColorTexture(1, 1, 1, .04) end end)
        b:SetScript("OnLeave", function() if win.sel ~= i then b.hl:SetColorTexture(1, 1, 1, 0) end end)
        win.navs[i] = b
    end

    repaint[#repaint + 1] = function()
        local a = accent()
        topLine:SetColorTexture(a[1], a[2], a[3], 1)
        title:SetTextColor(1, 1, 1)
        O.Select(win.sel or 1)
    end

    -- open animation
    win.openAnim = L.Anim(win, { dur = .18, scaleFrom = .96, scaleTo = 1, alphaFrom = 0, alphaTo = 1 })
end

function O.Select(i)
    win.sel = i
    local a = accent()
    for j, page in ipairs(win.pages) do
        page:SetShown(j == i)
        local b = win.navs[j]
        if j == i then
            b.bar:SetColorTexture(a[1], a[2], a[3], 1)
            b.hl:SetColorTexture(a[1], a[2], a[3], .1)
            b.text:SetTextColor(1, 1, 1)
        else
            b.bar:SetColorTexture(0, 0, 0, 0)
            b.hl:SetColorTexture(1, 1, 1, 0)
            b.text:SetTextColor(.66, .7, .8)
        end
    end
end

function O.Repaint()
    if not win then return end
    for _, fn in ipairs(repaint) do fn() end
end

function O.Show()
    if not win then build() end
    for _, fn in ipairs(refreshers) do fn() end
    O.Repaint()
    win:Show()
    win.openAnim:Stop(); win.openAnim:Play()
end

function O.Hide() if win then win:Hide() end end

function O.Toggle()
    if win and win:IsShown() then O.Hide() else O.Show() end
end

-- Entry in Blizzard's Options -> AddOns list
function O.RegisterBlizzard()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local t = font(panel, 22)
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText("Lumen")
    local s = font(panel, 14, .7, .74, .82)
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    s:SetText("All of Lumen's settings live in its own window.")
    local b = Button(panel, "Open Lumen options", 200, function()
        if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
        O.Show()
    end)
    b:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -14)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Lumen")
    if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end
