-- Minimal WoW API mock to exercise Lumen's load + event paths.
local SECRET_MODE = os.getenv("SECRET") == "1"
local secrets = setmetatable({}, {__mode="k"})
local function mkSecret(v) local s = setmetatable({v=v}, {__tostring=function() return "<secret>" end}); secrets[s]=true; return s end
issecretvalue = function(v) return secrets[v] == true end

local now = 100
GetTime = function() return now end
local frames, eventFrames, onUpdates = {}, {}, {}
FRAMES = frames
local function newObj(kind, name)
  local o = { __kind = kind, scripts = {}, attrs = {}, alpha = 1, __shown = true, w=0, h=0, scale=1, events = {}, __level = 1, parent = false, fs = false, drivers = {} }
  local mt = {}
  mt.__index = function(t, k)
    if type(k) ~= "string" or k:match("^[%l_]") then return nil end
    local f = function(self, ...)
      local a = {...}
      if k == "SetScript" then self.scripts[a[1]] = a[2]; if a[1]=="OnUpdate" then onUpdates[self]=a[2] end; return end
      if k == "HookScript" then local old=self.scripts[a[1]]; self.scripts[a[1]] = function(...) if old then old(...) end a[2](...) end return end
      if k == "GetScript" then return self.scripts[a[1]] end
      if k == "RegisterEvent" or k == "RegisterUnitEvent" then eventFrames[self]=true; self.events[a[1]]=true; return end
      if k == "UnregisterEvent" then if self.events then self.events[a[1]]=nil end return end
      if k == "SetAttribute" then self.attrs[a[1]] = a[2]; local s=self.scripts.OnAttributeChanged; if s then s(self, a[1], a[2]) end return end
      if k == "GetAttribute" then return self.attrs[a[1]] end
      if k == "GetName" then return self.__name end
      if k == "SetAlpha" then assert(type(a[1])=="number", "SetAlpha non-number"); self.alpha = a[1] return end
      if k == "GetAlpha" then return self.alpha end
      if k == "SetSize" then self.w, self.h = a[1], a[2] return end
      if k == "SetWidth" then assert(type(a[1])=="number"); self.w = a[1] return end
      if k == "SetHeight" then self.h = a[1] return end
      if k == "GetWidth" then return self.w end
      if k == "GetHeight" then return self.h end
      if k == "SetScale" then self.scale = a[1] return end
      if k == "GetScale" then return self.scale end
      if k == "GetFrameLevel" then return rawget(self, "__level") or 1 end
      if k == "SetFrameLevel" then rawset(self, "__level", a[1]) return end
      if k == "Show" then self.__shown = true return end
      if k == "Hide" then self.__shown = false return end
      if k == "SetShown" then self.__shown = a[1] and true or false return end
      if k == "IsShown" then return self.__shown end
      if k == "GetParent" then return self.parent or nil end
      if k == "SetParent" then self.parent = a[1] return end
      if k == "GetPoint" then return "BOTTOM", nil, "BOTTOM", 10, 20 end
      if k == "GetStringWidth" then return 12 end
      if k == "GetNumPoints" then return 1 end
      if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
      if k == "GetCenter" then if rawget(self, "__cx") then return self.__cx, 100 end return 500, 120 end
      if k == "IsMouseOver" then return rawget(self, "__mouse") or false end
      if k == "IsVisible" then return true end
      if k == "GetEffectiveScale" then return 1 end
      if k == "SetScale" then self.scale = a[1]; return end
      if k == "SetText" then rawset(self, "__txt", secrets[a[1]] and "<secret>" or a[1]) return end
      if k == "GetStatusBarTexture" then self.sbt = rawget(self, "sbt") or newObj("Texture"); return self.sbt end
      if k == "GetRegions" then return end
      if k == "GetObjectType" then return self.__kind end
      if k == "GetCountdownFontString" then self.fs = self.fs or newObj("FontString"); return self.fs end
      if k == "SetVertexColor" or k == "SetTextColor" or k == "SetSwipeColor" then
        for i=1,3 do if secrets[a[i]] then -- widget setters accept secrets in game
        elseif type(a[i]) ~= "number" then error(k.." got "..type(a[i])) end end
        return end
      if k == "IsOwned" then return false end
      if k == "GetTexture" then return 1234 end
      if k:match("^Create") then local c = newObj(k:sub(7), nil); c.parent=self; return c end
      if k:match("^Is") or k:match("^Has") then return false end
      if k:match("^Get") then return nil end
      return nil
    end
    rawset(t, k, f)
    return f
  end
  return setmetatable(o, mt)
