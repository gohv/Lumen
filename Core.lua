local ADDON, L = ...
local Button = L.Button

L.pending = L.pending or {}
L.dirty = { all = true }

------------------------------------------------------------------------
-- Theme
------------------------------------------------------------------------
function L.ApplyTheme(name)
    if name and L.themes[name] then L.db.theme = name end
    L.theme = L.themes[L.db.theme] or L.themes.aurora
    L.curve = L.BuildCurve(L.theme.stops)
    if L.ApplyXPTheme then L.ApplyXPTheme() end
    if L.Avatar and L.Avatar.ApplyTheme then L.Avatar.ApplyTheme() end
    if L.UpdateAuraRings then L.UpdateAuraRings() end
    if L.Options then L.Options.Repaint() end
    for _, b in ipairs(L.buttons) do
        b.proc = nil -- force re-tint
        Button.UpdateState(b)
        Button.UpdateProc(b)
    end
end

------------------------------------------------------------------------
-- Frame loop: batched event work, cooldown colors (~30 Hz), range (5 Hz)
------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
ticker:Hide()
local colorAcc, rangeAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    local d = L.dirty
    if d.all then
        d.all, d.cd, d.state, d.count, d.proc = false, false, false, false, false
        for _, b in ipairs(L.buttons) do Button.Update(b) end
    else
        if d.cd then
            d.cd = false
            for _, b in ipairs(L.buttons) do Button.UpdateCooldown(b) end
        end
        if d.state then
            d.state = false
            for _, b in ipairs(L.buttons) do Button.UpdateState(b); Button.UpdateUsable(b) end
        end
        if d.count then
            d.count = false
            for _, b in ipairs(L.buttons) do Button.UpdateCount(b) end
        end
        if d.proc then
            d.proc = false
            for _, b in ipairs(L.buttons) do Button.UpdateProc(b) end
        end
    end

    colorAcc = colorAcc + elapsed
    if colorAcc >= .033 then
        colorAcc = 0
        for b in pairs(L.cdActive) do Button.Colorize(b) end
    end
    rangeAcc = rangeAcc + elapsed
    if rangeAcc >= .2 then
        rangeAcc = 0
        for _, b in ipairs(L.buttons) do
            if b.has then Button.UpdateUsable(b) end
        end
    end
end)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local H = {}

local function reg(e)
    if H[e] then pcall(ev.RegisterEvent, ev, e) end
end

local function mark(key) return function() L.dirty[key] = true end end

H.ACTIONBAR_SLOT_CHANGED = function(slot)
    slot = L.plain(slot)
    for _, b in ipairs(L.buttons) do
        if not slot or slot == 0 or b.action == slot then Button.Update(b) end
    end
end
H.ACTIONBAR_UPDATE_COOLDOWN = mark("cd")
H.SPELL_UPDATE_COOLDOWN = mark("cd")
H.LOSS_OF_CONTROL_UPDATE = mark("cd")
H.SPELL_UPDATE_CHARGES = mark("count")
H.ACTIONBAR_UPDATE_STATE = mark("state")
H.ACTIONBAR_UPDATE_USABLE = mark("state")
H.SPELL_UPDATE_USABLE = mark("state")
H.PLAYER_TARGET_CHANGED = mark("state")
H.START_AUTOREPEAT_SPELL = mark("state")
H.STOP_AUTOREPEAT_SPELL = mark("state")
H.PLAYER_ENTER_COMBAT = mark("state")
H.PLAYER_LEAVE_COMBAT = mark("state")
H.TRADE_SKILL_SHOW = mark("state")
H.TRADE_SKILL_CLOSE = mark("state")
H.BAG_UPDATE_DELAYED = mark("count")
H.PLAYER_EQUIPMENT_CHANGED = mark("all")
H.UPDATE_SHAPESHIFT_FORM = mark("all")
H.ACTIONBAR_PAGE_CHANGED = mark("all")
H.UPDATE_BONUS_ACTIONBAR = mark("all")
H.PLAYER_ENTERING_WORLD = function()
    L.dirty.all = true
    if L.UpdateXP then L.UpdateXP(true) end
end
H.UPDATE_BINDINGS = function() L.UpdateBindings() end

H.ACTIONBAR_SHOWGRID = function()
    L.showGrid = true
    for _, b in ipairs(L.buttons) do Button.ApplyAlpha(b) end
    L.UpdateAllBarAlpha()
