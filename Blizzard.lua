local _, L = ...

-- Bars Lumen replaces. Hidden by reparenting to a hidden frame (the same
-- approach Bartender/Dominos use), done once, out of combat.
local BURY = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight" }

-- Things that may live inside those bars on some skins (Forever's classic
-- "Camelot" look keeps micro menu, bags and XP inside the main bar). If they
-- do, they are lifted back out to UIParent so they stay visible.
local RESCUE = {
    "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar", "BagsBar",
    "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
    "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar",
    "StanceBar", "StanceBarFrame", "PetActionBar", "PetActionBarFrame", "PossessActionBar", "PossessBarFrame",
    "MultiCastActionBarFrame", "MainMenuBarVehicleLeaveButton", "ExtraActionBarFrame", "ZoneAbilityFrame",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton", "MainMenuBarPerformanceBarFrame",
}

function L.HideBlizzard()
    if L.blizzHidden or not L.db.hideBlizzard then return end
    if InCombatLockdown() then L.pending.blizz = true return end

    local hider = CreateFrame("Frame", "LumenHiddenParent", UIParent)
    hider:Hide()

    local buried = {}
    for _, name in ipairs(BURY) do
        local f = _G[name]
        if type(f) == "table" and f.SetParent then buried[f] = true end
    end

    local function isUnder(f)
        local p, depth = f:GetParent(), 0
        while p and depth < 20 do
            if buried[p] then return true end
            p, depth = p:GetParent(), depth + 1
        end
        return false
    end

    local rescue = {}
    for _, n in ipairs(RESCUE) do rescue[#rescue + 1] = n end
    if type(MICRO_BUTTONS) == "table" then
        for _, n in ipairs(MICRO_BUTTONS) do rescue[#rescue + 1] = n end
    end
    for _, name in ipairs(rescue) do
        local f = _G[name]
        if type(f) == "table" and f.GetParent and not buried[f] and isUnder(f) then
            pcall(f.SetParent, f, UIParent)
        end
    end

    for f in pairs(buried) do pcall(f.SetParent, f, hider) end
    L.blizzHidden = true
end

------------------------------------------------------------------------
-- Player frame: hidden while the avatar replaces it, restorable live.
------------------------------------------------------------------------
-- Class/totem/combo bars that may sit inside the player frame; lifted out so
-- they keep working.
local PLAYER_RESCUE = {
    "PlayerFrameBottomManagedFramesContainer", "TotemFrame", "RuneFrame", "ComboPointPlayerFrame",
    "PlayerFrameAlternateManaBar", "AlternatePowerBar", "EclipseBarFrame", "ShardBarFrame",
    "PaladinPowerBarFrame", "WarlockPowerFrame", "MonkHarmonyBarFrame", "PriestBarFrame",
    "MageArcaneChargesFrame", "EssencePlayerFrame", "DruidComboPointBarFrame", "RogueComboPointBarFrame",
}

local playerHider, playerOrigParent, rescued

function L.UpdatePlayerFrame()
    local pf = PlayerFrame
    if type(pf) ~= "table" or not pf.SetParent then return end
    if InCombatLockdown() then L.pending.playerFrame = true return end
    local hide = L.db.avatar and L.db.hidePlayerFrame

    if hide and not playerHider then
        playerHider = CreateFrame("Frame", "LumenPlayerFrameHider", UIParent)
        playerHider:Hide()
    end
    if hide and pf:GetParent() ~= playerHider then
        playerOrigParent = pf:GetParent() or UIParent
        rescued = {}
        for _, name in ipairs(PLAYER_RESCUE) do
            local f = _G[name]
            if type(f) == "table" and f.GetParent then
                local p, under = f:GetParent(), false
                for _ = 1, 10 do
                    if not p then break end
                    if p == pf then under = true break end
                    p = p:GetParent()
                end
                if under then
                    rescued[f] = f:GetParent()
                    pcall(f.SetParent, f, UIParent)
                end
            end
        end
        pcall(pf.SetParent, pf, playerHider)
    elseif not hide and playerHider and pf:GetParent() == playerHider then
        pcall(pf.SetParent, pf, playerOrigParent or UIParent)
        for f, parent in pairs(rescued or {}) do pcall(f.SetParent, f, parent) end
        rescued = nil
    end
end

------------------------------------------------------------------------
-- Blizzard's XP bar: hidden while Lumen's XP bar is showing, so the two
-- never overlap. Reputation bars are left alone.
------------------------------------------------------------------------
local XP_FRAMES = { "MainStatusTrackingBarContainer", "MainMenuExpBar", "MainMenuBarMaxLevelBar" }
local xpHider, xpOrig = nil, {}

function L.UpdateBlizzardXP(hide)
    L.blizzXPWanted = hide
    if InCombatLockdown() then L.pending.blizzXP = true return end
    if hide and not xpHider then
        xpHider = CreateFrame("Frame", "LumenXPHider", UIParent)
        xpHider:Hide()
    end
    local frames = {}
    for _, name in ipairs(XP_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and f.SetParent then frames[#frames + 1] = f end
    end
    -- older layouts keep XP only inside the shared manager
    if #frames == 0 and type(StatusTrackingBarManager) == "table" and StatusTrackingBarManager.SetParent then
        frames[1] = StatusTrackingBarManager
    end
    for _, f in ipairs(frames) do
        if hide then
            if f:GetParent() ~= xpHider then
                xpOrig[f] = f:GetParent() or UIParent
                pcall(f.SetParent, f, xpHider)
            end
        elseif xpOrig[f] then
            pcall(f.SetParent, f, xpOrig[f])
            xpOrig[f] = nil
        end
    end
end

------------------------------------------------------------------------
-- Generic hide/restore by reparenting (live, out of combat only)
------------------------------------------------------------------------
local stash, stashHider = {}, nil

local function bury(f, hide)
    if type(f) ~= "table" or not f.SetParent then return end
    if hide then
        if not stashHider then
            stashHider = CreateFrame("Frame", "LumenStashHider", UIParent)
            stashHider:Hide()
        end
        if f:GetParent() ~= stashHider then
            stash[f] = f:GetParent() or UIParent
            pcall(f.SetParent, f, stashHider)
        end
    elseif stash[f] then
        pcall(f.SetParent, f, stash[f])
        stash[f] = nil
    end
end

-- Target frame: replaced by the target orb. Classic combo points live on it,
-- so they move next to the orb while it is hidden.
local comboHome
function L.UpdateTargetFrame()
    if InCombatLockdown() then L.pending.targetFrame = true return end
    local hide = L.db.target and L.db.hideTargetFrame and true or false
    bury(TargetFrame, hide)

    local cf, orb = ComboFrame, L.Target and L.Target.orb
    if type(cf) ~= "table" or not orb then return end
    if hide and not comboHome then
        comboHome = { parent = cf:GetParent(), points = {} }
        for i = 1, cf:GetNumPoints() do comboHome.points[i] = { cf:GetPoint(i) } end
        pcall(cf.SetParent, cf, orb)
        cf:ClearAllPoints()
        cf:SetPoint("RIGHT", orb, "LEFT", 4, 0)
    elseif not hide and comboHome then
        pcall(cf.SetParent, cf, comboHome.parent or UIParent)
        cf:ClearAllPoints()
        for _, p in ipairs(comboHome.points) do cf:SetPoint(unpack(p)) end
        comboHome = nil
    end
end

-- Blizzard's player cast bar: replaced by the cast arc.
function L.UpdateCastBars()
    if InCombatLockdown() then L.pending.castBars = true return end
    local hasArc = L.castArcs and L.castArcs[1] ~= nil
    local hide = hasArc and L.db.avatar and L.db.castArc and L.db.hideCastBar and true or false
    bury(PlayerCastingBarFrame, hide)
    if CastingBarFrame ~= PlayerCastingBarFrame then bury(CastingBarFrame, hide) end
end