end

CreateFrame = function(kind, name, parent, template)
  local f = newObj(kind, name); f.__name = name; f.parent = parent; f.template = template
  if name then _G[name] = f end
  frames[#frames+1] = f
  return f
end
UIParent = newObj("Frame"); UIParent.__name = "UIParent"
MainMenuBar = CreateFrame("Frame", "MainMenuBar", UIParent)
MultiBarBottomLeft = CreateFrame("Frame", "MultiBarBottomLeft", UIParent)
MicroMenu = CreateFrame("Frame", "MicroMenu", MainMenuBar)
MainMenuExpBar = CreateFrame("StatusBar", "MainMenuExpBar", MainMenuBar)
StanceBar = CreateFrame("Frame", "StanceBar", UIParent)
PlayerFrame = CreateFrame("Button", "PlayerFrame", UIParent)
TotemFrame = CreateFrame("Frame", "TotemFrame", PlayerFrame)
GameTooltip = newObj("GameTooltip")
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers+1] = { at = (GetTime and GetTime() or 0) + d, fn = fn } end }
local function runTimers() local due = {} for i = #timers, 1, -1 do if timers[i].at <= GetTime() then due[#due+1] = timers[i].fn; table.remove(timers, i) end end for _, f in ipairs(due) do f() end end
InCombatLockdown = function() return false end
GetCVarBool = function() return true end
GetCVar = function() return "0" end
SetCVar = function() end
IsModifiedClick = function() return false end
IsShiftKeyDown = function() return true end
local CURX = 0
GetCursorPosition = function() return CURX, 0 end
hooksecurefunc = function(t, name, fn) if type(t) == "string" then t, name, fn = _G, t, name end local o = t[name]; t[name] = function(...) local r = o(...); fn(...); return r end end
EditModeManagerFrame = { EnterEditMode = function() end, ExitEditMode = function() end }
GetBindingKey = function(cmd) local n = cmd:match("(%d+)$"); if cmd:match("^ACTIONBUTTON") then return n == "1" and "SHIFT-1" or n end end
ClearOverrideBindings = function() end
local overrides = 0
SetOverrideBindingClick = function(owner, prio, key, btn) assert(_G[btn], "binding target missing "..btn); overrides = overrides + 1 end
RegisterStateDriver = function(f, state, cond) f.drivers = f.drivers or {}; f.drivers[state] = cond end
local XPV = 450
UnitXP = function() return XPV end
UnitXPMax = function() return 1000 end
UnitLevel = function() return 20 end
GetXPExhaustion = function() return 200 end
BreakUpLargeNumbers = tostring
IsXPUserDisabled = function() return false end
GetMaxLevelForPlayerExpansion = function() return 60 end
CreateColor = function(r,g,b,a) return { r=r,g=g,b=b,a=a, GetRGB=function(s) return s.r,s.g,s.b end } end
Enum = { LuaCurveType = { Linear = 1, Step = 2 } }
C_CurveUtil = {
  CreateColorCurve = function()
    local c = { pts = {} }
    function c:SetType() end
    function c:AddPoint(x, col) self.pts[#self.pts+1] = {x, col} end
    return c
  end,
  EvaluateColorFromBoolean = function(b, t, f) return t end,
}
-- action bar API (modern table-returning shape)
local actions = {}
for s = 1, 72 do if s % 3 ~= 0 then actions[s] = true end end
local function S(v) if SECRET_MODE then return mkSecret(v) end return v end
local durObj = { EvaluateRemainingPercent = function(self, curve) return CreateColor(0.5, 0.2, 0.9, 1) end }
C_ActionBar = {
  HasAction = function(s) return actions[s] or false end,
  GetActionTexture = function(s) return 136000 + s end,
  GetActionCount = function(s) return S(3) end,
  IsUsableAction = function(s) return S(s % 5 ~= 0), S(s % 7 == 0) end,
  IsActionInRange = function(s) return S(s % 4 ~= 0) end,
  IsCurrentAction = function(s) return s == 1 end,
  IsAutoRepeatAction = function() return false end,
  IsEquippedAction = function(s) return s == 2 end,
  IsConsumableAction = function(s) return s == 4 end,
  IsStackableAction = function() return false end,
  GetActionInfo = function(s) return "spell", 1000 + s end,
  GetActionCharges = function(s) return { currentCharges = S(1), maxCharges = S(2) } end,
  GetActionCooldown = function(s)
    local active = s % 2 == 0
    return { startTime = S(active and 95 or 0), duration = S(active and 20 or 0), isEnabled = true, isActive = active, isOnGCD = (s % 4 == 0), modRate = S(1) }
  end,
  GetActionCooldownDuration = function(s) return durObj end,
  PickupAction = function() end, PlaceAction = function() end,
}
C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return id == 1005 end }
GetOverrideBarIndex = function() return 14 end
GetVehicleBarIndex = function() return 12 end
GetTempShapeshiftBarIndex = function() return 13 end
SlashCmdList = {}
tinsert = table.insert
UISpecialFrames = {}
ReloadUI = function() end
local TARGET = true
UnitExists = function(u) if u == "target" or u == "targettarget" then return TARGET end return true end
UnitName = function(u) return S(u == "target" and "Defias Bandit" or "Me"), nil end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitReaction = function() return S(2) end
UnitIsPlayer = function() return false end
UnitIsTapDenied = function() return false end
UnitIsDead = function() return false end
UnitIsUnit = function(a, b) return S(a == "targettarget" and b == "player") end
UnitCanAttack = function() return S(true) end
UnitClassification = function() return "elite" end
GetCreatureDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
RAID_CLASS_COLORS = { WARRIOR = { r = .78, g = .61, b = .43 } }
DebuffTypeColor = { Magic = { r = .2, g = .6, b = 1 } }
local CASTING = false
UnitCastingInfo = function(u) if CASTING then return S("Fireball"), "", 1234, S(100000), S(102500), false, 1, S(false), 133 end end
UnitChannelInfo = function() end
RegisterUnitWatch = function(f) f.__watched = true end
UnregisterUnitWatch = function(f) f.__watched = false end
C_AddOns = { GetAddOnMetadata = function() return "0.5.0" end }
Settings = { RegisterCanvasLayoutCategory = function(f, n) return { name = n } end, RegisterAddOnCategory = function() end }
TargetFrame = CreateFrame("Button", "TargetFrame", UIParent)
ComboFrame = CreateFrame("Frame", "ComboFrame", TargetFrame)
PlayerCastingBarFrame = CreateFrame("StatusBar", "PlayerCastingBarFrame", UIParent)
local HP = 800
UnitHealth = function() return S(HP) end
UnitHealthMax = function() return S(1000) end
UnitHealthPercent = function(u, pred, curve) return CreateColor(.2, .9, .4, 1) end
UnitIsDeadOrGhost = function() return false end
UnitIsGhost = function() return false end
local SPEED = 0
GetUnitSpeed = function() return SPEED end
IsSwimming = function() return false end
IsFalling = function() return false end
IsFlying = function() return false end
IsStealthed = function() return false end
UnitIsAFK = function() return false end
IsResting = function() return true end
local COMBAT = false
UnitAffectingCombat = function() return COMBAT end
GetInventoryItemID = function() return 12345 end
C_Item = { GetItemInfoInstant = function() return 12345, "Weapon", "Swords", "INVTYPE_2HWEAPON" end }
UnitPowerType = function() return S(0), S("MANA") end
UnitPower = function() return S(300) end
UnitPowerMax = function() return S(500) end
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, [0] = { r = 0, g = 0, b = 1 } }
DoEmote = function(token) end
C_Spell = { IsCurrentSpell = function() return true end }
C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
  if i <= 3 then return { name = (i == 1 and "Food" or "Buff"), icon = 136000 + i, applications = S(i), duration = S(30), expirationTime = S(120), dispelName = S("Magic"), auraInstanceID = S(i) } end end }