end
H.ACTIONBAR_HIDEGRID = function()
    L.showGrid = false
    for _, b in ipairs(L.buttons) do Button.ApplyAlpha(b) end
    L.UpdateAllBarAlpha()
end

H.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(id)
    id = L.plain(id)
    if id then L.procs[id] = true end
    L.dirty.proc = true
end
H.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = function(id)
    id = L.plain(id)
    if id then L.procs[id] = nil end
    L.dirty.proc = true
end

H.PLAYER_XP_UPDATE = function() L.UpdateXP() end
H.PLAYER_LEVEL_UP = function() C_Timer.After(.2, function() L.UpdateXP() end) end
H.UPDATE_EXHAUSTION = function() L.DrawXP(); L.XPText() end

H.PLAYER_REGEN_DISABLED = function()
    L.inCombat = true
    if L.unlocked then L.SetUnlocked(false) end
    L.UpdateAllBarAlpha()
end
H.PLAYER_REGEN_ENABLED = function()
    L.inCombat = false
    local p = L.pending
    if p.init then p.init = nil; L.Init() end
    if p.blizz then p.blizz = nil; L.HideBlizzard() end
    if p.layout then p.layout = nil; L.RelayoutAll() end
    if p.bindings then p.bindings = nil; L.UpdateBindings() end
    if p.playerFrame then p.playerFrame = nil; L.UpdatePlayerFrame() end
    if p.blizzXP then p.blizzXP = nil; L.UpdateBlizzardXP(L.blizzXPWanted) end
    if p.targetFrame then p.targetFrame = nil; L.UpdateTargetFrame() end
    if p.castBars then p.castBars = nil; L.UpdateCastBars() end
    L.UpdateAllBarAlpha()
end

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON then
            L.InitDB()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        L.Init()
    elseif L.ready then
        local h = H[event]
        if h then h(...) end
    elseif event == "PLAYER_REGEN_ENABLED" and L.pending.init then
        L.pending.init = nil
        L.Init()
    end
