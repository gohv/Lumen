local _, L = ...

-- Cooldown "stops" are keyed by REMAINING percent: 1 = just pressed, 0 = ready.
-- accent = ready bloom / hover, base = idle rim, active = current/auto-attack,
-- proc = spell-alert comet.
L.themes = {
    aurora = {
        name = "Aurora",
        stops = { { 0, .25, .95, .70 }, { .35, 1, .70, .25 }, { .70, .98, .33, .62 }, { 1, .56, .40, 1 } },
        accent = { .40, 1, .80 }, base = { .80, .84, 1 }, active = { .62, .45, 1 }, proc = { 1, .80, .35 },
    },
    ember = {
        name = "Ember",
        stops = { { 0, 1, .88, .40 }, { .5, 1, .48, .12 }, { 1, .80, .10, .16 } },
        accent = { 1, .85, .45 }, base = { 1, .86, .78 }, active = { 1, .55, .20 }, proc = { 1, .35, .15 },
    },
    frost = {
        name = "Frost",
        stops = { { 0, .80, .97, 1 }, { .5, .25, .65, 1 }, { 1, .28, .22, .80 } },
        accent = { .70, .95, 1 }, base = { .78, .88, 1 }, active = { .35, .70, 1 }, proc = { .60, .85, 1 },
    },
    neon = {
        name = "Neon",
        stops = { { 0, .10, .98, 1 }, { .5, .62, .25, 1 }, { 1, 1, .12, .58 } },
        accent = { .20, 1, 1 }, base = { .90, .80, 1 }, active = { 1, .20, .70 }, proc = { 1, .95, .20 },
    },
    verdant = {
        name = "Verdant",
        stops = { { 0, .75, 1, .35 }, { .5, .15, .80, .65 }, { 1, .10, .40, .55 } },
        accent = { .70, 1, .45 }, base = { .82, 1, .88 }, active = { .30, .95, .60 }, proc = { 1, .85, .30 },
    },
}

L.defaults = {
    theme = "aurora",
    layout = "arc",        -- arc | line
    scale = 1,
    fade = false,          -- upper bars fade out of combat (off: looked "unavailable")
    fadeAlpha = 0.35,
    pulse = true,          -- center-screen pulse when a long cooldown is ready
    pulseMin = 6,          -- seconds
    xp = true,
    hideBlizzard = true,
    numbers = true,        -- countdown numbers on cooldowns
    hotkeys = true,
    sockets = true,        -- show empty slots as faint glass sockets
    avatar = true,         -- living 3D avatar orb
    avatarZoom = .75,
    hidePlayerFrame = true, -- the avatar replaces Blizzard's player frame
    target = true,         -- target orb
    targetZoom = .65,
    hideTargetFrame = true,
    castArc = true,        -- cast arc around the avatar
    targetCast = true,     -- cast arc around the target orb
    hideCastBar = true,
    auras = true,          -- buff/debuff bubbles around the avatar
    targetAuras = true,    -- aura bubbles around the target orb      -- 0 = full body, 1 = face (mouse wheel on the orb)
    magnify = true,        -- macOS-dock-style magnification on hover
    magnifyScale = 1.6,
    grid = true,           -- edit-mode grid + snapping
    pos = {},              -- element positions/sizes set in edit mode
}

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function L.InitDB()
    LumenDB = LumenDB or {}
    merge(LumenDB, L.defaults)
    L.db = LumenDB
    -- v0.4: fading made full bars look unavailable; turn it off once for
    -- existing installs (it can be turned back on with /lumen fade on).
    if not L.db.migratedFade then
        L.db.migratedFade = true
        L.db.fade = false
    end
end