C_LossOfControl = { GetActiveLossOfControlDataCount = function() return 0 end }

-- load addon
local L = {}
local dir = arg[1]
for line in io.lines(os.getenv("TOCFILE") or (dir .. "/Lumen.toc")) do
  if line:match("%.lua$") then
    local chunk = assert(loadfile(dir .. "/" .. line))
    chunk("Lumen", L)
  end
end
local function fire(event, ...)
  for f in pairs(eventFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function tick(n, dt) for i = 1, n do now = now + dt; runTimers(); for f, fn in pairs(onUpdates) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end end end end

fire("ADDON_LOADED", "Lumen")
fire("PLAYER_LOGIN")
assert(L.ready, "not ready")
print("buttons:", #L.buttons, "bars:", #L.bars, "overrides:", overrides)
print("page driver:", L.bars[1].header.drivers.page)
print("MainMenuBar parent hidden:", MainMenuBar.parent and MainMenuBar.parent.__name, "MicroMenu parent:", MicroMenu.parent.__name)
fire("PLAYER_ENTERING_WORLD")
tick(10, 0.05)
-- simulate the page snippet: set actions like the secure env would
for i, b in ipairs(L.bars[1].buttons) do b:SetAttribute("action", 6*12 + i) end
assert(L.bars[1].buttons[3].action == 75)
for _, e in ipairs({"ACTIONBAR_UPDATE_COOLDOWN","SPELL_UPDATE_USABLE","ACTIONBAR_SLOT_CHANGED","BAG_UPDATE_DELAYED","PLAYER_TARGET_CHANGED","UPDATE_BINDINGS","ACTIONBAR_SHOWGRID","ACTIONBAR_HIDEGRID","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_XP_UPDATE","PLAYER_EQUIPMENT_CHANGED"}) do fire(e, 0) tick(3, .05) end
fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1076); tick(2,.05)
local active = 0; for b in pairs(L.cdActive) do active = active + 1 end
print("active cds:", active); local t={} for b in pairs(L.cdActive) do t[#t+1]=b.action end table.sort(t) print(table.concat(t,",")); for _,b in ipairs(L.buttons) do if b.action%2==0 and b.has and b.action%4~=0 and not L.cdActive[b] then print("missing", b.action, b.demoUntil, b.cdActive) end end
-- interactions
local b = L.buttons[1]
b.scripts.OnEnter(b); b.scripts.PostClick(b, "LeftButton", true); b.scripts.OnLeave(b); b.scripts.OnDragStart(b); b.scripts.OnReceiveDrag(b)
b.ring.scripts.OnCooldownDone(b.ring)
for _, cmd in ipairs({"", "theme ember", "theme neon", "layout line", "layout arc", "scale 1.2", "fade off", "fade", "pulse off", "xp off", "xp on", "numbers off", "hotkeys off", "sockets off", "blizzard off", "unlock", "lock", "reset", "test", "theme bogus"}) do
  SlashCmdList.LUMEN(cmd)
end
tick(200, .05)
for _, bb in ipairs(L.buttons) do if bb.ring.scripts.OnCooldownDone then bb.ring.scripts.OnCooldownDone(bb.ring) end end
tick(20, .05)
-- edit mode exercise
SlashCmdList.LUMEN("move")
assert(L.unlocked, "not unlocked")
for _, e in ipairs(L.movers) do
  local m = e.mover
  m.scripts.OnEnter(m); m.scripts.OnKeyDown(m, "UP"); m.scripts.OnKeyDown(m, "A"); m.scripts.OnMouseWheel(m, 1)
  m.scripts.OnDragStart(m); tick(2, .05); m.scripts.OnDragStop(m); m.scripts.OnMouseUp(m, "RightButton"); m.scripts.OnLeave(m)
end
print("movers:", #L.movers, "pos keys:", (function() local n=0 for k in pairs(L.db.pos) do n=n+1 end return n end)())
local panel = LumenEditPanel
local kids = {}
SlashCmdList.LUMEN("lock"); assert(not L.unlocked)
EditModeManagerFrame.EnterEditMode(); assert(L.unlocked, "edit mode hook"); EditModeManagerFrame.ExitEditMode(); assert(not L.unlocked)
fire("PLAYER_REGEN_DISABLED"); SlashCmdList.LUMEN("move"); fire("PLAYER_REGEN_ENABLED")
-- avatar
local Av = L.Avatar
assert(Av and Av.orb, "avatar missing")
print("avatar state:", Av.state)
SPEED = 7; tick(3, .1); print("moving ->", Av.state); SPEED = 0; tick(3, .1)
COMBAT = true; fire("PLAYER_REGEN_DISABLED"); tick(3, .1); print("combat ->", Av.state)
HP = 500; fire("UNIT_HEALTH", "player"); fire("UNIT_COMBAT", "player", "WOUND"); tick(20, .1)
fire("UNIT_SPELLCAST_START", "player"); tick(2, .1); print("cast ->", Av.state); fire("UNIT_SPELLCAST_SUCCEEDED", "player"); fire("UNIT_SPELLCAST_STOP", "player"); tick(2,.1)
HP = 200; fire("UNIT_HEALTH", "player"); tick(2,.1); print("low ->", Av.state)
COMBAT = false; HP = 900; fire("UNIT_HEALTH", "player"); fire("PLAYER_REGEN_ENABLED"); tick(10, .1); print("after combat ->", Av.state)
fire("UNIT_AURA", "player"); tick(2,.1); print("food ->", Av.state)
local savedAura = C_UnitAuras.GetAuraDataByIndex; C_UnitAuras.GetAuraDataByIndex = function() end; fire("UNIT_AURA", "player"); C_UnitAuras.GetAuraDataByIndex = savedAura
DoEmote("dance"); tick(2,.1); print("emote ->", Av.state); DoEmote("wave"); tick(30,.1)
Av.orb.scripts.PostClick(Av.orb, "LeftButton"); for i=1,6 do Av.orb.scripts.PostClick(Av.orb, "LeftButton") end
fire("UNIT_POWER_FREQUENT", "player"); fire("UNIT_HEALTH", "player"); print("hp line:", Av.orb.hpLine.cur.__txt, Av.orb.hpLine.max.__txt, "pp line:", Av.orb.ppLine.cur.__txt, Av.orb.ppLine.max.__txt)
print("unit attrs:", Av.orb.attrs.unit, Av.orb.attrs["*type1"], Av.orb.attrs["*type2"])
print("PlayerFrame parent:", PlayerFrame.parent.__name, "TotemFrame parent:", TotemFrame.parent.__name)
SlashCmdList.LUMEN("playerframe on"); print("restored:", PlayerFrame.parent.__name, TotemFrame.parent.__name)
SlashCmdList.LUMEN("playerframe off"); print("hidden again:", PlayerFrame.parent.__name)
SlashCmdList.LUMEN("avatar off"); print("avatar off ->", PlayerFrame.parent.__name); SlashCmdList.LUMEN("avatar on"); print("avatar on ->", PlayerFrame.parent.__name)
Av.orb.scripts.OnMouseWheel(Av.orb, 1)
fire("PLAYER_LEVEL_UP", 21); fire("LOOT_READY"); fire("PLAYER_ENTERING_WORLD"); fire("UNIT_MODEL_CHANGED", "player")
SPEED = 7; tick(2,.1); SPEED = 0
tick(800, 1); print("long idle ->", Av.state)
SlashCmdList.LUMEN("avatar demo"); local seen = {} for i = 1, 400 do tick(1, .1); seen[Av.state] = true end
local list = {} for k in pairs(seen) do list[#list+1] = k end table.sort(list) print("demo states:", table.concat(list, " "))
SlashCmdList.LUMEN("avatar off"); assert(not Av.orb.__shown); SlashCmdList.LUMEN("avatar on")
SlashCmdList.LUMEN("theme frost")
-- xp gains
for i = 1, 6 do now = now + 40; XPV = XPV + 35; fire("PLAYER_XP_UPDATE") end
now = now + 100; XPV = XPV + 30; fire("PLAYER_XP_UPDATE")
LumenXP.scripts.OnEnter(LumenXP)
print("xp main:", LumenXP.main and rawget(LumenXP.main, "__txt"))
print("xp sub:", LumenXP.sub and rawget(LumenXP.sub, "__txt"))
print("xp lvl:", rawget(LumenXP.lvl, "__txt"), rawget(LumenXP.nextLvl, "__txt"))
print("blizz xp parent (lumen xp on):", MainMenuExpBar.parent.__name)
SlashCmdList.LUMEN("xp off"); print("blizz xp parent (lumen xp off):", MainMenuExpBar.parent.__name)
SlashCmdList.LUMEN("xp on"); print("blizz xp parent (lumen xp on again):", MainMenuExpBar.parent.__name)
-- dock magnifier
local bar = L.bars[1]
for i, b in ipairs(bar.buttons) do b.__cx = (i - 6.5) * 54 end
CURX = bar.buttons[4].__cx; bar.header.__mouse = true
bar.buttons[4].scripts.OnEnter(bar.buttons[4])
tick(30, .016)
local out = {}
for i, b in ipairs(bar.buttons) do out[#out+1] = string.format("%.2f", b.visual.scale) end
print("dock scales:", table.concat(out, " "))
bar.header.__mouse = false; bar.buttons[4].scripts.OnLeave(bar.buttons[4]); tick(60, .016)
out = {} for i, b in ipairs(bar.buttons) do out[#out+1] = string.format("%.2f", b.visual.scale) end
print("after leave:", table.concat(out, " "), "dock hidden:", not bar.dock.__shown)
SlashCmdList.LUMEN("magnify 1.8"); SlashCmdList.LUMEN("magnify off"); SlashCmdList.LUMEN("magnify on")
print("fade:", L.db.fade)
-- target orb
local T = L.Target
print("target orb:", T.orb ~= nil, "watched:", T.orb.__watched, "TargetFrame parent:", TargetFrame.parent.__name, "ComboFrame parent:", ComboFrame.parent.__name)
print("cast bar parent:", PlayerCastingBarFrame.parent.__name)
fire("PLAYER_TARGET_CHANGED"); fire("UNIT_HEALTH", "target"); fire("UNIT_COMBAT", "target", "WOUND"); fire("UNIT_TARGET", "target"); tick(10, .1)
print("target name:", rawget(T.orb.nameText, "__txt"), "level:", rawget(T.orb.levelText, "__txt"), "tot:", rawget(T.orb.tot, "__txt"))
-- casts
CASTING = true; fire("UNIT_SPELLCAST_START", "player"); fire("UNIT_SPELLCAST_START", "target"); tick(5, .1)
fire("UNIT_SPELLCAST_FAILED", "player"); tick(3, .1)
print("after mid-cast FAILED (should stay true):", L.castArcs[1].casting)
print("arcs casting:", L.castArcs[1].casting, L.castArcs[2].casting, "text:", rawget(L.castArcs[1].text, "__txt"))
fire("UNIT_SPELLCAST_INTERRUPTED", "target"); CASTING = false; fire("UNIT_SPELLCAST_STOP", "player"); tick(20, .1)
print("arcs after:", L.castArcs[1].casting, L.castArcs[2].casting, "target text:", rawget(L.castArcs[2].text, "__txt"))
-- auras
fire("UNIT_AURA", "player"); fire("UNIT_AURA", "target"); tick(5, .1)
local shown = 0 for _, r in ipairs(L.auraRings) do for _, b in ipairs(r.all) do if b.__shown then shown = shown + 1 end end end
print("aura bubbles shown:", shown)
L.auraRings[1].top[1].scripts.OnEnter(L.auraRings[1].top[1])
-- edit preview
SlashCmdList.LUMEN("move"); SlashCmdList.LUMEN("lock")
-- options window: open, visit all pages, click every control
L.Options.Show()
local win = LumenOptions
assert(win and win.__shown, "options not shown")
for i = 1, #win.pages do L.Options.Select(i) end
local clicked, slid = 0, 0
for _, f in ipairs(FRAMES) do
  local p, under = f.parent, false
  for _ = 1, 8 do if p == win then under = true break end if not p then break end p = p.parent end
  if under then
    if f.scripts.OnClick then f.scripts.OnClick(f); clicked = clicked + 1 end
    if f.scripts.OnValueChanged then f.scripts.OnValueChanged(f, 1.3); slid = slid + 1 end
    if f.scripts.OnMouseWheel then f.scripts.OnMouseWheel(f, 1) end
  end
end
print("options controls clicked:", clicked, "sliders:", slid)
SlashCmdList.LUMEN("options"); SlashCmdList.LUMEN("help")
TARGET = false; fire("PLAYER_TARGET_CHANGED"); tick(5, .1)
SlashCmdList.LUMEN("debug")
print("OK secret=" .. tostring(SECRET_MODE))