end)
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED") -- needed for a deferred init

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function L.Init()
    if L.ready then return end
    if not L.db then L.InitDB() end
    if InCombatLockdown() then
        L.pending.init = true
        L.Print("finishing setup when combat ends.")
        return
    end
    L.theme = L.themes[L.db.theme] or L.themes.aurora
    L.curve = L.BuildCurve(L.theme.stops)

    -- WoW reads an addon's file list only at game start: files added by an
    -- update are missing until a full restart (a /reload is not enough).
    local missing = {}
    for _, fn in ipairs({ "CreateTargetOrb", "CreateCastArc", "CreateAuraRing" }) do
        if not L[fn] then missing[#missing + 1] = fn end
    end
    if not L.Options then missing[#missing + 1] = "Options" end
    if #missing > 0 then
        L.Print("|cffff6060was updated with new files. Please exit and restart WoW|r (a /reload is not enough).")
    end

    -- Each part starts on its own, so one failure can't take the rest down.
    L.failed = {}
    local function step(name, fn, ...)
        if not fn then return end
        local args = { ... }
        local n = select("#", ...)
        local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, function(e) return tostring(e) end)
        if not ok then
            L.failed[#L.failed + 1] = name
            L.Print("|cffff6060" .. name .. " failed to start:|r " .. err)
        end
    end

    for i, def in ipairs(L.BAR_DEFS) do step("bar " .. i, L.CreateBar, i, def) end
    step("default bar hiding", L.HideBlizzard)
    step("cooldown pulse", L.CreatePulse)
    step("XP bar", L.CreateXPBar)
    step("avatar", L.CreateAvatar)
    step("target orb", L.CreateTargetOrb)
    if L.CreateCastArc then
        if L.Avatar.orb then step("avatar cast arc", L.CreateCastArc, L.Avatar.orb, "player", "castArc") end
        if L.Target and L.Target.orb then step("target cast arc", L.CreateCastArc, L.Target.orb, "target", "targetCast") end
    end
    if L.CreateAuraRing then
        if L.Avatar.orb then
            step("avatar auras", L.CreateAuraRing, L.Avatar.orb, "player", { key = "auras", side = "left", size = 24, top = 7, sideCount = 3 })
        end
        if L.Target and L.Target.orb then
            step("target auras", L.CreateAuraRing, L.Target.orb, "target", { key = "targetAuras", side = "right", size = 22, top = 7, sideCount = 3 })
        end
    end
    step("player frame", L.UpdatePlayerFrame)
    step("target frame", L.UpdateTargetFrame)
    step("cast bar", L.UpdateCastBars)
    if L.Options then step("options", L.Options.RegisterBlizzard) end
    step("keybinds", L.UpdateBindings)
    step("edit mode hook", L.HookEditMode)

    if L.db.numbers and GetCVar and GetCVar("countdownForCooldowns") == "0" then
        pcall(SetCVar, "countdownForCooldowns", "1")
    end

    for e in pairs(H) do reg(e) end
    L.ready = true
    L.inCombat = InCombatLockdown()
    L.ApplyTheme()
    L.UpdateAllBarAlpha(true)
    L.dirty.all = true
    ticker:Show()

    if not L.db.welcomed then
        L.db.welcomed = true
        L.Print("loaded. |cffffffff/lumen|r opens the options window.")
    end
end

------------------------------------------------------------------------
-- Demo: fake cooldowns + procs so every effect can be seen at once
------------------------------------------------------------------------
function L.Demo()
    local now = GetTime()
    for i, b in ipairs(L.buttons) do
        if b.has then
            local dur = 2.5 + ((i - 1) % 12) * .45
            b.demoUntil = now + dur
            -- only bar 1's last button triggers the center pulse when it finishes
            b.cdActive, b.cdBegan = true, (b.bar.id == 1 and b.index == 12) and now - 10 or now
            b.durObj, b.cdStart, b.cdDur = nil, now, dur
            b.cd:SetSwipeColor(0, 0, 0, .62)
            b.cd:SetHideCountdownNumbers(not L.db.numbers)
            b.cd:SetCooldown(now, dur)
            b.ring:SetCooldown(now, dur)
            L.cdActive[b] = true
            Button.UpdateUsable(b)
        end
    end
    for _, bar in ipairs(L.bars) do
        local b = bar.buttons[1]
        b.demoProc = true
        Button.UpdateProc(b)
        C_Timer.After(6, function()
            b.demoProc = nil
            Button.UpdateProc(b)
        end)
    end
    if L.bars[1] then
        L.Pulse(L.bars[1].buttons[1])
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function onoff(v, cur)
    if v == "on" then return true elseif v == "off" then return false end
    return not cur
end

local HELP = {
    "|cffffffff/lumen|r  open the options window  ·  |cffffffff/lumen help|r  this list",
    "|cffffffff/lumen move|r  edit mode: drag, resize (wheel), nudge (arrows), right-click resets",
    "|cffffffff/lumen lock|r  leave edit mode (Blizzard's Edit Mode opens it too)",
    "|cffffffff/lumen theme|r aurora | ember | frost | neon | verdant",
    "|cffffffff/lumen layout|r arc | line",
    "|cffffffff/lumen scale|r 0.6-1.6",
    "|cffffffff/lumen magnify|r on|off|1.1-2.2  dock-style zoom on hover",
    "|cffffffff/lumen fade|r on|off  ·  |cffffffff/lumen pulse|r on|off  ·  |cffffffff/lumen xp|r on|off",
    "|cffffffff/lumen numbers|r on|off  ·  |cffffffff/lumen hotkeys|r on|off  ·  |cffffffff/lumen sockets|r on|off",
    "|cffffffff/lumen blizzard|r on|off  show (on) or hide (off) the default bars, needs /reload",
    "|cffffffff/lumen avatar|r on|off|demo  living avatar (wheel = zoom, left-click = target you, right-click = menu)",
    "|cffffffff/lumen playerframe|r on|off  show (on) or hide (off) Blizzard's player frame",
    "|cffffffff/lumen test|r  preview cooldowns, procs and the pulse",
    "|cffffffff/lumen reset|r  default positions and sizes",
}

SLASH_LUMEN1 = "/lumen"
SlashCmdList.LUMEN = function(msg)
    if not L.ready then L.Print("not ready yet.") return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local db = L.db
    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" then
        if L.Options then L.Options.Toggle()
        else L.Print("|cffff6060the options window needs a full WoW restart|r (exit the game and start it again).") end
    elseif cmd == "unlock" or cmd == "move" or cmd == "edit" then
        L.SetUnlocked(true)
    elseif cmd == "lock" then
        L.SetUnlocked(false)
    elseif cmd == "theme" then
        if L.themes[arg] then
            L.ApplyTheme(arg)
            L.Print("theme: " .. L.theme.name)
        else
            L.Print("themes: aurora, ember, frost, neon, verdant")
        end
    elseif cmd == "layout" and (arg == "arc" or arg == "line") then
        if InCombatLockdown() then L.Print("not in combat.") return end
        db.layout = arg
        L.RelayoutAll()
    elseif cmd == "scale" and tonumber(arg) then
        if InCombatLockdown() then L.Print("not in combat.") return end
        db.scale = L.Clamp(tonumber(arg), .6, 1.6)
        L.RelayoutAll()
    elseif cmd == "fade" then
        db.fade = onoff(arg, db.fade); L.UpdateAllBarAlpha()
        L.Print("fade " .. (db.fade and "on" or "off"))
    elseif cmd == "pulse" then
        db.pulse = onoff(arg, db.pulse)
        L.Print("pulse " .. (db.pulse and "on" or "off"))
    elseif cmd == "xp" then
        db.xp = onoff(arg, db.xp); L.UpdateXP(true)
        L.Print("xp bar " .. (db.xp and "on" or "off"))
    elseif cmd == "numbers" then
        db.numbers = onoff(arg, db.numbers)
        if db.numbers then pcall(SetCVar, "countdownForCooldowns", "1") end
        L.dirty.cd = true
        L.Print("countdown numbers " .. (db.numbers and "on" or "off"))
    elseif cmd == "hotkeys" then
        db.hotkeys = onoff(arg, db.hotkeys)
        for _, b in ipairs(L.buttons) do Button.UpdateHotkey(b) end
    elseif cmd == "sockets" then
        db.sockets = onoff(arg, db.sockets)
        for _, b in ipairs(L.buttons) do Button.ApplyAlpha(b) end
    elseif cmd == "blizzard" then
        db.hideBlizzard = not onoff(arg, not db.hideBlizzard)
        L.Print("default bars will be " .. (db.hideBlizzard and "hidden" or "shown") .. " after /reload")
    elseif cmd == "avatar" then
        if arg == "demo" then
            if not db.avatar then L.Avatar.SetEnabled(true) end
            L.Avatar.Demo()
        else
            L.Avatar.SetEnabled(onoff(arg, db.avatar))
            L.Print("avatar " .. (db.avatar and "on" or "off"))
        end
    elseif cmd == "playerframe" then
        if InCombatLockdown() then L.Print("not in combat.") return end
        db.hidePlayerFrame = not onoff(arg, not db.hidePlayerFrame)
        L.UpdatePlayerFrame()
        L.Print("Blizzard player frame " .. (db.hidePlayerFrame and "hidden" or "shown"))
    elseif cmd == "magnify" then
        local n = tonumber(arg)
        if n then
            db.magnify, db.magnifyScale = true, L.Clamp(n, 1.1, 2.2)
        else
            db.magnify = onoff(arg, db.magnify)
        end
        L.Print("dock magnify " .. (db.magnify and ("on (" .. db.magnifyScale .. "x)") or "off"))
    elseif cmd == "debug" then
        L.Print("version " .. ((C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Lumen", "Version")) or "?"))
        print("   modules: target " .. tostring(L.CreateTargetOrb ~= nil) .. ", cast arcs " .. tostring(L.CreateCastArc ~= nil)
            .. ", auras " .. tostring(L.CreateAuraRing ~= nil) .. ", options " .. tostring(L.Options ~= nil))
        print("   failed to start: " .. ((L.failed and #L.failed > 0) and table.concat(L.failed, ", ") or "nothing"))
        print("   cast arcs: " .. #(L.castArcs or {}) .. ", UnitCastingDuration " .. tostring(UnitCastingDuration ~= nil))
        if L.castDebug then print("   last cast: " .. L.castDebug) end
    elseif cmd == "test" then
        L.Demo()
    elseif cmd == "reset" then
        if InCombatLockdown() then L.Print("not in combat.") return end
        db.pos = {}
        L.RelayoutAll()
    else
        L.Print("commands:")
        for _, line in ipairs(HELP) do print("   " .. line) end
    end
end
